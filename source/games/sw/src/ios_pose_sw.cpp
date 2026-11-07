// The CAMERA's selfies in Shadow Warrior: the enemies and their poses (see
// core/ioscamera.h). An enemy's picture is its state (user.Rot: a group of
// five rotations; user.State: the frame in it), so a pose is a frame of one
// of its own action set's groups: standing, running, attacking, ducking.
// What it changes beyond spr is kept and put back.

#include "ns.h"
#include "build.h"
#include "names2.h"
#include "game.h"
#include "ioscamera.h"

#ifdef RAZE_IOSCAMERA

BEGIN_SW_NS

static bool iosCam_SWAlive(DCoreActor *a)
{
	auto act = static_cast<DSWActor *>(a);
	return act->hasU() && act->user.Health > 0;
}

static void iosCam_SWCollect(TArray<DCoreActor *> &out)
{
	SWStatIterator it(STAT_ENEMY);
	while (auto act = it.Next())
	{
		if (act->hasU() && act->user.Health > 0 && !act->user.PlayerP) out.Push(act);
	}
}

static void iosCam_SWSave(DCoreActor *a, intptr_t aux[4])
{
	auto act = static_cast<DSWActor *>(a);
	if (!act->hasU()) return;
	aux[0] = (intptr_t)act->user.Rot;
	aux[1] = (intptr_t)act->user.State;
	aux[2] = (intptr_t)act->user.StateStart;
	aux[3] = act->user.Tics;
}

static void iosCam_SWRestore(DCoreActor *a, const intptr_t aux[4])
{
	auto act = static_cast<DSWActor *>(a);
	if (!act->hasU()) return;
	act->user.Rot = (STATE **)aux[0];
	act->user.State = (STATE *)aux[1];
	act->user.StateStart = (STATE *)aux[2];
	act->user.Tics = (int)aux[3];
}

static void iosCam_SWPose(DCoreActor *a, unsigned rnd, bool calm)
{
	auto act = static_cast<DSWActor *>(a);
	if (!act->hasU() || !act->user.ActorActionSet || act->user.RotNum <= 0) return;
	auto s = act->user.ActorActionSet;
	STATE **aGroup[12];
	int n = 0;
	if (s->Stand) aGroup[n++] = s->Stand;
	if (s->Run) aGroup[n++] = s->Run;
	if (!calm)
	{
		for (int i = 0; i < MAX_ACTOR_ATTACK && n < 10; i++) if (s->Attack[i]) aGroup[n++] = s->Attack[i];
		for (int i = 0; i < MAX_ACTOR_CLOSE_ATTACK && n < 11; i++) if (s->CloseAttack[i]) aGroup[n++] = s->CloseAttack[i];
		if (s->Duck && n < 12) aGroup[n++] = s->Duck;
	}
	if (!n) return;
	STATE **g = aGroup[rnd % n];
	STATE *start = g[0];
	if (!start) return;
	// a frame along it (the drawing finds the other rotations' frame by its
	// place in the group, so only the frames that follow in order)
	STATE *st = start;
	int k = (rnd >> 8) % 6;
	for (int i = 0; i < k && st->NextState == st + 1 && st[1].Pic > 0; i++) st++;
	if (st->Pic <= 0) return;
	act->user.Rot = g;
	act->user.StateStart = start;
	act->user.State = st;
	act->spr.picnum = st->Pic;
}

static const IOSCamPeople iosCam_SWPeople = { iosCam_SWAlive, iosCam_SWCollect, iosCam_SWSave, iosCam_SWRestore, iosCam_SWPose };

const IOSCamPeople *iosCam_People() { return &iosCam_SWPeople; }

END_SW_NS

#endif
