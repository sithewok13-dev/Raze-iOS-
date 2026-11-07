// The CAMERA button's frame grabs: see iosCapture.h. (C++ only for the
// engine's precompiled header; plain C otherwise.)

#if defined(RAZE_IOS) || defined(RAZE_GLES_RIG)

#include "iosCapture.h"

#include <stdlib.h>
#include <string.h>
#include <time.h>

static int _iWanted = 0;            // the kinds the next frame should take (0: none waiting)
static int _iMode = IOSCAPTURE_MODE_PHOTO;
static long _slBytesSaving = 0;     // handed to iosPhotos, not saved yet
static int _ctSaving = 0;
static unsigned char *_pClean = NULL;
static int _iW = 0, _iH = 0;        // this frame's size (FrameBegin)
static int _bSceneSeen = 0;         // AfterScene ran in this frame
static iosCaptureStats _stats;

static double iosCapture_Now(void)
{
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

// One full-screen image (the last frame's size)
static long iosCapture_ImageBytes(void)
{
  return (_iW > 0 && _iH > 0) ? (long)_iW * _iH * 4 : 0;
}

// The full-screen images a capture of these kinds holds until it is saved:
// the clean one and the one with the HUD (read back here), and the HUD with
// the buttons drawn on (a third, made by iosPhotos from the HUD one)
static int iosCapture_NumImages(int kinds)
{
  return ((kinds & IOSCAPTURE_CLEAN) ? 1 : 0) + ((kinds & (IOSCAPTURE_HUD | IOSCAPTURE_HUDBTNS)) ? 1 : 0)
         + ((kinds & IOSCAPTURE_HUDBTNS) ? 1 : 0);
}

int iosCapture_HasRoom(int kinds, int n)
{
  const long image = iosCapture_ImageBytes();
  if (image <= 0) return 0;
  return _slBytesSaving + image * iosCapture_NumImages(kinds & IOSCAPTURE_ALL) * n <= image * IOSCAPTURE_BUDGET_IMAGES;
}

int iosCapture_Request(int kinds, int mode)
{
  kinds &= IOSCAPTURE_ALL;
  if (mode != IOSCAPTURE_MODE_PHOTO) kinds = IOSCAPTURE_CLEAN;
  if (!kinds || _iWanted || !iosCapture_HasRoom(kinds, 1)) return 0;
  _iWanted = kinds;
  _iMode = mode;
  return 1;
}

int iosCapture_IsPending(void)
{
  return _iWanted != 0;
}

void iosCapture_Cancel(void)
{
  free(_pClean);
  _pClean = NULL;
  _iWanted = 0;
}

int iosCapture_IsBusy(void)
{
  return _iWanted || _ctSaving;
}

void iosCapture_Done(long bytes, double saveSeconds)
{
  if (_ctSaving > 0) _ctSaving--;
  _slBytesSaving -= bytes;
  if (_slBytesSaving < 0 || !_ctSaving) _slBytesSaving = 0;
  _stats.saveSeconds = saveSeconds;
}

void iosCapture_TakeStats(iosCaptureStats *pStats)
{
  if (pStats) *pStats = _stats;
  _stats.saveSeconds = 0;
  _stats.peakBytes = _slBytesSaving;
  _stats.freezeSeconds = 0;
}

void iosCapture_NoteFreeze(double seconds)
{
  _stats.freezeSeconds = seconds;
}

// Hands what was taken to iosPhotos
static void iosCapture_Hand(unsigned char *pHud)
{
  unsigned char *pClean = _pClean;
  const int kinds = _iWanted;
  _pClean = NULL;
  _iWanted = 0;
  _ctSaving++;
  // (the same count iosPhotos hands back to iosCapture_Done)
  _slBytesSaving += (long)_iW * _iH * 4
                    * ((pClean ? 1 : 0) + (pHud ? 1 : 0) + ((pHud && (kinds & IOSCAPTURE_HUDBTNS)) ? 1 : 0));
  if (_slBytesSaving > _stats.peakBytes) _stats.peakBytes = _slBytesSaving;
  iosPhotos_SaveCapture(pClean, pHud, _iW, _iH, kinds, _iMode);
}

// The frame as drawn so far: RGBA, the top row first, fully opaque
static unsigned char *iosCapture_Read(void)
{
  const double t0 = iosCapture_Now();
  const size_t row = (size_t)_iW * 4;
  unsigned char *p = (unsigned char *)malloc(row * _iH);
  unsigned char *tmp = (unsigned char *)malloc(row);
  if (!p || !tmp || !iosCapture_ReadFrame(_iW, _iH, p)) {
    free(p);
    free(tmp);
    return NULL;
  }
  // GL's rows come bottom up
  for (int y = 0; y < _iH / 2; y++) {
    unsigned char *a = p + row * y;
    unsigned char *b = p + row * (_iH - 1 - y);
    memcpy(tmp, a, row);
    memcpy(a, b, row);
    memcpy(b, tmp, row);
  }
  free(tmp);
  for (size_t i = 3; i < row * _iH; i += 4) p[i] = 255;
  _stats.readSeconds = iosCapture_Now() - t0;
  return p;
}

static void iosCapture_Failed(void)
{
  iosCapture_Cancel();
  iosCamera_Message("Couldn't take the photos");
}

void iosCapture_FrameBegin(int w, int h)
{
  _iW = w;
  _iH = h;
  _bSceneSeen = 0;
  // a clean one read in a frame that never got as far as the HUD
  free(_pClean);
  _pClean = NULL;
}

void iosCapture_AfterScene(void)
{
  if (_bSceneSeen) return; // (once a frame: the first view drawn)
  _bSceneSeen = 1;
  if (!(_iWanted & IOSCAPTURE_CLEAN) || _iW <= 0 || _iH <= 0) return;
  _pClean = iosCapture_Read();
  if (!_pClean) {
    iosCapture_Failed();
    return;
  }
  // The clean one alone needs nothing more of this frame
  if (_iWanted == IOSCAPTURE_CLEAN) iosCapture_Hand(NULL);
}

void iosCapture_AfterHud(void)
{
  if (!_iWanted || _iW <= 0 || _iH <= 0) return;
  if (!_bSceneSeen) {
    // No HUD was drawn in this frame (it is turned off, or a photo view):
    // the whole frame is the clean one, and the HUD one too
    unsigned char *p = iosCapture_Read();
    if (!p) {
      iosCapture_Failed();
      return;
    }
    if (_iWanted & (IOSCAPTURE_HUD | IOSCAPTURE_HUDBTNS)) {
      unsigned char *q = NULL;
      if (_iWanted & IOSCAPTURE_CLEAN) {
        q = (unsigned char *)malloc((size_t)_iW * _iH * 4);
        if (!q) {
          free(p);
          iosCapture_Failed();
          return;
        }
        memcpy(q, p, (size_t)_iW * _iH * 4);
      }
      _pClean = q;
      iosCapture_Hand(p);
    }
    else {
      _pClean = p;
      iosCapture_Hand(NULL);
    }
    return;
  }
  if (!(_iWanted & (IOSCAPTURE_HUD | IOSCAPTURE_HUDBTNS))) return;
  if ((_iWanted & IOSCAPTURE_CLEAN) && !_pClean) return; // (not read: wait for the next frame)
  unsigned char *pHud = iosCapture_Read();
  if (!pHud) {
    iosCapture_Failed();
    return;
  }
  iosCapture_Hand(pHud);
}

#endif
