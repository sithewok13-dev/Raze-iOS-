/* Linux test rig for Raze's iOS touch controls: the real overlay core
   (ios/IOSTouch.m, built as C with IOSTOUCH_RIG), driven by a script of
   touches, in the real engine (configure with
   -DRAZE_TOUCH_RIG_SOURCE=<this file>). No UIKit, so nothing of the
   overlay is drawn: its state goes to the log (and to TOUCHRIG_DUMP, for
   pictures made outside). The screen is an iPhone 14 in landscape (844 x
   390 points, the notch side 47 pt, the home bar 21 pt), or
   TOUCHRIG_SCREEN="W H side bottom" (points; e.g. "956 440 62 21", the
   Pro Max the HUD's mockups were made on).

   TOUCHRIG_SCRIPT=file: lines "<t> <cmd> ..." (t: seconds since the level
   first showed the overlay), cmds:
     down <id> <x|@BTN[+dx]> <y|[+dy]>   move <id> ...   up <id> ...   cancel <id>
     log <text>        state of the overlay and what the game said
     buttons           every button's place
     hud <split|strip|classic|none> [face 0/1]   the tray's HUD and FACE
     hudopacity <0.2-1>, opacity <0.2-1>          OPACITY's panel's sliders
     items             the item buttons (useitem, kind, charge, count, on, dim, place)
     dump <name>       the overlay's state (buttons shown, places, the
                       items) appended to TOUCHRIG_DUMP as one JSON line
     xshot <png>       the X screen (RIGDISPLAY) as a picture
     quit              ends the run
   The HUD's settings are kept in $HOME/.iosrig-hud.
   TOUCHRIG_LOG=file: where the log goes (stdout without). */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <stdarg.h>
#include <SDL.h>

static double IOSTouchRig_Now(void)
{
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec + ts.tv_nsec * 1e-9;
}

#include "IOSTouch.m"

static void IOSTouch_GyroRunUpdates(int bRun) { (void)bRun; }

static double RIG_W = 844.0, RIG_H = 390.0, RIG_IN_L = 47.0, RIG_IN_T = 0.0, RIG_IN_R = 47.0, RIG_IN_B = 21.0;

// The HUD's settings, in a file of the rig's (the app's are NSUserDefaults)
static void IOSTouch_LoadHudPrefs(void)
{
  char path[512];
  snprintf(path, sizeof(path), "%s/.iosrig-hud", getenv("HOME") ? getenv("HOME") : ".");
  FILE *f = fopen(path, "r");
  if (!f) return;
  if (fscanf(f, "%d %d %f", &_iHudStyle, &_bHudFace, &_fHudOpacity) != 3) { _iHudStyle = 0; _bHudFace = 1; _fHudOpacity = 1.0f; }
  fclose(f);
}

static void IOSTouch_SaveHudPrefs(void)
{
  char path[512];
  snprintf(path, sizeof(path), "%s/.iosrig-hud", getenv("HOME") ? getenv("HOME") : ".");
  FILE *f = fopen(path, "w");
  if (!f) return;
  fprintf(f, "%d %d %.2f\n", _iHudStyle, _bHudFace, (double)_fHudOpacity);
  fclose(f);
}

static void RigLayout(void)
{
  IOSTouch_SetHudFrame(RIG_W, RIG_H, RIG_IN_L, RIG_IN_T, RIG_IN_R, RIG_IN_B);
  IOSTouch_LayoutButtons(RIG_W, RIG_H, RIG_IN_L, RIG_IN_T, RIG_IN_R, RIG_IN_B, 1, &(IOSTouchRect){0}, &(IOSTouchRect){0},
                         &(IOSTouchRect){0});
}

static FILE *_rigLog = NULL;
static int _rigInit = 0;
static double _rigT0 = -1.0;
static char _rigLines[512][400];
static int _rigCount = 0, _rigNext = 0;
static unsigned int _rigReqs = 0;
static int _rigTouchIds[64];

