/*
** IOSGame.cpp: the touch controls' game side (see IOSGame.h, IOSTouch.h)
**
** Once a frame it tells the overlay what the game is doing (playing, the
** console, paused, or nothing to show), what the player has for the weapon
** wheel, and carries out what the player asked for (the menu, the console,
** quick save and load, the cheat). In the input it puts the stick, the
** buttons, the look and the tilt aiming straight into the input bits the
** games read, whatever keys are bound.
*/

#include "IOSNet.h"
#include "IOSGame.h"
#include "IOSPad.h"
#include "iosCamera.h"

#include <sys/stat.h>

#include <SDL.h>

#include "gamecontrol.h"
#include "gameinput.h"
#include "inputstate.h"
#include "c_console.h"
#include "c_dispatch.h"
#include "c_cvars.h"
#include "d_event.h"
#include "d_eventbase.h"
#include "menu.h"
#include "mapinfo.h"
#include "filesystem.h"
#include "savegamemanager.h"
#include "cmdlib.h"
#include "printf.h"
#include "keydef.h"
#include "dikeys.h"
#include "gamestate.h"
#include "savegamehelp.h"
#include "i_interface.h"
#include "texturemanager.h"
#include "buildtiles.h"
#include "bitmap.h"
#include "s_soundinternal.h"

EXTERN_CVAR(Float, m_sensitivity_x)
EXTERN_CVAR(Float, m_sensitivity_y)
EXTERN_CVAR(Bool, invertmouse)
EXTERN_CVAR(Bool, invertmousex)
EXTERN_CVAR(Int, quicksavecount)
EXTERN_CVAR(Bool, cl_noexitscreens)
EXTERN_CVAR(Bool, cl_nostartscreens)

extern TArray<TPointer<MapRecord>> mapList;
extern bool pausedWithKey;
extern int chatmodeon;
extern int gametic;
bool CheckCheatmode(bool printmsg, bool sponly);

static const IOSGamePart* Part()
{
	if (isDukeEngine()) return &iosDukePart;
	if (isBlood()) return &iosBloodPart;
	if (isSWALL()) return &iosSWPart;
	if (isExhumed()) return &iosExhumedPart;
	return nullptr;
}

// What the overlay shows: the game being played (no menu, no console, no
// typing a message), the console over it, the game paused with the pause
// key, or nothing (menus, cutscenes, the title screen, loading)
static int TouchMode()
{
	if (gamestate != GS_LEVEL || M_Active()) return IOSTOUCH_HIDDEN;
	if (ConsoleState == c_down || ConsoleState == c_falling) return IOSTOUCH_CONSOLE;
	if (chatmodeon) return IOSTOUCH_HIDDEN;
	if (pausedWithKey) return IOSTOUCH_PAUSED;
	return IOSTOUCH_GAMEPLAY;
}

//---------------------------------------------------------------------------
//
// The cheat's list of levels: the game's own, in their order, the ones
// whose map is there (no user maps)
//
//---------------------------------------------------------------------------

static TArray<MapRecord*> cheatLevels;

static void FindLevels()
{
	cheatLevels.Clear();
	for (auto& map : mapList)
	{
		if (map.Data() == nullptr || (map->flags & MI_USERMAP) || map->levelNumber <= 0 || map->fileName.IsEmpty()) continue;
		if (fileSystem.FindFile(map->fileName.GetChars()) < 0) continue;
		cheatLevels.Push(map.Data());
	}
	// (in the game's order: by episode, then level)
	std::stable_sort(cheatLevels.begin(), cheatLevels.end(), [](MapRecord* a, MapRecord* b) { return a->levelNumber < b->levelNumber; });
}

int IOSGame_LevelInfo(int iLevel, char* strName, int ctName, char* strFile, int ctFile)
{
	if (iLevel < 1 || iLevel > (int)cheatLevels.Size()) return 0;
	auto map = cheatLevels[iLevel - 1];
	snprintf(strName, ctName, "%s", map->DisplayName());
	snprintf(strFile, ctFile, "%s", map->fileName.GetChars());
	return 1;
}

