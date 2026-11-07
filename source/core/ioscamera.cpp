// The CAMERA, the engine's side: see ioscamera.h and ios/iosCamera.h.

#include "ioscamera.h"

#ifdef RAZE_IOSCAMERA

#include <chrono>
#include <math.h>
#include "gamecontrol.h"
#include "gamefuncs.h"
#include "gamestate.h"
#include "coreactor.h"
#include "coreplayer.h"
#include "d_net.h"
#include "i_net.h"
#include "c_dispatch.h"
#include "c_console.h"
#include "menu.h"
#include "printf.h"
#include "texturemanager.h"
#include "buildtiles.h"
#include "inputstate.h"
#include "gameinput.h"
#include "../../ios/iosCamera.h"
#include "../../ios/iosCapture.h"

// Lengths are metres, as the player's eye height above the floor makes
// them (IOSCAM_EYE_HEIGHT); angles are degrees.
#define IOSCAM_EYE_HEIGHT 1.6
// A burst: IOSCAM_BURST_MAX photos, IOSCAM_BURST_GAP apart (or as soon after
// as the photos before leave room)
#define IOSCAM_BURST_MAX 10
#define IOSCAM_BURST_GAP 0.2
// A photo the game hasn't taken in this long is dropped (a menu came up)
#define IOSCAM_PHOTO_TIMEOUT 0.5
// A selfie's or a cinematic burst's last photo stays this long on screen
#define IOSCAM_SHOW_TIME 0.8
// ...and either gives up when the photos can't be taken for this long
#define IOSCAM_GIVE_UP 4.0
// Selfies: the people are enemies within IOSCAM_SELFIE_RANGE, in sight of
// the player, the nearest IOSCAM_SELFIE_PEOPLE of them. The camera is held
// out IOSCAM_CAM_NEAR from the eyes (further, up to IOSCAM_CAM_MAX, only
// where that shows more of them), at one of IOSCAM_NUM_DIRS headings, with
// IOSCAM_CAM_CLEARANCE round it clear of walls, never looking down more
// steeply than IOSCAM_PITCH_DOWN_MAX
#define IOSCAM_SELFIE_RANGE 30.0
#define IOSCAM_SELFIE_PEOPLE 48
#define IOSCAM_NUM_DIRS 16
#define IOSCAM_CAM_NEAR 2.8
#define IOSCAM_CAM_MAX 12.0
#define IOSCAM_CAM_CLEARANCE 0.25
#define IOSCAM_PITCH_DOWN_MAX 35.0
// A posed enemy nearer the camera than the player by more than this, or
// within IOSCAM_LENS_CLEAR of the lens, is left out of the photo
#define IOSCAM_FRONT_MARGIN 0.3
#define IOSCAM_LENS_CLEAR 1.5
// The view's half widths used to judge what is in a photo (degrees)
#define IOSCAM_HALF_H 40.0
#define IOSCAM_HALF_V 30.0
// Action Freeze: the camera never comes nearer its focus than this, nor
// goes further than IOSCAM_FREEZE_FAR; it keeps IOSCAM_WALL_GAP off walls
#define IOSCAM_FREEZE_NEAR 0.4
#define IOSCAM_FREEZE_FAR 20.0
#define IOSCAM_WALL_GAP 0.3
#define IOSCAM_PITCH_LIMIT 55.0

enum { STAGE_NONE = 0, STAGE_SELFIE, STAGE_FREEZE, STAGE_CINEMA };

// ------------------------------------------------------------ small things

static double Now()
{
	using namespace std::chrono;
	return duration<double>(steady_clock::now().time_since_epoch()).count();
}

// (xorshift32: the game's own random numbers aren't touched, so a selfie
// changes nothing of what happens next)
static unsigned _uRand = 2463534242u;
static unsigned Rand()
{
	unsigned x = _uRand;
	x ^= x << 13;
	x ^= x >> 17;
	x ^= x << 5;
	return _uRand = x;
}
static double Rand01() { return (Rand() & 0xFFFFFF) / (double)0x1000000; }

// The settings
static int _iKinds = IOSCAPTURE_CLEAN, _iSelfieShots = 3, _bFreezeOn = 1;
extern "C" int iosCam_GetKinds(void) { return _iKinds; }
extern "C" void iosCam_SetKinds(int k) { k &= IOSCAPTURE_ALL; _iKinds = k ? k : IOSCAPTURE_CLEAN; }
extern "C" int iosCam_GetSelfieShots(void) { return _iSelfieShots; }
extern "C" void iosCam_SetSelfieShots(int n) { _iSelfieShots = (n == 1 || n == 5) ? n : 3; }
extern "C" int iosCam_GetFreezeOn(void) { return _bFreezeOn; }
extern "C" void iosCam_SetFreezeOn(int on) { _bFreezeOn = on != 0; }

// The game's people, by game
static const IOSCamPeople *People()
{
	if (isDukeEngine()) return Duke3d::iosCam_People();
	if (isBlood()) return Blood::iosCam_People();
	if (isSWALL()) return ShadowWarrior::iosCam_People();
	return nullptr;
}

// ------------------------------------------------------------ the view

struct IOSCamView
{
	DCoreActor *viewer = nullptr;
	DVector3 pos;
	sectortype *sect = nullptr;
	DRotator angles;
	float fov = 90;
};

