/* Stand-in for the camera system (iosCamera.h) until it is merged in: the
   touch overlay's CAMERA button and the tray's CAMERA call these, and they
   do nothing yet. The camera system's own file replaces this one. */
#include "iosCamera.h"

void iosCamera_Photo(void) {}
void iosCamera_Selfie(void) {}
void iosCamera_Burst(void) {}
void iosCamera_Freeze(void) {}
void iosCamera_Cinematic(void) {}
int iosCamera_IsBusy(void) { return 0; }
void iosCamera_ShowOptions(void) {}
void iosCamera_FrameBegin(int w, int h) { (void)w; (void)h; }
void iosCamera_AfterScene(void) {}
void iosCamera_AfterHud(void) {}