int IOSGame_CurrentLevel()
{
	for (unsigned i = 0; i < cheatLevels.Size(); i++)
	{
		if (cheatLevels[i] == currentLevel) return i + 1;
	}
	return 0;
}

//---------------------------------------------------------------------------
//
// The cheat, on Raze's own: god mode and "give all", again at each new
// level while it is on, and the ammo kept full
//
//---------------------------------------------------------------------------

static bool cheatOn = false;
static bool godOffLevel = false; // a level came: god mode off once it is going, unless the cheat is on
static MapRecord* cheatLevel = nullptr;
static int cheatLevelCount = 0; // frames into the level (it gives once the level is going)
static int ammoTimer = 0;

// The cheat works in a single-player level being played -- and only where
// the game's own cheats do (Raze's CheckCheatmode: cl_blockcheats, Shadow
// Warrior's top skill, Redneck Rampage Rides Again's no-cheat levels...)
static bool CheatAllowed()
{
	return !netgame && gamestate == GS_LEVEL && currentLevel != nullptr && Part() != nullptr && !CheckCheatmode(false, true);
}

// Why not, for the message (nullptr: it is allowed)
static const char* CheatRefusal()
{
	if (netgame) return "No cheat in a network game";
	if (gamestate != GS_LEVEL || currentLevel == nullptr || Part() == nullptr) return "The cheat works in a level being played";
	if (CheckCheatmode(false, true)) return "The game doesn't allow cheats here";
	return nullptr;
}

static void CheatGive()
{
	C_DoCommand("godon");
	C_DoCommand("give all");
}

static void CheatFrame()
{
	if (!cheatOn || !CheatAllowed()) return;
	if (cheatLevel != currentLevel)
	{
		cheatLevel = currentLevel;
		cheatLevelCount = 0;
	}
	// a new level (or the same one again, after dying): everything again,
	// once it has run a moment (the player is made as the level starts)
	if (cheatLevelCount >= 0 && ++cheatLevelCount > 10)
	{
		cheatLevelCount = -1;
		CheatGive();
	}
	// the ammo, kept full (a few times a second)
	if (++ammoTimer >= 15)
	{
		ammoTimer = 0;
		auto part = Part();
		if (part && part->FillAmmo && !paused) part->FillAmmo();
	}
}

// The word typed in the console: "sithewok" switches the cheat, "sithewok
// on" / "sithewok off" set it (the overlay says so, and shows or hides CHEAT)
CCMD(sithewok)
{
	bool want = !IOSTouch_CheatOn();
	if (argv.argc() >= 2) want = !stricmp(argv[1], "on");
	if (want != (IOSTouch_CheatOn() != 0)) IOSTouch_CheatTyped();
}

//---------------------------------------------------------------------------
//
// The weapon wheel's and CHEAT's pictures, from the game's own art (the
// player's data, read now: nothing of it is in the app): each part names
// the textures (its HUD's weapon icons, pickup sprites, a tile by number
// as "#<n>"), the first one there is taken, cropped to its pixels, in the
// game's palette, and scaled to fit IOSTOUCH_ICON_MAX: down by averaging,
// up by a whole number (sharp pixels)
//
//---------------------------------------------------------------------------

static FGameTexture* FindIconTexture(const char* const* names)
{
	for (; names && *names; names++)
	{
		FGameTexture* tex = nullptr;
		if (**names == '#') tex = tileGetTexture(atoi(*names + 1));
		else
		{
			auto id = TexMan.CheckForTexture(*names, ETextureType::Any);
			if (id.isValid()) tex = TexMan.GetGameTexture(id);
		}
		if (tex && tex->isValid() && tex->GetTexture() && tex->GetTexelWidth() > 0 && tex->GetTexelHeight() > 0) return tex;
	}
	return nullptr;
}