static IOSCamView _game;          // what the player saw last
static bool _bGameValid = false;
static bool _bViewSeen = false;   // render_drawrooms ran in this frame
static bool _bCamOn = false;      // the photo camera draws the view
static IOSCamView _cam;
static bool _bShowPlayer = false; // the player's body in the photo camera's view
static int _iStage = STAGE_NONE;
static double _fUnit = 24;        // map units per metre

bool iosCam_View(DCoreActor *viewer, DVector3 &pos, sectortype *&sect, DRotator &angles, float &fov)
{
	if (!_bViewSeen)
	{
		_bViewSeen = true;
		if (!_bCamOn || !_bGameValid)
		{
			_game.viewer = viewer;
			_game.pos = pos;
			_game.sect = sect;
			_game.angles = angles;
			_game.fov = fov > 0 ? fov : (float)r_fov;
			_bGameValid = sect != nullptr;
		}
	}
	if (!_bCamOn || !_cam.sect) return false;
	pos = _cam.pos;
	sect = _cam.sect;
	angles = _cam.angles;
	fov = _cam.fov;
	return true;
}

bool iosCam_ShowsPlayer() { return _bCamOn && _bShowPlayer; }
bool iosCam_HoldsGame() { return _iStage != STAGE_NONE; }
bool iosCam_HidesHud() { return _bCamOn; }
extern "C" int iosCam_Stage(void) { return _iStage; }
extern "C" int iosCam_IsFrozen(void) { return _iStage == STAGE_FREEZE; }

static DCoreActor *PlayerActor()
{
	auto pl = PlayerArray[myconnectindex];
	return pl ? pl->actor : nullptr;
}

// Whether a selfie or a freeze can be had now: 0 if so, else why not
static const char *CantHere()
{
	if (netgame || numplayers > 1) return "single";
	if (gamestate != GS_LEVEL || M_Active() || ConsoleState == c_down || ConsoleState == c_falling) return "here";
	auto pp = People();
	auto pa = PlayerActor();
	if (!_bGameValid || !pa || !pp || !pp->playerAlive(pa)) return "here";
	if (_game.viewer != pa) return "here"; // (a security camera's view, a cutscene's)
	return nullptr;
}

// Lines through the level: how far from a towards b (in a's sector) before
// a wall, a floor or a ceiling (not sprites); the whole way if clear
static double ClearDist(const DVector3 &a, sectortype *sa, const DVector3 &b)
{
	DVector3 v = b - a;
	double len = v.Length();
	if (len < 1e-6 || !sa) return len;
	HitInfoBase hit;
	hit.clearObj();
	hitscan(a, sa, v, hit, CSTAT_WALL_BLOCK_HITSCAN << 16);
	if (!hit.hitSector && !hit.hitWall) return len;
	double d = (hit.hitpos - a).Length();
	return d < len ? d : len;
}

// The sector of a point reached from a in sa, NULL if outside the level
static sectortype *SectorAt(const DVector3 &v, sectortype *sa)
{
	sectortype *s = sa;
	updatesectorz(v, &s);
	return s;
}

// Whether a camera at v (seen clear from a) has room round it
static bool RoomAt(const DVector3 &a, sectortype *sa, const DVector3 &v, double r)
{
	if (ClearDist(a, sa, v) < (v - a).Length() - 0.01) return false;
	sectortype *s = SectorAt(v, sa);
	if (!s) return false;
	double cz, fz;
	calcSlope(s, v.X, v.Y, &cz, &fz);
	if (v.Z < cz + r || v.Z > fz - r) return false;
	for (int i = 0; i < 4; i++)
	{
		DVector2 d = DAngle::fromDeg(i * 90.0).ToVector() * r;
		if (ClearDist(v, s, v + DVector3(d, 0)) < r * 0.99) return false;
	}
	return true;
}

static DRotator LookAt(const DVector3 &from, const DVector3 &to)
{
	DVector3 d = to - from;
	double flat = d.XY().Length();
	return DRotator(DAngle::fromRad(atan2(d.Z, flat)), d.XY().Angle(), nullAngle);
}

// Where p is seen from a view looking along ang: degrees right and down
// from its middle; false if behind
static bool AngleTo(const DVector3 &cam, const DRotator &ang, const DVector3 &p, double &h, double &v)
{
	DRotator to = LookAt(cam, p);
	h = deltaangle(ang.Yaw, to.Yaw).Degrees();
	v = (to.Pitch - ang.Pitch).Degrees();
	return fabs(h) < 89;
}

static void CamOn(const DVector3 &pos, sectortype *sect, const DRotator &ang)
{
	_cam.pos = pos;
	_cam.sect = sect;
	_cam.angles = ang;
	_cam.fov = _game.fov;
	_bCamOn = true;
	// (from inside the player's head, the body would fill the view)
	_bShowPlayer = (pos.XY() - _game.pos.XY()).Length() > 0.6 * _fUnit || fabs(pos.Z - _game.pos.Z) > 0.6 * _fUnit;
}

// The player's body's height (map units), as drawn
static double PlayerHeight()
{
	auto pa = PlayerActor();
	if (!pa) return 0;
	auto tex = TexMan.GetGameTexture(pa->spr.spritetexture());
	return (tex && tex->isValid()) ? tex->GetDisplayHeight() * pa->spr.scale.Y : 0;
}

