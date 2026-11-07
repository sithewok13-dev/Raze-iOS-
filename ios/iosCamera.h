// ios/iosCamera.h: what the touch overlay calls; implemented by the camera system.
#pragma once
#ifdef __cplusplus
extern "C" {
#endif
void iosCamera_Photo(void);          // CAMERA tap
void iosCamera_Selfie(void);         // CAMERA held 0.5 s
void iosCamera_Burst(void);          // slide sideways
void iosCamera_Freeze(void);         // slide down (Action Freeze)
void iosCamera_Cinematic(void);      // slide up (cinematic burst)
int  iosCamera_IsBusy(void);         // nonzero while a capture/selfie/freeze runs (overlay dims the button, ignores new presses)
void iosCamera_ShowOptions(void);    // tray CAMERA held: the options panel (PHOTO kinds, SELFIES, FREEZE)
void iosCamera_FrameBegin(int w, int h); // hooks the engine calls each frame / after the 3D view / after the HUD
void iosCamera_AfterScene(void);
void iosCamera_AfterHud(void);
#ifdef __cplusplus
}
#endif