static bool MakeIcon(FGameTexture* tex, TArray<uint8_t>& out, int& ow, int& oh)
{
	if (!tex) return false;
	FBitmap bmp = tex->GetTexture()->GetBgraBitmap(nullptr);
	const int w = bmp.GetWidth(), h = bmp.GetHeight(), pitch = bmp.GetPitch();
	const uint8_t* px = bmp.GetPixels();
	if (!px || w <= 0 || h <= 0) return false;
	// (cropped to what isn't see-through)
	int x0 = w, y0 = h, x1 = -1, y1 = -1;
	for (int y = 0; y < h; y++)
		for (int x = 0; x < w; x++)
			if (px[y * pitch + x * 4 + 3] > 8)
			{
				x0 = min(x0, x); x1 = max(x1, x);
				y0 = min(y0, y); y1 = max(y1, y);
			}
	if (x1 < x0 || y1 < y0) return false;
	const int cw = x1 - x0 + 1, ch = y1 - y0 + 1, big = max(cw, ch);
	if (big <= IOSTOUCH_ICON_MAX)
	{
		const int k = max(1, IOSTOUCH_ICON_MAX / big);
		ow = cw * k;
		oh = ch * k;
		out.Resize(ow * oh * 4);
		for (int y = 0; y < oh; y++)
			for (int x = 0; x < ow; x++)
			{
				const uint8_t* p = px + (y0 + y / k) * pitch + (x0 + x / k) * 4;
				uint8_t* q = &out[(y * ow + x) * 4];
				q[0] = p[2]; q[1] = p[1]; q[2] = p[0]; q[3] = p[3]; // (BGRA to RGBA)
			}
		return true;
	}
	ow = max(1, cw * IOSTOUCH_ICON_MAX / big);
	oh = max(1, ch * IOSTOUCH_ICON_MAX / big);
	out.Resize(ow * oh * 4);
	for (int y = 0; y < oh; y++)
		for (int x = 0; x < ow; x++)
		{
			// the average of the texels under it, weighted by their alpha
			const int sx0 = x0 + x * cw / ow, sx1 = x0 + max((x + 1) * cw / ow, x * cw / ow + 1);
			const int sy0 = y0 + y * ch / oh, sy1 = y0 + max((y + 1) * ch / oh, y * ch / oh + 1);
			double r = 0, g = 0, b = 0, a = 0;
			int n = 0;
			for (int sy = sy0; sy < sy1; sy++)
				for (int sx = sx0; sx < sx1; sx++, n++)
				{
					const uint8_t* p = px + sy * pitch + sx * 4;
					const double al = p[3];
					r += p[2] * al; g += p[1] * al; b += p[0] * al; a += al;
				}
			uint8_t* q = &out[(y * ow + x) * 4];
			if (a > 0)
			{
				q[0] = (uint8_t)(r / a + 0.5); q[1] = (uint8_t)(g / a + 0.5); q[2] = (uint8_t)(b / a + 0.5);
			}
			else q[0] = q[1] = q[2] = 0;
			q[3] = (uint8_t)(a / max(n, 1) + 0.5);
		}
	return true;
}

// Once a frame: the pictures the overlay wants (each once for the
// process: Raze plays one game a run)
static void FeedIcons(const IOSGamePart* part)
{
	if (!part) return;
	TArray<uint8_t> px;
	int w = 0, h = 0;
	const unsigned wanted = IOSTouch_WantedIcons();
	for (int i = 0; i < IOSTOUCH_WPN_MAX; i++)
	{
		if (!(wanted & (1u << i))) continue;
		if (part->Icon && MakeIcon(FindIconTexture(part->Icon(i)), px, w, h)) IOSTouch_SetWeaponIcon(i, px.Data(), w, h);
		else IOSTouch_SetWeaponIcon(i, nullptr, 0, 0); // (its name shows)
	}
	if (IOSTouch_WantsCheatIcon())
	{
		if (part->CheatIcon && MakeIcon(FindIconTexture(part->CheatIcon()), px, w, h)) IOSTouch_SetCheatIcon(px.Data(), w, h);
		else IOSTouch_SetCheatIcon(nullptr, 0, 0); // (the drawn emblem stays)
	}
}