// Metres: from the eyes' height over the floor, or the body's height
// where that is drawn bigger (Blood's Caleb)
static void SetUnit()
{
	double cz, fz;
	calcSlope(_game.sect, _game.pos.X, _game.pos.Y, &cz, &fz);
	double h = fz - _game.pos.Z;
	_fUnit = clamp(max(h / IOSCAM_EYE_HEIGHT, PlayerHeight() / 1.8), 12.0, 64.0);
}

// ------------------------------------------------------------ people

struct IOSCamPerson
{
	DCoreActor *act;
	DVector3 head, mid;
	double height, dist;
	bool inPhoto;
};

struct IOSCamKept
{
	DCoreActor *act;
	spritetype spr;
	intptr_t aux[4];
};

static TArray<IOSCamPerson> _people;
static TArray<IOSCamKept> _kept;

static void Keep(DCoreActor *act)
{
	for (auto &k : _kept) if (k.act == act) return;
	IOSCamKept k;
	k.act = act;
	k.spr = act->spr;
	memset(k.aux, 0, sizeof(k.aux));
	auto pp = People();
	if (pp && pp->save) pp->save(act, k.aux);
	_kept.Push(k);
}

// Everything posed or hidden as it was
static void PutBack()
{
	auto pp = People();
	for (int i = (int)_kept.Size() - 1; i >= 0; i--)
	{
		auto &k = _kept[i];
		k.act->spr = k.spr;
		if (pp && pp->restore) pp->restore(k.act, k.aux);
	}
	_kept.Clear();
}

static void Measure(DCoreActor *act, IOSCamPerson &p)
{
	double h = 1.6 * _fUnit;
	auto tex = TexMan.GetGameTexture(act->spr.spritetexture());
	if (tex && tex->isValid()) h = tex->GetDisplayHeight() * act->spr.scale.Y;
	h = clamp(h, 0.5 * _fUnit, 4.0 * _fUnit);
	double feet = act->spr.pos.Z;
	if (act->spr.cstat & CSTAT_SPRITE_YCENTER) feet += h * 0.5;
	p.act = act;
	p.height = h;
	p.head = DVector3(act->spr.pos.XY(), feet - h * 0.85);
	p.mid = DVector3(act->spr.pos.XY(), feet - h * 0.5);
	p.dist = (p.mid - _game.pos).Length();
	p.inPhoto = false;
}

// The enemies near the player, in sight, nearest first (at most max)
static void FindPeople(double range, unsigned max)
{
	_people.Clear();
	auto pp = People();
	if (!pp) return;
	TArray<DCoreActor *> all;
	pp->collect(all);
	for (auto act : all)
	{
		if (!act || act == PlayerActor() || (act->spr.cstat & CSTAT_SPRITE_INVISIBLE)) continue;
		IOSCamPerson p;
		Measure(act, p);
		if (p.dist > range * _fUnit) continue;
		if (!cansee(_game.pos, _game.sect, p.head, act->sector())) continue;
		_people.Push(p);
	}
	std::sort(_people.begin(), _people.end(), [](const IOSCamPerson &a, const IOSCamPerson &b) { return a.dist < b.dist; });
	if (_people.Size() > max) _people.Resize(max);
}

// ------------------------------------------------------------ the selfie

static DVector3 _vPlayerHead, _vPlayerMid;
static double _fPlayerDist;
static int _ctShots, _ctTaken;
static double _tStage, _tShown, _tWaited;
static bool _bPosed, _bAsked;

// The camera at cam: how good a photo (-1: none), and where it looks
static double SelfieScore(const DVector3 &cam, sectortype *s, DRotator &ang)
{
	DVector3 aim = _vPlayerHead;
	int n = 0;
	DVector3 sum(0, 0, 0);
	for (unsigned i = 0; i < _people.Size() && i < 12; i++) { sum += _people[i].head; n++; }
	if (n) aim = _vPlayerHead * 0.6 + (sum / n) * 0.4;
	ang = LookAt(cam, aim);
	if (ang.Pitch.Degrees() > IOSCAM_PITCH_DOWN_MAX) return -1;
	double h, v;
	// the player's face near the middle, and clear
	if (!AngleTo(cam, ang, _vPlayerHead, h, v) || fabs(h) > IOSCAM_HALF_H * 0.6 || fabs(v) > IOSCAM_HALF_V * 0.7) return -1;
	double score = 3;
	double pd = (cam - _vPlayerMid).Length();
	for (unsigned i = 0; i < _people.Size(); i++)
	{
		auto &p = _people[i];
		double d = (cam - p.mid).Length();
		if (d < pd - IOSCAM_FRONT_MARGIN * _fUnit || d < IOSCAM_LENS_CLEAR * _fUnit) continue; // (left out)
		if (!AngleTo(cam, ang, p.head, h, v) || fabs(h) > IOSCAM_HALF_H * 0.88 || fabs(v) > IOSCAM_HALF_V * 0.85) continue;
		if (!cansee(cam, s, p.head, p.act->sector())) continue;
		score += 1.0 / (1.0 + 0.08 * i);
	}
	return score;
}

