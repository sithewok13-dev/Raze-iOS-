// The CAMERA (photos, bursts, selfies, Action Freeze, the cinematic burst),
// as the Jedi Knight and Serious Sam ports have it: the engine's side, for
// every game. ios/iosCamera.h is what the touch overlay calls; this is what
// the engine and the games' small hooks call. Built for iOS (RAZE_IOS) and
// the Linux test rig (RAZE_GLES_RIG); on the game's thread.
//
// How it works: the games draw their view through render_drawrooms, which
// keeps the last view the player saw and, while the photo camera is on,
// draws from that camera instead (no first-person weapon, no HUD, the
// player's own body shown). Selfies, Action Freeze and the cinematic burst
// hold the game still (updatePauseStatus: paused, as the menu does, music
// playing on) and put back everything they changed when they end.

#pragma once

#if defined(RAZE_IOS) || defined(RAZE_GLES_RIG)
#define RAZE_IOSCAMERA 1
#endif

#ifdef RAZE_IOSCAMERA

#include "vectors.h"
#include "tarray.h"

class DCoreActor;
struct sectortype;

// (render_drawrooms) The game's view: kept, and replaced by the photo
// camera's while it is on (then 1, and the player's body is shown)
bool iosCam_View(DCoreActor *viewer, DVector3 &pos, sectortype *&sect, DRotator &angles, float &fov);
// Whether the player's own body is drawn in this view (the games' hooks)
bool iosCam_ShowsPlayer();
// (updatePauseStatus) whether the game is held still
bool iosCam_HoldsGame();
// (GameTicker) a save, a load or a level change is about to run: whatever
// the camera is doing ends now, everything put back
void iosCam_Abort();
// (Display) whether the HUD is left out of this frame: the photo camera's
bool iosCam_HidesHud();

// A game's people for selfies (source/games/*/src/ios_pose_*.cpp)
struct IOSCamPeople
{
	// whether the player can be in a photo (alive)
	bool (*playerAlive)(DCoreActor *player);
	// the living enemies of the level (not the player)
	void (*collect)(TArray<DCoreActor *> &out);
	// keeps what pose changes beyond spr (spr is kept by the camera)
	void (*save)(DCoreActor *act, intptr_t aux[4]);
	void (*restore)(DCoreActor *act, const intptr_t aux[4]);
	// a frame of one of its own animations (rnd: a random number; calm:
	// crowded, so a standing one); may be NULL
	void (*pose)(DCoreActor *act, unsigned rnd, bool calm);
};
namespace Duke3d { const IOSCamPeople *iosCam_People(); }
namespace Blood { const IOSCamPeople *iosCam_People(); }
namespace ShadowWarrior { const IOSCamPeople *iosCam_People(); }

// The settings (iOS: the options panel, kept in NSUserDefaults; the rig:
// the ioscam_set command): what a tap takes (IOSCAPTURE_* bits), photos per
// selfie (1, 3, 5), whether Action Freeze is on
extern "C" {
int iosCam_GetKinds(void);
void iosCam_SetKinds(int kinds);
int iosCam_GetSelfieShots(void);
void iosCam_SetSelfieShots(int n);
int iosCam_GetFreezeOn(void);
void iosCam_SetFreezeOn(int on);

// Action Freeze's moves (iOS: iosPhotos.mm's gestures; the rig: commands)
int iosCam_IsFrozen(void);
void iosCam_FreezeOrbit(float yawDeg, float pitchDeg);
void iosCam_FreezePan(float right, float down);
void iosCam_FreezeZoom(float factor);
float iosCam_FreezeZoomNow(void); // the lens's zoom (1: none)
void iosCam_FreezeEnd(void);
// What the camera is doing (0: nothing, 1: selfie, 2: freeze, 3: cinema)
int iosCam_Stage(void);
// Photos taken so far in this selfie or cinematic burst
int iosCam_NumTaken(void);

// (iosPhotos) the iOS side shows its Action Freeze controls while frozen
void iosPhotos_FreezeShown(int bOn);
// (iosPhotos) once, as the first frame is drawn: the remembered settings
void iosPhotos_Init(void);
}

#endif