//---------------------------------------------------------------------------
//
// Quick save and quick load: the rotating quick saves (no menu, no
// question), and the newest of them
//
//---------------------------------------------------------------------------

// (never while the camera is at work: a selfie or Action Freeze holds the
// game's actors posed, which a load or a level change would free and a save
// would keep)
static bool CameraBusy()
{
	if (!iosCamera_IsBusy()) return false;
	IOSTouch_ShowMessage("Camera busy", 1.5);
	return true;
}

static bool QuickSave()
{
	if (netgame || CameraBusy()) return false;
	auto part = Part();
	if (!gi->CanSave() || (part && part->Alive && !part->Alive()))
	{
		IOSTouch_ShowMessage("Can't save now", 2.0);
		return false;
	}
	C_DoCommand("rotatingquicksave");
	IOSTouch_ShowMessage("Quick save", 1.5);
	return true;
}

// The newest of the quick saves in this game's own save folder (the
// rotation's number, quicksavenum, is shared by every game)
static FString NewestQuickSave()
{
	FString best;
	time_t tBest = 0;
	const int count = max((int)quicksavecount, 1);
	for (int n = 0; n < count && n < 100; n++)
	{
		auto name = G_BuildSaveName(FStringf("quick%04d", n).GetChars());
		struct stat st;
		if (stat(name.GetChars(), &st) != 0) continue;
		if (best.IsEmpty() || st.st_mtime > tBest)
		{
			best = name;
			tBest = st.st_mtime;
		}
	}
	return best;
}

static bool QuickLoad()
{
	if (netgame || CameraBusy()) return false;
	auto name = NewestQuickSave();
	if (name.IsEmpty())
	{
		IOSTouch_ShowMessage("No quick save yet (hold QUICK SAVE)", 3.0);
		return false;
	}
	G_LoadGame(name.GetChars());
	IOSTouch_ShowMessage("Quick load", 1.5);
	return true;
}

// The game controller's Back held (ios/IOSPad.cpp): the same quick save and
// load, while a level is being played (not paused, no console)
bool IOSGame_PadInLevel()
{
	return TouchMode() == IOSTOUCH_GAMEPLAY;
}

bool IOSGame_PadQuickSave()
{
	return IOSGame_PadInLevel() && QuickSave();
}

bool IOSGame_PadQuickLoad()
{
	return IOSGame_PadInLevel() && QuickLoad();
}

//---------------------------------------------------------------------------
//
// Once a frame
//
//---------------------------------------------------------------------------

static void PostKey(int key)
{
	event_t ev = {};
	ev.type = EV_KeyDown;
	ev.data1 = key;
	D_PostEvent(&ev);
	ev.type = EV_KeyUp;
	D_PostEvent(&ev);
}

// The level picked from the cheat's list: the exit and start screens are
// skipped (cl_noexitscreens, cl_nostartscreens) until it is there, then set
// back. What they were is kept in ios_levelscreens too (archived: bit 0 exit,
// bit 1 start; -1 nothing to put back), so they are put back even if the
// app ended in between.
CVAR(Int, ios_levelscreens, -1, CVAR_ARCHIVE | CVAR_GLOBALCONFIG | CVAR_NOSET)

static void RestoreLevelScreens()
{
	const int v = ios_levelscreens;
	if (v < 0) return;
	cl_noexitscreens = (v & 1) != 0;
	cl_nostartscreens = (v & 2) != 0;
	UCVarValue val;
	val.Int = -1;
	ios_levelscreens->ForceSet(val, CVAR_Int);
}