static bool PlaceSelfieCamera()
{
	DAngle face = _game.angles.Yaw;
	static const double aDist[] = { IOSCAM_CAM_NEAR, 2.0, 4.0, 6.0, 9.0, IOSCAM_CAM_MAX, 1.4, 0.8 };
	static const double aLift[] = { 0.15, 0.6, -0.25, 1.2, 2.5 };
	double best = -1;
	DVector3 bestPos;
	sectortype *bestSect = nullptr;
	DRotator bestAng;
	const int start = Rand01() < 0.5 ? 1 : -1;
	for (int i = 0; i < IOSCAM_NUM_DIRS; i++)
	{
		// first a bit to the side of where the player looks (a held-out
		// arm), then round them
		int k = (i + 1) / 2;
		double side = (i & 1) ? start : -start;
		DAngle head = face + DAngle::fromDeg(20.0 * start + side * k * (360.0 / IOSCAM_NUM_DIRS));
		for (double dist : aDist)
		{
			for (int l = 0; l < 5; l++)
			{
				if (l && Rand01() < 0.5) continue; // (now and then held higher or lower)
				DVector3 cam = _vPlayerHead + DVector3(head.ToVector() * dist * _fUnit, -aLift[l] * _fUnit);
				if (!RoomAt(_game.pos, _game.sect, cam, IOSCAM_CAM_CLEARANCE * _fUnit)) continue;
				sectortype *s = SectorAt(cam, _game.sect);
				DRotator ang;
				double score = SelfieScore(cam, s, ang);
				if (score < 0) continue;
				// near and low is best; further only for more of them
				score -= dist * 0.12 + (l >= 3 ? 0.4 : 0) + i * 0.01;
				if (score > best)
				{
					best = score;
					bestPos = cam;
					bestSect = s;
					bestAng = ang;
				}
			}
		}
	}
	if (best < 0 || !bestSect) return false;
	// one in three a little tilted
	if (Rand01() < 1.0 / 3) bestAng.Roll = DAngle::fromDeg((Rand01() * 2 - 1) * 6.0);
	CamOn(bestPos, bestSect, bestAng);
	_bShowPlayer = true;
	return true;
}

// Everyone turns to the camera and strikes a pose; whoever would block it
// is left out
static void Pose()
{
	PutBack();
	auto pp = People();
	auto pa = PlayerActor();
	const DVector3 cam = _cam.pos;
	_fPlayerDist = (cam - _vPlayerMid).Length();
	Keep(pa);
	pa->spr.Angles.Yaw = (cam.XY() - pa->spr.pos.XY()).Angle();
	for (unsigned i = 0; i < _people.Size(); i++)
	{
		auto &p = _people[i];
		Keep(p.act);
		double d = (cam - p.mid).Length();
		if (d < _fPlayerDist - IOSCAM_FRONT_MARGIN * _fUnit || d < IOSCAM_LENS_CLEAR * _fUnit)
		{
			p.act->spr.cstat |= CSTAT_SPRITE_INVISIBLE;
			continue;
		}
		p.act->spr.Angles.Yaw = (cam.XY() - p.act->spr.pos.XY()).Angle() + DAngle::fromDeg((Rand01() * 2 - 1) * 15.0);
		bool calm = false;
		for (unsigned j = 0; j < _people.Size() && !calm; j++)
		{
			if (j == i) continue;
			double gap = (_people[j].mid.XY() - p.mid.XY()).Length();
			if (gap < (p.height + _people[j].height) * 0.25 * 0.8) calm = true;
		}
		if (pp && pp->pose) pp->pose(p.act, Rand(), calm);
	}
	_bPosed = true;
}

static bool SelfieBegin()
{
	SetUnit();
	double cz, fz;
	calcSlope(_game.sect, _game.pos.X, _game.pos.Y, &cz, &fz);
	// the head: the eyes, or higher where the body is drawn taller
	const double top = fz - max(PlayerHeight(), fz - _game.pos.Z);
	_vPlayerHead = DVector3(_game.pos.XY(), min(_game.pos.Z, fz - (fz - top) * 0.88));
	_vPlayerMid = DVector3(_game.pos.XY(), (top + fz) * 0.5);
	FindPeople(IOSCAM_SELFIE_RANGE, IOSCAM_SELFIE_PEOPLE);
	if (!PlaceSelfieCamera()) return false;
	Pose();
	return true;
}

// ------------------------------------------------------------ Action Freeze

static DVector3 _vFocus;
static sectortype *_pFocusSect;
static double _fYaw, _fPitch, _fDist, _fDistNow;
static bool _bSmooth = true;

// The camera where the orbit puts it, kept out of walls
static bool PlaceOrbit(bool bSnap)
{
	DRotator ang(DAngle::fromDeg(_fPitch), DAngle::fromDeg(_fYaw), nullAngle);
	DVector3 dir(ang);
	DVector3 want = _vFocus - dir * (_fDist * _fUnit);
	double room = ClearDist(_vFocus, _pFocusSect, want) / _fUnit - IOSCAM_WALL_GAP;
	double d = clamp(room, IOSCAM_FREEZE_NEAR * 0.5, _fDist);
	// coming in from a wall is at once; going back out glides
	if (bSnap || !_bSmooth || d < _fDistNow) _fDistNow = d;
	else _fDistNow += (d - _fDistNow) * 0.2;
	DVector3 pos = _vFocus - dir * (_fDistNow * _fUnit);
	sectortype *s = SectorAt(pos, _pFocusSect);
	if (!s) return false;
	CamOn(pos, s, ang);
	return true;
}

