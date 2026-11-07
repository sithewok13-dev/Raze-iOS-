// The CAMERA button's frame grabs (as the Jedi Knight and Serious Sam ports):
// a request for the next frame, read back from GL at two points of it --
// once the 3D view and the first-person weapon are drawn (clean), and once
// the HUD is too (HUD) -- and handed to iosPhotos to save. A budget keeps
// the images waiting to be saved within a few screens' worth. Plain C, on
// the game's thread (which is the main thread on iOS). The Linux test rig
// drives this very code.

#ifndef IOSCAPTURE_H
#define IOSCAPTURE_H

#ifdef __cplusplus
extern "C" {
#endif

// What a photo is of (the PHOTO option's ticks; a bit mask)
#define IOSCAPTURE_CLEAN    1 // the game alone
#define IOSCAPTURE_HUD      2 // with the HUD
#define IOSCAPTURE_HUDBTNS  4 // with the HUD and the touch buttons, as the screen shows
#define IOSCAPTURE_ALL      7

// Full-screen images that may wait to be saved at once
#define IOSCAPTURE_BUDGET_IMAGES 6

// What a capture is for (a burst's and a selfie's are always clean only)
#define IOSCAPTURE_MODE_PHOTO  0
#define IOSCAPTURE_MODE_BURST  1
#define IOSCAPTURE_MODE_SELFIE 2

// Asks for these kinds of the next frame. 0 if one is already waiting or
// there is no room for it in the budget.
int iosCapture_Request(int kinds, int mode);
// Whether n captures of these kinds would fit in the budget now
int iosCapture_HasRoom(int kinds, int n);
int iosCapture_IsPending(void);
// Drops a capture not taken yet
void iosCapture_Cancel(void);
// Whether one is waiting or being saved
int iosCapture_IsBusy(void);
// (iosPhotos) one capture of `bytes` saved (or given up), saveSeconds after it was handed over
void iosCapture_Done(long bytes, double saveSeconds);

// How the last photos went, for the message with the FPS readout on
typedef struct {
  double readSeconds;
  double saveSeconds;
  long peakBytes;
  double freezeSeconds;
} iosCaptureStats;
void iosCapture_TakeStats(iosCaptureStats *pStats);
void iosCapture_NoteFreeze(double seconds);

// The game's frame (w x h pixels), in order: FrameBegin before anything of
// it is drawn; AfterScene once the 3D view and the weapon are, before the
// crosshair and the HUD (not called where no HUD is drawn: the HUD off, a
// photo view); AfterHud once everything is, before the swap.
void iosCapture_FrameBegin(int w, int h);
void iosCapture_AfterScene(void);
void iosCapture_AfterHud(void);

// The host's side (iosCapture_ReadFrame: the GLES frame buffer; the rest:
// iosPhotos.mm on iOS, iosPhotos_rig.cpp on the Linux rig). Reads the w x h
// frame drawn so far into p as RGBA, the bottom row first (as GL has it):
// 1 if it could.
int iosCapture_ReadFrame(int w, int h, unsigned char *p);
// A line for the player at the top of the screen
void iosCamera_Message(const char *str);
// Whether the iosPhotos saver also gives a burst's photos one message
void iosPhotos_SetBatch(int bOn);
// iosPhotos: takes the images (malloc'd RGBA, top row first, opaque; either may be NULL) and frees them
void iosPhotos_SaveCapture(unsigned char *pClean, unsigned char *pHud, int w, int h, int kinds, int mode);

#ifdef __cplusplus
}
#endif

#endif // IOSCAPTURE_H