static void SkipLevelScreens()
{
	if (ios_levelscreens < 0)
	{
		UCVarValue val;
		val.Int = (cl_noexitscreens ? 1 : 0) | (cl_nostartscreens ? 2 : 0);
		ios_levelscreens->ForceSet(val, CVAR_Int);
	}
	cl_noexitscreens = true;
	cl_nostartscreens = true;
}

// Levels started, restarted or loaded (GameTicker's ga_level), and the
// count the frame last saw
static unsigned int levelStarts = 0, levelStartsSeen = 0;
static unsigned int framesDrawn = 0;

void IOSGame_LevelStarted()
{
	levelStarts++;
	auto part = Part();
	if (part && part->Reset) part->Reset();
}

// For the log (Documents/raze-log.txt): the game's state each time it
// changes, so a report of the game stuck says where it was
static void LogStateChanges(int mode)
{
	static FString last;
	FString now;
	now.Format("gs %d ga %d menu %d paused %d/%d held %d touch %d level %s", (int)gamestate, (int)gameaction, (int)M_Active(),
		paused, (int)pauseext, (int)IOSTouch_HoldsGame(), mode, currentLevel ? currentLevel->labelName.GetChars() : "-");
	if (now.Compare(last) != 0)
	{
		Printf(PRINT_NONOTIFY, "iOS: state %s\n", now.GetChars());
		last = now;
	}
}