// What the player was looking at: an enemy near the middle of the view, or
// where the view meets the level
static void FindFocus()
{
	DVector3 dir(_game.angles);
	FindPeople(25.0, 64);
	for (auto &p : _people)
	{
		double h, v;
		if (AngleTo(_game.pos, _game.angles, p.mid, h, v) && fabs(h) < 12 && fabs(v) < 15)
		{
			double t = ((p.mid - _game.pos) | dir);
			if (t > 0.5 * _fUnit)
			{
				_vFocus = _game.pos + dir * t;
				_fDist = t / _fUnit;
				return;
			}
		}
	}
	double d = ClearDist(_game.pos, _game.sect, _game.pos + dir * (8.0 * _fUnit)) / _fUnit - 0.5;
	_fDist = clamp(d, 1.5, 6.0);
	_vFocus = _game.pos + dir * (_fDist * _fUnit);
}

static bool FreezeBegin()
{
	SetUnit();
	FindFocus();
	_pFocusSect = SectorAt(_vFocus, _game.sect);
	if (!_pFocusSect) return false;
	_fYaw = _game.angles.Yaw.Degrees();
	_fPitch = clamp(_game.angles.Pitch.Degrees(), -IOSCAM_PITCH_LIMIT, IOSCAM_PITCH_LIMIT);
	_fDistNow = _fDist;
	return PlaceOrbit(true);
}

extern "C" void iosCam_FreezeOrbit(float yawDeg, float pitchDeg)
{
	if (_iStage != STAGE_FREEZE) return;
	double y0 = _fYaw, p0 = _fPitch;
	_fYaw += yawDeg;
	_fPitch = clamp(_fPitch + pitchDeg, -IOSCAM_PITCH_LIMIT, IOSCAM_PITCH_LIMIT);
	if (!PlaceOrbit(false)) { _fYaw = y0; _fPitch = p0; PlaceOrbit(true); }
}

extern "C" void iosCam_FreezePan(float right, float down)
{
	if (_iStage != STAGE_FREEZE) return;
	// what is seen follows the fingers: the focus moves across the view, by
	// fractions of its height at the focus
	double span = 2.0 * _fDistNow * _fUnit * tan(IOSCAM_HALF_V * pi::pi() / 180.0);
	DVector2 fwd = DAngle::fromDeg(_fYaw).ToVector();
	DVector2 rgt(-fwd.Y, fwd.X);
	DVector3 up = DVector3(DRotator(DAngle::fromDeg(_fPitch - 90.0), DAngle::fromDeg(_fYaw), nullAngle));
	DVector3 move = DVector3(rgt * (-right * span), 0) + up * (down * span);
	DVector3 to = _vFocus + move;
	double room = ClearDist(_vFocus, _pFocusSect, to);
	double len = move.Length();
	if (len < 1e-6) return;
	double k = clamp((room - IOSCAM_WALL_GAP * _fUnit) / len, 0.0, 1.0);
	to = _vFocus + move * k;
	sectortype *s = SectorAt(to, _pFocusSect);
	if (!s) return;
	_vFocus = to;
	_pFocusSect = s;
	PlaceOrbit(false);
}

extern "C" void iosCam_FreezeZoom(float factor)
{
	if (_iStage != STAGE_FREEZE || factor <= 0) return;
	_fDist = clamp(_fDist / factor, IOSCAM_FREEZE_NEAR, IOSCAM_FREEZE_FAR);
	PlaceOrbit(false);
}

// ------------------------------------------------------------ cinematic

#define IOSCAM_CINEMA_SHOTS 5
static double _aCineYaw[IOSCAM_CINEMA_SHOTS];

// Round the most interesting thing in front: an enemy being fought (the
// player and it both in the shots, from the side), else the player; on the
// side with the most room
static bool CinemaBegin()
{
	SetUnit();
	double cz, fz;
	calcSlope(_game.sect, _game.pos.X, _game.pos.Y, &cz, &fz);
	DVector3 playerMid(_game.pos.XY(), (_game.pos.Z + fz) * 0.5);
	FindPeople(25.0, 64);
	const IOSCamPerson *target = nullptr;
	for (auto &p : _people)
	{
		double h, v;
		if (AngleTo(_game.pos, _game.angles, p.mid, h, v) && fabs(h) < 50) { target = &p; break; }
	}
	double yaw0 = _game.angles.Yaw.Degrees();
	double start, step;
	if (target)
	{
		_vFocus = (playerMid + target->mid) * 0.5;
		_fDist = clamp((target->mid - playerMid).Length() / _fUnit * 0.9, 3.0, 12.0);
		start = 60;
		step = 30;
	}
	else
	{
		_vFocus = playerMid;
		_fDist = 3.0;
		start = 60;
		step = 40;
	}
	_pFocusSect = SectorAt(_vFocus, _game.sect);
	if (!_pFocusSect) return false;
	// the side with the most room
	double aRoom[2] = { 0, 0 };
	for (int side = 0; side < 2; side++)
	{
		for (int i = 0; i < 4; i++)
		{
			double y = yaw0 + (side ? -1 : 1) * (start + step * i);
			DVector3 dir(DRotator(DAngle::fromDeg(10), DAngle::fromDeg(y), nullAngle));
			aRoom[side] += min(ClearDist(_vFocus, _pFocusSect, _vFocus - dir * (_fDist * _fUnit)) / _fUnit, _fDist);
		}
	}
	const int sgn = aRoom[0] >= aRoom[1] ? 1 : -1;
	for (int i = 0; i < 4; i++) _aCineYaw[i + 1] = yaw0 + sgn * (start + step * i);
	_fPitch = 10;
	_bSmooth = false;
	return true;
}