static void RigLog(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void RigLog(const char *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  FILE *f = _rigLog ? _rigLog : stdout;
  fprintf(f, "[%7.3f] ", _rigT0 < 0 ? 0.0 : IOSTouchRig_Now() - _rigT0);
  vfprintf(f, fmt, ap);
  fputc('\n', f);
  fflush(f);
  va_end(ap);
}

static const char *const _rigNames[BTN_COUNT] = {
  "FIRE", "SECONDARY", "CROUCH", "USE", "JUMP", "NEXTWPN", "PREVWPN", "QUICKSAVE", "QUICKLOAD", "MENU",
  "CAMERA", "CHEAT", "ITEM0", "ITEM1", "ITEM2", "ITEM3", "ITEM4", "ITEM5", "RESUME", "TRAYLOOK", "TRAYSENS", "TRAYGYRO", "TRAYFPS", "TRAYOPACITY", "TRAYHUD", "TRAYFACE", "TRAYCAM", "TRAYCHEAT",
  "TRAYLEVEL", "TRAYGAMES", "TRAYKEYS",
};

static void RigInit(void)
{
  _rigInit = 1;
  const char *lf = getenv("TOUCHRIG_LOG");
  if (lf) _rigLog = fopen(lf, "w");
  const char *sf = getenv("TOUCHRIG_SCRIPT");
  FILE *f = sf ? fopen(sf, "r") : NULL;
  if (f) {
    while (_rigCount < 512 && fgets(_rigLines[_rigCount], sizeof(_rigLines[0]), f)) {
      if (_rigLines[_rigCount][0] == '#' || _rigLines[_rigCount][0] == '\n') continue;
      _rigCount++;
    }
    fclose(f);
  }
  RigLog("rig: %d script lines", _rigCount);
  const char *scr = getenv("TOUCHRIG_SCREEN");
  if (scr) {
    double w, h, side, b;
    if (sscanf(scr, "%lf %lf %lf %lf", &w, &h, &side, &b) == 4) {
      RIG_W = w; RIG_H = h; RIG_IN_L = RIG_IN_R = side; RIG_IN_B = b;
    }
  }
  RigLayout();
  _bGyroAvailable = 0;
}

// a coordinate: a number, or @BTN (its centre) with +dx/-dx after
static double RigCoord(const char *s, int bY, int *pBtn)
{
  if (s[0] != '@') {
    const double v = atof(s);
    return v;
  }
  char name[32];
  int k = 0;
  s++;
  while (*s && *s != '+' && *s != '-' && k < 31) name[k++] = *s++;
  name[k] = 0;
  for (int i = 0; i < BTN_COUNT; i++) {
    if (!strcmp(name, _rigNames[i])) {
      *pBtn = i;
      return (bY ? _aButtons[i].y : _aButtons[i].x) + (*s ? atof(s) : 0.0);
    }
  }
  RigLog("rig: no button %s", name);
  return 0.0;
}

static void RigState(const char *text)
{
  char sl[256] = "";
  for (int i = 0; i < IOSTOUCH_WPN_MAX; i++) {
    if (_wpn.ulOwned & (1u << i)) {
      char b[24];
      snprintf(b, sizeof(b), " %d:%d%s", i, _wpn.aiAmmo[i], (_wpn.ulReady & (1u << i)) ? "" : "x");
      strncat(sl, b, sizeof(sl) - strlen(sl) - 1);
    }
  }
  RigLog("state %s: mode %d wheel %d(tap %d hot %d map %d) tray %d levels %d(open %d) cheat %d/show %d flying %d hud(noclip %d fly %d items %d sec %d nosave %d) "
         "inhand %d canselect %d owned[%s] stick %d move %.2f,%.2f holds %d",
         text, _iMode, _bWheelOpen, _bWheelTapMode, IOSTouch_WheelHot(), _iWheelMap, _bTrayOpen, _hud.ctLevels, _bLevelListOpen,
         _bCheatOn, _bShowCheat, _bFlying, _hud.bNoclip, _hud.bFlying, _items.ctItems, _hud.iSecondary, _hud.bNoSaves,
         _wpn.iWanted, _wpn.bCanSelect, sl, _bStickActive, _fMoveX, _fMoveY, IOSTouch_HoldsGame());
}

// The overlay's state as one JSON line (for pictures of it made outside):
// the screen, every button shown (place, size, label, held), the items,
// the HUD's settings, the tray and OPACITY's panel
static void RigDump(const char *name)
{
  const char *path = getenv("TOUCHRIG_DUMP");
  FILE *f = path ? fopen(path, "a") : NULL;
  if (!f) return;
  fprintf(f, "{\"name\":\"%s\",\"w\":%.1f,\"h\":%.1f,\"mode\":%d,\"hud\":%d,\"face\":%d,\"hudalpha\":%.2f,\"opacity\":%.2f,\"tray\":%d,"
          "\"opacityopen\":%d,\"cheaton\":%d,\"fps\":[%.1f,%.1f,%d],\"pills\":[%.1f,%.1f,%.1f,%.1f,%.1f],\"buttons\":[",
          name, RIG_W, RIG_H, _iMode, _iHudStyle, _bHudFace, (double)_fHudOpacity, (double)_fOpacity, _bTrayOpen, _bOpacityOpen,
          _bCheatOn && _hud.bCheatAllowed, _fFpsX, _fFpsY, _bShowFps, _fPillTop, _fPillBottom, _fPillLeft, _fPillRight, _fStripHalf);
  int first = 1;
  for (int i = 0; i < BTN_COUNT; i++) {
    if (!IOSTouch_IsShown(i)) continue;
    char lab[40];
    snprintf(lab, sizeof(lab), "%s", i == BTN_SECONDARY ? (_hud.iSecondary == IOSTOUCH_SEC_KICK ? "KICK" : "ALT\nFIRE") : _aButtons[i].label);
    for (char *q = lab; *q; q++) if (*q == '\n') *q = '|';
    fprintf(f, "%s{\"n\":\"%s\",\"x\":%.1f,\"y\":%.1f,\"r\":%.1f,\"label\":\"%s\",\"held\":%d}", first ? "" : ",", _rigNames[i],
            _aButtons[i].x, _aButtons[i].y, _aButtons[i].radius, lab, _aButtonHeld[i] != 0);
    first = 0;
  }
  fprintf(f, "]");
  fprintf(f, ",\"items\":[");
  for (int k = 0; k < _items.ctItems; k++) {
    const IOSTouchItem *it = &_items.aItems[k];
    fprintf(f, "%s{\"use\":%d,\"kind\":%d,\"charge\":%.3f,\"count\":%d,\"on\":%d,\"dim\":%d}", k ? "," : "", it->iUse, it->iKind,
            (double)it->fCharge, it->iCount, it->bOn, it->bDim);
  }
  fprintf(f, "]");
  fprintf(f, "}\n");
  fclose(f);
  // the items' pictures and CHEAT's as the overlay has them: raw files (4-byte
  // width, height, then RGBA) beside the dump
  for (int u = 0; u < 9; u++) {
    const IOSTouchIcon *pi = (u == 8) ? &_cheatIcon : &_aItemIcons[u];
    if (!pi->bHave) continue;
    char ipath[600];
    snprintf(ipath, sizeof(ipath), "%s.%s%d.rgba", path, u == 8 ? "cheat" : "item", u);
    FILE *g = fopen(ipath, "wb");
    if (!g) continue;
    const int wh[2] = { pi->w, pi->h };
    fwrite(wh, 4, 2, g);
    fwrite(pi->aub[WICON_READY], 1, (size_t)pi->w * pi->h * 4, g);
    fwrite(pi->aub[u == 8 ? WICON_NOTFOUND : WICON_NOAMMO], 1, (size_t)pi->w * pi->h * 4, g);
    fclose(g);
  }
  RigLog("dump %s", name);
}

static void RigRun(double t)
{
  while (_rigNext < _rigCount) {
    double at;
    char cmd[32], a[300] = "", b[48] = "", c[48] = "";
    const int n = sscanf(_rigLines[_rigNext], "%lf %31s %299s %47s %47s", &at, cmd, a, b, c);
    if (n < 2 || at > t) return;
    _rigNext++;
    const double now = IOSTouchRig_Now();
    if (!strcmp(cmd, "down") || !strcmp(cmd, "move") || !strcmp(cmd, "up") || !strcmp(cmd, "cancel")) {
      const int id = atoi(a);
      int btn = -1;
      const double x = n >= 4 ? RigCoord(b, 0, &btn) : 0, y = n >= 5 ? RigCoord(c, 1, &btn) : 0;
      const void *touch = &_rigTouchIds[id & 63];
      if (!strcmp(cmd, "down")) IOSTouch_TouchBegan(touch, x, y, RIG_W, now, now);
      else if (!strcmp(cmd, "move")) { IOSTouch_TouchPassed(touch, x, y); IOSTouch_TouchMoved(touch, x, y); }
      else IOSTouch_TouchEnded(touch, x, y, !strcmp(cmd, "cancel"), now);
      RigLog("%s %d at %.0f,%.0f", cmd, id, x, y);
    }
    else if (!strcmp(cmd, "log")) {
      RigState(a);
    }
    else if (!strcmp(cmd, "buttons")) {
      for (int i = 0; i < BTN_COUNT; i++) RigLog("button %-10s %4.0f,%4.0f r%2.0f shown %d", _rigNames[i], _aButtons[i].x, _aButtons[i].y,
                                                 _aButtons[i].radius, IOSTouch_IsShown(i));
      RigLog("wheel centre %.0f,%.0f R0 %.0f R1 %.0f; hud frame %.3f %.3f %.3f %.3f", _fWheelCX, _fWheelCY, _fWheelR0, _fWheelR1,
             _afHudFrame[0], _afHudFrame[1], _afHudFrame[2], _afHudFrame[3]);
      RigLog("pills top %.1f bottom %.1f left %.1f right %.1f strip half %.1f; messages %.1f,%.1f; fps %.0f,%.0f", _fPillTop, _fPillBottom,
             _fPillLeft, _fPillRight, _fStripHalf, _fMsgLeft, _fMsgTop, _fFpsX, _fFpsY);
    }
    else if (!strcmp(cmd, "hud")) {
      static const char *const astr[IOSTOUCH_HUD_COUNT] = { "split", "strip", "classic", "none" };
      IOSTouch_HudPrefs();
      for (int k = 0; k < IOSTOUCH_HUD_COUNT; k++) if (!strcmp(a, astr[k])) _iHudStyle = k;
      if (b[0]) _bHudFace = atoi(b) != 0;
      IOSTouch_SaveHudPrefs();
      RigLog("hud %s face %d", astr[_iHudStyle], _bHudFace);
    }
    else if (!strcmp(cmd, "hudopacity")) {
      IOSTouch_SetHudOpacity((float)atof(a), 1);
      RigLog("hud opacity %.2f", (double)_fHudOpacity);
    }
    else if (!strcmp(cmd, "opacity")) {
      _fOpacity = IOSTouch_OpacityStep((float)atof(a));
      RigLog("opacity %.2f", (double)_fOpacity);
    }
    else if (!strcmp(cmd, "dump")) {
      RigDump(a);
    }
    else if (!strcmp(cmd, "items")) {
      // the item buttons as the game gives them: each its useitem number, kind, charge, count, on, dim
      char sl[400] = "";
      for (int k = 0; k < _items.ctItems; k++) {
        const IOSTouchItem *it = &_items.aItems[k];
        char one[80];
        snprintf(one, sizeof(one), " [%d %s %.2f x%d%s%s @%.0f r%.0f]", it->iUse, it->iKind ? "count" : "charge", (double)it->fCharge, it->iCount,
                 it->bOn ? " on" : "", it->bDim ? " dim" : "", _aButtons[BTN_ITEM0 + k].x, _aButtons[BTN_ITEM0 + k].radius);
        strncat(sl, one, sizeof(sl) - strlen(sl) - 1);
      }
      RigLog("items %d:%s", _items.ctItems, sl);
    }
    else if (!strcmp(cmd, "xshot")) {
      char line[400];
      snprintf(line, sizeof(line), "DISPLAY=%s import -window root %s", getenv("RIGDISPLAY") ? getenv("RIGDISPLAY") : ":79", a);
      RigLog("xshot %s: %d", a, system(line));
    }
    else if (!strcmp(cmd, "finger")) {
      // SDL finger events, as UIKit's touches on SDL's view give them (a: down/move/up, b c: 0..1 of the window)
      SDL_Event ev;
      memset(&ev, 0, sizeof(ev));
      ev.type = !strcmp(a, "down") ? SDL_FINGERDOWN : !strcmp(a, "up") ? SDL_FINGERUP : SDL_FINGERMOTION;
      ev.tfinger.touchId = 1;
      ev.tfinger.fingerId = 7;
      ev.tfinger.x = (float)atof(b);
      ev.tfinger.y = (float)atof(c);
      ev.tfinger.pressure = 1.0f;
      RigLog("finger %s %.3f %.3f: %d", a, ev.tfinger.x, ev.tfinger.y, SDL_PushEvent(&ev));
    }
    else if (!strcmp(cmd, "tap")) {
      // a tap on SDL's view as iOS gives it: finger down/up plus SDL's touch-mouse emulation (b c: 0..1)
      SDL_Event ev;
      for (int k = 0; k < 2; k++) {
        memset(&ev, 0, sizeof(ev));
        ev.type = k ? SDL_FINGERUP : SDL_FINGERDOWN;
        ev.tfinger.touchId = 1; ev.tfinger.fingerId = 7;
        ev.tfinger.x = (float)atof(b); ev.tfinger.y = (float)atof(c); ev.tfinger.pressure = 1.0f;
        SDL_PushEvent(&ev);
        memset(&ev, 0, sizeof(ev));
        ev.type = k ? SDL_MOUSEBUTTONUP : SDL_MOUSEBUTTONDOWN;
        ev.button.which = SDL_TOUCH_MOUSEID;
        ev.button.button = SDL_BUTTON_LEFT;
        ev.button.state = k ? SDL_RELEASED : SDL_PRESSED;
        SDL_PushEvent(&ev);
      }
      RigLog("tap %s %s", b, c);
    }
    else if (!strcmp(cmd, "mouse")) {
      // a real mouse's click at window pixel (b, c): warp there, then press and release (a: "click")
      SDL_Window *w = SDL_GL_GetCurrentWindow();
      SDL_WarpMouseInWindow(w, atoi(b), atoi(c));
      SDL_Event ev;
      memset(&ev, 0, sizeof(ev));
      ev.type = SDL_MOUSEBUTTONDOWN;
      ev.button.button = SDL_BUTTON_LEFT;
      ev.button.state = SDL_PRESSED;
      ev.button.x = atoi(b);
      ev.button.y = atoi(c);
      SDL_PushEvent(&ev);
      ev.type = SDL_MOUSEBUTTONUP;
      ev.button.state = SDL_RELEASED;
      SDL_PushEvent(&ev);
      RigLog("mouse click %s %s", b, c);
    }
    else if (!strcmp(cmd, "text")) {
      // what SDL's iOS text field sends as letters are typed: a key press and the text, each
      for (const char *q = a; *q; q++) {
        SDL_Event ev;
        memset(&ev, 0, sizeof(ev));
        ev.type = SDL_KEYDOWN; ev.key.state = SDL_PRESSED; ev.key.keysym.sym = (SDL_Keycode)*q; ev.key.keysym.scancode = SDL_GetScancodeFromKey((SDL_Keycode)*q);
        SDL_PushEvent(&ev);
        memset(&ev, 0, sizeof(ev));
        ev.type = SDL_TEXTINPUT; ev.text.text[0] = *q;
        SDL_PushEvent(&ev);
        memset(&ev, 0, sizeof(ev));
        ev.type = SDL_KEYUP; ev.key.state = SDL_RELEASED; ev.key.keysym.sym = (SDL_Keycode)*q; ev.key.keysym.scancode = SDL_GetScancodeFromKey((SDL_Keycode)*q);
        SDL_PushEvent(&ev);
      }
      RigLog("typed %s", a);
    }
    else if (!strcmp(cmd, "key")) {
      // return / backspace from the iOS keyboard (a press and its release)
      const SDL_Keycode k = !strcmp(a, "return") ? SDLK_RETURN : !strcmp(a, "backspace") ? SDLK_BACKSPACE : SDLK_ESCAPE;
      SDL_Event ev;
      memset(&ev, 0, sizeof(ev));
      ev.type = SDL_KEYDOWN; ev.key.state = SDL_PRESSED; ev.key.keysym.sym = k; ev.key.keysym.scancode = SDL_GetScancodeFromKey(k);
      SDL_PushEvent(&ev);
      ev.type = SDL_KEYUP; ev.key.state = SDL_RELEASED;
      SDL_PushEvent(&ev);
      RigLog("key %s", a);
    }
    else if (!strcmp(cmd, "picklevel")) {
      // (the level panel's table, which is UIKit's: as a tap on row a)
      RigLog("level panel: row %s tapped", a);
      IOSTouch_PickLevel(atoi(a));
    }
    else if (!strcmp(cmd, "cmd")) {
      // the rest of the line, as a console command
      const char *p = strstr(_rigLines[_rigNext - 1], "cmd ") + 4;
      char line[160];
      snprintf(line, sizeof(line), "%s", p);
      line[strcspn(line, "\n")] = 0;
      RigLog("console: %s", line);
      extern void IOSGame_RigCommand(const char *cmd);
      IOSGame_RigCommand(line);
    }
    else if (!strcmp(cmd, "quit")) {
      RigLog("rig: quit");
      if (_rigLog) fclose(_rigLog);
      _exit(0);
    }
  }
}

int IOSTouch_Update(void *pSDLWindow, int iMode, const IOSTouchHud *pHud, unsigned int ulFramesDrawn)
{
  (void)pSDLWindow;
  if (!_rigInit) RigInit();
  const int iRequests = _iRequests;
  _iRequests = 0;
  if (iRequests) RigLog("requests 0x%x", iRequests);
  _rigReqs |= iRequests;
  if (pHud) _hud = *pHud;
  if (iMode != _iMode) {
    RigLog("mode %d -> %d", _iMode, iMode);
    _iMode = iMode;
    IOSTouch_ResetTouches(iMode == IOSTOUCH_GAMEPLAY);
  }
  const double now = IOSTouchRig_Now();
  if (iMode == IOSTOUCH_GAMEPLAY && _rigT0 < 0) _rigT0 = now;
  if (_rigInit && IOSTouch_LayoutKey() != _iLaidOutKey) RigLayout(); // (the HUD, CAMERA or CHEAT changed: as the view's setNeedsLayout)
  if (iMode != IOSTOUCH_HIDDEN) {
    IOSTouch_TickHolds(now);
    IOSTouch_CountFrames(ulFramesDrawn, now);
    if (_ctWheelTicks) { RigLog("haptic: wheel tick x%d (hot %d)", _ctWheelTicks, IOSTouch_WheelHot()); _ctWheelTicks = 0; }
  }
  if (_rigT0 >= 0) RigRun(now - _rigT0);
  if (_strCamMessage[0] && _tCamMessage > 0) {
    RigLog("message: %s", _strCamMessage);
    _tCamMessage = 0;
  }
  return iRequests;
}

void IOSTouch_Hide(void)
{
  if (_iMode != IOSTOUCH_HIDDEN) {
    _iMode = IOSTOUCH_HIDDEN;
    IOSTouch_ResetTouches(0);
  }
}