void IOSGame_Frame()
{
	framesDrawn++;
	const int mode = TouchMode();
	LogStateChanges(mode);
	const IOSGamePart* part = Part();

	// (the level screens left skipped by an earlier run)
	if (framesDrawn == 1) RestoreLevelScreens();

	// a level started, restarted or loaded: the world changed
	if (levelStarts != levelStartsSeen)
	{
		levelStartsSeen = levelStarts;
		RestoreLevelScreens();
		if (cheatLevels.Size() == 0) FindLevels();
		cheatLevel = nullptr; // (the cheat gives again)
		// god mode brought back by a save made with the cheat on, the cheat
		// off now: off (god mode only ever comes from the cheat here)
		if (!cheatOn) godOffLevel = true;
	}
	if (godOffLevel && gamestate == GS_LEVEL && gameaction == ga_nothing)
	{
		godOffLevel = false;
		if (!cheatOn && part && part->GodOn && part->GodOn() && CheatAllowed()) C_DoCommand("godoff");
	}

	IOSTouchWeapons wpn = {};
	IOSTouchHud hud = {};
	if (mode != IOSTOUCH_HIDDEN && part)
	{
		part->Weapons(&wpn);
		part->State(&hud);
		hud.bValid = 1;
	}
	hud.bNoSaves = netgame; // (QUICK SAVE says when it can't save; QUICK LOAD works dead too)
	hud.bCheatAllowed = CheatAllowed();
	hud.strCheatRefusal = hud.bCheatAllowed ? nullptr : CheatRefusal();
	// The tray's LEVEL: every game's own levels, in single player whether or
	// not the cheat is on (the owner's choice)
	const bool levelPick = !netgame && gamestate == GS_LEVEL && currentLevel != nullptr && part != nullptr;
	if (levelPick && cheatLevels.Size() == 0) FindLevels();
	hud.ctLevels = levelPick ? cheatLevels.Size() : 0;
	hud.uWorld = levelStarts;
	if (part && part->PickTick) part->PickTick();
	IOSTouch_SetWeapons(&wpn);
	if (mode != IOSTOUCH_HIDDEN) FeedIcons(part);

	const int req = IOSTouch_Update(SDL_GL_GetCurrentWindow(), mode, &hud, framesDrawn);

	if (req & IOSTOUCH_REQ_MENU)
	{
		if (mode == IOSTOUCH_CONSOLE) C_ToggleConsole();
		else PostKey(KEY_ESCAPE);
	}
	if (req & IOSTOUCH_REQ_CONSOLE) C_ToggleConsole();
	if ((req & IOSTOUCH_REQ_QUICKSAVE) && mode == IOSTOUCH_GAMEPLAY) QuickSave();
	else if ((req & IOSTOUCH_REQ_QUICKLOAD) && mode == IOSTOUCH_GAMEPLAY) QuickLoad();
	if ((req & IOSTOUCH_REQ_RESUME) && pausedWithKey) C_DoCommand("pause");
	if (req & IOSTOUCH_REQ_INVPREV) gameInput.SendAction(SB_INVPREV);
	if (req & IOSTOUCH_REQ_INVNEXT) gameInput.SendAction(SB_INVNEXT);
	// (flying and noclip before the cheat goes off: Shadow Warrior flies only in god mode)
	if (CheatAllowed())
	{
		if (req & IOSTOUCH_REQ_NOCLIP) C_DoCommand("noclip");
		if (req & IOSTOUCH_REQ_FLY) C_DoCommand("fly");
	}
	if (req & IOSTOUCH_REQ_CHEATON)
	{
		// the game's own line for it (only when it can come on here)
		if (!cheatOn && CheatAllowed() && part && part->CheatSound) part->CheatSound();
		cheatOn = true;
		cheatLevel = nullptr;
		godOffLevel = false;
	}
	if (req & IOSTOUCH_REQ_CHEATOFF)
	{
		cheatOn = false;
		if (CheatAllowed()) C_DoCommand("godoff");
	}
	if (levelPick)
	{
		if (req & IOSTOUCH_REQ_LEVEL)
		{
			const int i = IOSTouch_TakeLevelPick();
			if (i >= 1 && i <= (int)cheatLevels.Size() && gameaction == ga_nothing && !CameraBusy())
			{
				// as if the level were finished, to the one picked (so each
				// game carries the player over as it does), with the exit
				// and start screens skipped until the new level is there
				Printf(PRINT_NONOTIFY, "iOS: level %d picked: %s\n", i, cheatLevels[i - 1]->labelName.GetChars());
				SkipLevelScreens();
				ChangeLevel(cheatLevels[i - 1], g_nextskill);
			}
			else
			{
				Printf(PRINT_NONOTIFY, "iOS: level %d not picked (ga %d)\n", i, (int)gameaction);
				if (!iosCamera_IsBusy()) IOSTouch_CheatLevelFailed();
			}
		}
	}
	CheatFrame();
}

//---------------------------------------------------------------------------
//
// The input
//
//---------------------------------------------------------------------------

static bool useWasDown = false;
// Tilt aiming taken this read, for processMovement (degrees, the game's way round)
static double gyroYaw = 0, gyroPitch = 0;