static void CinemaPlace(int shot)
{
	if (shot == 0)
	{
		_bCamOn = false; // (the first is exactly what the player saw)
		return;
	}
	_fYaw = _aCineYaw[shot];
	PlaceOrbit(true);
}

// ------------------------------------------------------------ stages

static double _tPhotoAsked = 0;
static int _ctBurst = 0;
static double _tBurstNext = 0;
static bool _bBurst = false;

static void EndBurst()
{
	if (!_bBurst) return;
	_bBurst = false;
	iosPhotos_SetBatch(0);
}

static void HoldOn()
{
	// the touch or mouse moves made while held are dropped, not saved up
	inputState.ClearAllInput();
}

#ifdef RAZE_GLES_RIG
// (the rig: a sum over every actor's sprite and what a pose changes, to
// show a selfie or a freeze leaves the level exactly as it was)
struct RigSnap { DCoreActor *act; spritetype spr; };
static TArray<RigSnap> _rigSnap;
static unsigned RigHash(bool bSnap = false)
{
	if (!bSnap)
	{
		for (auto &r : _rigSnap)
		{
			const unsigned char *a = (const unsigned char *)&r.spr, *b = (const unsigned char *)&r.act->spr;
			for (size_t i = 0; i < sizeof(spritetype); i++)
				if (a[i] != b[i]) { Printf("ioscam: changed: statnum %d tex %d at byte %d\n", r.act->spr.statnum, r.act->spr.spritetexture().GetIndex(), (int)i); break; }
		}
	}
	_rigSnap.Clear();
	unsigned h = 2166136261u;
	auto pp = People();
	for (int st = 0; st < MAXSTATUS; st++)
	{
		TStatIterator<DCoreActor> it(st);
		while (auto act = it.Next())
		{
			if (bSnap) _rigSnap.Push({ act, act->spr });
			const unsigned char *b = (const unsigned char *)&act->spr;
			for (size_t i = 0; i < sizeof(act->spr); i++) h = (h ^ b[i]) * 16777619u;
			intptr_t aux[4] = { 0, 0, 0, 0 };
			if (pp && pp->save) pp->save(act, aux);
			b = (const unsigned char *)aux;
			for (size_t i = 0; i < sizeof(aux); i++) h = (h ^ b[i]) * 16777619u;
		}
	}
	return h;
}
#endif

static void EndStage()
{
#ifdef RAZE_GLES_RIG
	const bool bHash = _iStage != STAGE_NONE;
#endif
	PutBack();
	_bCamOn = false;
	_bShowPlayer = false;
	_bSmooth = true;
	if (_iStage == STAGE_FREEZE) iosPhotos_FreezeShown(0);
	if (_iStage == STAGE_SELFIE || _iStage == STAGE_CINEMA) iosPhotos_SetBatch(0);
	if (_iStage != STAGE_NONE)
	{
		iosCapture_NoteFreeze(Now() - _tStage);
		inputState.ClearAllInput();
	}
	_iStage = STAGE_NONE;
	_people.Clear();
#ifdef RAZE_GLES_RIG
	if (bHash) Printf("ioscam: level hash after %08x\n", RigHash());
#endif
}

extern "C" void iosCam_FreezeEnd(void)
{
	if (_iStage != STAGE_FREEZE) return;
	iosCapture_Cancel();
	EndStage();
}

extern "C" int iosCam_NumTaken(void) { return _ctTaken; }

static void Say(const char *why, const char *what)
{
	if (why && !strcmp(why, "single")) iosCamera_Message(!strcmp(what, "selfie") ? "Selfies are for single player" : "Action Freeze is for single player");
	else iosCamera_Message(!strcmp(what, "selfie") ? "Can't take a selfie here" : "Can't freeze here");
}

extern "C" void iosCamera_Photo(void)
{
	if (_iStage == STAGE_SELFIE || _iStage == STAGE_CINEMA) return;
	// in Action Freeze: a clean photo of the view
	int kinds = _iStage == STAGE_FREEZE ? IOSCAPTURE_CLEAN : _iKinds;
	if (iosCapture_Request(kinds, IOSCAPTURE_MODE_PHOTO)) _tPhotoAsked = Now();
	else iosCamera_Message("Still saving the last photo");
}

extern "C" void iosCamera_Burst(void)
{
	if (_iStage != STAGE_NONE || _bBurst) return;
	_bBurst = true;
	_ctBurst = 0;
	_tBurstNext = Now();
	iosPhotos_SetBatch(1);
}

