// The CAMERA's selfies in Duke Nukem 3D and Redneck Rampage: the enemies
// and their poses (see core/ioscamera.h). An enemy's frame comes from its
// action (curAction, curframe: the game's scripts set them), so a pose is
// one of the actions its own kind has, at one of its frames. The game's
// scripts don't say which actions are whose; they are named for the enemy
// ("ATROOPSTAND", "ATROOPSHOOT", ...), so a kind's are the ones its enemies
// in the level are using now and any others named the same way, less the
// dying, dead, frozen and hiding ones.

#include "ns.h"
#include "duke3d.h"
#include "dukeactor.h"
#include "texturemanager.h"
#include "ioscamera.h"

#ifdef RAZE_IOSCAMERA

BEGIN_DUKE_NS

static bool iosCam_DukeAlive(DCoreActor *a)
{
	auto act = static_cast<DDukeActor *>(a);
	return act->spr.extra > 0;
}

static void iosCam_DukeCollect(TArray<DCoreActor *> &out)
{
	for (int stat : { STAT_ACTOR, STAT_ZOMBIEACTOR })
	{
		DukeStatIterator it(stat);
		while (auto act = it.Next())
		{
			if (!act->isPlayer() && badguy(act) && act->spr.extra > 0 && act->curAction) out.Push(act);
		}
	}
}

static void iosCam_DukeSave(DCoreActor *a, intptr_t aux[4])
{
	auto act = static_cast<DDukeActor *>(a);
	aux[0] = (intptr_t)act->curAction;
	aux[1] = act->curframe;
	aux[2] = act->actioncounter;
}

static void iosCam_DukeRestore(DCoreActor *a, const intptr_t aux[4])
{
	auto act = static_cast<DDukeActor *>(a);
	act->curAction = (ActorAction *)aux[0];
	act->curframe = (int16_t)aux[1];
	act->actioncounter = (int16_t)aux[2];
}

// Not a pose: what dying, lying, frozen, hit or hiding looks like
static bool iosCam_BadName(const char *n)
{
	static const char *aBad[] = { "DEAD", "DIE", "DYING", "FROZ", "LYING", "LAY", "GROW", "HIDE", "REAPPEAR", "SHRUNK", "SHRINK",
		"ILL", "SUFFER", "PLAYING", "FLINTCH", "PAIN", "HIT", "SQUISH", "EXPLOD", "BURN", "GIB", "FALL", "SLEEP", "WAIT", "SPAWN",
		"DORMANT", "CORPSE", "TORN", "SPLIT", "MELT", "THAW" };
	for (auto b : aBad) if (strstr(n, b)) return true;
	return false;
}

static bool iosCam_CalmName(const char *n)
{
	return strstr(n, "STAND") || strstr(n, "IDLE") || strstr(n, "WALK") || strstr(n, "LOOK");
}

// The start of an action's name that names the enemy ("ATROOP" of
// "ATROOPWALKING"): the part the kind's actions in use have in common, or
// one name less the action it says
static FString iosCam_Stem(const TArray<FString> &names)
{
	if (names.Size() == 0) return "";
	FString stem = names[0];
	for (unsigned i = 1; i < names.Size(); i++)
	{
		unsigned n = 0;
		while (n < stem.Len() && n < names[i].Len() && stem[n] == names[i][n]) n++;
		stem.Truncate(n);
	}
	if (names.Size() > 1) return stem.Len() >= 4 ? stem : FString("");
	static const char *aWhat[] = { "WALKINGBACK", "WALKING", "WALKBACK", "WALK", "RUNNING", "RUN", "STAYSTAND", "STAND", "SHOOTING",
		"SHOOT", "DUCKSHOOT", "DUCK", "JUMP", "FLYING", "FLY", "IDLE", "ATTACK", "SEEK", "LOOK", "FIRE", "SPIN", "SWIM", "CHASE",
		"SCREAM", "STRAFE", "BITE", "SLIDE", "THINK", "FRONT", "BACK" };
	for (auto w : aWhat)
	{
		size_t l = strlen(w);
		if (stem.Len() > l + 2 && !strcmp(stem.GetChars() + stem.Len() - l, w))
		{
			stem.Truncate(stem.Len() - l);
			return stem.Len() >= 3 ? stem : FString("");
		}
	}
	return "";
}

// Whether the action's first frame is a picture the game has
static bool iosCam_HasFrames(DDukeActor *act, const ActorAction &a)
{
	if (a.numframes <= 0) return false;
	int base = act->spr.spritetexture().GetIndex() + a.offset;
	auto tex = TexMan.GameByIndex(base);
	return tex && tex->isValid();
}

static void iosCam_DukePose(DCoreActor *a, unsigned rnd, bool calm)
{
	auto act = static_cast<DDukeActor *>(a);
	if (!act->curAction || (act->flags2 & SFLAG2_DONTANIMATE)) return;
	const int tex = act->spr.spritetexture().GetIndex();
	// the actions this kind uses now
	TArray<ActorAction *> seen;
	for (int stat : { STAT_ACTOR, STAT_ZOMBIEACTOR })
	{
		DukeStatIterator it(stat);
		while (auto o = it.Next())
		{
			auto ca = o->curAction;
			if (!ca || ca == &actions[0] || ca->name == NAME_None || o->GetClass() != act->GetClass() || o->spr.spritetexture().GetIndex() != tex)
				continue;
			if (seen.Find(ca) == seen.Size()) seen.Push(ca);
		}
	}
	TArray<FString> names;
	for (auto s : seen)
	{
		FString n = s->name.GetChars();
		n.ToUpper();
		names.Push(n);
	}
	FString stem = iosCam_Stem(names);
	// ...and those named as its own
	TArray<ActorAction *> cand, calmCand;
	for (unsigned i = 1; i < actions.Size(); i++)
	{
		auto &ac = actions[i];
		if (ac.name == NAME_None) continue;
		FString n = ac.name.GetChars();
		n.ToUpper();
		bool own = seen.Find(&ac) < seen.Size() || (stem.Len() && !strncmp(n.GetChars(), stem.GetChars(), stem.Len()));
		if (!own || iosCam_BadName(n.GetChars()) || !iosCam_HasFrames(act, ac)) continue;
		cand.Push(&ac);
		if (iosCam_CalmName(n.GetChars())) calmCand.Push(&ac);
	}
	auto &from = (calm && calmCand.Size()) ? calmCand : cand;
	if (from.Size() == 0) return;
	ActorAction *pick = from[rnd % from.Size()];
	act->curAction = pick;
	int frames = max<int>(pick->numframes, 1);
	int inc = pick->increment ? pick->increment : 1;
	act->curframe = (int16_t)(((rnd >> 8) % frames) * inc);
	act->actioncounter = 0;
}

static const IOSCamPeople iosCam_DukePeople = { iosCam_DukeAlive, iosCam_DukeCollect, iosCam_DukeSave, iosCam_DukeRestore, iosCam_DukePose };

const IOSCamPeople *iosCam_People() { return &iosCam_DukePeople; }

END_DUKE_NS

#endif
