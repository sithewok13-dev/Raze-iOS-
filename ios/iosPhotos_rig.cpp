// The CAMERA's photos on the Linux test rig (iosPhotos.mm is the iOS one):
// PNGs into the folder $IOSCAM_DIR (or ./ioscam), named as on iOS, and
// the messages on the console and the game's message line. No touch
// buttons here: a "hud+buttons" photo is the HUD one. Saved at once, on the
// game's thread.

#if defined(RAZE_IOS) || defined(RAZE_GLES_RIG)

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/stat.h>
#include "files.h"
#include "m_png.h"
#include "printf.h"
#include "iosCamera.h"
#include "iosCapture.h"
#include "../source/core/ioscamera.h"

static int _bBatch = 0, _numSaved = 0, _numFailed = 0, _shot = 0;

static void iosPhotos_Report(void)
{
	if (_bBatch || (!_numSaved && !_numFailed)) return;
	char msg[128];
	if (_numFailed) snprintf(msg, sizeof(msg), "%d photos saved, %d couldn't be saved", _numSaved, _numFailed);
	else snprintf(msg, sizeof(msg), _numSaved == 1 ? "1 photo saved" : "%d photos saved", _numSaved);
	iosCamera_Message(msg);
	_numSaved = _numFailed = 0;
}

extern "C" void iosPhotos_SetBatch(int bOn)
{
	_bBatch = bOn != 0;
	if (bOn) _shot = 0;
	iosPhotos_Report();
}

static bool iosPhotos_WritePng(const unsigned char *p, int w, int h, const char *name)
{
	const char *dir = getenv("IOSCAM_DIR");
	if (!dir || !*dir) dir = "ioscam";
	mkdir(dir, 0755);
	char path[1024];
	snprintf(path, sizeof(path), "%s/%s", dir, name);
	unsigned char *rgb = (unsigned char *)malloc((size_t)w * h * 3);
	if (!rgb) return false;
	for (size_t i = 0, n = (size_t)w * h; i < n; i++) memcpy(rgb + i * 3, p + i * 4, 3);
	FileWriter *f = FileWriter::Open(path);
	bool ok = f && M_CreatePNG(f, rgb, nullptr, SS_RGB, w, h, w * 3, 1.f) && M_FinishPNG(f);
	delete f;
	free(rgb);
	if (ok) Printf("ioscam: saved %s (%dx%d)\n", path, w, h);
	return ok;
}

extern "C" void iosPhotos_SaveCapture(unsigned char *pClean, unsigned char *pHud, int w, int h, int kinds, int mode)
{
	const long bytes = (long)w * h * 4 * ((pClean ? 1 : 0) + (pHud ? 1 : 0) + ((pHud && (kinds & IOSCAPTURE_HUDBTNS)) ? 1 : 0));
	char base[96], name[160];
	time_t t = time(nullptr);
	strftime(base, sizeof(base), "Raze %Y-%m-%d %H.%M.%S", localtime(&t));
	static int same = 0;
	static char last[96];
	if (!strcmp(last, base)) same++;
	else { strcpy(last, base); same = 1; }
	if (same > 1) snprintf(base + strlen(base), sizeof(base) - strlen(base), "-%d", same);
	const bool numbered = mode == IOSCAPTURE_MODE_BURST || (mode == IOSCAPTURE_MODE_SELFIE && _bBatch);
	if (numbered) snprintf(base + strlen(base), sizeof(base) - strlen(base), mode == IOSCAPTURE_MODE_BURST ? " burst %02d" : " selfie %d", ++_shot);
	struct { unsigned char *p; int bit; const char *suffix; } a[3] = {
		{ pClean, IOSCAPTURE_CLEAN, "clean" }, { pHud, IOSCAPTURE_HUD, "hud" }, { pHud, IOSCAPTURE_HUDBTNS, "hud+buttons" } };
	for (auto &e : a)
	{
		if (!(kinds & e.bit)) continue;
		if (!e.p) { _numFailed++; continue; }
		if (numbered) snprintf(name, sizeof(name), "%s.png", base);
		else snprintf(name, sizeof(name), "%s %s.png", base, mode == IOSCAPTURE_MODE_SELFIE ? "selfie" : e.suffix);
		if (iosPhotos_WritePng(e.p, w, h, name)) _numSaved++;
		else _numFailed++;
	}
	free(pClean);
	free(pHud);
	iosCapture_Done(bytes, 0);
	iosPhotos_Report();
}

extern "C" void iosCamera_Message(const char *str)
{
	Printf(PRINT_NOTIFY, "%s\n", str);
}

extern "C" void iosCamera_ShowOptions(void)
{
	Printf("CAMERA options: ioscam_set kinds %d (1 clean, 2 HUD, 4 HUD and buttons), selfies %d, freeze %d\n", iosCam_GetKinds(),
		iosCam_GetSelfieShots(), iosCam_GetFreezeOn());
}

extern "C" void iosPhotos_Init(void)
{
}

extern "C" void iosPhotos_FreezeShown(int bOn)
{
	Printf("ioscam: Action Freeze %s\n", bOn ? "on" : "off");
}

#endif