static bool StartHeld(int stage)
{
	EndBurst();
	if (_iStage != STAGE_NONE) return false;
	const char *what = stage == STAGE_SELFIE ? "selfie" : "freeze";
	if (const char *why = CantHere())
	{
		Say(why, what);
		return false;
	}
	if (stage != STAGE_FREEZE && !iosCapture_HasRoom(IOSCAPTURE_CLEAN, 1))
	{
		iosCamera_Message("Still saving the last photo");
		return false;
	}
	iosCapture_Cancel(); // (a photo not taken yet would be of the held view)
#ifdef RAZE_GLES_RIG
	Printf("ioscam: level hash before %08x\n", RigHash(true));
#endif
	_uRand ^= (unsigned)(Now() * 1000.0);
	if (!_uRand) _uRand = 2463534242u;
	_iStage = stage; // (held from here: the game draws no new tic)
	_tStage = Now();
	_ctTaken = 0;
	_bPosed = _bAsked = false;
	_tShown = _tWaited = 0;
	bool ok = stage == STAGE_SELFIE ? SelfieBegin() : stage == STAGE_FREEZE ? FreezeBegin() : CinemaBegin();
	if (!ok)
	{
		EndStage();
		Say(nullptr, what);
		return false;
	}
	HoldOn();
	if (stage == STAGE_SELFIE)
	{
		_ctShots = _iSelfieShots;
		if (_ctShots > 1) iosPhotos_SetBatch(1);
	}
	if (stage == STAGE_CINEMA)
	{
		_ctShots = IOSCAM_CINEMA_SHOTS;
		iosPhotos_SetBatch(1);
		CinemaPlace(0);
	}
	if (stage == STAGE_FREEZE) iosPhotos_FreezeShown(1);
	return true;
}

extern "C" void iosCamera_Selfie(void) { StartHeld(STAGE_SELFIE); }
extern "C" void iosCamera_Cinematic(void) { StartHeld(STAGE_CINEMA); }

extern "C" void iosCamera_Freeze(void)
{
	if (_iStage == STAGE_FREEZE)
	{
		iosCam_FreezeEnd();
		return;
	}
	if (!_bFreezeOn) return;
	StartHeld(STAGE_FREEZE);
}

extern "C" int iosCamera_IsBusy(void)
{
	// (Action Freeze too: its own controls are on screen then)
	return _iStage != STAGE_NONE || _bBurst || iosCapture_IsPending();
}

// A selfie's or the cinematic burst's photos, one a frame as they are taken
static void TickShots(double now)
{
	if (_tShown > 0)
	{
		if (now - _tShown > IOSCAM_SHOW_TIME) EndStage();
		return;
	}
	if (_bAsked)
	{
		if (iosCapture_IsPending()) return; // (taken in this frame's AfterScene)
		_bAsked = false;
		_ctTaken++;
		if (_ctTaken >= _ctShots)
		{
			_tShown = now;
			if (_iStage == STAGE_SELFIE || _iStage == STAGE_CINEMA) iosPhotos_SetBatch(0);
			return;
		}
		if (_iStage == STAGE_SELFIE) Pose();
		else CinemaPlace(_ctTaken);
		_tWaited = now;
	}
	if (!iosCapture_Request(IOSCAPTURE_CLEAN, _iStage == STAGE_CINEMA ? IOSCAPTURE_MODE_BURST : IOSCAPTURE_MODE_SELFIE))
	{
		if (_tWaited == 0) _tWaited = now;
		if (now - _tWaited > IOSCAM_GIVE_UP)
		{
			iosCamera_Message("Couldn't take the photos");
			EndStage();
		}
		return;
	}
	_bAsked = true;
}

// Once a frame, before anything of it is drawn
static int _ctFrames = 0;

#ifdef RAZE_GLES_RIG
// The Linux rig's script: $IOSCAM_SCRIPT is "<frame> <command>;..." run by
// the count of frames drawn in a level (the console's wait counts tics,
// which run all at once while a level loads)
static void RigScript()
{
	static TArray<FString> cmds;
	static TArray<int> at;
	static bool read = false;
	if (!read)
	{
		read = true;
		const char *env = getenv("IOSCAM_SCRIPT");
		if (env)
		{
			auto parts = FString(env).Split(";");
			for (auto &p : parts)
			{
				p.StripLeftRight();
				int n = atoi(p.GetChars());
				long sp = p.IndexOf(' ');
				if (n > 0 && sp > 0)
				{
					at.Push(n);
					cmds.Push(p.Mid(sp + 1));
				}
			}
		}
	}
	for (unsigned i = 0; i < at.Size(); i++)
		if (at[i] == _ctFrames) C_DoCommand(cmds[i].GetChars());
}
#endif

