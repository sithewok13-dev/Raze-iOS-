// The CAMERA's selfies in Blood: the enemies and their poses (see
// core/ioscamera.h). A dude's picture is a frame of one of its sequences
// (the SEQ files): its own sequences start at its dudeInfo's seqStartID,
// and a pose is a frame of its standing (0), attacking (6, 7, 8) or
// walking (9) one, where it has them. Only spr changes, which the camera
// keeps and puts back.

#include "ns.h"
#include "build.h"
#include "blood.h"
#include "ioscamera.h"

#ifdef RAZE_IOSCAMERA

BEGIN_BLD_NS

static bool iosCam_BloodAlive(DCoreActor *a)
{
	auto act = static_cast<DBloodActor *>(a);
	return act->hasX() && act->xspr.health > 0;
}

static void iosCam_BloodCollect(TArray<DCoreActor *> &out)
{
	BloodStatIterator it(kStatDude);
	while (auto act = it.Next())
	{
		if (act->IsDudeActor() && !act->IsPlayerActor() && act->hasX() && act->xspr.health > 0) out.Push(act);
	}
}

static void iosCam_BloodPose(DCoreActor *a, unsigned rnd, bool calm)
{
	auto act = static_cast<DBloodActor *>(a);
	if (!act->IsDudeActor()) return;
	static const int aAll[] = { 0, 6, 7, 8, 9 }, aCalm[] = { 0, 9 };
	const int *from = calm ? aCalm : aAll;
	const int n = calm ? 2 : 5;
	const int base = getDudeInfo(act->spr.type)->seqStartID;
	for (int k = 0; k < n; k++)
	{
		Seq *seq = getSequence(base + from[(rnd + k) % n]);
		if (!seq || seq->nFrames <= 0) continue;
		SEQFRAME *f = &seq->frames[(rnd >> 8) % seq->nFrames];
		auto tex = seqGetTexture(f);
		if (!tex.isValid()) continue;
		act->spr.setspritetexture(tex);
		if (f->palette) act->spr.pal = f->palette;
		act->spr.shade = f->shade;
		return;
	}
}

static const IOSCamPeople iosCam_BloodPeople = { iosCam_BloodAlive, iosCam_BloodCollect, nullptr, nullptr, iosCam_BloodPose };

const IOSCamPeople *iosCam_People() { return &iosCam_BloodPeople; }

END_BLD_NS

#endif