void IOSGame_Input(float* joyAxes, bool bTic)
{
	const IOSGamePart* part = Part();

	// tilt aiming: taken every read, so what processMovement doesn't use
	// (paused, driving: RRRA's vehicles turn in processVehicle) is dropped
	// instead of piling up to spin the view later
	{
		float yaw, pitch;
		IOSTouch_TakeGyro(&yaw, &pitch);
		// (the overlay's + left and + up; the game's + right and + down)
		gyroYaw = paused ? 0.0 : -yaw;
		gyroPitch = paused ? 0.0 : -pitch;
	}

	// the stick, as a gamepad's left stick (forward +, the side axis - to the right)
	float mx, my;
	IOSTouch_ReadMove(&mx, &my);
	joyAxes[JOYAXIS_Forward] += my;
	joyAxes[JOYAXIS_Side] -= mx;

	// the look, as the mouse (its sensitivity and invert settings apply)
	float dx, dy;
	IOSTouch_TakeLook(&dx, &dy);
	if (dx != 0.f || dy != 0.f)
	{
		float x = dx * m_sensitivity_x, y = -dy * m_sensitivity_y;
		if (invertmousex) x = -x;
		if (invertmouse) y = -y;
		gameInput.MouseAddToPos(x, y);
	}

	if (!bTic) return;

	IOSTouchInput in;
	IOSTouch_ReadInput(&in);
	ESyncBits actions = ESyncBits::FromInt(0);
	const unsigned b = in.ulButtons;
	if (b & IOSTOUCH_FIRE) actions |= SB_FIRE;
	if (b & IOSTOUCH_JUMP) actions |= SB_JUMP;
	if (b & IOSTOUCH_CROUCH) actions |= SB_CROUCH;
	// USE: held, or one press for the games that take it so
	const bool useDown = (b & IOSTOUCH_USE) != 0;
	if (useDown && (!part || !part->bUseOnce || !useWasDown)) actions |= SB_OPEN;
	useWasDown = useDown;
	if (b & IOSTOUCH_SECONDARY)
	{
		if (isBlood()) actions |= SB_ALTFIRE;
		else if (isDuke() || isNam() || isWW2GI()) actions |= SB_QUICK_KICK;
	}
	if (b & IOSTOUCH_ITEM) actions |= SB_INVUSE;
	if (b & IOSTOUCH_NEXTWEAPON) gameInput.SendWeapon(WeaponSel_Next);
	else if (b & IOSTOUCH_PREVWEAPON) gameInput.SendWeapon(WeaponSel_Prev);
	if (actions) gameInput.SendAction(actions);
	if (in.iSelectWeapon >= 0 && part) part->Pick(in.iSelectWeapon);
}

void IOSGame_TakeGyro(double* pYaw, double* pPitch)
{
	*pYaw = gyroYaw;
	*pPitch = gyroPitch;
	gyroYaw = gyroPitch = 0.0;
}

bool IOSGame_HoldsGame()
{
	return IOSTouch_HoldsGame() != 0;
}

void IOSGame_HudFrame(double w, double h, double* pFrame)
{
	float f[4];
	IOSTouch_GetHudFrame(f);
	pFrame[0] = f[0] * w;
	pFrame[1] = f[1] * h;
	pFrame[2] = f[2] * w;
	pFrame[3] = f[3] * h;
}

#ifndef RAZE_IOS
//---------------------------------------------------------------------------
//
// The Linux test rig's own (RAZE_TOUCH_RIG_SOURCE): a console command from
// its script, and where the player is, for its log
//
//---------------------------------------------------------------------------

// LAN games: the hosts waiting for players on this Wi-Fi (the search the
// iOS start screen makes), in the console: net_scan
CCMD(net_scan)
{
	if (netgame) return;	// (it waits 1.5 s: never in a network game)
	IOSNetHost hosts[IOSNET_MAXHOSTS];
	char mine[64] = "";
	IOSNet_WifiAddress(mine, sizeof(mine));
	const int n = IOSNet_Scan(hosts, IOSNET_MAXHOSTS, 1.5);
	Printf("net_scan: this machine %s, %d host(s)\n", mine, n);
	for (int i = 0; i < n; i++)
		Printf("net_scan: %s | %s | %s | %d/%d\n", hosts[i].strAddress, hosts[i].strGame, hosts[i].strMode, hosts[i].ctPresent, hosts[i].ctWanted);
}

extern "C" void IOSGame_RigCommand(const char* cmd)
{
	C_DoCommand(cmd);
}

// The pictures as the overlay gets them, as raw files (4-byte width, height,
// then RGBA) in argv[1]: ios_icondump <dir> (the wheel's and CHEAT's), and
// ios_tiledump <dir> <first> <last> (tiles, to look for pictures)
static void DumpIcon(const char* dir, const char* name, FGameTexture* tex)
{
	TArray<uint8_t> px;
	int w = 0, h = 0;
	if (!MakeIcon(tex, px, w, h)) return;
	FILE* f = fopen(FStringf("%s/%s.rgba", dir, name).GetChars(), "wb");
	if (!f) return;
	int32_t wh[2] = { w, h };
	fwrite(wh, 4, 2, f);
	fwrite(px.Data(), 1, px.Size(), f);
	fclose(f);
}