extern "C" void iosCamera_FrameBegin(int w, int h)
{
	static bool bInit = false;
	if (!bInit)
	{
		bInit = true;
		iosPhotos_Init();
	}
	if (gamestate == GS_LEVEL) _ctFrames++;
#ifdef RAZE_GLES_RIG
	if (gamestate == GS_LEVEL) RigScript();
#endif
	iosCapture_FrameBegin(w, h);
	_bViewSeen = false;
	const double now = Now();
	if (_iStage != STAGE_NONE && (gamestate != GS_LEVEL || M_Active() || ConsoleState == c_down || ConsoleState == c_falling))
	{
		// a mode change: everything put back at once
		iosCapture_Cancel();
		EndStage();
	}
	if (gamestate != GS_LEVEL)
	{
		_bGameValid = false;
		EndBurst();
	}
	if (_tPhotoAsked > 0 && !iosCapture_IsPending()) _tPhotoAsked = 0;
	if (_tPhotoAsked > 0 && now - _tPhotoAsked > IOSCAM_PHOTO_TIMEOUT && _iStage != STAGE_SELFIE && _iStage != STAGE_CINEMA)
	{
		iosCapture_Cancel();
		_tPhotoAsked = 0;
	}
	if (_bBurst && now >= _tBurstNext)
	{
		if (_ctBurst >= IOSCAM_BURST_MAX) EndBurst();
		else if (iosCapture_Request(IOSCAPTURE_CLEAN, IOSCAPTURE_MODE_BURST))
		{
			_ctBurst++;
			_tBurstNext = now + IOSCAM_BURST_GAP;
		}
	}
	if (_iStage == STAGE_SELFIE || _iStage == STAGE_CINEMA) TickShots(now);
	if (_iStage == STAGE_FREEZE) PlaceOrbit(false);
}

extern "C" void iosCamera_AfterScene(void) { iosCapture_AfterScene(); }
extern "C" void iosCamera_AfterHud(void) { iosCapture_AfterHud(); }

// ------------------------------------------------------------ commands
// (for the Linux rig and for testing: the touch overlay calls the same)

CCMD(ioscam_photo) { iosCamera_Photo(); }
CCMD(ioscam_selfie) { iosCamera_Selfie(); }
CCMD(ioscam_burst) { iosCamera_Burst(); }
CCMD(ioscam_freeze) { iosCamera_Freeze(); }
CCMD(ioscam_cinema) { iosCamera_Cinematic(); }
CCMD(ioscam_options) { iosCamera_ShowOptions(); }
CCMD(ioscam_orbit)
{
	if (argv.argc() >= 3) iosCam_FreezeOrbit((float)atof(argv[1]), (float)atof(argv[2]));
}
CCMD(ioscam_pan)
{
	if (argv.argc() >= 3) iosCam_FreezePan((float)atof(argv[1]), (float)atof(argv[2]));
}
CCMD(ioscam_zoom)
{
	if (argv.argc() >= 2) iosCam_FreezeZoom((float)atof(argv[1]));
}
CCMD(ioscam_set)
{
	if (argv.argc() < 3)
	{
		Printf("ioscam_set kinds|selfies|freeze <n>: kinds %d, selfies %d, freeze %d\n", _iKinds, _iSelfieShots, _bFreezeOn);
		return;
	}
	int n = atoi(argv[2]);
	if (!stricmp(argv[1], "kinds")) iosCam_SetKinds(n);
	else if (!stricmp(argv[1], "selfies")) iosCam_SetSelfieShots(n);
	else if (!stricmp(argv[1], "freeze")) iosCam_SetFreezeOn(n);
}
#ifdef RAZE_GLES_RIG
// (the rig only, to have people for selfies where none stand near the
// start: moves the nearest n enemies to stand in a row ahead of the player)
CCMD(ioscam_rig_gather)
{
	auto pp = People();
	auto pa = PlayerActor();
	if (!pp || !pa || !_bGameValid) return;
	SetUnit();
	int n = argv.argc() >= 2 ? atoi(argv[1]) : 6;
	TArray<DCoreActor *> all;
	pp->collect(all);
	std::sort(all.begin(), all.end(), [=](DCoreActor *a, DCoreActor *b) {
		return (a->spr.pos - pa->spr.pos).LengthSquared() < (b->spr.pos - pa->spr.pos).LengthSquared(); });
	DVector2 fwd = _game.angles.Yaw.ToVector(), side(-fwd.Y, fwd.X);
	double cz, fz;
	calcSlope(_game.sect, _game.pos.X, _game.pos.Y, &cz, &fz);
	for (int i = 0; i < n && i < (int)all.Size(); i++)
	{
		DVector2 at = _game.pos.XY() + fwd * ((3.0 + 1.2 * (i / 3)) * _fUnit) + side * (((i % 3) - 1) * 1.3 * _fUnit);
		SetActor(all[i], DVector3(at, fz));
		all[i]->spr.Angles.Yaw = (_game.pos.XY() - at).Angle();
	}
	Printf("ioscam: gathered %d\n", min(n, (int)all.Size()));
}
#endif

CCMD(ioscam_status)
{
	Printf("ioscam: room %d pending %d frames %d, ", iosCapture_HasRoom(IOSCAPTURE_CLEAN, 1), iosCapture_IsPending(), _ctFrames);
	Printf("ioscam: stage %d, cam %d, showplayer %d, people %u, kept %u, taken %d, busy %d, pos %.1f %.1f %.1f yaw %.1f pitch %.1f\n", _iStage,
		_bCamOn, _bShowPlayer, _people.Size(), _kept.Size(), _ctTaken, iosCamera_IsBusy(), _cam.pos.X, _cam.pos.Y, _cam.pos.Z,
		_cam.angles.Yaw.Degrees(), _cam.angles.Pitch.Degrees());
}

#endif