CCMD(ios_icondump)
{
	auto part = Part();
	if (argv.argc() < 2 || !part) return;
	for (int i = 0; i < IOSTOUCH_WPN_MAX; i++)
	{
		auto names = part->Icon ? part->Icon(i) : nullptr;
		auto tex = FindIconTexture(names);
		Printf("icon %d: %s -> %s\n", i, names && names[0] ? names[0] : "-", tex ? tex->GetName().GetChars() : "none");
		DumpIcon(argv[1], FStringf("w%02d", i).GetChars(), tex);
	}
	auto names = part->CheatIcon ? part->CheatIcon() : nullptr;
	auto tex = FindIconTexture(names);
	Printf("icon cheat: %s -> %s\n", names && names[0] ? names[0] : "-", tex ? tex->GetName().GetChars() : "none");
	DumpIcon(argv[1], "cheat", tex);
}

CCMD(ios_tiledump)
{
	if (argv.argc() < 4) return;
	for (int t = atoi(argv[2]); t <= atoi(argv[3]); t++) DumpIcon(argv[1], FStringf("t%05d", t).GetChars(), tileGetTexture(t));
}

// What plays now, with the file it comes from
CCMD(ios_rigsounds)
{
	soundEngine->EnumerateChannels([](FSoundChan* chan)
	{
		auto sfx = soundEngine->GetSfx(chan->SoundID);
		Printf("rig sound playing: %s (%s)\n", soundEngine->GetSoundName(chan->OrgID),
			sfx && sfx->lumpnum >= 0 ? fileSystem.GetFileFullName(sfx->lumpnum) : "-");
		return 0;
	});
}

// The cheat's line, as when it comes on
CCMD(ios_cheatsound)
{
	auto part = Part();
	if (part && part->CheatSound) part->CheatSound();
	C_DoCommand("ios_rigsounds");
}

// The menu open, how deep, and the item picked in it (the pad's tests)
CCMD(ios_rigmenu)
{
	int depth = 0;
	for (DMenu* m = CurrentMenu; m; m = m->mParentMenu) depth++;
	int sel = -99;
	FString desc;
	if (CurrentMenu)
	{
		auto f = dyn_cast<PField>(CurrentMenu->GetClass()->FindSymbol("mDesc", true));
		if (f)
		{
			auto d = *(DMenuDescriptor**)((uint8_t*)CurrentMenu + f->Offset);
			if (d)
			{
				desc = d->mMenuName.GetChars();
				if (auto l = dyn_cast<DListMenuDescriptor>(d)) sel = l->mSelectedItem;
				else if (auto o = dyn_cast<DOptionMenuDescriptor>(d)) sel = o->mSelectedItem;
			}
		}
	}
	Printf("rigmenu active %d depth %d class %s desc %s sel %d\n", (int)M_Active(), depth,
		CurrentMenu ? CurrentMenu->GetClass()->TypeName.GetChars() : "-", desc.GetChars(), sel);
}

CCMD(ios_rigpos)
{
	auto pl = PlayerArray[myconnectindex];
	auto act = pl ? pl->GetActor() : nullptr;
	if (!act) return;
	Printf("rigpos tic %d pauseext %d active %d menu %d gs %d %.1f %.1f %.1f yaw %.2f pitch %.2f paused %d level %s\n", gametic, (int)pauseext, (int)AppActive, (int)M_Active(), (int)gamestate, act->spr.pos.X, act->spr.pos.Y, act->spr.pos.Z,
		act->spr.Angles.Yaw.Degrees(), act->spr.Angles.Pitch.Degrees(), paused, currentLevel ? currentLevel->labelName.GetChars() : "-");
}
#endif
