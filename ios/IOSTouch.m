/* On-screen touch controls for iOS. See IOSTouch.h.
   Built with ARC. The overlay lives for the whole process. Ported from the
   Serious Sam port's IOSTouch.m (the same controls, timings and looks).

   Everything up to the overlay view is plain C: the buttons and their
   layout, the state shared with the game, and what each touch does (the
   stick, looking, the buttons, the QUICK SAVE, QUICK LOAD and MENU holds,
   MENU's tray, the FPS count, tilt aiming, NEXT WPN's and PREV WPN's taps,
   slides and holds and the weapon wheel they open: its slices, what it
   picks, its layout, CAMERA's gestures and the cheat). The view below only
   hands UIKit's touches and CoreMotion's samples to it and shows its state,
   so the Linux test rig (built with IOSTOUCH_RIG, as C, without UIKit)
   drives this very code. */

#ifndef IOSTOUCH_RIG
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreMotion/CoreMotion.h>
#import <AudioToolbox/AudioToolbox.h>
#include <os/lock.h>
#include "SDL.h"
#include "SDL_syswm.h"
#else
// The Linux rig: the same core, a lock that does nothing (one thread), and
// the rig's clock (IOSTouchRig.c, which #includes this file)
typedef int os_unfair_lock;
#define OS_UNFAIR_LOCK_INIT 0
#define os_unfair_lock_lock(p) ((void)(p))
#define os_unfair_lock_unlock(p) ((void)(p))
static double IOSTouchRig_Now(void);
#define CACurrentMediaTime() IOSTouchRig_Now()
#endif
#include <math.h>
#include <stdio.h>
#include <string.h>
#include "IOSTouch.h"
#include "iosCamera.h"

// Look speed: mouse counts per point of finger travel. At Raze's default
// mouse settings (m_sensitivity_x/y 2, m_yaw/m_pitch 1, a count being 1/16
// degree before them) a count turns the view 0.125 degrees, so this turns it
// as far per point as the Jedi Knight and Serious Sam ports do (0.64 degrees
// across, 0.39 up/down).
#define IOSTOUCH_LOOK_SCALE_X 5.12f
#define IOSTOUCH_LOOK_SCALE_Y 3.12f
// ...times the look speed set with MENU's tray's LOOK: a tap goes on to the
// next of these (round to the first), held IOSTOUCH_MENU_HOLD it goes back to
// 1x. Kept in the app's settings (IOSTOUCH_LOOKSCALE_DEFAULTS_KEY).
static const float _afLookSteps[] = { 0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 2.0f, 2.5f, 3.0f };
#define IOSTOUCH_LOOK_NUM_STEPS ((int)(sizeof(_afLookSteps) / sizeof(_afLookSteps[0])))
#define IOSTOUCH_LOOKSCALE_MIN 0.25f
#define IOSTOUCH_LOOKSCALE_MAX 4.0f
// Stick: radius in points; it appears wherever the left thumb lands in the
// left IOSTOUCH_STICK_ZONE of the screen, and only while that thumb is down.
// Pushed past IOSTOUCH_STICK_DEADZONE of the radius it starts moving, and by
// IOSTOUCH_STICK_FULL it moves at full speed (below about half speed the
// player walks). Full speed comes early because the Build games are played
// running (Raze's autorun is on by default), as with the keyboard on PC.
#define IOSTOUCH_STICK_ZONE 0.42f
#define IOSTOUCH_STICK_RADIUS 60.0f
#define IOSTOUCH_STICK_DEADZONE 0.15f
#define IOSTOUCH_STICK_FULL 0.30f
// Buttons show at this opacity while untouched, so they hide less of the game;
// a touched one shows at full strength
#define IOSTOUCH_IDLE_ALPHA 0.65
// Edge-to-edge gap between the buttons around FIRE (the arc, the secondary
// button and ITEM)
#define IOSTOUCH_CLUSTER_GAP 30.0
// QUICK SAVE and QUICK LOAD have to be held this long, so a stray tap can't
// save over the quicksave (the one QUICK LOAD loads) or throw away progress
#define IOSTOUCH_QUICKSAVE_HOLD 0.3
#define IOSTOUCH_QUICKLOAD_HOLD 0.3
// NEXT WPN and PREV WPN each take three gestures (as Jedi Knight's FORCE
// WHEEL and NEXT WPN). A quick tap (lifted sooner than IOSTOUCH_WHEEL_HOLD by
// the touch's own clock, never IOSTOUCH_WHEEL_OPEN_SLIDE from where it went
// down) is the next / previous weapon, as it lifts. Sliding that far opens
// the weapon wheel at once, to slide to a slice; held still for
// IOSTOUCH_WHEEL_HOLD (known as QUICK SAVE's hold is) it opens to tap one.
// Sliding to pick is measured from where the thumb went down: it points
// nowhere until IOSTOUCH_WHEEL_DEAD away, the point it is measured from
// trails at most IOSTOUCH_WHEEL_LEASH behind the thumb, and a slice stays
// picked until the thumb points IOSTOUCH_WHEEL_HYST degrees past its edge; on
// the wheel itself the slice under the thumb is picked. The wheel's outer
// radius is at most IOSTOUCH_WHEEL_R1_MAX, its hole IOSTOUCH_WHEEL_R0_FRAC of
// that; the slice pointed at pops out IOSTOUCH_WHEEL_POP. The name in the
// middle keeps IOSTOUCH_WHEEL_NEEDLE_CLEAR inside the hole's edge, clear of
// the needle that shows which way the thumb points.
#define IOSTOUCH_WHEEL_OPEN_SLIDE 10.0
#define IOSTOUCH_WHEEL_HOLD IOSTOUCH_QUICKSAVE_HOLD
#define IOSTOUCH_WHEEL_DEAD 14.0
#define IOSTOUCH_WHEEL_LEASH 60.0
#define IOSTOUCH_WHEEL_HYST 4.0
#define IOSTOUCH_WHEEL_POP 10.0
#define IOSTOUCH_WHEEL_R1_MAX 168.0
#define IOSTOUCH_WHEEL_R0_FRAC 0.37
#define IOSTOUCH_WHEEL_NEEDLE_CLEAR 12.0
#define IOSTOUCH_WHEEL_CANCEL (-2) // the "slice" of the gap at the bottom
// MENU held this long opens its tray (the look speed, tilt aiming's
// sensitivity and mode, FPS, CAMERA, CHEAT, LEVEL, the keyboard); a tap opens
// the menu as it lifts. The tray's buttons are IOSTOUCH_TRAY_STEP apart in a
// row.
#define IOSTOUCH_MENU_HOLD 0.45
#define IOSTOUCH_TRAY_STEP 50.0
// ITEM: a slide this far sideways picks the previous / next inventory item
// (one step each time it goes this much further), instead of using the item
#define IOSTOUCH_ITEM_STEP 28.0
// The FPS readout: its size in points, and how long it counts frames for
// before it shows a new number
#define IOSTOUCH_FPS_W 54.0
#define IOSTOUCH_FPS_H 18.0
#define IOSTOUCH_FPS_PERIOD 0.5
// A tap too quick for any game tick to see is reported for this many ticks,
// then released for one
#define IOSTOUCH_PULSE_READS 2
// The HUD's frame (IOSTouch_GetHudFrame) keeps its corners this far inside the
// screen's rounded corners
#define IOSTOUCH_HUD_CORNER_GAP 2.0
// Tilt aiming (see IOSTouch_GyroFrame), as in the Jedi Knight port.
// CoreMotion's device motion gives the rotation rate with the gyro's bias
// already taken out, IOSTOUCH_GYRO_HZ times a second. Turning left and right
// is measured about the way up (against gravity), so it works the same
// however far back the phone is tipped ("player space": what the screen's
// yaw and roll axes turn about up together -- made up by as much as
// IOSTOUCH_GYRO_YAW_RELAX times for a phone held rolled a little to one
// side, but never more than the two turn in all). Where up says nothing
// about which way the player's head is -- the screen facing down at a player
// lying under it, or rolled over on its side -- it is about the screen's own
// up axis instead ("local space"). Tilting is about the screen's own
// side-to-side axis. Under IOSTOUCH_GYRO_SMOOTH deg/s the motion is averaged
// over the last IOSTOUCH_GYRO_SMOOTH_N samples (all of it under half that),
// and under IOSTOUCH_GYRO_SOFT deg/s it is scaled down, to nothing at rest,
// so a phone held still doesn't creep. A gap between two samples longer than
// IOSTOUCH_GYRO_MAX_DT (a stall) is skipped, and so is what the phone did
// between two frames more than IOSTOUCH_GYRO_MAX_FRAME apart (the game was
// stopped: it would come all at once), or in the IOSTOUCH_GYRO_TURN_HOLD
// after the screen turned round to the other landscape side (the phone is
// still on its way round). The sensitivity is one of _afGyroSens: at 1.0x
// the view turns as far as the phone does.
#define IOSTOUCH_GYRO_HZ 100.0
#define IOSTOUCH_GYRO_YAW_RELAX 1.41
#define IOSTOUCH_GYRO_SMOOTH 4.0
#define IOSTOUCH_GYRO_SMOOTH_N 12 // about 0.125 s
#define IOSTOUCH_GYRO_SOFT 1.5
#define IOSTOUCH_GYRO_MAX_DT 0.05
#define IOSTOUCH_GYRO_MAX_FRAME 0.5
#define IOSTOUCH_GYRO_TURN_HOLD 0.35
// CAMERA (as the Serious Sam and Jedi Knight ports'): a tap takes a photo,
// held still IOSTOUCH_SELFIE_HOLD a selfie (a ring fills), slid off sideways
// (IOSTOUCH_WHEEL_OPEN_SLIDE) a burst, a slide mostly down,
// IOSTOUCH_FREEZE_SWIPE long, Action Freeze, and one mostly up the cinematic
// burst: up, a slide that reaches within IOSTOUCH_FREEZE_EDGE of the top of
// the screen is enough, but never one shorter than IOSTOUCH_FREEZE_SWIPE_MIN.
// The camera system does the work (iosCamera.h); while it is busy CAMERA is
// dimmed and takes no new presses. A message shows for
// IOSTOUCH_CAMERA_MESSAGE_TIME.
#define IOSTOUCH_SELFIE_HOLD 0.5

// The cheat (sithewok): CHEAT held IOSTOUCH_CHEAT_HOLD switches it on or off
// (a tap does nothing). While it's on, USE held still that long goes through
// walls (or stops: the game's noclip), and in Shadow Warrior, the one Build
// game that can fly, JUMP held still that long flies; CROUCH only crouches.
// The tray's LEVEL (there while the cheat is on) opens the list of the
// game's levels, to tap one. Still: never further than IOSTOUCH_CHEAT_STILL
// from where the finger went down. Flying, two quick still taps on JUMP
// land: each shorter than IOSTOUCH_CHEAT_TAP, the second going down within
// IOSTOUCH_CHEAT_DOUBLE of the first one's lift (the touches' own clock).
// The Jedi Knight port's values.
#define IOSTOUCH_CHEAT_HOLD 0.5
#define IOSTOUCH_CHEAT_STILL 10.0
#define IOSTOUCH_CHEAT_TAP 0.25
#define IOSTOUCH_CHEAT_DOUBLE 0.35
#define IOSTOUCH_FREEZE_SWIPE 36.0
#define IOSTOUCH_FREEZE_EDGE 6.0
#define IOSTOUCH_FREEZE_SWIPE_MIN 16.0
#define IOSTOUCH_CAMERA_MESSAGE_TIME 3.0
#define IOSTOUCH_GYRO_DEFAULT_SENS 1 // 1.5x

#define IOSTOUCH_MAX_TOUCHES 10

// ---------------------------------------------------------------- buttons

enum {
  KIND_HOLD = 0, // holds its game button while touched
  KIND_ITEM,     // ITEM: uses the item when the touch lifts on it; slid sideways, the previous / next item instead
  KIND_MENU,     // asks for the menu when the touch lifts on it; held IOSTOUCH_MENU_HOLD, opens its tray
  KIND_TAP,      // asks for its request when the touch lifts on it
  KIND_HOLDSAVE, // asks for a quick save once held IOSTOUCH_QUICKSAVE_HOLD seconds without leaving it
  KIND_HOLDLOAD, // asks for a quick load once held IOSTOUCH_QUICKLOAD_HOLD seconds without leaving it
  KIND_KEYBOARD, // (MENU's tray) opens or closes the console, when the touch lifts on it
  KIND_FPS,      // (MENU's tray) shows or hides the FPS readout, when the touch lifts on it
  KIND_GYRO,     // (MENU's tray) the next tilt aiming mode, when the touch lifts on it
  KIND_GYROSENS, // (MENU's tray) the next tilt aiming sensitivity, when the touch lifts on it
  KIND_WHEEL,    // NEXT WPN, PREV WPN: a tap presses its game button once as it lifts; a slide or a hold opens the weapon wheel
  KIND_CAMERA,   // CAMERA: a tap, a hold, a slide (see IOSTOUCH_SELFIE_HOLD)
  KIND_CAMSWITCH,// (MENU's tray) shows or hides CAMERA, when the touch lifts on it; held IOSTOUCH_MENU_HOLD, CAMERA's options
  KIND_CHEAT,    // CHEAT: held IOSTOUCH_CHEAT_HOLD, the cheat on or off; a tap does nothing
  KIND_CHEATSWITCH, // (MENU's tray) shows CHEAT and switches the cheat on, or leaves cheat mode, when the touch lifts on it
  KIND_LEVELPICK,// (MENU's tray, the cheat on) opens the list of levels, when the touch lifts on it
  KIND_LOOKSPEED,// (MENU's tray) the next look speed, when the touch lifts on it; held IOSTOUCH_MENU_HOLD, back to 1x
  KIND_GAMES,    // (MENU's tray) "Switch game" (ios/IOSPicker.mm), when the touch lifts on it
  KIND_OPACITY,  // (MENU's tray) opens or closes its slider under the tray, when the touch lifts on it; held IOSTOUCH_MENU_HOLD, back to 100%
};

// which modes a button shows in
#define SHOW_PLAY  (1 << IOSTOUCH_GAMEPLAY)
#define SHOW_CONS  (1 << IOSTOUCH_CONSOLE)
#define SHOW_PAUSE (1 << IOSTOUCH_PAUSED)
#define SHOW_ALL   (SHOW_PLAY | SHOW_CONS | SHOW_PAUSE)

typedef struct {
  const char *label;
  int kind;
  unsigned int ulAction; // KIND_HOLD, KIND_ITEM: IOSTOUCH_FIRE...; otherwise IOSTOUCH_REQ_* (0: none)
  double radius;         // points
  int bLookWhileHeld;    // dragging on this button also turns the view
  int iShowIn;           // SHOW_*
  double x, y;           // centre, set in layout
} IOSTouchButton;

// Layout (see IOSTouch_LayoutButtons). Bottom right, under the right thumb:
// FIRE, an arc of CROUCH / USE / JUMP around it, the secondary button (ALT
// FIRE in Blood, KICK in Duke Nukem 3D; none in the others) right of FIRE
// and ITEM right of JUMP -- all IOSTOUCH_CLUSTER_GAP apart, in Serious Sam's
// ZOOM and BOMB places. ITEM shows while the game has items. These pass
// drags through to looking, so a thumb that lands on one while aiming keeps
// aiming -- except ITEM, which uses the item as the finger lifts on it (a
// look swipe that starts on it mustn't use a medkit up) and is slid sideways
// to pick another item. Top left: next and previous weapon (a tap; slid or
// held, the weapon wheel). Top right: quick save and quick load (each a
// short hold) and the menu. CAMERA in the top row, as near its middle as it
// is clear of the other buttons, CHEAT beside it. Holding MENU opens a tray
// just under it: the look speed (LOOK), tilt aiming's sensitivity and mode
// (SENS, GYRO), FPS, which shows or hides a frame rate readout by QUICK SAVE,
// CAMERA (the camera symbol: shows or hides CAMERA; held, its options), CHEAT
// (the cheat's switch), LEVEL (the list of levels, only while the cheat is
// on) and the keyboard, for the console. RESUME, in the middle, only while
// the game is paused.
enum {
  BTN_FIRE, BTN_SECONDARY, BTN_CROUCH, BTN_USE, BTN_JUMP, BTN_ITEM,
  BTN_NEXTWPN, BTN_PREVWPN,
  BTN_QUICKSAVE, BTN_QUICKLOAD, BTN_MENU,
  BTN_CAMERA,
  BTN_CHEAT,
  BTN_RESUME,
  BTN_TRAYLOOK, BTN_TRAYSENS, BTN_TRAYGYRO, BTN_TRAYFPS, BTN_TRAYOPACITY, BTN_TRAYCAM, BTN_TRAYCHEAT, BTN_TRAYLEVEL, BTN_TRAYGAMES, BTN_TRAYKEYS, // MENU's tray (left to right), hidden unless it is open
  BTN_COUNT
};
static IOSTouchButton _aButtons[] = {
  [BTN_FIRE]      = { "FIRE",        KIND_HOLD,     IOSTOUCH_FIRE,          42.0, 1, SHOW_PLAY },
  [BTN_SECONDARY] = { "ALT\nFIRE",   KIND_HOLD,     IOSTOUCH_SECONDARY,     28.0, 1, SHOW_PLAY },
  [BTN_CROUCH]    = { "CROUCH",      KIND_HOLD,     IOSTOUCH_CROUCH,        29.0, 1, SHOW_PLAY },
  [BTN_USE]       = { "USE",         KIND_HOLD,     IOSTOUCH_USE,           29.0, 1, SHOW_PLAY },
  [BTN_JUMP]      = { "JUMP",        KIND_HOLD,     IOSTOUCH_JUMP,          31.0, 1, SHOW_PLAY },
  [BTN_ITEM]      = { "ITEM",        KIND_ITEM,     IOSTOUCH_ITEM,          30.0, 0, SHOW_PLAY },
  [BTN_NEXTWPN]   = { "NEXT\nWPN",   KIND_WHEEL,    IOSTOUCH_NEXTWEAPON,    22.0, 0, SHOW_PLAY },
  [BTN_PREVWPN]   = { "PREV\nWPN",   KIND_WHEEL,    IOSTOUCH_PREVWEAPON,    22.0, 0, SHOW_PLAY },
  [BTN_QUICKSAVE] = { "QUICK\nSAVE", KIND_HOLDSAVE, IOSTOUCH_REQ_QUICKSAVE, 22.0, 0, SHOW_PLAY },
  [BTN_QUICKLOAD] = { "QUICK\nLOAD", KIND_HOLDLOAD, IOSTOUCH_REQ_QUICKLOAD, 22.0, 0, SHOW_PLAY },
  [BTN_MENU]      = { "MENU",        KIND_MENU,     IOSTOUCH_REQ_MENU,      22.0, 0, SHOW_ALL },
  [BTN_CAMERA]    = { "",            KIND_CAMERA,   0,                      22.0, 0, SHOW_PLAY },
  [BTN_CHEAT]     = { "",            KIND_CHEAT,    0,                      22.0, 0, SHOW_PLAY },
  [BTN_RESUME]    = { "RESUME",      KIND_TAP,      IOSTOUCH_REQ_RESUME,    44.0, 0, SHOW_PAUSE },
  [BTN_TRAYLOOK]  = { "LOOK",        KIND_LOOKSPEED, 0,                     20.0, 0, SHOW_ALL },
  [BTN_TRAYSENS]  = { "SENS",        KIND_GYROSENS, 0,                      20.0, 0, SHOW_ALL },
  [BTN_TRAYGYRO]  = { "GYRO",        KIND_GYRO,     0,                      20.0, 0, SHOW_ALL },
  [BTN_TRAYFPS]   = { "FPS",         KIND_FPS,      0,                      20.0, 0, SHOW_ALL },
  [BTN_TRAYOPACITY] = { "OPACITY",   KIND_OPACITY,  0,                      20.0, 0, SHOW_ALL },
  [BTN_TRAYCAM]   = { "",            KIND_CAMSWITCH, 0,                     20.0, 0, SHOW_ALL },
  [BTN_TRAYCHEAT] = { "CHEAT",       KIND_CHEATSWITCH, 0,                   20.0, 0, SHOW_ALL },
  [BTN_TRAYLEVEL] = { "LEVEL",       KIND_LEVELPICK, 0,                     20.0, 0, SHOW_PLAY },
  [BTN_TRAYGAMES] = { "GAMES",       KIND_GAMES,    IOSTOUCH_REQ_GAMES,     20.0, 0, SHOW_ALL },
  [BTN_TRAYKEYS]  = { "",            KIND_KEYBOARD, IOSTOUCH_REQ_CONSOLE,   20.0, 0, SHOW_ALL },
};
#define IOSTOUCH_NUM_BUTTONS ((int)(sizeof(_aButtons) / sizeof(_aButtons[0])))
typedef char IOSTouch_assertButtonCount[(IOSTOUCH_NUM_BUTTONS == BTN_COUNT) ? 1 : -1];

// ------------------------------------------------------- shared with the game
// The game reads these on its own thread (IOSTouch_ReadInput, 20 times a
// second; IOSTouch_TakeLook and IOSTouch_TakeGyro, also every frame): only
// touch them under _lock.

static os_unfair_lock _lock = OS_UNFAIR_LOCK_INIT;
static int _bReading = 0;         // gameplay controls are showing; otherwise the game gets nothing
static unsigned int _ulHeld = 0;  // game buttons held down by touches
static unsigned int _ulSeen = 0;  // ...that a game tick has seen held since they were pressed
// One-off presses waiting to be read, and the one being read right now
static unsigned char _aPulseQueue[IOSTOUCH_NUMBUTTONS];
static unsigned char _aPulseReads[IOSTOUCH_NUMBUTTONS];
static unsigned char _aPulseGap[IOSTOUCH_NUMBUTTONS];
static float _fMoveX = 0.0f, _fMoveY = 0.0f;
static float _fLookX = 0.0f, _fLookY = 0.0f;
static float _fGyroYaw = 0.0f, _fGyroPitch = 0.0f; // tilt aiming: degrees for the view to turn (+ left) and tilt (+ up)
// The weapon wheel's pick (a weapon number) waiting to be read, and the one
// being read now: reads left, its value, and the read after it with none
// (weapon numbers + 1 here, 0 being none: Duke's knee is weapon 0)
static int _iPickPending = 0, _iPickReads = 0, _iPickNow = 0, _bPickGap = 0;

// Sets the game buttons held by touches. ulLifted: buttons whose touch just
// lifted (not cancelled) -- if no tick saw them held, it was a tap quicker
// than a tick (or a KIND_PRESS button, never held), and they are reported as
// one press.
static void IOSTouch_SetHeld(unsigned int ulHeld, unsigned int ulLifted)
{
  os_unfair_lock_lock(&_lock);
  for (int i = 0; i < IOSTOUCH_NUMBUTTONS; i++) {
    const unsigned int ul = 1u << i;
    if ((ulLifted & ul) && !(_ulSeen & ul) && _aPulseQueue[i] < 255) _aPulseQueue[i]++;
  }
  _ulSeen &= ~(ulHeld & ~_ulHeld); // newly pressed: not seen yet
  _ulHeld = ulHeld;
  os_unfair_lock_unlock(&_lock);
}

// Drops everything held and queued; bReading: whether the game gets input now
static void IOSTouch_ResetShared(int bReading)
{
  os_unfair_lock_lock(&_lock);
  _bReading = bReading;
  _ulHeld = _ulSeen = 0;
  memset(_aPulseQueue, 0, sizeof(_aPulseQueue));
  memset(_aPulseReads, 0, sizeof(_aPulseReads));
  memset(_aPulseGap, 0, sizeof(_aPulseGap));
  _fMoveX = _fMoveY = 0.0f;
  _fLookX = _fLookY = 0.0f;
  _fGyroYaw = _fGyroPitch = 0.0f;
  _iPickPending = _iPickReads = _iPickNow = _bPickGap = 0;
  os_unfair_lock_unlock(&_lock);
}

// The weapon wheel picked a weapon: the game gets it in the select field of
// its next free read (IOSTouch_ReadInput); a later pick replaces one still
// waiting
static void IOSTouch_QueuePick(int iWeapon)
{
  os_unfair_lock_lock(&_lock);
  _iPickPending = iWeapon + 1;
  os_unfair_lock_unlock(&_lock);
}

// The weapon wheel opened: a NEXT/PREV tap the game hasn't started reading
// (a slow frame) would go off after the wheel closes and undo its pick, so it
// is dropped (one already being read finishes); look and tilt aiming taken
// before the opening are dropped too, so nothing jumps once the game goes on
static void IOSTouch_SharedWheelOpened(void)
{
  os_unfair_lock_lock(&_lock);
  for (int i = 0; i < IOSTOUCH_NUMBUTTONS; i++) {
    if ((1u << i) & (IOSTOUCH_NEXTWEAPON | IOSTOUCH_PREVWEAPON)) _aPulseQueue[i] = 0;
  }
  _fLookX = _fLookY = 0.0f;
  _fGyroYaw = _fGyroPitch = 0.0f;
  os_unfair_lock_unlock(&_lock);
}

// ---------------------------------------------------------------- layout

// The HUD, and the game's messages, clock and stats, lay themselves out inside
// a frame: the screen less its rounded corners and the home indicator
// (IOSTouch_GetHudFrame). UIKit doesn't give the corners' radius, but a phone's
// side insets in landscape (notch or Dynamic Island) come to about it or a
// little more -- 62 pt on the 18 Pro Max for about 62, 59 for 55 on the 14 Pro,
// 47 for 47.3 on the 12, 44 for 39 on the X -- and so does an iPad's bottom
// inset (20 for 18). The frame's corners go on the screen corners' arcs at 45
// degrees, IOSTOUCH_HUD_CORNER_GAP inside (19.6 pt in on the 18 Pro Max), so
// nothing drawn inside the frame is cut off; its bottom also stays above the
// home indicator (21 pt). Screens without insets have square corners: the
// frame is the whole screen. The camera cutout sits at mid-height by a side:
// the Dynamic Island (side insets 59 pt and up, 126 pt long) is well clear of
// the HUD, but a notch (side insets 44-50 pt, up to about 210 pt long and 33
// pt deep) reaches down to the armour box at the bottom left, so there the
// frame's sides keep 22 pt less than the inset in (the inset is the same on
// both sides).
static void IOSTouch_HudFrameInsets(double inLeft, double inTop, double inRight, double inBottom,
                                    double *pfLeft, double *pfTop, double *pfRight, double *pfBottom)
{
  const double R = fmax(fmax(inLeft, inRight), fmax(inTop, inBottom));
  const double c = (R > IOSTOUCH_HUD_CORNER_GAP) ? R - (R - IOSTOUCH_HUD_CORNER_GAP) / M_SQRT2 : 0.0;
  const double side = fmax(inLeft, inRight);
  *pfLeft = *pfRight = (side >= 40.0 && side < 55.0) ? fmax(c, side - 22.0) : c;
  *pfTop = fmax(inTop, c);
  // The bottom goes to the screen's edge, under the home indicator (the
  // owner's choice for Raze: the HUD at the very bottom, as in the
  // original games, rather than lifted above the indicator)
  *pfBottom = 0.0;
  (void)inBottom;
}

typedef struct {
  int bValid;
  double x0, y0, x1, y1;
} IOSTouchRect;

// What the layout puts besides the buttons (points): the backing behind
// MENU's tray, the part of it behind its right two buttons (FPS and the
// keyboard: where the FPS readout keeps clear of), and the FPS readout's
// centre
static IOSTouchRect _rTrayBack, _rTrayKeysBack;
// where the tray's row goes (the keyboard's x, the row's y, the screen's usable
// left and right); whether it was placed with LEVEL in it
static double _fTrayKeysX, _fTrayY, _fTrayLeft, _fTrayRight;
static int _bTrayLevelPlaced = 0;
// The messages' line (its middle; points)
static double _fCamMessageX = 0.0, _fCamMessageY = 0.0;
static double _fFpsX = 0.0, _fFpsY = 0.0;

static double IOSTouch_DistToRect(double px, double py, const IOSTouchRect *r)
{
  const double cx = fmin(fmax(px, r->x0), r->x1), cy = fmin(fmax(py, r->y0), r->y1);
  return hypot(px - cx, py - cy);
}

// Distance from (px,py) to the segment (ax,ay)-(bx,by)
static double IOSTouch_DistToSegment(double px, double py, double ax, double ay, double bx, double by)
{
  const double vx = bx - ax, vy = by - ay;
  const double len2 = vx * vx + vy * vy;
  double t = len2 > 0 ? ((px - ax) * vx + (py - ay) * vy) / len2 : 0;
  if (t < 0) t = 0;
  if (t > 1) t = 1;
  return hypot(px - (ax + t * vx), py - (ay + t * vy));
}

// Whether the box hw x hh either side of (cx,cy) keeps 4pt clear of these
// HUD boxes and 6pt clear of these buttons
static int IOSTouch_BoxIsClear(double cx, double cy, double hw, double hh, const IOSTouchRect *const *apr, int ctRects,
                               const int *aiButtons, int ctButtons)
{
  const IOSTouchRect box = { 1, cx - hw, cy - hh, cx + hw, cy + hh };
  for (int i = 0; i < ctRects; i++) {
    const IOSTouchRect *r = apr[i];
    if (!r->bValid) continue;
    const double dx = fmax(fmax(r->x0 - box.x1, box.x0 - r->x1), 0.0);
    const double dy = fmax(fmax(r->y0 - box.y1, box.y0 - r->y1), 0.0);
    if (hypot(dx, dy) < 4.0) return 0;
  }
  for (int i = 0; i < ctButtons; i++) {
    const IOSTouchButton *b = &_aButtons[aiButtons[i]];
    if (IOSTouch_DistToRect(b->x, b->y, &box) < b->radius + 6.0) return 0;
  }
  return 1;
}

// (the HUD's boxes the layout keeps clear of: none in Raze, its HUD keeps
// to the HUD frame's edges)
static IOSTouchRect _rMessages;

// The weapon wheel (points): round the middle of the safe area, 4 pt down,
// as big as fits with room for a slice to pop out (as Jedi Knight's)
static double _fWheelCX = 0.0, _fWheelCY = 0.0, _fWheelR0 = 0.0, _fWheelR1 = 0.0;
static void IOSTouch_WheelGeometry(double W, double H, double inLeft, double inTop, double inRight, double inBottom,
                                   double *pfCX, double *pfCY, double *pfR0, double *pfR1)
{
  const double left = fmax(inLeft, 8.0), right = W - fmax(inRight, 8.0);
  const double top = fmax(inTop, 8.0), bottom = H - fmax(inBottom, 8.0);
  *pfCX = (left + right) * 0.5;
  *pfCY = (top + bottom) * 0.5 + 4.0;
  *pfR1 = fmin(IOSTOUCH_WHEEL_R1_MAX, (bottom - top) * 0.5 - IOSTOUCH_WHEEL_POP - 6.0);
  *pfR0 = round(*pfR1 * IOSTOUCH_WHEEL_R0_FRAC);
}

// MENU's tray along its row (IOSTouch_LayoutButtons found where): the
// keyboard under MENU, then GAMES, LEVEL (if it shows: bLevel), CHEAT, CAMERA, FPS,
// GYRO, SENS and LOOK to the left, IOSTOUCH_TRAY_STEP apart. LEVEL hidden
// sits under CHEAT (nothing finds it there: IOSTouch_ButtonAt passes over
// hidden buttons).
static void IOSTouch_PlaceTray(int bLevel)
{
  _bTrayLevelPlaced = bLevel != 0;
  int ctLeft = 0; // buttons right of the one being placed
  for (int i = BTN_TRAYKEYS; i >= BTN_TRAYLOOK; i--) {
    if (i == BTN_TRAYLEVEL && !bLevel) {
      continue; // (placed under CHEAT below)
    }
    else {
      _aButtons[i].x = _fTrayKeysX - ctLeft * IOSTOUCH_TRAY_STEP;
      ctLeft++;
    }
    _aButtons[i].y = _fTrayY;
  }
  if (!bLevel) {
    _aButtons[BTN_TRAYLEVEL].x = _aButtons[BTN_TRAYCHEAT].x;
    _aButtons[BTN_TRAYLEVEL].y = _fTrayY;
  }
  _rTrayBack.bValid = 1;
  _rTrayBack.x0 = _aButtons[BTN_TRAYLOOK].x - 26;
  _rTrayBack.y0 = _fTrayY - 26;
  _rTrayBack.x1 = _fTrayKeysX + 26;
  _rTrayBack.y1 = _fTrayY + 26;
  _rTrayKeysBack = _rTrayBack;
  _rTrayKeysBack.x0 = _fTrayKeysX - IOSTOUCH_TRAY_STEP - 26;
}

// Places every button on a W x H point screen with these safe-area insets,
// keeping clear of the HUD's score and high score boxes and unread messages
// box (in points) and of the camera cutout when it may be on the right. (The
// messages box is in the HUD's top row, which only the FPS readout comes
// near. Nothing of the HUD is at the bottom right: the ammo row isn't drawn.)
static void IOSTouch_LayoutButtons(double W, double H, double inLeft, double inTop, double inRight, double inBottom,
                                   int bCutoutMayBeRight, const IOSTouchRect *prScore, const IOSTouchRect *prHiScore,
                                   const IOSTouchRect *prMessages)
{
  _rMessages = *prMessages;

  const double left = fmax(inLeft, 8.0);
  const double right = W - fmax(inRight, 8.0);
  const double top = fmax(inTop, 8.0);
  const double bottom = H - fmax(inBottom, 8.0);

  // FIRE in the corner, above the home indicator. Without side insets there
  // is no spare edge for the secondary button to sit in beside FIRE, so FIRE sits further in.
  const double FR = _aButtons[BTN_FIRE].radius;
  const double fireX = right - (inRight < 20.0 ? 100 : 76), fireY = bottom - 58;
  _aButtons[BTN_FIRE].x = fireX;
  _aButtons[BTN_FIRE].y = fireY;

  // CROUCH, USE and JUMP on an arc around FIRE (angles counter-clockwise from
  // pointing right, so 90 is straight up), 45 degrees apart -- which at this
  // radius leaves about IOSTOUCH_CLUSTER_GAP between them
  const double arc = 115.0;
  const int aArcBtn[3] = { BTN_CROUCH, BTN_USE, BTN_JUMP };
  const double aArcDeg[3] = { 180.0, 135.0, 90.0 };
  for (int i = 0; i < 3; i++) {
    const double rad = aArcDeg[i] * M_PI / 180.0;
    _aButtons[aArcBtn[i]].x = fireX + arc * cos(rad);
    _aButtons[aArcBtn[i]].y = fireY - arc * sin(rad);
  }

  // The camera cutout, when it is on the right, as a capsule along the right
  // edge: the Dynamic Island (side inset ~59-62pt) is ~126x37pt, 11pt in
  // from the edge; a notch (side inset ~44-50pt) is up to ~210x33pt at the
  // edge. The landscape side insets are the same both ways round, so which
  // side it is on comes from the screen's orientation.
  const int bCutout = inRight >= 40.0 && bCutoutMayBeRight;
  const double cutX = (inRight >= 55.0) ? W - 29.5 : W - 16.5;
  const double cutR = (inRight >= 55.0) ? 18.5 : 16.5;
  const double cutHalf = ((inRight >= 55.0) ? 63.0 : 105.0) - cutR;

  // the secondary button: up and to the right of FIRE, IOSTOUCH_CLUSTER_GAP from it, as low as
  // it can sit while staying on screen, clear of JUMP and clear of the
  // cutout. Where the cutout takes that side (on a short screen), level with
  // FIRE or a little below it.
  {
    IOSTouchButton *a = &_aButtons[BTN_SECONDARY];
    const IOSTouchButton *j = &_aButtons[BTN_JUMP];
    const double AR = a->radius;
    const double D = FR + AR + IOSTOUCH_CLUSTER_GAP;
    // If nothing at that distance fits, step outwards; failing that, allow
    // the secondary button closer to JUMP.
    double bx = fireX + D * cos(M_PI * 35.0 / 180.0), by = fireY - D * sin(M_PI * 35.0 / 180.0);
    int bFound = 0;
    for (int pass = 0; pass < 2 && !bFound; pass++) {
      const double jumpGap = pass ? 2.0 : 8.0;
      for (int extra = 0; extra <= 80 && !bFound; extra += 2) {
        for (int i = 0; i <= 105; i++) {
          const int deg = (i <= 75) ? 10 + i : 85 - i; // 10 up to 85 degrees, then 9 down to -20
          const double rad = deg * M_PI / 180.0;
          const double px = fireX + (D + extra) * cos(rad), py = fireY - (D + extra) * sin(rad);
          if (px + AR > W - 4 || py - AR < top + 60 || py + AR > bottom) continue;     // on screen, below the top row
          if (hypot(px - j->x, py - j->y) < AR + j->radius + jumpGap) continue;          // clear of JUMP
          if (bCutout && IOSTouch_DistToSegment(px, py, cutX, H * 0.5 - cutHalf, cutX, H * 0.5 + cutHalf) < AR + cutR + 2)
            continue;                                                                     // clear of the cutout
          bx = px;
          by = py;
          bFound = 1;
          break;
        }
      }
    }
    a->x = bx;
    a->y = by;
  }

  // ITEM: right of JUMP and above the secondary button, out of the way of aiming -- on the
  // circle IOSTOUCH_CLUSTER_GAP out from JUMP, as far round towards pointing
  // right as it fits on screen, below the top row and clear of the secondary button, USE,
  // FIRE and the cutout. Where the cutout (or, on smaller
  // screens, the secondary button) takes that spot it goes higher, over JUMP; failing that,
  // the gaps shrink.
  {
    IOSTouchButton *f = &_aButtons[BTN_ITEM];
    const IOSTouchButton *j = &_aButtons[BTN_JUMP];
    const IOSTouchButton *a = &_aButtons[BTN_SECONDARY];
    const IOSTouchButton *c = &_aButtons[BTN_USE];
    const IOSTouchButton *d = &_aButtons[BTN_CROUCH];
    const double R = f->radius;
    const double aGap[3] = { IOSTOUCH_CLUSTER_GAP, 20.0, 12.0 };
    // If nothing fits (a very short screen, e.g. with Display Zoom): just
    // outside the arc, IOSTOUCH_CLUSTER_GAP from both CROUCH and USE
    const double dist = d->radius + R + IOSTOUCH_CLUSTER_GAP; // CROUCH and USE are the same size
    const double mx = (d->x + c->x) * 0.5, my = (d->y + c->y) * 0.5;
    const double vx = c->x - d->x, vy = c->y - d->y;
    const double L = sqrt(vx * vx + vy * vy);
    const double h = (dist > L * 0.5) ? sqrt(dist * dist - L * L * 0.25) : 0;
    double nx = vy / L, ny = -vx / L; // the perpendicular pointing away from FIRE
    if ((mx - fireX) * nx + (my - fireY) * ny < 0) { nx = -nx; ny = -ny; }
    double bx = mx + nx * h, by = my + ny * h;
    int bFound = 0;
    for (int pass = 0; pass < 3 && !bFound; pass++) {
      const double gap = aGap[pass];
      const double D = j->radius + R + gap;
      for (int deg = 0; deg <= 135; deg++) {
        const double rad = deg * M_PI / 180.0;
        const double px = j->x + D * cos(rad), py = j->y - D * sin(rad);
        if (px + R > W - 4 || py - R < top + 60) continue;                    // on screen, below the top row
        if (hypot(px - a->x, py - a->y) < R + a->radius + gap) continue;     // clear of the secondary button
        if (hypot(px - c->x, py - c->y) < R + c->radius + gap) continue;     // USE
        if (hypot(px - fireX, py - fireY) < R + FR + gap) continue;          // FIRE
        if (bCutout && IOSTouch_DistToSegment(px, py, cutX, H * 0.5 - cutHalf, cutX, H * 0.5 + cutHalf) < R + cutR + 2)
          continue;                                                          // the cutout
        bx = px;
        by = py;
        bFound = 1;
        break;
      }
    }
    f->x = bx;
    f->y = by;
  }

  // Top left: NEXT WPN | PREV WPN, below the score box
  double topLeftY = top + 26;
  if (prScore->bValid) topLeftY = fmax(topLeftY, prScore->y1 + 4 + _aButtons[BTN_NEXTWPN].radius);
  _aButtons[BTN_NEXTWPN].x = left + 24;
  _aButtons[BTN_PREVWPN].x = left + 84;
  _aButtons[BTN_NEXTWPN].y = _aButtons[BTN_PREVWPN].y = topLeftY;
  // Top right: QUICK SAVE, QUICK LOAD, MENU in the corner -- spaced well
  // apart, so a press meant for one of the two quick holds can't land on the
  // other
  _aButtons[BTN_QUICKSAVE].x = right - 156;
  _aButtons[BTN_QUICKLOAD].x = right - 90;
  _aButtons[BTN_MENU].x = right - 24;
  _aButtons[BTN_QUICKSAVE].y = _aButtons[BTN_QUICKLOAD].y = _aButtons[BTN_MENU].y = top + 26;

  // MENU's tray: a row just under the corner, the keyboard right below MENU
  // (a held thumb slides straight down onto it), then the rest to the left,
  // IOSTOUCH_TRAY_STEP apart (IOSTouch_PlaceTray). Where ITEM, the secondary button or JUMP
  // sits high in that corner (a smaller screen) the row moves left until it is
  // clear of them -- or, if that never happens, to wherever it is furthest
  // from them. (While open, the tray is on top and takes its own touches, but
  // a touch meant for it mustn't land nearer one of those.) Measured with
  // LEVEL in it, so the keyboard stays put whether or not LEVEL shows.
  {
    const IOSTouchButton *m = &_aButtons[BTN_MENU];
    const int aAvoid[3] = { BTN_ITEM, BTN_SECONDARY, BTN_JUMP };
    const double ty = m->y + 52;
    const double row = (BTN_TRAYKEYS - BTN_TRAYLOOK) * IOSTOUCH_TRAY_STEP; // LOOK to the keyboard, LEVEL too
    double kx = m->x, bestGap = -1e9;
    for (double x = m->x; x >= m->x - 240; x -= 4) {
      double gap = 1e9;
      for (int i = 0; i < 3; i++) {
        const IOSTouchButton *f = &_aButtons[aAvoid[i]];
        gap = fmin(gap, IOSTouch_DistToSegment(f->x, f->y, x - row, ty, x, ty) - 26 - f->radius);
      }
      if (gap > bestGap) {
        bestGap = gap;
        kx = x;
      }
      if (gap >= 8) break;
    }
    _fTrayKeysX = kx;
    _fTrayY = ty;
    _fTrayLeft = left;
    _fTrayRight = right;
    IOSTouch_PlaceTray(_bTrayLevelPlaced);
  }

  // The FPS readout where the keyboard button used to be, left of QUICK SAVE:
  // the game prints its messages at the top left, and its high score box is
  // in the middle. Where that spot is on the high score box or the unread
  // messages box right of it (a narrower screen, a larger HUD), it moves right
  // towards QUICK SAVE; if it never fits there, it goes below QUICK SAVE (and
  // on to the left), clear of ITEM, the secondary button and MENU's tray's FPS and keyboard
  // as well. (Where the rest of the open tray lies over it, it hides while
  // the tray is open: IOSTouch_FpsUnderTray.)
  {
    const IOSTouchButton *q = &_aButtons[BTN_QUICKSAVE];
    const IOSTouchRect *const apr[4] = { prScore, prHiScore, prMessages, &_rTrayKeysBack };
    const int aAvoid[2] = { BTN_ITEM, BTN_SECONDARY };
    const double hw = IOSTOUCH_FPS_W * 0.5, hh = IOSTOUCH_FPS_H * 0.5;
    const double y2 = q->y + q->radius + 8 + hh;
    int bFound = 0;
    _fFpsX = right - 216;
    _fFpsY = top + 26;
    for (double x = right - 216; x <= q->x - q->radius - 6 - hw && !bFound; x += 2) {
      if (IOSTouch_BoxIsClear(x, top + 26, hw, hh, apr, 3, NULL, 0)) {
        _fFpsX = x;
        bFound = 1;
      }
    }
    for (double x = q->x; x >= left + hw && !bFound; x -= 4) {
      if (IOSTouch_BoxIsClear(x, y2, hw, hh, apr, 4, aAvoid, 2)) {
        _fFpsX = x;
        _fFpsY = y2;
        bFound = 1;
      }
    }
  }

  // CAMERA in the top row, as near its middle as it keeps clear of the HUD's
  // boxes, the FPS readout and the buttons either side (in Jedi Knight it is
  // in the middle); where the row has no room for it, the same a row lower.
  // Its burst counter goes right of it, or under it where that is in the
  // way.
  {
    const IOSTouchRect rFps = { 1, _fFpsX - IOSTOUCH_FPS_W * 0.5, _fFpsY - IOSTOUCH_FPS_H * 0.5,
                                _fFpsX + IOSTOUCH_FPS_W * 0.5, _fFpsY + IOSTOUCH_FPS_H * 0.5 };
    const IOSTouchRect *const apr[4] = { prScore, prHiScore, prMessages, &rFps };
    const int aAvoid[5] = { BTN_NEXTWPN, BTN_PREVWPN, BTN_QUICKSAVE, BTN_QUICKLOAD, BTN_MENU };
    IOSTouchButton *c = &_aButtons[BTN_CAMERA];
    const double r = c->radius, mid = (left + right) * 0.5;
    int bFound = 0;
    for (int row = 0; row < 2 && !bFound; row++) {
      const double y = top + 26 + row * 52;
      for (double d = 0; d <= (right - left) * 0.5 && !bFound; d += 2) {
        for (int side = 0; side < 2 && !bFound; side++) {
          const double x = side ? mid - d : mid + d;
          if (x - r < left || x + r > right) continue;
          if (IOSTouch_BoxIsClear(x, y, r, r, apr, 4, aAvoid, 5)) {
            c->x = x;
            c->y = y;
            bFound = 1;
          }
        }
      }
    }
    if (!bFound) {
      c->x = mid;
      c->y = top + 26 + 52;
    }
  }

  // CHEAT in the top row beside CAMERA: the nearest place right of it, or
  // else left of it, clear of the HUD's boxes, the FPS readout and the
  // buttons either side; where the row has no room, under CAMERA
  {
    const IOSTouchRect rFps = { 1, _fFpsX - IOSTOUCH_FPS_W * 0.5, _fFpsY - IOSTOUCH_FPS_H * 0.5,
                                _fFpsX + IOSTOUCH_FPS_W * 0.5, _fFpsY + IOSTOUCH_FPS_H * 0.5 };
    const IOSTouchRect *const apr[4] = { prScore, prHiScore, prMessages, &rFps };
    const int aAvoid[6] = { BTN_NEXTWPN, BTN_PREVWPN, BTN_QUICKSAVE, BTN_QUICKLOAD, BTN_MENU, BTN_CAMERA };
    const IOSTouchButton *c = &_aButtons[BTN_CAMERA];
    IOSTouchButton *h = &_aButtons[BTN_CHEAT];
    const double r = h->radius, y = c->y;
    int bFound = 0;
    for (double d = 2 * r + 8; d <= right - left && !bFound; d += 2) {
      for (int side = 0; side < 2 && !bFound; side++) {
        const double x = side ? c->x - d : c->x + d;
        if (x - r < left || x + r > right) continue;
        if (IOSTouch_BoxIsClear(x, y, r, r, apr, 4, aAvoid, 6)) {
          h->x = x;
          h->y = y;
          bFound = 1;
        }
      }
    }
    if (!bFound) {
      h->x = c->x;
      h->y = c->y + c->radius + 8 + r;
    }
  }

  // The messages, centred under the top row
  _fCamMessageX = (left + right) * 0.5;
  _fCamMessageY = fmax(top + 26 + 22, fmax(_aButtons[BTN_CAMERA].y + _aButtons[BTN_CAMERA].radius,
                                           _aButtons[BTN_CHEAT].y + _aButtons[BTN_CHEAT].radius));
  if (prHiScore->bValid) _fCamMessageY = fmax(_fCamMessageY, prHiScore->y1);
  if (prMessages->bValid) _fCamMessageY = fmax(_fCamMessageY, prMessages->y1);
  _fCamMessageY += 16;

  // RESUME in the middle of the screen, below the game's "Paused" (centred
  // at 0.4 of the height of the HUD's frame, as in Serious Sam)
  {
    double fl, ft, fr, fb;
    IOSTouch_HudFrameInsets(inLeft, inTop, inRight, inBottom, &fl, &ft, &fr, &fb);
    _aButtons[BTN_RESUME].x = (left + right) * 0.5;
    _aButtons[BTN_RESUME].y = fmax((top + bottom) * 0.5, ft + (H - ft - fb) * 0.4 + 60.0);
  }

  // The weapon wheel, over the middle of the screen
  IOSTouch_WheelGeometry(W, H, inLeft, inTop, inRight, inBottom, &_fWheelCX, &_fWheelCY, &_fWheelR0, &_fWheelR1);
}

// A HUD box (fractions of the screen) in points
static IOSTouchRect IOSTouch_RectInPoints(const IOSTouchRect *prFrac, double W, double H)
{
  IOSTouchRect r = { 0, 0, 0, 0, 0 };
  if (prFrac->bValid) {
    r.bValid = 1;
    r.x0 = prFrac->x0 * W;
    r.y0 = prFrac->y0 * H;
    r.x1 = prFrac->x1 * W;
    r.y1 = prFrac->y1 * H;
  }
  return r;
}

// The HUD's frame (fractions of the screen), from the game view's size and
// safe-area insets once a frame (IOSTouch_UpdateOverlay)
static float _afHudFrame[4] = { 0.0f, 0.0f, 1.0f, 1.0f };

static void IOSTouch_SetHudFrame(double W, double H, double inLeft, double inTop, double inRight, double inBottom)
{
  if (W <= 0.0 || H <= 0.0) return;
  double fl, ft, fr, fb;
  IOSTouch_HudFrameInsets(inLeft, inTop, inRight, inBottom, &fl, &ft, &fr, &fb);
  _afHudFrame[0] = (float)(fl / W);
  _afHudFrame[1] = (float)(ft / H);
  _afHudFrame[2] = (float)(1.0 - fr / W);
  _afHudFrame[3] = (float)(1.0 - fb / H);
}

void IOSTouch_GetHudFrame(float afFrame[4])
{
  memcpy(afFrame, _afHudFrame, sizeof(_afHudFrame));
}

// ---------------------------------------------------------------- touches
// Main thread. The overlay view hands each touch to IOSTouch_TouchBegan /
// Passed / Moved / Ended (points, seconds) and calls IOSTouch_TickHolds once
// a frame; it shows what the state below says.

typedef enum {
  ROLE_NONE = 0,
  ROLE_STICK,
  ROLE_LOOK,
  ROLE_BUTTON,
  ROLE_IGNORED,  // not on a button while only buttons are live, or only closed MENU's tray; ignored until it lifts
  ROLE_WHEEL,    // on the open weapon wheel (or the NEXT/PREV touch that opened it)
} IOSTouchRole;

typedef struct {
  const void *touch;    // the UITouch: only compared, never used after it ends (NULL: a free slot)
  IOSTouchRole role;
  int button;
  double x, y;          // where it is now
  double tDown;         // when it began
  int bFired;           // QUICK SAVE, QUICK LOAD: the hold is over (a save or load was asked for, by this finger or
                        // another one on either button, or it slid off). MENU: the hold is over (tray opened, or
                        // slid off). CAMERA: the gesture is decided (a slide or the hold went off). ITEM: it slid
                        // (to pick items), so its lift uses none
  int trayButton;       // MENU, after its tray opened: the tray button under the finger, or -1
  // Where it went down (NEXT WPN, PREV WPN: a slide's distance and aim are measured from there; CAMERA's and
  // ITEM's slides too; the cheat's holds keep still from there)
  double xDown, yDown;
  int iItemSteps;       // ITEM: the item steps its slide has made (+ right, - left)
  // NEXT WPN, PREV WPN: when it went down by the touch's own clock (UITouch.timestamp: a tap is told from a
  // hold by it, so a slow frame between the two doesn't make a tap long). bFired: no tap any more (it slid or
  // held while the wheel couldn't open). On the wheel: the slice picked (an index into the wheel's map,
  // IOSTOUCH_WHEEL_CANCEL, or -1); whether it is the touch that opened it, and opened it by holding still (it
  // is open to tap until this slides IOSTOUCH_WHEEL_DEAD), whether it has slid out of the dead zone, where
  // its slide is measured from and which way it points (degrees, counter-clockwise from pointing right)
  double tDownTouch;
  int wheelSlot;
  int bWheelOpener, bWheelHeld, bArmed;
  double wheelOriginX, wheelOriginY;
  double wheelAim;
  unsigned int uSeq;    // the order the touches went down in (IOSTouch_WheelPointed: the newest finger)
  // The cheat: CHEAT's hold, or JUMP's or USE's, is over (done, slid, or nothing to do)
  int bCheatDone;
} IOSTouchSlot;

static IOSTouchSlot _aSlots[IOSTOUCH_MAX_TOUCHES];
static unsigned int _uTouchSeq = 0;
static int _aButtonHeld[IOSTOUCH_NUM_BUTTONS]; // touches on each button
static int _bStickActive = 0;
static double _fStickOriginX = 0.0, _fStickOriginY = 0.0; // where the stick's thumb came down
static float _fStickX = 0.0f, _fStickY = 0.0f;           // -1..1 of the radius, screen axes
static int _iMode = IOSTOUCH_HIDDEN;
static int _iRequests = 0;                 // IOSTOUCH_REQ_* not handed out yet
static IOSTouchHud _hud;                   // the latest HUD state
static int _bTrayOpen = 0;                 // MENU's tray
// The look speed (a step of _afLookSteps, or what the app's settings had),
// LOOK's hold's ring, and the times it was held back to 1x (a haptic thump
// for each, the view's)
static float _fLookScale = 1.0f;
static float _fLookRing = 0.0f;
static int _ctLookResets = 0;
static int _bShowFps = 0;                  // the FPS readout (the view keeps it in the app's settings)
// The frame rate asked of the screen: 60, or 120 on a ProMotion screen
// (smoother, more battery). The tray's FPS held switches it, with a ring;
// the view keeps it in the app's settings and asks the screen for it
static int _iMaxFps = 60;
// The tray's OPACITY: how strongly the touch controls show in play
// (IOSTOUCH_OPACITY_MIN to 1, IOSTOUCH_OPACITY_STEP steps; 1, the default,
// as they always were), with its slider under the tray (tapped open), held
// back to 1 (a ring). The tray itself, and the wheels, stay at full. The
// view keeps it in the app's settings.
#define IOSTOUCH_OPACITY_MIN 0.10f
#define IOSTOUCH_OPACITY_STEP 0.05f
static float _fOpacity = 1.0f;
static int _bOpacityOpen = 0;
static float _fOpacityRing = 0.0f;
static int _ctOpacityResets = 0;

// The frame rate asked for in the tray (FPS held): 60 or 120
int IOSTouch_MaxFps(void)
{
  return _iMaxFps;
}

static float IOSTouch_OpacityStep(float k)
{
  if (!(k == k)) return 1.0f;
  if (k < IOSTOUCH_OPACITY_MIN) return IOSTOUCH_OPACITY_MIN;
  if (k > 1.0f) return 1.0f;
  return roundf(k / IOSTOUCH_OPACITY_STEP) * IOSTOUCH_OPACITY_STEP;
}
static float _fFpsRing = 0.0f;
static int _ctMaxFpsChanges = 0;
// CAMERA: whether it shows (the view keeps it in the app's settings), its
// selfie hold's ring and the tray CAMERA's (held for the options)
static int _bShowCamera = 1;
static float _fCameraRing = 0.0f, _fCamSwitchRing = 0.0f;
// The cheat (sithewok): its button showing (kept in the app's settings); on
// (never kept: off each time the app opens); flying (Shadow Warrior). CHEAT's
// ring, and JUMP's and USE's; the list of levels open (the game holds still)
// and the level picked from it, for the game; when the last quick still JUMP
// tap lifted (the touches' clock; flying, a second one soon after lands);
// haptic ticks the view still has to give; the last level seen.
static int _bShowCheat = 0, _bCheatOn = 0, _bFlying = 0;
static float _fCheatRing = 0.0f;
static float _afCheatActRing[2] = { 0.0f, 0.0f }; // JUMP, USE
static int _bLevelListOpen = 0, _iLevelPicked = 0;
static double _tJumpTapLift = -1.0;
static double _tFlyAsked = -1.0e9; // when flying was last asked for or against
static int _ctCheatTicks = 0;
static unsigned int _uWorldSeen = 0;
// The touch controls hidden while a game controller is played (IOSTouch_SetPadHidden)
static int _bPadHidden = 0;
// The message line, what it says and when it came
static char _strCamMessage[192] = "";
static double _tCamMessage = -1.0e9;
static double _fCamMessageTime = IOSTOUCH_CAMERA_MESSAGE_TIME; // how long it shows
// how far QUICK SAVE's, QUICK LOAD's and MENU's hold rings have filled
static float _fSaveRing = 0.0f, _fLoadRing = 0.0f, _fMenuRing = 0.0f;
static double _tLastTick = 0.0;            // when IOSTouch_TickHolds last ran (0: not since the last reset)
// The FPS readout: frames counted since _ulFpsFrames at _tFpsBase, and the
// number it shows (-1: none measured yet)
static int _bFpsBase = 0;
static unsigned int _ulFpsFrames = 0;
static double _tFpsBase = 0.0;
static int _iFpsShown = -1;
// Tilt aiming: its mode and sensitivity (an index into _afGyroSens; the view
// keeps both in the app's settings), whether the device has device motion
// (the view sets it) and whether iOS refused it; whether the motion updates
// are running, whether the last frame could have aimed (and when it was);
// the landscape side the screen was last turned and when it turned round to
// it. Under _gyroLock, as the samples come in on the motion queue: which way
// round the screen is (+1 landscape left, -1 landscape right, 0 neither, so
// no aiming), how far the view is to turn (degrees, + left) and tilt (+ up)
// for the samples since the last frame, what the samples keep (the last
// one's time, the smoothing's), and whether one came back refused.
enum { IOSTOUCH_GYRO_OFF = 0, IOSTOUCH_GYRO_TOUCH, IOSTOUCH_GYRO_ALWAYS, IOSTOUCH_GYRO_NUM_MODES };
static const float _afGyroSens[] = { 1.0f, 1.5f, 2.0f, 3.0f };
#define IOSTOUCH_GYRO_NUM_SENS ((int)(sizeof(_afGyroSens) / sizeof(_afGyroSens[0])))
static int _iGyroMode = IOSTOUCH_GYRO_OFF; // until it is switched on in MENU's tray
static int _iGyroSens = IOSTOUCH_GYRO_DEFAULT_SENS;
static int _bGyroAvailable = 0;
static int _bGyroRefused = 0;
static int _bGyroRunning = 0;
static int _bGyroWasOk = 0;
static double _tGyroLastFrame = 0.0;
static int _iGyroLastSide = 0;
static double _tGyroTurnedRound = -1.0e9;
static os_unfair_lock _gyroLock = OS_UNFAIR_LOCK_INIT;
static int _iGyroSide = 0;
static double _fGyroQueueYaw = 0.0, _fGyroQueuePitch = 0.0;
static double _tGyroLastSample = 0.0;
static double _afGyroSmooth[IOSTOUCH_GYRO_SMOOTH_N][2];
static int _iGyroSmoothNext = 0;
static int _bGyroRefusedOnQueue = 0;

// Whether this device has what tilt aiming needs (not the Simulator), and
// iOS hasn't refused it
static int IOSTouch_GyroAvailable(void)
{
  return _bGyroAvailable && !_bGyroRefused;
}

// The next mode or sensitivity (MENU's tray's GYRO and SENS)
static void IOSTouch_GyroNextMode(void)
{
  _iGyroMode = (_iGyroMode + 1) % IOSTOUCH_GYRO_NUM_MODES;
}
static void IOSTouch_GyroNextSens(void)
{
  _iGyroSens = (_iGyroSens + 1) % IOSTOUCH_GYRO_NUM_SENS;
}

// Whether the tray's LEVEL is in the tray: playing a game that has levels to
// pick, in single player (ctLevels is 0 in network games), cheat on or off
static int IOSTouch_LevelPickShows(void)
{
  return _hud.ctLevels > 0 && _iMode == IOSTOUCH_GAMEPLAY;
}

// Whether a button shows now
static int IOSTouch_IsShown(int button)
{
  if (!(_aButtons[button].iShowIn & (1 << _iMode))) return 0;
  if (button == BTN_SECONDARY) return _hud.bValid && _hud.iSecondary != IOSTOUCH_SEC_NONE;
  if (button == BTN_ITEM) return _hud.bValid && _hud.bItem;
  if (button == BTN_CAMERA) return _bShowCamera;
  if (button == BTN_CHEAT) return _bShowCheat;
  if (button == BTN_QUICKSAVE || button == BTN_QUICKLOAD) return !_hud.bNoSaves;
  if (button == BTN_TRAYLEVEL) return _bTrayOpen && IOSTouch_LevelPickShows();
  if (button >= BTN_TRAYLOOK && button <= BTN_TRAYKEYS) return _bTrayOpen;
  return 1;
}

// Closest showing button the touch is on (with a little forgiveness), so a
// touch in the gap between two buttons picks the nearer one rather than the
// first listed. The open MENU tray is drawn on top of the rest, so its
// buttons come first: anywhere on its backing (which reaches as far round
// each as that forgiveness does) is on the nearest one, the corners between
// two of them too.
static int IOSTouch_ButtonAt(double x, double y)
{
  int best = -1;
  double bestDist = 0;
  {
    const IOSTouchButton *l = &_aButtons[BTN_TRAYLOOK], *r = &_aButtons[BTN_TRAYKEYS];
    if (IOSTouch_IsShown(BTN_TRAYLOOK) && IOSTouch_DistToSegment(x, y, l->x, l->y, r->x, r->y) <= 26.0) {
      for (int i = BTN_TRAYLOOK; i <= BTN_TRAYKEYS; i++) {
        const double d = fabs(x - _aButtons[i].x);
        if (!IOSTouch_IsShown(i)) continue; // (the tray's LEVEL while the cheat is off)
        if (best < 0 || d < bestDist) {
          best = i;
          bestDist = d;
        }
      }
      return best;
    }
  }
  for (int i = 0; i < IOSTOUCH_NUM_BUTTONS; i++) {
    const IOSTouchButton *b = &_aButtons[i];
    if (!IOSTouch_IsShown(i)) continue;
    const double d = hypot(x - b->x, y - b->y);
    if (d <= b->radius + 6.0 && (best < 0 || d - b->radius < bestDist)) {
      best = i;
      bestDist = d - b->radius;
    }
  }
  return best;
}

static int IOSTouch_IsOnButton(double x, double y, int button)
{
  const IOSTouchButton *b = &_aButtons[button];
  return hypot(x - b->x, y - b->y) <= b->radius + 6.0;
}

static int IOSTouch_IsTrayButton(int button);

// Whether a finger lifting at (x,y) lifts on the button it came down on: on
// it -- or, for one of the open tray's, anywhere on the backing nearer it
// than the others (as IOSTouch_ButtonAt has it)
static int IOSTouch_LiftsOnButton(double x, double y, int button)
{
  return IOSTouch_IsOnButton(x, y, button) || (IOSTouch_IsTrayButton(button) && IOSTouch_ButtonAt(x, y) == button);
}

// MENU's tray's buttons (all act as the touch lifts, and keep the tray open)
static int IOSTouch_IsTrayButton(int button)
{
  return button >= BTN_TRAYLOOK && button <= BTN_TRAYKEYS;
}

// QUICK SAVE and QUICK LOAD: the holds that end for good when the finger leaves the button
static int IOSTouch_IsQuickHold(int button)
{
  return button == BTN_QUICKSAVE || button == BTN_QUICKLOAD;
}

static IOSTouchSlot *IOSTouch_FindSlot(const void *touch)
{
  for (int i = 0; i < IOSTOUCH_MAX_TOUCHES; i++) {
    if (_aSlots[i].touch == touch) return &_aSlots[i];
  }
  return NULL;
}

// The stick as movement: nothing inside the dead zone, full speed from
// IOSTOUCH_STICK_FULL of the radius out, in the direction it is pushed
static void IOSTouch_SetMoveFromStick(void)
{
  float fX = 0.0f, fY = 0.0f;
  const float fLen = sqrtf(_fStickX * _fStickX + _fStickY * _fStickY);
  if (_bStickActive && fLen > IOSTOUCH_STICK_DEADZONE) {
    float fSpeed = (fLen - IOSTOUCH_STICK_DEADZONE) / (IOSTOUCH_STICK_FULL - IOSTOUCH_STICK_DEADZONE);
    if (fSpeed > 1.0f) fSpeed = 1.0f;
    fX = _fStickX / fLen * fSpeed;
    fY = -_fStickY / fLen * fSpeed; // up the screen is forward
  }
  os_unfair_lock_lock(&_lock);
  _fMoveX = fX;
  _fMoveY = fY;
  os_unfair_lock_unlock(&_lock);
}

// The game buttons the touches on KIND_HOLD buttons hold down
static unsigned int IOSTouch_HeldButtons(void)
{
  unsigned int ul = 0;
  for (int i = 0; i < IOSTOUCH_NUM_BUTTONS; i++) {
    if (_aButtonHeld[i] && _aButtons[i].kind == KIND_HOLD) ul |= _aButtons[i].ulAction;
  }
  return ul;
}

// Opens or closes MENU's tray. Closing it lets go of any touch on its buttons.
static void IOSTouch_SetTrayOpen(int bOpen)
{
  bOpen = bOpen != 0;
  if (_bTrayOpen == bOpen) return;
  _bTrayOpen = bOpen;
  if (!bOpen) _bOpacityOpen = 0;
  if (!bOpen) {
    for (int i = 0; i < IOSTOUCH_MAX_TOUCHES; i++) {
      IOSTouchSlot *s = &_aSlots[i];
      if (!s->touch || s->role != ROLE_BUTTON) continue;
      if (IOSTouch_IsTrayButton(s->button)) {
        if (_aButtonHeld[s->button] > 0) _aButtonHeld[s->button]--;
        s->role = ROLE_IGNORED;
      }
      s->trayButton = -1;
    }
  }
}

// Shows or hides the FPS readout; it starts counting afresh
static void IOSTouch_SetShowFps(int bShow)
{
  _bShowFps = bShow != 0;
  _bFpsBase = 0;
  _iFpsShown = -1;
}

// ---------------------------------------------------------------- messages

static void IOS_ShowCameraMessage(const char *str)
{
  IOSTouch_ShowMessage(str, IOSTOUCH_CAMERA_MESSAGE_TIME);
}

void IOSTouch_ShowMessage(const char *str, double fSeconds)
{
  snprintf(_strCamMessage, sizeof(_strCamMessage), "%s", str ? str : "");
  _tCamMessage = CACurrentMediaTime();
  _fCamMessageTime = fSeconds;
}

// Lets go of every touch but s (it carries on as it is): they are ignored
// until they lift. MENU's tray closes; the stick stops.
static void IOSTouch_DropTouches(const IOSTouchSlot *s)
{
  IOSTouch_SetTrayOpen(0);
  for (int i = 0; i < IOSTOUCH_MAX_TOUCHES; i++) {
    IOSTouchSlot *o = &_aSlots[i];
    if (!o->touch || o == s) continue;
    if (o->role == ROLE_BUTTON && _aButtonHeld[o->button] > 0) _aButtonHeld[o->button]--;
    if (o->role == ROLE_STICK) {
      _bStickActive = 0;
      _fStickX = _fStickY = 0.0f;
    }
    o->role = ROLE_IGNORED;
  }
  _fSaveRing = _fLoadRing = _fMenuRing = _fLookRing = _fFpsRing = _fOpacityRing = 0.0f;
  IOSTouch_SetMoveFromStick();
  IOSTouch_SetHeld(IOSTouch_HeldButtons(), 0);
}

// ---------------------------------------------------------------- CAMERA
// CAMERA's gestures; the camera system (iosCamera.h) does the work. While it
// is busy (a selfie, Action Freeze, the cinematic burst, a photo being
// saved) CAMERA is dimmed and a new press on it does nothing.

static int IOSTouch_CameraBusy(void)
{
  return iosCamera_IsBusy() != 0;
}

static void IOSTouch_SetShowCamera(int bShow)
{
  _bShowCamera = bShow != 0;
}

static void IOSTouch_UseCheatSwitch(void); // (the cheat, below)
static void IOSTouch_OpenLevelList(void);

// The next look speed up from the one now, round to the first (from one
// between two steps: the step above it)
static void IOSTouch_LookNextStep(void)
{
  float next = _afLookSteps[0];
  for (int k = 0; k < IOSTOUCH_LOOK_NUM_STEPS; k++) {
    if (_afLookSteps[k] > _fLookScale + 0.01f) {
      next = _afLookSteps[k];
      break;
    }
  }
  _fLookScale = next;
}

// A tray button picked: it does its thing, and the tray closes -- except
// after LOOK, GYRO and SENS, which stay for another tap to go on to the next
// (with no gyro, GYRO and SENS do nothing)
static void IOSTouch_UseTrayButton(int button)
{
  const int kind = _aButtons[button].kind;
  if (kind == KIND_CAMSWITCH) {
    IOSTouch_SetShowCamera(!_bShowCamera);
  }
  else if (kind == KIND_CHEATSWITCH) {
    IOSTouch_UseCheatSwitch();
  }
  else if (kind == KIND_LEVELPICK) {
    IOSTouch_OpenLevelList(); // (the tray closes)
    return;
  }
  else if (kind == KIND_LOOKSPEED) {
    IOSTouch_LookNextStep(); // (the tray stays)
    return;
  }
  else if (kind == KIND_KEYBOARD) {
    _iRequests |= _aButtons[button].ulAction; // the console, with the iOS keyboard
  }
  else if (kind == KIND_GAMES) {
    _iRequests |= _aButtons[button].ulAction; // "Switch game", over the game
  }
  else if (kind == KIND_OPACITY) {
    _bOpacityOpen = !_bOpacityOpen; // its slider (the tray stays)
    return;
  }
  else if (kind == KIND_FPS) {
    IOSTouch_SetShowFps(!_bShowFps);
  }
  else if ((kind == KIND_GYRO || kind == KIND_GYROSENS) && IOSTouch_GyroAvailable()) {
    if (kind == KIND_GYRO) IOSTouch_GyroNextMode();
    else IOSTouch_GyroNextSens();
  }
  if (kind != KIND_GYRO && kind != KIND_GYROSENS) IOSTouch_SetTrayOpen(0);
}

// ---------------------------------------------------------------- weapon wheel
// One slice per weapon of the game being played, in the order NEXT WPN goes
// through them, clockwise from the bottom left, the gap at the bottom to
// cancel. The weapon numbers are the game's own (IOSTouchWeapons). Each
// slice is tinted by the kind of ammo it takes. The name shows in the slice
// and in the middle, on two lines where it doesn't fit one: at its middle
// space, or after the hyphen given here. A weapon and its alternate (Duke's
// shrinker and expander, Redneck Rampage's ripsaw and buzzsaw...) each get
// a slice. Slices are 320/n degrees wide, which leaves a 40 degree gap at
// the bottom (Serious Sam's widths: 14 slices of 23, 11 of 29).
enum { WCOL_NONE = 0, WCOL_SHELLS, WCOL_BULLETS, WCOL_ROCKETS, WCOL_GRENADES, WCOL_NAPALM, WCOL_SNIPER,
       WCOL_ELECTRICITY, WCOL_CANNONBALLS, WCOL_COUNT };
static const unsigned char _aubWheelColours[WCOL_COUNT][3] = {
  { 255, 214, 120 }, { 255, 160, 80 }, { 120, 200, 255 }, { 255, 105, 90 }, { 110, 220, 170 },
  { 255, 190, 60 }, { 190, 150, 255 }, { 90, 230, 230 }, { 200, 200, 215 },
};
typedef struct {
  int iWeapon;
  int iColour;
  const char *strName;
  const char *strName2; // on two lines ("\n"), when it has no space to break at
} IOSTouchWheelSlot;
typedef struct {
  const IOSTouchWheelSlot *aSlots;
  int ctSlots;
  double fSliceDeg; // each slice's width; the gap at the bottom is what is left
} IOSTouchWheelMap;
#define IOSTOUCH_WHEEL_MAX 14
// Duke Nukem 3D (dukeweapon_t; the expander is the Atomic Edition's, the
// incinerator World Tour's: a slice only where the game has them)
static const IOSTouchWheelSlot _aWheelDukeWT[] = {
  {  0, WCOL_NONE,        "MIGHTY FOOT",      NULL }, {  1, WCOL_BULLETS,     "PISTOL",           NULL },
  {  2, WCOL_SHELLS,      "SHOTGUN",          NULL }, {  3, WCOL_BULLETS,     "RIPPER",           NULL },
  {  4, WCOL_ROCKETS,     "RPG",              NULL }, {  5, WCOL_GRENADES,    "PIPE BOMB",        NULL },
  {  6, WCOL_ELECTRICITY, "SHRINKER",         "SHRINK-\nER" }, { 11, WCOL_SNIPER, "EXPANDER",     "EXPAND-\nER" },
  {  7, WCOL_ROCKETS,     "DEVASTATOR",       "DEVAS-\nTATOR" }, {  8, WCOL_GRENADES, "TRIP BOMB",  NULL },
  {  9, WCOL_CANNONBALLS, "FREEZETHROWER",    "FREEZE-\nTHROWER" }, { 12, WCOL_NAPALM, "INCINERATOR", "INCINER-\nATOR" },
};
// (the same less the incinerator)
#define IOSTOUCH_WHEEL_DUKE_CT 11
// Redneck Rampage (the same numbers: names.h), Rides Again with the sling
// blade and the chicken bow
static const IOSTouchWheelSlot _aWheelRRRA[] = {
  {  0, WCOL_NONE,        "CROWBAR",          NULL }, { 15, WCOL_NONE,        "SLING BLADE",      NULL },
  {  1, WCOL_BULLETS,     "REVOLVER",         NULL }, {  2, WCOL_SHELLS,      "SHOTGUN",          NULL },
  {  3, WCOL_BULLETS,     "RIFLE",            NULL }, {  4, WCOL_GRENADES,    "DYNAMITE",         NULL },
  {  5, WCOL_ROCKETS,     "CROSSBOW",         NULL }, { 16, WCOL_ROCKETS,     "CHICKEN BOW",      NULL },
  {  6, WCOL_CANNONBALLS, "RIPSAW",           NULL }, { 11, WCOL_CANNONBALLS, "BUZZSAW",          NULL },
  {  7, WCOL_ELECTRICITY, "ALIEN ARM GUN",    NULL }, {  8, WCOL_NAPALM,      "POWDER KEG",       NULL },
  { 12, WCOL_NAPALM,      "BOWLING BALL",     NULL }, {  9, WCOL_SNIPER,      "TEAT GUN",         NULL },
};
static const IOSTouchWheelSlot _aWheelRR[] = {
  {  0, WCOL_NONE,        "CROWBAR",          NULL }, {  1, WCOL_BULLETS,     "REVOLVER",         NULL },
  {  2, WCOL_SHELLS,      "SHOTGUN",          NULL }, {  3, WCOL_BULLETS,     "RIFLE",            NULL },
  {  4, WCOL_GRENADES,    "DYNAMITE",         NULL }, {  5, WCOL_ROCKETS,     "CROSSBOW",         NULL },
  {  6, WCOL_CANNONBALLS, "RIPSAW",           NULL }, { 11, WCOL_CANNONBALLS, "BUZZSAW",          NULL },
  {  7, WCOL_ELECTRICITY, "ALIEN ARM GUN",    NULL }, {  8, WCOL_NAPALM,      "POWDER KEG",       NULL },
  { 12, WCOL_NAPALM,      "BOWLING BALL",     NULL }, {  9, WCOL_SNIPER,      "TEAT GUN",         NULL },
};
// Blood (kWeap*; the beast's claws aren't picked)
static const IOSTouchWheelSlot _aWheelBlood[] = {
  {  1, WCOL_NONE,        "PITCHFORK",        "PITCH-\nFORK" }, {  2, WCOL_NAPALM,  "FLARE GUN",    NULL },
  {  3, WCOL_SHELLS,      "SHOTGUN",          NULL }, {  4, WCOL_BULLETS,     "TOMMY GUN",        NULL },
  {  5, WCOL_NAPALM,      "NAPALM LAUNCHER",  NULL }, {  6, WCOL_GRENADES,    "TNT",              NULL },
  {  7, WCOL_ROCKETS,     "SPRAY CAN",        NULL }, {  8, WCOL_ELECTRICITY, "TESLA CANNON",     NULL },
  {  9, WCOL_SNIPER,      "LIFE LEECH",       NULL }, { 10, WCOL_CANNONBALLS, "VOODOO DOLL",      NULL },
  { 11, WCOL_GRENADES,    "PROXIMITY TNT",    NULL }, { 12, WCOL_GRENADES,    "REMOTE TNT",       NULL },
};
// Shadow Warrior (WPN_*: the sword is 13)
static const IOSTouchWheelSlot _aWheelSW[] = {
  {  0, WCOL_NONE,        "FISTS",            NULL }, { 13, WCOL_NONE,        "SWORD",            NULL },
  {  1, WCOL_CANNONBALLS, "SHURIKENS",        "SHURI-\nKENS" }, {  2, WCOL_SHELLS, "RIOT GUN",    NULL },
  {  3, WCOL_BULLETS,     "UZI",              NULL }, {  4, WCOL_ROCKETS,     "MISSILES",         NULL },
  {  5, WCOL_GRENADES,    "GRENADES",         "GRE-\nNADES" }, {  6, WCOL_GRENADES, "STICKY BOMBS", NULL },
  {  7, WCOL_ELECTRICITY, "RAIL GUN",         NULL }, {  8, WCOL_NAPALM,      "GUARDIAN HEAD",    NULL },
  {  9, WCOL_SNIPER,      "RIPPER HEART",     NULL },
};
// Exhumed / PowerSlave (kWeapon*)
static const IOSTouchWheelSlot _aWheelExhumed[] = {
  {  0, WCOL_NONE,        "MACHETE",          NULL }, {  1, WCOL_BULLETS,     "MAGNUM",           NULL },
  {  2, WCOL_BULLETS,     "M-60",             NULL }, {  3, WCOL_NAPALM,      "FLAMETHROWER",     "FLAME-\nTHROWER" },
  {  4, WCOL_GRENADES,    "GRENADES",         "GRE-\nNADES" }, {  5, WCOL_ELECTRICITY, "COBRA STAFF", NULL },
  {  6, WCOL_SNIPER,      "RING OF RA",       NULL },
};
#define WHEEL_COUNT(a) ((int)(sizeof(a) / sizeof((a)[0])))
#define WHEEL_MAP(a, ct) { a, ct, 320.0 / (ct) }
static const IOSTouchWheelMap _aWheelMaps[IOSTOUCH_WHEEL_NUM] = {
  [IOSTOUCH_WHEEL_NONE]    = { _aWheelDukeWT, 0, 30.0 },
  [IOSTOUCH_WHEEL_DUKE]    = WHEEL_MAP(_aWheelDukeWT, IOSTOUCH_WHEEL_DUKE_CT),
  [IOSTOUCH_WHEEL_DUKEWT]  = WHEEL_MAP(_aWheelDukeWT, WHEEL_COUNT(_aWheelDukeWT)),
  [IOSTOUCH_WHEEL_RR]      = WHEEL_MAP(_aWheelRR, WHEEL_COUNT(_aWheelRR)),
  [IOSTOUCH_WHEEL_RRRA]    = WHEEL_MAP(_aWheelRRRA, WHEEL_COUNT(_aWheelRRRA)),
  [IOSTOUCH_WHEEL_BLOOD]   = WHEEL_MAP(_aWheelBlood, WHEEL_COUNT(_aWheelBlood)),
  [IOSTOUCH_WHEEL_SW]      = WHEEL_MAP(_aWheelSW, WHEEL_COUNT(_aWheelSW)),
  [IOSTOUCH_WHEEL_EXHUMED] = WHEEL_MAP(_aWheelExhumed, WHEEL_COUNT(_aWheelExhumed)),
};
typedef char IOSTouch_assertWheelSize[(WHEEL_COUNT(_aWheelDukeWT) <= IOSTOUCH_WHEEL_MAX && WHEEL_COUNT(_aWheelRRRA) <= IOSTOUCH_WHEEL_MAX
                                       && WHEEL_COUNT(_aWheelBlood) <= IOSTOUCH_WHEEL_MAX && WHEEL_COUNT(_aWheelSW) <= IOSTOUCH_WHEEL_MAX) ? 1 : -1];

// A slice's state, from what the game says
enum { WSTATE_READY = 0, WSTATE_NOAMMO, WSTATE_NOTFOUND };

// What the game said last (IOSTouch_SetWeapons); the wheel: open or not
// (and whether open to tap a slice), the button that opened it and the map
// it shows; the NEXT/PREV hold rings; what was pointed at last and the haptic
// ticks the view still has to give (one each time the thumb moves onto
// another slice or the gap)
static IOSTouchWeapons _wpn;
static int _bWheelOpen = 0, _bWheelTapMode = 0, _iWheelButton = BTN_NEXTWPN, _iWheelMap = IOSTOUCH_WHEEL_NONE;
static float _afWheelRing[2] = { 0.0f, 0.0f }; // NEXT WPN's, PREV WPN's
static int _iWheelHot = -1;
static int _ctWheelTicks = 0;

// ---------------------------------------------------------------- the cheat
// sithewok, on Raze's own cheats: on, the game's god mode comes on and it
// gives everything ("give all"), again at each new level, and keeps the
// ammo full (IOSGame.cpp, on IOSTOUCH_REQ_CHEATON); off, god mode goes off
// and the player keeps what was given. CHEAT on the top row: held, on or off
// (grey); the tray's CHEAT: shows it and switches the cheat on, or leaves
// cheat mode (off, CHEAT gone); the word typed in the console: on (CHEAT
// shows, if it was gone), or off (CHEAT goes). While it's on, USE held still:
// the game's noclip on or off; JUMP held still: flying, in Shadow Warrior
// (the one that can fly; two quick taps on JUMP land); the tray's LEVEL: the
// list of levels, to tap one (the view's level panel). CROUCH only crouches:
// held still behind cover, it mustn't change the level.

static void IOSTouch_CheatNotAllowed(void)
{
  IOS_ShowCameraMessage(_hud.strCheatRefusal ? _hud.strCheatRefusal : "The cheat works in a level being played");
}

static void IOSTouch_SetCheat(int bOn)
{
  bOn = bOn != 0;
  if (bOn == _bCheatOn) return;
  _bCheatOn = bOn;
  _iRequests |= bOn ? IOSTOUCH_REQ_CHEATON : IOSTOUCH_REQ_CHEATOFF;
  if (!bOn) {
    // (what it gave is kept: the game does that) flying and noclip end
    // (asked in the same frame as god mode goes off: the game flies only in god mode)
    if (_hud.bFlying) _iRequests |= IOSTOUCH_REQ_FLY;
    if (_hud.bNoclip) _iRequests |= IOSTOUCH_REQ_NOCLIP;
    _bFlying = 0;
    _bLevelListOpen = 0;
  }
}

// CHEAT held: on (coloured) or off (grey); CHEAT stays
static void IOSTouch_ToggleCheat(void)
{
  if (!_bCheatOn && !_hud.bCheatAllowed) {
    IOSTouch_CheatNotAllowed();
    return;
  }
  IOSTouch_SetCheat(!_bCheatOn);
  IOS_ShowCameraMessage(_bCheatOn ? "Cheat on" : "Cheat off");
  _ctCheatTicks++;
}

// The tray's CHEAT: CHEAT shows and the cheat comes on, or cheat mode ends
static void IOSTouch_UseCheatSwitch(void)
{
  if (_bShowCheat) {
    if (_bCheatOn) IOS_ShowCameraMessage("Cheat off");
    _bShowCheat = 0;
    IOSTouch_SetCheat(0);
    return;
  }
  _bShowCheat = 1;
  if (!_hud.bCheatAllowed) {
    IOSTouch_CheatNotAllowed();
    return;
  }
  if (!_bCheatOn) {
    IOSTouch_SetCheat(1);
    IOS_ShowCameraMessage("Cheat on");
  }
}

void IOSTouch_CheatTyped(void)
{
  if (_bCheatOn) {
    IOSTouch_SetCheat(0);
    _bShowCheat = 0;
    IOS_ShowCameraMessage("Cheat off");
    return;
  }
  if (!_hud.bCheatAllowed) {
    IOSTouch_CheatNotAllowed();
    return;
  }
  IOSTouch_SetCheat(1);
  _bShowCheat = 1;
  IOS_ShowCameraMessage("Cheat on");
}

int IOSTouch_CheatOn(void)
{
  return _bCheatOn;
}

void IOSTouch_CheatLevelFailed(void)
{
  IOS_ShowCameraMessage("That level couldn't be started");
}

int IOSTouch_TakeLevelPick(void)
{
  const int i = _iLevelPicked;
  _iLevelPicked = 0;
  return i;
}

// JUMP, USE: 0, 1 (the cheat's holds on them); -1 any other
static int IOSTouch_CheatActOf(int button)
{
  return button == BTN_JUMP ? 0 : button == BTN_USE ? 1 : -1;
}

// Whether the holds on JUMP and USE, and the tray's LEVEL, do the cheat's things now
static int IOSTouch_CheatCanAct(void)
{
  return _bCheatOn && _hud.bCheatAllowed && _iMode == IOSTOUCH_GAMEPLAY && !_bWheelOpen;
}

// The tray's LEVEL list can open (with or without the cheat): in play, no
// wheel open
static int IOSTouch_LevelListCanAct(void)
{
  return _iMode == IOSTOUCH_GAMEPLAY && !_bWheelOpen;
}

// A finger moved away from where it went down on CHEAT, JUMP or USE: no
// hold there
static void IOSTouch_CheatMoved(IOSTouchSlot *s, double x, double y)
{
  if (s->role != ROLE_BUTTON || s->bCheatDone) return;
  if (s->button != BTN_CHEAT && IOSTouch_CheatActOf(s->button) < 0) return;
  if (hypot(x - s->xDown, y - s->yDown) < IOSTOUCH_CHEAT_STILL) return;
  s->bCheatDone = 1;
}

// The tray's LEVEL: the list of the game's levels opens over the game, which
// holds still while it's open (IOSTouch_HoldsGame); the tray closes, and
// every finger down is let go of. The view shows it (its level panel) and
// says which was tapped (IOSTouch_PickLevel), or that it closed.
static void IOSTouch_OpenLevelList(void)
{
  IOSTouch_SetTrayOpen(0);
  if (!IOSTouch_LevelListCanAct() || !IOSTouch_LevelPickShows()) return;
  IOSTouch_DropTouches(NULL);
  _bLevelListOpen = 1;
}

static void IOSTouch_CloseLevelList(void)
{
  _bLevelListOpen = 0;
}

// Level iLevel (1..ctLevels) tapped in the list: it closes, and the game
// goes there (IOSTouch_TakeLevelPick)
static void IOSTouch_PickLevel(int iLevel)
{
  const int bOpen = _bLevelListOpen;
  _bLevelListOpen = 0;
  if (!bOpen || !IOSTouch_LevelListCanAct() || !IOSTouch_LevelPickShows() || iLevel < 1 || iLevel > _hud.ctLevels) return;
  _iLevelPicked = iLevel;
  _iRequests |= IOSTOUCH_REQ_LEVEL;
  char str[64];
  snprintf(str, sizeof(str), "Loading level %d", iLevel);
  IOS_ShowCameraMessage(str);
}

// A finger lifted from CHEAT, JUMP or USE: JUMP's quick taps, two of which
// land a flight
static void IOSTouch_CheatLifted(IOSTouchSlot *s, double x, double y, int bCancelled, double tTouch)
{
  if (s->role != ROLE_BUTTON) return;
  if (s->button == BTN_JUMP && _bFlying && !bCancelled && tTouch - s->tDownTouch < IOSTOUCH_CHEAT_TAP
      && hypot(x - s->xDown, y - s->yDown) < IOSTOUCH_CHEAT_STILL) {
    const double dt = s->tDownTouch - _tJumpTapLift;
    if (_tJumpTapLift >= 0.0 && dt >= 0.0 && dt < IOSTOUCH_CHEAT_DOUBLE) {
      _bFlying = 0; // (the game lands: IOSTouch_TickCheat)
      _tJumpTapLift = -1.0;
      _ctCheatTicks++;
      IOS_ShowCameraMessage("Landed");
    }
    else {
      _tJumpTapLift = tTouch;
    }
  }
}

// Once a frame: the holds on CHEAT, JUMP and USE, timed as QUICK SAVE's are
// (known: when the previous tick ran); the list of levels closing once
// LEVEL is gone; a new level
static void IOSTouch_TickCheat(double now, double known)
{
  // (the cheat off, the console open...)
  if (_bLevelListOpen && (!IOSTouch_LevelPickShows() || !IOSTouch_LevelListCanAct())) IOSTouch_CloseLevelList();
  // the tray with LEVEL in it while it shows, without it otherwise (the view
  // moves its buttons along as it sees this changed)
  if (IOSTouch_LevelPickShows() != _bTrayLevelPlaced) IOSTouch_PlaceTray(IOSTouch_LevelPickShows());
  // a new level (started or loaded): no flying or noclip in it to begin with
  if (_hud.uWorld != _uWorldSeen) {
    _uWorldSeen = _hud.uWorld;
    if (_hud.bNoclip) _iRequests |= IOSTOUCH_REQ_NOCLIP;
    _bFlying = 0;
    _tJumpTapLift = -1.0;
  }
  // Flying as the overlay wants it, once the game has had a moment to take
  // the last ask (the game toggles it, and takes it only in god mode, which
  // the cheat gives a moment into a level): still flying when it shouldn't
  // be, asked again; stopped flying on its own, so be it
  if (_hud.bValid && _hud.bFlying != _bFlying && now - _tFlyAsked > 1.0) {
    if (_bFlying) {
      _bFlying = 0;
    }
    else if (_hud.bCheatAllowed && _bCheatOn) {
      _iRequests |= IOSTOUCH_REQ_FLY;
      _tFlyAsked = now;
    }
  }
  float fCheatRing = 0.0f;
  float afAct[2] = { 0.0f, 0.0f };
  for (int i = 0; i < IOSTOUCH_MAX_TOUCHES; i++) {
    IOSTouchSlot *s = &_aSlots[i];
    if (!s->touch || s->role != ROLE_BUTTON || s->bCheatDone) continue;
    const double held = known - s->tDown;
    const float fRing = (float)fmin(fmax(0.0, (now - s->tDown) / IOSTOUCH_CHEAT_HOLD), 1.0);
    if (s->button == BTN_CHEAT) {
      if (_iMode != IOSTOUCH_GAMEPLAY || !IOSTouch_IsOnButton(s->x, s->y, BTN_CHEAT)) {
        s->bCheatDone = 1;
      }
      else if (held >= IOSTOUCH_CHEAT_HOLD) {
        s->bCheatDone = 1;
        IOSTouch_ToggleCheat();
      }
      else {
        fCheatRing = fmaxf(fCheatRing, fRing);
      }
      continue;
    }
    const int k = IOSTouch_CheatActOf(s->button);
    if (k < 0) continue;
    // nothing to do: the cheat off; JUMP in a game that can't fly, while
    // flying (holding it rises) or going through walls
    if (!IOSTouch_CheatCanAct() || (k == 0 && (!_hud.bCanFly || _bFlying || _hud.bNoclip))) {
      s->bCheatDone = 1;
      continue;
    }
    if (held < IOSTOUCH_CHEAT_HOLD) {
      afAct[k] = fmaxf(afAct[k], fRing);
      continue;
    }
    s->bCheatDone = 1;
    _ctCheatTicks++;
    if (k == 0) {
      _bFlying = 1;
      if (!_hud.bFlying) {
        _iRequests |= IOSTOUCH_REQ_FLY;
        _tFlyAsked = now;
      }
      _tJumpTapLift = -1.0;
      IOS_ShowCameraMessage("Flying: JUMP rises, CROUCH sinks; tap JUMP twice to land");
    }
    else {
      _iRequests |= IOSTOUCH_REQ_NOCLIP;
      IOS_ShowCameraMessage(!_hud.bNoclip ? "Noclip: through walls" : "Noclip off");
    }
  }
  _fCheatRing = fCheatRing;
  for (int k = 0; k < 2; k++) _afCheatActRing[k] = afAct[k];
}

// The game holds still while the weapon wheel or the cheat's list of levels
// is open
int IOSTouch_HoldsGame(void)
{
  return (_bWheelOpen || _bLevelListOpen) && _iMode == IOSTOUCH_GAMEPLAY;
}


static const IOSTouchWheelMap *IOSTouch_WheelMapOf(int iMap)
{
  return &_aWheelMaps[(iMap > 0 && iMap < IOSTOUCH_WHEEL_NUM) ? iMap : IOSTOUCH_WHEEL_NONE];
}

// Whether the game would take a pick now: the player there, alive, not
// driving or in a cutscene, and a wheel for this game
static int IOSTouch_WheelCanOpen(void)
{
  return _wpn.bValid && _wpn.bCanSelect && IOSTouch_WheelMapOf(_wpn.iMap)->ctSlots > 0;
}

// A slice's middle (degrees, counter-clockwise from pointing right): the
// first one's edge at the gap's left edge, then clockwise
static double IOSTouch_WheelSlotDeg(const IOSTouchWheelMap *m, int i)
{
  const double gap = 360.0 - m->ctSlots * m->fSliceDeg;
  return 270.0 - gap * 0.5 - m->fSliceDeg * 0.5 - i * m->fSliceDeg;
}

static int IOSTouch_WheelSlotStateIn(const IOSTouchWeapons *pw, int iWeapon)
{
  if (iWeapon < 0 || iWeapon >= IOSTOUCH_WPN_MAX) return WSTATE_NOTFOUND;
  if (!(pw->ulOwned & (1u << iWeapon))) return WSTATE_NOTFOUND;
  if (!(pw->ulReady & (1u << iWeapon))) return WSTATE_NOAMMO;
  return WSTATE_READY;
}

static int IOSTouch_WheelSlotState(int i)
{
  return IOSTouch_WheelSlotStateIn(&_wpn, IOSTouch_WheelMapOf(_iWheelMap)->aSlots[i].iWeapon);
}

// The ammo count a slice shows (at most 999), or -1 for none: the melee
// weapons have none, infinite ammo shows none, nor does a weapon not found
// yet
static int IOSTouch_WheelSlotCount(int i)
{
  const int w = IOSTouch_WheelMapOf(_iWheelMap)->aSlots[i].iWeapon;
  if (_wpn.bInfiniteAmmo || IOSTouch_WheelSlotStateIn(&_wpn, w) == WSTATE_NOTFOUND || _wpn.aiAmmo[w] < 0) return -1;
  return _wpn.aiAmmo[w] > 999 ? 999 : _wpn.aiAmmo[w];
}

// Whether a slice is picked when lifted on: a weapon the game would switch to
// -- not the one in hand (picking that again would switch some games to its
// alternate)
static int IOSTouch_WheelCanPick(int i)
{
  const IOSTouchWheelMap *m = IOSTouch_WheelMapOf(_iWheelMap);
  if (i < 0 || i >= m->ctSlots) return 0;
  return IOSTouch_WheelSlotState(i) == WSTATE_READY && m->aSlots[i].iWeapon != _wpn.iWanted;
}

static double IOSTouch_AngleDiff(double a, double b)
{
  double d = fmod(a - b, 360.0);
  if (d > 180.0) d -= 360.0;
  if (d < -180.0) d += 360.0;
  return d;
}

// The slice a direction (degrees) points into, or IOSTOUCH_WHEEL_CANCEL in
// the gap at the bottom. The slice already picked (cur) holds on
// IOSTOUCH_WHEEL_HYST past its edges.
static int IOSTouch_WheelSliceForAngle(double deg, int cur)
{
  const IOSTouchWheelMap *m = IOSTouch_WheelMapOf(_iWheelMap);
  const double half = m->fSliceDeg * 0.5;
  if (cur >= 0 && cur < m->ctSlots && fabs(IOSTouch_AngleDiff(deg, IOSTouch_WheelSlotDeg(m, cur))) <= half + IOSTOUCH_WHEEL_HYST)
    return cur;
  int best = IOSTOUCH_WHEEL_CANCEL;
  double bestDiff = 0.0;
  for (int i = 0; i < m->ctSlots; i++) {
    const double d = fabs(IOSTouch_AngleDiff(deg, IOSTouch_WheelSlotDeg(m, i)));
    if (d <= half && (best < 0 || d < bestDiff)) {
      best = i;
      bestDiff = d;
    }
  }
  return best;
}

// The slice under (x,y) (cur as above): anywhere on it by its angle, from a
// little inside the hole's edge out to past a popped-out slice's;
// IOSTOUCH_WHEEL_CANCEL in the gap at the bottom; -1 off the ring (the middle,
// or well outside it)
static int IOSTouch_WheelSliceAt(double x, double y, int cur)
{
  const double dx = x - _fWheelCX, dy = _fWheelCY - y;
  const double r = sqrt(dx * dx + dy * dy);
  if (r < _fWheelR0 - 4.0 || r > _fWheelR1 + IOSTOUCH_WHEEL_POP + 14.0) return -1;
  return IOSTouch_WheelSliceForAngle(atan2(dy, dx) * 180.0 / M_PI, cur);
}

// The opener's slide: the direction from where it went down picks the slice.
// Inside the dead zone nothing is picked (once it has been out, lifting there
// cancels); the point it is measured from trails behind the thumb. Dragged
// onto the wheel itself, the slice under the thumb is picked instead (none
// in the middle, the gap cancels). Back where it went down, nothing is
// picked, however far it went. (Jedi Knight's aimWheel.)
static void IOSTouch_WheelAim(IOSTouchSlot *s, double x, double y)
{
  double dx = x - s->wheelOriginX, dy = y - s->wheelOriginY;
  double r = sqrt(dx * dx + dy * dy);
  if (r > IOSTOUCH_WHEEL_LEASH) {
    const double k = (r - IOSTOUCH_WHEEL_LEASH) / r;
    s->wheelOriginX += dx * k;
    s->wheelOriginY += dy * k;
    dx = x - s->wheelOriginX;
    dy = y - s->wheelOriginY;
    r = IOSTOUCH_WHEEL_LEASH;
  }
  const double cx = x - _fWheelCX, cy = _fWheelCY - y;
  if (sqrt(cx * cx + cy * cy) <= _fWheelR1 + IOSTOUCH_WHEEL_POP + 14.0) {
    s->bArmed = 1;
    s->wheelAim = atan2(cy, cx) * 180.0 / M_PI;
    s->wheelSlot = IOSTouch_WheelSliceAt(x, y, s->wheelSlot);
    return;
  }
  if (s->bArmed && hypot(x - s->xDown, y - s->yDown) < IOSTOUCH_WHEEL_DEAD) {
    s->wheelOriginX = s->xDown;
    s->wheelOriginY = s->yDown;
    s->wheelSlot = -1;
    return;
  }
  if (r < IOSTOUCH_WHEEL_DEAD) {
    s->wheelSlot = -1;
    return;
  }
  s->bArmed = 1;
  s->wheelAim = atan2(-dy, dx) * 180.0 / M_PI;
  s->wheelSlot = IOSTouch_WheelSliceForAngle(s->wheelAim, s->wheelSlot);
}

// What is pointed at on the open wheel: by the opener once it has slid, else
// by the newest other finger on it (an opener that opened it by holding still
// points at nothing until it slides). A slice, IOSTOUCH_WHEEL_CANCEL (the
// gap), or -1; *pbCancel: lifting would cancel (the gap, back in the dead
// zone, or a finger off the ring); *ppSlide: the sliding opener, if it points.
static int IOSTouch_WheelPointed(int *pbCancel, const IOSTouchSlot **ppSlide)
{
  const IOSTouchSlot *pSlide = NULL, *pFinger = NULL;
  for (int i = 0; i < IOSTOUCH_MAX_TOUCHES; i++) {
    const IOSTouchSlot *s = &_aSlots[i];
    if (!s->touch || s->role != ROLE_WHEEL) continue;
    if (s->bWheelOpener && s->bWheelHeld) continue;
    if (s->bWheelOpener && !_bWheelTapMode) pSlide = s;
    else if (!pFinger || s->uSeq > pFinger->uSeq) pFinger = s;
  }
  int hot = -1, bCancel = 0;
  if (pSlide && pSlide->bArmed) {
    hot = pSlide->wheelSlot;
    bCancel = hot < 0;
  }
  else if (pFinger) {
    hot = pFinger->wheelSlot;
    bCancel = hot < 0;
    pSlide = NULL;
  }
  else {
    pSlide = NULL;
  }
  if (pbCancel) *pbCancel = _bWheelOpen && bCancel;
  if (ppSlide) *ppSlide = _bWheelOpen ? pSlide : NULL;
  return _bWheelOpen ? hot : -1;
}

static int IOSTouch_WheelHot(void)
{
  return IOSTouch_WheelPointed(NULL, NULL);
}

// After every touch on the open wheel: a haptic tick each time the thumb
// moves onto another slice or the gap (not when it leaves them)
static void IOSTouch_WheelUpdateHot(void)
{
  const int hot = IOSTouch_WheelHot();
  if (hot != _iWheelHot) {
    if (hot != -1) _ctWheelTicks++;
    _iWheelHot = hot;
  }
}

// Opens the wheel from a press on NEXT WPN or PREV WPN (s): slid (to slide to
// a slice, measured from where it went down) or held still (bHeld: to tap
// one). Every other touch lets go of what it held and is ignored until it
// lifts (a press waiting on the other button too); MENU's tray closes; the
// stick stops. The game holds still until it closes (IOSTouch_HoldsGame).
static void IOSTouch_WheelOpen(IOSTouchSlot *s, int bHeld)
{
  IOSTouch_SetTrayOpen(0);
  for (int i = 0; i < IOSTOUCH_MAX_TOUCHES; i++) {
    IOSTouchSlot *o = &_aSlots[i];
    if (!o->touch) continue;
    if (o->role == ROLE_BUTTON && _aButtonHeld[o->button] > 0) _aButtonHeld[o->button]--;
    if (o->role == ROLE_STICK) {
      _bStickActive = 0;
      _fStickX = _fStickY = 0.0f;
    }
    if (o != s) o->role = ROLE_IGNORED;
  }
  _fSaveRing = _fLoadRing = _fMenuRing = 0.0f;
  _afWheelRing[0] = _afWheelRing[1] = 0.0f;
  IOSTouch_SetMoveFromStick();
  IOSTouch_SharedWheelOpened();
  _bWheelOpen = 1;
  _bWheelTapMode = bHeld != 0;
  _iWheelButton = s->button;
  _iWheelMap = (_wpn.iMap > 0 && _wpn.iMap < IOSTOUCH_WHEEL_NUM) ? _wpn.iMap : IOSTOUCH_WHEEL_NONE;
  s->role = ROLE_WHEEL;
  s->bWheelOpener = 1;
  s->bWheelHeld = bHeld != 0;
  s->bArmed = 0;
  s->wheelSlot = -1;
  s->wheelOriginX = s->xDown;
  s->wheelOriginY = s->yDown;
  _iWheelHot = -1;
  IOSTouch_WheelUpdateHot();
  IOSTouch_SetHeld(IOSTouch_HeldButtons(), 0);
}

// Closes the wheel, picking what is in slice i if it can be picked (the game
// gets it as soon as it goes on: IOSTouch_ReadInput). Fingers still on it are
// ignored until they lift.
static void IOSTouch_WheelClose(int i)
{
  if (_bWheelOpen && IOSTouch_WheelCanPick(i)) IOSTouch_QueuePick(IOSTouch_WheelMapOf(_iWheelMap)->aSlots[i].iWeapon);
  for (int t = 0; t < IOSTOUCH_MAX_TOUCHES; t++) {
    if (_aSlots[t].touch && _aSlots[t].role == ROLE_WHEEL) _aSlots[t].role = ROLE_IGNORED;
  }
  _bWheelOpen = 0;
  _bWheelTapMode = 0;
  _iWheelHot = -1;
}

// A press on NEXT WPN or PREV WPN still waiting to see which gesture it is
static int IOSTouch_IsWheelPress(const IOSTouchSlot *s)
{
  return s->touch && s->role == ROLE_BUTTON && _aButtons[s->button].kind == KIND_WHEEL;
}

// A wheel press slid IOSTOUCH_WHEEL_OPEN_SLIDE from where it went down: the
// wheel opens, to slide -- or, if it can't now, the press is no tap any more
// either. Returns whether it opened.
static int IOSTouch_WheelPressSlid(IOSTouchSlot *s, double x, double y)
{
  if (!IOSTouch_IsWheelPress(s) || s->bFired || hypot(x - s->xDown, y - s->yDown) < IOSTOUCH_WHEEL_OPEN_SLIDE) return 0;
  if (!IOSTouch_WheelCanOpen()) {
    s->bFired = 1;
    _afWheelRing[s->button == BTN_PREVWPN] = 0.0f;
    return 0;
  }
  IOSTouch_WheelOpen(s, 0);
  return 1;
}

// What the game says, every frame before IOSTouch_Update. The wheel closes,
// picking nothing, once the game couldn't take a pick (the player died, a
// cutscene's camera, a level change).
void IOSTouch_SetWeapons(const IOSTouchWeapons *pw)
{
  _wpn = *pw;
  if (_bWheelOpen && !IOSTouch_WheelCanOpen()) IOSTouch_WheelClose(-1);
}

// ------------------------------------------------- the wheel's icons
// Weapon icons, which the game hands over from its own art
// (IOSTouch_WantedIcons, IOSTouch_SetWeaponIcon): kept for the process, each
// as it is and tinted for the states that grey it (IOSTouch_TintIcon). A
// weapon the game has no picture of shows its name. CHEAT's picture comes
// the same way (IOSTouch_SetCheatIcon): as it is (on) and greyed (off).
enum { WICON_READY = 0, WICON_NOAMMO, WICON_NOTFOUND, WICON_NUM };
typedef struct {
  int bHave, bGaveUp;
  int w, h;
  unsigned char aub[WICON_NUM][IOSTOUCH_ICON_MAX * IOSTOUCH_ICON_MAX * 4];
} IOSTouchIcon;
static IOSTouchIcon _aIcons[IOSTOUCH_WPN_MAX];
static unsigned int _ulIconsNew = 0; // icons the view hasn't made images of yet
static IOSTouchIcon _cheatIcon;      // [WICON_READY] on, [WICON_NOTFOUND] off
static int _bCheatIconAsked = 0, _bCheatIconNew = 0;

// The icon a weapon shows: its own
static int IOSTouch_WheelIconOf(int iWeapon)
{
  return iWeapon;
}

// A state's tint of an icon (RGBA, not premultiplied): grey (luma x k), alpha
// x a -- no ammo 0.80 / 0.70, not found yet 0.40 / 0.45, so the two read
// apart and a weapon not found yet is a faint silhouette
static void IOSTouch_TintIcon(const unsigned char *pubSrc, int ctTexels, int iState, unsigned char *pubDst)
{
  if (iState == WICON_READY) {
    memcpy(pubDst, pubSrc, (size_t)ctTexels * 4);
    return;
  }
  const float k = (iState == WICON_NOAMMO) ? 0.80f : 0.40f;
  const float a = (iState == WICON_NOAMMO) ? 0.70f : 0.45f;
  for (int i = 0; i < ctTexels; i++) {
    const unsigned char *p = pubSrc + i * 4;
    const float lum = 0.299f * p[0] + 0.587f * p[1] + 0.114f * p[2];
    float v = lum * k + 0.5f, al = p[3] * a + 0.5f;
    if (v > 255.0f) v = 255.0f;
    if (al > 255.0f) al = 255.0f;
    pubDst[i * 4 + 0] = pubDst[i * 4 + 1] = pubDst[i * 4 + 2] = (unsigned char)v;
    pubDst[i * 4 + 3] = (unsigned char)al;
  }
}

// The icons of the game being played's weapons not asked for yet (each is
// asked for once: the game answers at once, with it or with none)
unsigned int IOSTouch_WantedIcons(void)
{
  if (_iMode == IOSTOUCH_HIDDEN || !_wpn.bValid) return 0;
  const IOSTouchWheelMap *m = IOSTouch_WheelMapOf(_wpn.iMap);
  unsigned int ul = 0;
  for (int i = 0; i < m->ctSlots; i++) {
    const int w = IOSTouch_WheelIconOf(m->aSlots[i].iWeapon);
    if (_aIcons[w].bHave || _aIcons[w].bGaveUp) continue;
    ul |= 1u << w;
  }
  return ul;
}

static int IOSTouch_IconFits(const unsigned char *pubRGBA, int iWidth, int iHeight)
{
  return pubRGBA && iWidth > 0 && iHeight > 0 && iWidth <= IOSTOUCH_ICON_MAX && iHeight <= IOSTOUCH_ICON_MAX;
}

void IOSTouch_SetWeaponIcon(int iWeapon, const unsigned char *pubRGBA, int iWidth, int iHeight)
{
  if (iWeapon < 0 || iWeapon >= IOSTOUCH_WPN_MAX) return;
  IOSTouchIcon *pi = &_aIcons[iWeapon];
  if (!IOSTouch_IconFits(pubRGBA, iWidth, iHeight)) {
    if (!pi->bHave) pi->bGaveUp = 1; // its name shows instead
    _ulIconsNew |= 1u << iWeapon;
    return;
  }
  pi->w = iWidth;
  pi->h = iHeight;
  for (int st = 0; st < WICON_NUM; st++) IOSTouch_TintIcon(pubRGBA, iWidth * iHeight, st, pi->aub[st]);
  pi->bHave = 1;
  pi->bGaveUp = 0;
  _ulIconsNew |= 1u << iWeapon;
}

int IOSTouch_WantsCheatIcon(void)
{
  if (_bCheatIconAsked || _iMode == IOSTOUCH_HIDDEN) return 0;
  _bCheatIconAsked = 1;
  return 1;
}

void IOSTouch_SetCheatIcon(const unsigned char *pubRGBA, int iWidth, int iHeight)
{
  _bCheatIconAsked = 1;
  if (!IOSTouch_IconFits(pubRGBA, iWidth, iHeight)) {
    if (!_cheatIcon.bHave) _cheatIcon.bGaveUp = 1;
    return;
  }
  _cheatIcon.w = iWidth;
  _cheatIcon.h = iHeight;
  IOSTouch_TintIcon(pubRGBA, iWidth * iHeight, WICON_READY, _cheatIcon.aub[WICON_READY]);
  // off: grey, a little dimmer than a weapon out of ammo
  const float k = 0.70f, a = 0.80f;
  for (int i = 0; i < iWidth * iHeight; i++) {
    const unsigned char *p = pubRGBA + i * 4;
    const float lum = 0.299f * p[0] + 0.587f * p[1] + 0.114f * p[2];
    unsigned char *q = _cheatIcon.aub[WICON_NOTFOUND] + i * 4;
    q[0] = q[1] = q[2] = (unsigned char)fminf(lum * k + 0.5f, 255.0f);
    q[3] = (unsigned char)fminf(p[3] * a + 0.5f, 255.0f);
  }
  _cheatIcon.bHave = 1;
  _cheatIcon.bGaveUp = 0;
  _bCheatIconNew = 1;
}

// ------------------------------------------------- the wheel's layout
// Each slice shows its icon in a box IOSTOUCH_WHEEL_ICON_W x
// IOSTOUCH_WHEEL_ICON_H x k points (wider than tall: the games' weapon
// pictures mostly are; each is fitted in it, its shape kept),
// and under it, IOSTOUCH_WHEEL_ROW_GAP down, its ammo count in a row as tall
// as the digits (IOSTOUCH_WHEEL_AMMO_INK of the IOSTOUCH_WHEEL_AMMO_FONT x k
// pt font) and as wide as "000". The two are fitted as one block, upright,
// IOSTOUCH_WHEEL_BLOCK_MARGIN inside the slice as drawn (a degree in from
// its edges) and the hole, every slice with the row (so the layout never
// depends on the counts); k is the largest of 1.15, 1.10 ... 0.60 at which
// every slice's block fits, one for the wheel. Each block sits at the middle
// of the stretch of its slice's middle line where it fits; a slice without a
// count centres its icon in the block. A slice that pops out takes its block
// out IOSTOUCH_WHEEL_POP_SHIFT, the icon IOSTOUCH_WHEEL_POP_ICON as big.
#define IOSTOUCH_WHEEL_ICON_W 46.0
#define IOSTOUCH_WHEEL_ICON_H 30.0
#define IOSTOUCH_WHEEL_ROW_GAP 2.0
#define IOSTOUCH_WHEEL_AMMO_FONT 9.0
#define IOSTOUCH_WHEEL_AMMO_INK 0.705
#define IOSTOUCH_WHEEL_ROW_W (3 * 0.6 * IOSTOUCH_WHEEL_AMMO_FONT) // "000" in the system font's monospaced digits
#define IOSTOUCH_WHEEL_BLOCK_MARGIN 2.0
#define IOSTOUCH_WHEEL_POP_SHIFT 5.0
#define IOSTOUCH_WHEEL_POP_ICON 1.08

typedef struct {
  int iMap;
  double R0, R1;
  double k;                         // the icons' scale (0: nothing fits)
  double afR[IOSTOUCH_WHEEL_MAX];   // each block's middle, from the wheel's centre
} IOSTouchWheelFit;

// The block's size at scale k
static void IOSTouch_WheelBlockSize(double k, double *pfW, double *pfH)
{
  *pfW = fmax(IOSTOUCH_WHEEL_ICON_W, IOSTOUCH_WHEEL_ROW_W) * k;
  *pfH = IOSTOUCH_WHEEL_ICON_H * k + IOSTOUCH_WHEEL_ROW_GAP + IOSTOUCH_WHEEL_AMMO_FONT * IOSTOUCH_WHEEL_AMMO_INK * k;
}

// Whether a w x h block centred at (cx,cy) (y up, from the wheel's centre)
// is IOSTOUCH_WHEEL_BLOCK_MARGIN inside the slice at th (radians), drawn half
// either side, between the radii R0 and R1
static int IOSTouch_WheelBlockFits(double cx, double cy, double w, double h, double th, double half, double R0, double R1)
{
  const double M = IOSTOUCH_WHEEL_BLOCK_MARGIN;
  const double xs[2] = { cx - w * 0.5, cx + w * 0.5 }, ys[2] = { cy - h * 0.5, cy + h * 0.5 };
  for (int i = 0; i < 2; i++) {
    for (int j = 0; j < 2; j++) {
      if (hypot(xs[i], ys[j]) > R1 - M) return 0;
    }
  }
  const double nx = fmin(fmax(0.0, xs[0]), xs[1]), ny = fmin(fmax(0.0, ys[0]), ys[1]); // nearest the centre
  if (hypot(nx, ny) < R0 + M) return 0;
  // the slice's two edges, lines through the centre, and their inward normals
  const double a1 = th + half, a2 = th - half;
  const double an[2][2] = { { sin(a1), -cos(a1) }, { -sin(a2), cos(a2) } };
  for (int n = 0; n < 2; n++) {
    for (int i = 0; i < 2; i++) {
      for (int j = 0; j < 2; j++) {
        if (xs[i] * an[n][0] + ys[j] * an[n][1] < M) return 0;
      }
    }
  }
  return 1;
}

// The stretch of a slice's middle line where the block fits at scale k: its
// middle (0: nowhere)
static double IOSTouch_WheelBlockPlace(const IOSTouchWheelMap *m, int i, double k, double R0, double R1)
{
  double w, h;
  IOSTouch_WheelBlockSize(k, &w, &h);
  const double th = IOSTouch_WheelSlotDeg(m, i) * M_PI / 180.0;
  const double half = (m->fSliceDeg * 0.5 - 1.0) * M_PI / 180.0;
  double rIn = -1.0, rOut = -1.0;
  const int n = 400;
  for (int j = 0; j <= n; j++) {
    const double r = R0 + (R1 - R0) * j / n;
    if (IOSTouch_WheelBlockFits(r * cos(th), r * sin(th), w, h, th, half, R0, R1)) {
      if (rIn < 0.0) rIn = r;
      rOut = r;
    }
  }
  return rIn < 0.0 ? 0.0 : (rIn + rOut) * 0.5;
}

static void IOSTouch_WheelFitFor(int iMap, double R0, double R1, IOSTouchWheelFit *pf)
{
  const IOSTouchWheelMap *m = IOSTouch_WheelMapOf(iMap);
  memset(pf, 0, sizeof(*pf));
  pf->iMap = iMap;
  pf->R0 = R0;
  pf->R1 = R1;
  for (int n = 0; n <= 11; n++) {
    const double k = (115 - 5 * n) / 100.0;
    int bAll = 1;
    for (int i = 0; i < m->ctSlots && bAll; i++) {
      pf->afR[i] = IOSTouch_WheelBlockPlace(m, i, k, R0, R1);
      bAll = pf->afR[i] > 0.0;
    }
    if (bAll) {
      pf->k = k;
      return;
    }
  }
  // nothing fits (never on a phone or iPad screen): the smallest, in the middle of the ring
  pf->k = 0.60;
  for (int i = 0; i < m->ctSlots; i++) pf->afR[i] = (R0 + R1) * 0.5;
}

// The open wheel's fit (made again only when the map or the size changes)
static IOSTouchWheelFit _wheelFit;
static const IOSTouchWheelFit *IOSTouch_WheelFit(void)
{
  if (_wheelFit.k <= 0.0 || _wheelFit.iMap != _iWheelMap || _wheelFit.R0 != _fWheelR0 || _wheelFit.R1 != _fWheelR1) {
    IOSTouch_WheelFitFor(_iWheelMap, _fWheelR0, _fWheelR1, &_wheelFit);
  }
  return &_wheelFit;
}

// Where slice i draws its icon box and its count's row (points): popped out
// or not, with a count (the icon at the block's top, the row under it) or
// without (the icon in the block's middle)
static void IOSTouch_WheelSlotRects(int i, int bPopped, int bCount, IOSTouchRect *prIcon, IOSTouchRect *prRow)
{
  const IOSTouchWheelMap *m = IOSTouch_WheelMapOf(_iWheelMap);
  const IOSTouchWheelFit *f = IOSTouch_WheelFit();
  const double th = IOSTouch_WheelSlotDeg(m, i) * M_PI / 180.0;
  const double r = f->afR[i] + (bPopped ? IOSTOUCH_WHEEL_POP_SHIFT : 0.0);
  const double bx = _fWheelCX + r * cos(th), by = _fWheelCY - r * sin(th);
  double w, h;
  IOSTouch_WheelBlockSize(f->k, &w, &h);
  const double B = IOSTOUCH_WHEEL_ICON_H * f->k, rowH = IOSTOUCH_WHEEL_AMMO_FONT * IOSTOUCH_WHEEL_AMMO_INK * f->k;
  const double iy = bCount ? by - h * 0.5 + B * 0.5 : by; // the icon's middle
  const double s = B * (bPopped ? IOSTOUCH_WHEEL_POP_ICON : 1.0) * 0.5;
  const double sw = s * IOSTOUCH_WHEEL_ICON_W / IOSTOUCH_WHEEL_ICON_H;
  const IOSTouchRect rIcon = { 1, bx - sw, iy - s, bx + sw, iy + s };
  const double ry = by - h * 0.5 + B + IOSTOUCH_WHEEL_ROW_GAP + rowH * 0.5;
  const IOSTouchRect rRow = { bCount, bx - IOSTOUCH_WHEEL_ROW_W * f->k * 0.5, ry - rowH * 0.5, bx + IOSTOUCH_WHEEL_ROW_W * f->k * 0.5, ry + rowH * 0.5 };
  if (prIcon) *prIcon = rIcon;
  if (prRow) *prRow = rRow;
}

// ------------------------------------------------- the middle
// What the middle says: the name of what is pointed at (or of the weapon in
// hand), its count "37 / 50", and a hint. The view lays it out with
// IOSTouch_WheelMiddleLayout, measuring its own fonts.
enum { WTITLE_SLOT = 0, WTITLE_GREY, WTITLE_WHITE };
typedef struct {
  const char *strTitle;
  const char *strTitle2;  // on two lines, if it has no space to break at (else NULL)
  int iTitleLook;         // WTITLE_*
  int iColour;            // WTITLE_SLOT: the slice's WCOL_*
  char strCount[24];      // "" for none
  const char *strHint;
  int iHot;               // what is pointed at (IOSTouch_WheelPointed)
  int bCancel;
} IOSTouchWheelMiddle;

static void IOSTouch_WheelMiddleState(IOSTouchWheelMiddle *pm)
{
  const IOSTouchWheelMap *m = IOSTouch_WheelMapOf(_iWheelMap);
  memset(pm, 0, sizeof(*pm));
  pm->iHot = IOSTouch_WheelPointed(&pm->bCancel, NULL);
  int i = pm->iHot;
  if (i < 0 && !pm->bCancel) {
    // nothing pointed at: the weapon in hand
    for (int j = 0; j < m->ctSlots; j++) {
      if (m->aSlots[j].iWeapon == _wpn.iWanted) i = j;
    }
    pm->strHint = _bWheelTapMode ? "tap a weapon" : "slide toward a weapon";
    if (i < 0) {
      pm->strTitle = "WEAPONS";
      pm->iTitleLook = WTITLE_WHITE;
      return;
    }
  }
  if (i < 0) {
    pm->strTitle = "CANCEL";
    pm->iTitleLook = WTITLE_WHITE;
    pm->strHint = "lift to cancel";
    return;
  }
  const IOSTouchWheelSlot *sl = &m->aSlots[i];
  const int st = IOSTouch_WheelSlotState(i);
  pm->strTitle = sl->strName;
  pm->strTitle2 = sl->strName2;
  pm->iTitleLook = (st == WSTATE_READY) ? WTITLE_SLOT : WTITLE_GREY;
  pm->iColour = sl->iColour;
  const int ct = IOSTouch_WheelSlotCount(i);
  if (ct >= 0) {
    const int mx = _wpn.aiMaxAmmo[sl->iWeapon];
    if (mx < 0) snprintf(pm->strCount, sizeof(pm->strCount), "%d", ct); // (no maximum known: Exhumed)
    else snprintf(pm->strCount, sizeof(pm->strCount), "%d / %d", ct, mx > 999 ? 999 : mx);
  }
  if (pm->iHot >= 0) {
    pm->strHint = (st == WSTATE_READY) ? "lift to select" : ((st == WSTATE_NOAMMO) ? "no ammo" : "not found yet");
  }
}

// The middle's lines, stacked and centred on the wheel's centre: the title
// (WLINE_TITLE: bold 17 pt), the count (semibold 11 pt), the hint (semibold
// 10 pt), 2 pt between the three, each line 1.18 times its size tall. Each
// line keeps within the hole's chord at its height (measured
// IOSTOUCH_WHEEL_NEEDLE_CLEAR in from the hole's edge, at the height of its
// capitals, 0.75 of its size); an item's lines share one size, no smaller
// than its smallest scale (title 0.6, count 0.8, hint 0.7; the title 0.5
// where nothing fits so). The title and the hint may go on two lines; the
// count may be left out (the slice shows it). For each way of stacking them
// the sizes are searched for: the count as large as fits, then the title
// and the hint as large as fits. Of the ways that fit, the one that keeps
// the count, then has the larger of the title's and the hint's smaller
// scale, then the larger sum of the two, then the fewest lines. Returns how
// many lines (0: nothing fits).
enum { WLINE_TITLE = 0, WLINE_COUNT, WLINE_HINT };
typedef double (*IOSTouchTextWidth)(const char *str, int iKind, double fSize, void *pUser);
typedef struct {
  char str[64];
  int iKind;
  double fSize;
  double fDY; // the line's middle, below the wheel's centre
} IOSTouchMiddleLine;
#define IOSTOUCH_MIDDLE_LINES 5

// Text on two lines at its middle space ("a\nb"), or as given; 0 if it can't
static int IOSTouch_SplitLine(const char *str, const char *str2, char *a, char *b, size_t size)
{
  if (str2) {
    const char *nl = strchr(str2, '\n');
    snprintf(a, size, "%.*s", (int)(nl - str2), str2);
    snprintf(b, size, "%s", nl + 1);
    return 1;
  }
  const int n = (int)strlen(str);
  int best = -1;
  for (int i = 0; i < n; i++) {
    if (str[i] == ' ' && (best < 0 || fabs(i - n * 0.5) < fabs(best - n * 0.5))) best = i;
  }
  if (best < 0) return 0;
  snprintf(a, size, "%.*s", best, str);
  snprintf(b, size, "%s", str + best + 1);
  return 1;
}

// One way to stack the middle's lines (a candidate of IOSTouch_WheelMiddleLayout): the lines, how many items
// they are, each line's width at its item's nominal size, and the radius the chords are measured on
typedef struct {
  IOSTouchMiddleLine a[IOSTOUCH_MIDDLE_LINES];
  int n, ctItems;
  double afNomW[IOSTOUCH_MIDDLE_LINES];
  double r;
} IOSTouchMiddleStack;
static const double _afMiddleNom[3] = { 17.0, 11.0, 10.0 };

// Lays the lines out at these sizes (points, per item): each line's middle, and the chord it has
static void IOSTouch_MiddlePlace(IOSTouchMiddleStack *c, const double afSize[3], double afRoom[IOSTOUCH_MIDDLE_LINES])
{
  double h = 2.0 * (c->ctItems - 1);
  for (int j = 0; j < c->n; j++) h += afSize[c->a[j].iKind] * 1.18;
  double y = -h * 0.5;
  for (int j = 0; j < c->n; j++) {
    if (j > 0 && c->a[j].iKind != c->a[j - 1].iKind) y += 2.0;
    const double sz = afSize[c->a[j].iKind], lh = sz * 1.18;
    c->a[j].fSize = sz;
    c->a[j].fDY = y + lh * 0.5;
    y += lh;
    const double yy = fabs(c->a[j].fDY) + sz * 0.75 * 0.5;
    afRoom[j] = 2.0 * sqrt(fmax(0.0, c->r * c->r - yy * yy));
  }
}

// Whether every line keeps within its chord with the items at these scales of their nominal sizes (a line's
// width taken as its nominal width times the scale)
static int IOSTouch_MiddleFitsAt(IOSTouchMiddleStack *c, const double afScale[3])
{
  double afSize[3], afRoom[IOSTOUCH_MIDDLE_LINES];
  for (int k = 0; k < 3; k++) afSize[k] = _afMiddleNom[k] * afScale[k];
  IOSTouch_MiddlePlace(c, afSize, afRoom);
  for (int j = 0; j < c->n; j++) {
    if (c->afNomW[j] * afScale[c->a[j].iKind] > afRoom[j] + 1e-6) return 0;
  }
  return 1;
}

// Item k's scale grown as far as it goes (up to 1), the others as they are; it fits at afScale[k] already.
// A smaller item is narrower and makes the stack shorter, so this halves the step between a scale that fits
// and one that doesn't; whatever it ends on is one that was seen to fit.
#define IOSTOUCH_MIDDLE_STEPS 20
static void IOSTouch_MiddleGrow(IOSTouchMiddleStack *c, double afScale[3], int k)
{
  double ok = afScale[k];
  afScale[k] = 1.0;
  if (IOSTouch_MiddleFitsAt(c, afScale)) return;
  double bad = 1.0;
  for (int i = 0; i < IOSTOUCH_MIDDLE_STEPS; i++) {
    afScale[k] = 0.5 * (ok + bad);
    if (IOSTouch_MiddleFitsAt(c, afScale)) ok = afScale[k];
    else bad = afScale[k];
  }
  afScale[k] = ok;
}

static int IOSTouch_WheelMiddleLayout(double R0, const IOSTouchWheelMiddle *pm, IOSTouchTextWidth pfnWidth, void *pUser,
                                      IOSTouchMiddleLine aOut[IOSTOUCH_MIDDLE_LINES])
{
  const double *afNom = _afMiddleNom;
  const int bCount = pm->strCount[0] != 0;
  char aT[2][64], aH[2][64];
  const int bCanSplitT = IOSTouch_SplitLine(pm->strTitle, pm->strTitle2, aT[0], aT[1], sizeof(aT[0]));
  const int bCanSplitH = IOSTouch_SplitLine(pm->strHint, NULL, aH[0], aH[1], sizeof(aH[0]));
  int ctBest = 0;
  double afKey[3] = { -1.0, -1.0, -1.0 };
  int bBestCount = -1;
  // (should nothing fit, the title may go to half its size; no name, hint and count needs it on any screen)
  for (int pass = 0; pass < 2 && ctBest == 0; pass++) {
  const double afMin[3] = { pass ? 0.5 : 0.6, 0.8, 0.7 };
  for (int cand = 0; cand < 8; cand++) {
    const int bWrapT = (cand >> 2) & 1, bWrapH = (cand >> 1) & 1, bWith2 = !(cand & 1);
    if ((bWrapT && !bCanSplitT) || (bWrapH && !bCanSplitH)) continue;
    IOSTouchMiddleStack st;
    IOSTouchMiddleLine *a = st.a;
    int n = 0;
    if (bWrapT) {
      for (int j = 0; j < 2; j++) { snprintf(a[n].str, sizeof(a[n].str), "%s", aT[j]); a[n++].iKind = WLINE_TITLE; }
    }
    else {
      snprintf(a[n].str, sizeof(a[n].str), "%s", pm->strTitle);
      a[n++].iKind = WLINE_TITLE;
    }
    if (bWith2 && bCount) {
      snprintf(a[n].str, sizeof(a[n].str), "%s", pm->strCount);
      a[n++].iKind = WLINE_COUNT;
    }
    if (bWrapH) {
      for (int j = 0; j < 2; j++) { snprintf(a[n].str, sizeof(a[n].str), "%s", aH[j]); a[n++].iKind = WLINE_HINT; }
    }
    else {
      snprintf(a[n].str, sizeof(a[n].str), "%s", pm->strHint);
      a[n++].iKind = WLINE_HINT;
    }
    st.n = n;
    st.ctItems = (bWith2 && bCount) ? 3 : 2;
    st.r = R0 - IOSTOUCH_WHEEL_NEEDLE_CLEAR;
    for (int j = 0; j < n; j++) st.afNomW[j] = pfnWidth(a[j].str, a[j].iKind, afNom[a[j].iKind], pUser);
    // The sizes are searched for, not only shrunk from the nominal ones (a title shrunk to fit a tall stack
    // can grow again once the stack is shorter): first the count, as large as fits with the title and hint
    // at their smallest; then the title and the hint together, at the largest scale they can share (each
    // no smaller than its own smallest); then whichever of the two grows the further on its own
    double afScale[3] = { afMin[0], afMin[1], afMin[2] };
    if (!IOSTouch_MiddleFitsAt(&st, afScale)) continue;
    IOSTouch_MiddleGrow(&st, afScale, WLINE_COUNT);
    {
      const double lo = fmin(afMin[0], afMin[2]);
      double ok = lo, bad = 1.0, s = 1.0;
      afScale[0] = afScale[2] = 1.0;
      if (!IOSTouch_MiddleFitsAt(&st, afScale)) {
        for (int i = 0; i < IOSTOUCH_MIDDLE_STEPS; i++) {
          s = 0.5 * (ok + bad);
          afScale[0] = fmax(s, afMin[0]);
          afScale[2] = fmax(s, afMin[2]);
          if (IOSTouch_MiddleFitsAt(&st, afScale)) ok = s;
          else bad = s;
        }
        s = ok;
      }
      afScale[0] = fmax(s, afMin[0]);
      afScale[2] = fmax(s, afMin[2]);
    }
    double afT[3] = { afScale[0], afScale[1], afScale[2] }, afH[3] = { afScale[0], afScale[1], afScale[2] };
    IOSTouch_MiddleGrow(&st, afT, WLINE_TITLE);
    IOSTouch_MiddleGrow(&st, afH, WLINE_HINT);
    const double *afPick = (afT[0] + afT[2] >= afH[0] + afH[2]) ? afT : afH;
    double afSize[3], afRoom[IOSTOUCH_MIDDLE_LINES];
    for (int k = 0; k < 3; k++) afSize[k] = afNom[k] * afPick[k];
    // Measured as drawn (the view's fonts needn't scale exactly with size): an item with a line still over
    // its chord shrinks to fit it, until none is (sizes only go down here, so the stack only gets shorter)
    for (int it = 0; it <= 8; it++) {
      IOSTouch_MiddlePlace(&st, afSize, afRoom);
      if (it == 8) break;
      int bShrunk = 0;
      for (int k = 0; k < 3; k++) {
        double f = 1.0;
        for (int j = 0; j < n; j++) {
          if (a[j].iKind != k) continue;
          const double w = pfnWidth(a[j].str, k, afSize[k], pUser);
          if (w > afRoom[j] + 1e-6) f = fmin(f, afRoom[j] / w);
        }
        if (f < 1.0) {
          afSize[k] *= f;
          bShrunk = 1;
        }
      }
      if (!bShrunk) break;
    }
    // The result as laid out: every line within its chord, every item at or above its smallest scale
    int bOk = 1;
    for (int j = 0; j < n; j++) {
      const int k = a[j].iKind;
      if (afSize[k] < afNom[k] * afMin[k] - 1e-9 || pfnWidth(a[j].str, k, afSize[k], pUser) > afRoom[j] + 1e-6) bOk = 0;
    }
    if (!bOk) continue;
    const double ts = afSize[WLINE_TITLE] / afNom[WLINE_TITLE], hs = afSize[WLINE_HINT] / afNom[WLINE_HINT];
    const int bKeeps = bWith2 || !bCount;
    const double k1 = round(fmin(ts, hs) * 1000.0) / 1000.0, k2 = round((ts + hs) * 1000.0) / 1000.0, k3 = -n;
    const int bBetter = ctBest == 0 || bKeeps > bBestCount
                        || (bKeeps == bBestCount && (k1 > afKey[0] || (k1 == afKey[0] && (k2 > afKey[1] || (k2 == afKey[1] && k3 > afKey[2])))));
    if (bBetter) {
      bBestCount = bKeeps;
      afKey[0] = k1;
      afKey[1] = k2;
      afKey[2] = k3;
      ctBest = n;
      memcpy(aOut, a, sizeof(a[0]) * n);
    }
  }
  }
  return ctBest;
}

// ------------------------------------------------- the wheel's looks
// Each game's wheel has a look of its own (drawn here, nothing of the
// game's art): the disc's colour, its rim and what is drawn on it, a
// motif in the middle behind the words, the dark the slices' colours are
// mixed from (the slices keep their ammo groups' colours) and the middle's
// title colour.
//   Duke Nukem 3D: black, a radiation-yellow rim with hazard stripes, the
//     radiation sign in the middle
//   Redneck Rampage: dark wood, a rusty rim with rivets, a sheriff's star
//   Blood: near-black red, a bone-white double rim with ritual ticks, a
//     pentagram's circle (five points) in the middle
//   Shadow Warrior: black, a red rim with a black line, the yin-yang
//   Exhumed: lapis blue, a gold rim with gold dots, the sun disc's rays
enum { WMOTIF_NONE = 0, WMOTIF_TREFOIL, WMOTIF_STAR, WMOTIF_PENTACLE, WMOTIF_YINYANG, WMOTIF_SUN };
enum { WRIM_PLAIN = 0, WRIM_HAZARD, WRIM_RIVETS, WRIM_TICKS, WRIM_DOTS };
typedef struct {
  unsigned char aubDisc[4];   // the disc (RGBA)
  unsigned char aubRim[4];    // its rim, a band at its edge
  unsigned char aubRim2[4];   // the rim's marks (stripes, rivets, ticks, dots) and its inner line
  unsigned char aubMotif[4];  // the middle's motif
  unsigned char aubMotif2[4]; // ...its second colour (the yin-yang's dark half)
  unsigned char aubBase[3];   // the slices' colours are mixed from this dark
  unsigned char aubTitle[3];  // the middle's title when it isn't a slice's colour
  int iRim, iMotif;
} IOSTouchWheelTheme;
static const IOSTouchWheelTheme _aWheelThemes[IOSTOUCH_WHEEL_NUM] = {
  [IOSTOUCH_WHEEL_NONE]    = { { 0, 0, 0, 217 }, { 70, 70, 70, 255 }, { 120, 120, 120, 255 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 },
                               { 32, 32, 32 }, { 255, 255, 255 }, WRIM_PLAIN, WMOTIF_NONE },
  [IOSTOUCH_WHEEL_DUKE]    = { { 8, 8, 6, 222 }, { 255, 196, 0, 255 }, { 20, 18, 10, 255 }, { 255, 196, 0, 46 }, { 0, 0, 0, 0 },
                               { 34, 30, 18 }, { 255, 210, 60 }, WRIM_HAZARD, WMOTIF_TREFOIL },
  [IOSTOUCH_WHEEL_RR]      = { { 46, 28, 16, 225 }, { 150, 78, 38, 255 }, { 214, 170, 110, 255 }, { 226, 176, 90, 44 }, { 0, 0, 0, 0 },
                               { 44, 30, 20 }, { 236, 190, 120 }, WRIM_RIVETS, WMOTIF_STAR },
  [IOSTOUCH_WHEEL_BLOOD]   = { { 24, 4, 4, 225 }, { 120, 14, 14, 255 }, { 226, 214, 184, 255 }, { 200, 30, 24, 52 }, { 0, 0, 0, 0 },
                               { 38, 14, 14 }, { 232, 220, 190 }, WRIM_TICKS, WMOTIF_PENTACLE },
  [IOSTOUCH_WHEEL_SW]      = { { 6, 6, 6, 225 }, { 200, 24, 24, 255 }, { 0, 0, 0, 255 }, { 230, 40, 34, 52 }, { 240, 232, 220, 30 },
                               { 34, 18, 18 }, { 255, 90, 80 }, WRIM_PLAIN, WMOTIF_YINYANG },
  [IOSTOUCH_WHEEL_EXHUMED] = { { 14, 30, 72, 225 }, { 212, 168, 60, 255 }, { 255, 222, 120, 255 }, { 240, 196, 80, 48 }, { 0, 0, 0, 0 },
                               { 20, 30, 54 }, { 255, 214, 110 }, WRIM_DOTS, WMOTIF_SUN },
};
// (Duke World Tour's and Rides Again's are Duke's and Redneck Rampage's)
static const IOSTouchWheelTheme *IOSTouch_WheelThemeOf(int iMap)
{
  if (iMap == IOSTOUCH_WHEEL_DUKEWT) iMap = IOSTOUCH_WHEEL_DUKE;
  if (iMap == IOSTOUCH_WHEEL_RRRA) iMap = IOSTOUCH_WHEEL_RR;
  return &_aWheelThemes[(iMap > 0 && iMap < IOSTOUCH_WHEEL_NUM) ? iMap : IOSTOUCH_WHEEL_NONE];
}
static void IOSTouch_ThemeColour(const unsigned char aub[4], float af[4])
{
  for (int c = 0; c < 4; c++) af[c] = aub[c] / 255.0f;
}

// A slice's colour, k of the way to it from the wheel's dark (RGB 0..1)
static void IOSTouch_WheelMix(int iColour, double k, float af[4])
{
  const unsigned char *base = IOSTouch_WheelThemeOf(_iWheelMap)->aubBase;
  for (int c = 0; c < 3; c++) af[c] = (float)((_aubWheelColours[iColour][c] * k + base[c] * (1.0 - k)) / 255.0);
  af[3] = 1.0f;
}
static void IOSTouch_Grey(double v, double a, float af[4])
{
  af[0] = af[1] = af[2] = (float)v;
  af[3] = (float)a;
}

// Whether dark text (grey 0.08) reads better than white on this colour: the
// higher contrast of the two by WCAG's relative luminance (on the rockets'
// popped red white does, 4.7:1 to dark's 3.9:1; on the others dark does)
static double IOSTouch_Luminance(const float af[4])
{
  double l = 0.0;
  static const double afW[3] = { 0.2126, 0.7152, 0.0722 };
  for (int c = 0; c < 3; c++) {
    const double v = af[c];
    l += afW[c] * (v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4));
  }
  return l;
}
static int IOSTouch_DarkReads(const float afFill[4])
{
  const float afDark[4] = { 0.08f, 0.08f, 0.08f, 1.0f };
  const double lf = IOSTouch_Luminance(afFill), ld = IOSTouch_Luminance(afDark);
  return (lf + 0.05) / (ld + 0.05) >= (1.0 + 0.05) / (lf + 0.05);
}

// How slice i looks now (the view draws it so; the colours RGBA 0..1). A
// weapon it can switch to in its ammo type's colour, the weapon in hand
// edged in white, the one pointed at popped out and brighter; one out of
// ammo in a darker shade, its icon grey; one not found yet dark, its icon a
// faint silhouette, no count.
typedef struct {
  int iState;          // WSTATE_*
  int bHot, bWanted, bPopped;
  float afFill[4], afEdge[4];
  double fLine;        // the edge's width
  int iIcon;           // WICON_*: which tint of its icon
  int iCount;          // the count under the icon, -1: none
  float afText[4];     // the count's colour (and the name's, while it has no icon)
} IOSTouchWheelLook;

static void IOSTouch_WheelSlotLook(int i, int iHot, IOSTouchWheelLook *pl)
{
  const IOSTouchWheelMap *m = IOSTouch_WheelMapOf(_iWheelMap);
  const IOSTouchWheelSlot *sl = &m->aSlots[i];
  memset(pl, 0, sizeof(*pl));
  pl->iState = IOSTouch_WheelSlotState(i);
  pl->bHot = i == iHot;
  pl->bWanted = sl->iWeapon == _wpn.iWanted;
  pl->iCount = IOSTouch_WheelSlotCount(i);
  pl->fLine = 2.0;
  if (pl->iState == WSTATE_READY) {
    pl->bPopped = pl->bHot && !pl->bWanted;
    pl->iIcon = WICON_READY;
    IOSTouch_WheelMix(sl->iColour, pl->bPopped ? 0.70 : 0.42, pl->afFill);
    if (pl->bPopped) IOSTouch_Grey(1.0, 1.0, pl->afEdge);
    else IOSTouch_WheelMix(sl->iColour, 0.8, pl->afEdge);
    if (pl->bPopped) pl->fLine = 2.5;
    if (pl->bPopped) IOSTouch_Grey(IOSTouch_DarkReads(pl->afFill) ? 0.08 : 1.0, 1.0, pl->afText);
    else IOSTouch_Grey(1.0, 1.0, pl->afText);
  }
  else if (pl->iState == WSTATE_NOAMMO) {
    pl->iIcon = WICON_NOAMMO;
    IOSTouch_WheelMix(sl->iColour, 0.22, pl->afFill);
    IOSTouch_WheelMix(sl->iColour, pl->bHot ? 0.8 : 0.55, pl->afEdge);
    if (pl->bHot) pl->fLine = 2.5;
    IOSTouch_Grey(1.0, 0.75, pl->afText);
  }
  else {
    pl->iIcon = WICON_NOTFOUND;
    IOSTouch_Grey(pl->bHot ? 0.24 : 0.18, 0.92, pl->afFill);
    IOSTouch_WheelMix(sl->iColour, pl->bHot ? 0.7 : 0.45, pl->afEdge);
    if (pl->bHot) pl->fLine = 2.5;
    IOSTouch_Grey(pl->bHot ? 0.75 : 0.59, 1.0, pl->afText);
    pl->iCount = -1;
  }
  if (pl->bWanted) {
    IOSTouch_Grey(1.0, 1.0, pl->afEdge);
    pl->fLine = 2.5;
  }
}

// The needle at the edge of the middle, the way the sliding thumb points:
// whether it shows, its ends (points) and colour
static int IOSTouch_WheelNeedle(double *px0, double *py0, double *px1, double *py1, float af[4])
{
  const IOSTouchSlot *pSlide = NULL;
  const int hot = IOSTouch_WheelPointed(NULL, &pSlide);
  if (!pSlide || !pSlide->bArmed || hot == -1) return 0;
  const double a = pSlide->wheelAim * M_PI / 180.0;
  *px0 = _fWheelCX + (_fWheelR0 - 9.0) * cos(a);
  *py0 = _fWheelCY - (_fWheelR0 - 9.0) * sin(a);
  *px1 = _fWheelCX + (_fWheelR0 - 2.0) * cos(a);
  *py1 = _fWheelCY - (_fWheelR0 - 2.0) * sin(a);
  if (hot >= 0 && IOSTouch_WheelSlotState(hot) == WSTATE_READY) IOSTouch_WheelMix(IOSTouch_WheelMapOf(_iWheelMap)->aSlots[hot].iColour, 1.0, af);
  else IOSTouch_Grey(0.6, 1.0, af);
  return 1;
}

// A finger came down at (x,y) on a screen W points wide; now: when it
// reached us (as IOSTouch_TickHolds counts), tTouch: when it went down by
// the touch's own clock
static void IOSTouch_TouchBegan(const void *touch, double x, double y, double W, double now, double tTouch)
{
  IOSTouchSlot *s = IOSTouch_FindSlot(NULL);
  if (!s || !touch) return;
  memset(s, 0, sizeof(*s));
  s->touch = touch;
  s->x = x;
  s->y = y;
  s->tDown = now;
  s->tDownTouch = tTouch;
  s->uSeq = ++_uTouchSeq;
  s->trayButton = -1;
  s->wheelSlot = -1;
  // Hidden for a game controller: a touch brings the controls back, and
  // does nothing else until it lifts
  if (_bPadHidden) {
    _bPadHidden = 0;
    s->role = ROLE_IGNORED;
    s->button = -1;
    return;
  }
  // The cheat's list of levels open: the list itself takes the touches on it
  // (the view's level panel); one anywhere else closes it, and does nothing
  // more until it lifts
  if (_bLevelListOpen) {
    IOSTouch_CloseLevelList();
    s->role = ROLE_IGNORED;
    s->button = -1;
    return;
  }
  // The open weapon wheel takes every touch: on a slice it is a tap there,
  // anywhere else it closes the wheel as it lifts
  if (_bWheelOpen) {
    s->role = ROLE_WHEEL;
    s->button = -1;
    s->wheelSlot = IOSTouch_WheelSliceAt(x, y, -1);
    IOSTouch_WheelUpdateHot();
    return;
  }
  s->button = IOSTouch_ButtonAt(x, y);

  // An open tray closes at a touch anywhere else, which then does what it
  // would anyway -- except on MENU, where it only closes the tray
  if (_bTrayOpen && !IOSTouch_IsTrayButton(s->button)) {
    IOSTouch_SetTrayOpen(0);
    if (s->button == BTN_MENU) {
      s->role = ROLE_IGNORED;
      return;
    }
  }

  if (s->button >= 0 && _aButtons[s->button].kind == KIND_WHEEL) {
    // NEXT WPN, PREV WPN: nothing yet -- a tap, a slide or a hold
    // (IOSTouch_TouchMoved, IOSTouch_TickHolds, IOSTouch_TouchEnded). A
    // second finger on the same button is ignored.
    int bOther = 0;
    for (int k = 0; k < IOSTOUCH_MAX_TOUCHES; k++) {
      const IOSTouchSlot *o = &_aSlots[k];
      if (o != s && IOSTouch_IsWheelPress(o) && o->button == s->button) bOther = 1;
    }
    if (bOther) {
      s->role = ROLE_IGNORED;
    }
    else {
      s->role = ROLE_BUTTON;
      _aButtonHeld[s->button]++;
      s->xDown = x;
      s->yDown = y;
    }
  }
  else if (s->button == BTN_CAMERA && IOSTouch_CameraBusy()) {
    s->role = ROLE_IGNORED; // (the camera is busy: CAMERA is dimmed and takes no new press)
  }
  else if (s->button >= 0) {
    s->role = ROLE_BUTTON;
    _aButtonHeld[s->button]++;
    s->xDown = x; // (CAMERA's and ITEM's slides are measured from here, and the cheat's holds)
    s->yDown = y;
  }
  else if (_iMode != IOSTOUCH_GAMEPLAY) {
    s->role = ROLE_IGNORED; // only the buttons are live (console open, paused)
  }
  else if (x < W * IOSTOUCH_STICK_ZONE && !_bStickActive) {
    s->role = ROLE_STICK;
    _bStickActive = 1;
    _fStickOriginX = x;
    _fStickOriginY = y;
    _fStickX = _fStickY = 0.0f;
  }
  else {
    s->role = ROLE_LOOK;
  }
  IOSTouch_SetHeld(IOSTouch_HeldButtons(), 0);
}

// A finger moved to (x,y). Returns whether the buttons' looks changed (a
// thumb held on MENU slid onto or off a tray button, the weapon wheel opened).
static int IOSTouch_TouchMoved(const void *touch, double x, double y)
{
  IOSTouchSlot *s = touch ? IOSTouch_FindSlot(touch) : NULL;
  if (!s) return 0;
  int bLooksChanged = 0;
  // NEXT WPN, PREV WPN slid far enough from where they went down: the
  // weapon wheel opens at once, to slide to a slice (from here on this is
  // its opener)
  if (IOSTouch_WheelPressSlid(s, x, y)) bLooksChanged = 1;
  if (s->role == ROLE_WHEEL) {
    if (s->bWheelOpener && s->bWheelHeld) {
      // opened by holding still: open to tap, until it slides out of the
      // dead zone -- then it picks by sliding
      if (hypot(x - s->xDown, y - s->yDown) >= IOSTOUCH_WHEEL_DEAD) {
        _bWheelTapMode = 0;
        s->bWheelHeld = 0;
        IOSTouch_WheelAim(s, x, y);
      }
    }
    else if (s->bWheelOpener && !_bWheelTapMode) {
      IOSTouch_WheelAim(s, x, y);
    }
    else {
      s->wheelSlot = IOSTouch_WheelSliceAt(x, y, s->wheelSlot);
    }
    IOSTouch_WheelUpdateHot();
  }
  else if (s->role == ROLE_BUTTON && s->button == BTN_MENU && s->bFired && _bTrayOpen) {
    // Held until the tray opened: the tray button under the thumb lights up
    int tb = IOSTouch_ButtonAt(x, y);
    tb = IOSTouch_IsTrayButton(tb) ? tb : -1;
    if (tb != s->trayButton) {
      s->trayButton = tb;
      bLooksChanged = 1;
    }
  }
  else if (s->role == ROLE_BUTTON && s->button == BTN_CAMERA && !s->bFired && _iMode == IOSTOUCH_GAMEPLAY) {
    // CAMERA slid: mostly down far enough, Action Freeze; mostly up far
    // enough, the cinematic burst; any other way, a burst
    const double dx = x - s->xDown, dy = y - s->yDown;
    const int bVertical = fabs(dy) >= fabs(dx) && dy != 0.0;
    const double upFar = fmin(IOSTOUCH_FREEZE_SWIPE, fmax(s->yDown - IOSTOUCH_FREEZE_EDGE, IOSTOUCH_FREEZE_SWIPE_MIN));
    if (bVertical && fabs(dy) >= (dy > 0 ? IOSTOUCH_FREEZE_SWIPE : upFar)) {
      s->bFired = 1;
      _fCameraRing = 0.0f;
      if (_aButtonHeld[BTN_CAMERA] > 0) _aButtonHeld[BTN_CAMERA]--;
      s->role = ROLE_IGNORED;
      if (dy > 0) iosCamera_Freeze();
      else iosCamera_Cinematic();
      bLooksChanged = 1;
    }
    else if (!bVertical && hypot(dx, dy) >= IOSTOUCH_WHEEL_OPEN_SLIDE) {
      s->bFired = 1;
      _fCameraRing = 0.0f;
      iosCamera_Burst();
      bLooksChanged = 1;
    }
  }
  else if (s->role == ROLE_BUTTON && s->button == BTN_ITEM) {
    // ITEM slid sideways: the previous / next item, a step each
    // IOSTOUCH_ITEM_STEP; its lift then uses none
    const double dx = x - s->xDown;
    const int steps = (int)(dx / IOSTOUCH_ITEM_STEP); // (toward zero)
    if (steps != s->iItemSteps) {
      _iRequests |= steps > s->iItemSteps ? IOSTOUCH_REQ_INVNEXT : IOSTOUCH_REQ_INVPREV;
      s->iItemSteps = steps;
      s->bFired = 1;
      _ctCheatTicks++; // (a haptic tick for each step, the view's selection tick)
    }
    if (fabs(dx) >= IOSTOUCH_WHEEL_OPEN_SLIDE || fabs(y - s->yDown) >= IOSTOUCH_WHEEL_OPEN_SLIDE) s->bFired = 1;
  }
  else if (s->role == ROLE_STICK) {
    float dx = (float)(x - _fStickOriginX) / IOSTOUCH_STICK_RADIUS;
    float dy = (float)(y - _fStickOriginY) / IOSTOUCH_STICK_RADIUS;
    float len = sqrtf(dx * dx + dy * dy);
    if (len > 1.0f) { dx /= len; dy /= len; }
    _fStickX = dx;
    _fStickY = dy;
    IOSTouch_SetMoveFromStick();
  }
  else if (s->role == ROLE_LOOK || (s->role == ROLE_BUTTON && _aButtons[s->button].bLookWhileHeld)) {
    const float fLookX = (float)(x - s->x) * IOSTOUCH_LOOK_SCALE_X * _fLookScale;
    const float fLookY = (float)(y - s->y) * IOSTOUCH_LOOK_SCALE_Y * _fLookScale;
    os_unfair_lock_lock(&_lock);
    if (_bReading) {
      _fLookX += fLookX;
      _fLookY += fLookY;
    }
    os_unfair_lock_unlock(&_lock);
  }
  // QUICK SAVE, QUICK LOAD: a finger that leaves the button, even between two
  // frames, doesn't save or load, even if it comes back on (IOSTouch_TickHolds
  // checks too, for a button that moved away from a finger keeping still)
  if (s->role == ROLE_BUTTON && IOSTouch_IsQuickHold(s->button) && !IOSTouch_IsOnButton(x, y, s->button)) {
    s->bFired = 1;
  }
  // the cheat's holds: only a finger keeping still
  IOSTouch_CheatMoved(s, x, y);
  s->x = x;
  s->y = y;
  return bLooksChanged;
}

// A finger passed (x,y) on its way to where IOSTouch_TouchMoved is told it
// went next (UIKit merges a finger's moves while the game's frame runs, and
// keeps the places in between): only QUICK SAVE and QUICK LOAD care, so a
// slide off one and back on still ends its hold
static void IOSTouch_TouchPassed(const void *touch, double x, double y)
{
  IOSTouchSlot *s = touch ? IOSTouch_FindSlot(touch) : NULL;
  // (NEXT WPN and PREV WPN too: a slide that far opens the wheel, even if it
  // came back)
  if (s) IOSTouch_WheelPressSlid(s, x, y);
  if (s && s->role == ROLE_BUTTON && IOSTouch_IsQuickHold(s->button) && !IOSTouch_IsOnButton(x, y, s->button)) {
    s->bFired = 1;
  }
}

// A finger lifted at (x,y), at tTouch by its own clock. bCancelled: iOS
// took the touch away (a call, a system gesture...) -- release whatever it
// held, but don't treat it as a finished tap.
static void IOSTouch_TouchEnded(const void *touch, double x, double y, int bCancelled, double tTouch)
{
  IOSTouchSlot *s = touch ? IOSTouch_FindSlot(touch) : NULL;
  if (!s) return;
  unsigned int ulLifted = 0;
  if (s->role == ROLE_WHEEL && _bWheelOpen) {
    if (bCancelled) {
      // the opener taken away: the wheel stays open, to tap
      if (s->bWheelOpener) _bWheelTapMode = 1;
    }
    else if (s->bWheelOpener && s->bWheelHeld) {
      // opened by holding still, lifted without sliding: it stays open, to tap
    }
    else if (s->bWheelOpener && !_bWheelTapMode) {
      // the slide's lift: what it points at, or no change -- or, if it never
      // slid out of the dead zone, the wheel stays open to tap
      IOSTouch_WheelAim(s, x, y);
      if (!s->bArmed) _bWheelTapMode = 1;
      else IOSTouch_WheelClose(s->wheelSlot);
    }
    else {
      // A tap: on a weapon it can switch to picks it; on one it can't the
      // wheel stays open; anywhere else (the weapon in hand, the middle, the
      // gap, off the ring, a button) it closes with no change -- except off
      // the ring while the opener is still sliding and pointing: that finger
      // is only resting, the slide goes on
      const int slice = IOSTouch_WheelSliceAt(x, y, s->wheelSlot);
      int bSliding = 0;
      for (int k = 0; k < IOSTOUCH_MAX_TOUCHES; k++) {
        const IOSTouchSlot *o = &_aSlots[k];
        if (o != s && o->touch && o->role == ROLE_WHEEL && o->bWheelOpener && o->bArmed && !_bWheelTapMode) bSliding = 1;
      }
      if (!(slice == -1 && bSliding) && !(slice >= 0 && IOSTouch_WheelSlotState(slice) != WSTATE_READY)) {
        IOSTouch_WheelClose(slice);
      }
    }
  }
  else if (IOSTouch_IsWheelPress(s)) {
    // NEXT WPN, PREV WPN lifted before the wheel opened
    const IOSTouchButton *b = &_aButtons[s->button];
    if (_aButtonHeld[s->button] > 0) _aButtonHeld[s->button]--;
    _afWheelRing[s->button == BTN_PREVWPN] = 0.0f;
    if (bCancelled || s->bFired) {
      // iOS took it, or it slid or held while the wheel couldn't open: nothing
    }
    else if (hypot(x - s->xDown, y - s->yDown) >= IOSTOUCH_WHEEL_OPEN_SLIDE) {
      // a flick, with no move in between: as a slide, then its lift
      if (IOSTouch_WheelCanOpen()) {
        IOSTouch_WheelOpen(s, 0);
        IOSTouch_WheelAim(s, x, y);
        if (s->bArmed) IOSTouch_WheelClose(s->wheelSlot);
        else _bWheelTapMode = 1;
      }
    }
    else if (tTouch - s->tDownTouch < IOSTOUCH_WHEEL_HOLD) {
      // a quick tap (by the touch's own clock, so a slow frame between the
      // two doesn't make it long): one press of NEXT / PREV
      ulLifted |= b->ulAction;
    }
    else if (IOSTouch_WheelCanOpen()) {
      // held long enough, but lifted before a frame could see it (a slow
      // one): the hold, the wheel open to tap
      IOSTouch_WheelOpen(s, 1);
    }
  }
  else if (s->role == ROLE_BUTTON) {
    const IOSTouchButton *b = &_aButtons[s->button];
    if (_aButtonHeld[s->button] > 0) _aButtonHeld[s->button]--;
    // A tap so quick that no game tick saw it held still counts as one press
    if (!bCancelled && b->kind == KIND_HOLD && _aButtonHeld[s->button] == 0) {
      ulLifted |= b->ulAction;
    }
    // These act when the finger lifts on the button, so a slip onto one can
    // be dragged off again
    if (!bCancelled && IOSTouch_LiftsOnButton(x, y, s->button)) {
      if (b->kind == KIND_TAP) {
        _iRequests |= b->ulAction;
      }
      else if (b->kind == KIND_ITEM && !s->bFired) {
        ulLifted |= b->ulAction; // never held, so the game gets it as one press
      }
      else if (IOSTouch_IsTrayButton(s->button) && !((s->button == BTN_TRAYCAM || s->button == BTN_TRAYLOOK || s->button == BTN_TRAYFPS || s->button == BTN_TRAYOPACITY) && s->bFired)) {
        IOSTouch_UseTrayButton(s->button); // (not the tray's CAMERA, LOOK or FPS once held: that opened its options, set 1x, or switched 60/120)
      }
      else if (b->kind == KIND_MENU && !s->bFired) {
        _iRequests |= b->ulAction; // a tap: the menu
      }
      else if (b->kind == KIND_CAMERA && !s->bFired && !IOSTouch_CameraBusy()) {
        // a tap: a photo; held long enough but lifted before a frame could
        // see it (a slow one): the selfie
        if (tTouch - s->tDownTouch < IOSTOUCH_SELFIE_HOLD) iosCamera_Photo();
        else if (_iMode == IOSTOUCH_GAMEPLAY) iosCamera_Selfie();
      }
    }
    if (s->button == BTN_CAMERA) _fCameraRing = 0.0f;
    if (s->button == BTN_TRAYCAM) _fCamSwitchRing = 0.0f;
    if (s->button == BTN_TRAYLOOK) _fLookRing = 0.0f;
    if (s->button == BTN_TRAYFPS) _fFpsRing = 0.0f;
    if (s->button == BTN_TRAYOPACITY) _fOpacityRing = 0.0f;
    // MENU held until its tray opened, then slid onto one of its buttons
    if (!bCancelled && s->button == BTN_MENU && s->bFired && _bTrayOpen) {
      const int tb = IOSTouch_ButtonAt(x, y);
      if (IOSTouch_IsTrayButton(tb)) IOSTouch_UseTrayButton(tb);
    }
    // a lift never saves or loads: only a finished hold does
    if (s->button == BTN_QUICKSAVE) _fSaveRing = 0.0f;
    if (s->button == BTN_QUICKLOAD) _fLoadRing = 0.0f;
    if (s->button == BTN_MENU) _fMenuRing = 0.0f;
  }
  else if (s->role == ROLE_STICK) {
    _bStickActive = 0;
    _fStickX = _fStickY = 0.0f;
    IOSTouch_SetMoveFromStick();
  }
  IOSTouch_CheatLifted(s, x, y, bCancelled, tTouch);
  memset(s, 0, sizeof(*s));
  if (_bWheelOpen) IOSTouch_WheelUpdateHot();
  IOSTouch_SetHeld(IOSTouch_HeldButtons(), ulLifted);
}

// Once per frame while shown: the QUICK SAVE, QUICK LOAD and MENU holds,
// NEXT WPN's and PREV WPN's, CAMERA's and the tray's
static void IOSTouch_TickHolds(double now)
{
  // QUICK SAVE and QUICK LOAD go off only once the finger is known to have
  // stayed down long enough, so they are timed to the previous tick, not this
  // one. UIKit hands over touches whenever SDL pumps events, which Raze does
  // at least once each frame before it draws: by now, then, every lift made
  // before the previous tick has arrived, and a finger still down was down
  // from tDown to then. This costs at most a frame.
  const double known = _tLastTick;
  _tLastTick = now;
  IOSTouch_TickCheat(now, known);
  // NEXT WPN and PREV WPN held still (they haven't slid, or the wheel would
  // be open): known to be held IOSTOUCH_WHEEL_HOLD, the wheel opens to tap a
  // slice; until then the ring fills. The first to get there opens it (which
  // drops the other). This comes before the QUICK SAVE, QUICK LOAD and MENU
  // holds: one that completes in the same tick is then dropped by the wheel
  // opening, which ignores every other touch, rather than saving or loading
  // under the wheel. While the wheel couldn't open (the player dead...)
  // there is no ring, and a press held that long is no tap either.
  float afWheelRing[2] = { 0.0f, 0.0f };
  for (int i = 0; i < IOSTOUCH_MAX_TOUCHES && !_bWheelOpen; i++) {
    IOSTouchSlot *s = &_aSlots[i];
    if (!IOSTouch_IsWheelPress(s) || s->bFired) continue;
    if (known - s->tDown >= IOSTOUCH_WHEEL_HOLD) {
      if (IOSTouch_WheelCanOpen()) {
        IOSTouch_WheelOpen(s, 1);
        afWheelRing[0] = afWheelRing[1] = 0.0f;
        break; // (every other touch is ignored now)
      }
      s->bFired = 1;
      continue;
    }
    if (IOSTouch_WheelCanOpen()) {
      float *pf = &afWheelRing[s->button == BTN_PREVWPN];
      *pf = fmaxf(*pf, (float)fmax(0.0, (known - s->tDown) / IOSTOUCH_WHEEL_HOLD));
    }
  }
  _afWheelRing[0] = afWheelRing[0];
  _afWheelRing[1] = afWheelRing[1];
  // the furthest along of QUICK SAVE's and of QUICK LOAD's holds (a touch each)
  _fLookRing = 0.0f; // (set again below while LOOK is held)
  _fFpsRing = 0.0f; // (...and FPS)
  _fOpacityRing = 0.0f; // (...and OPACITY)
  float fSaveRing = 0.0f, fLoadRing = 0.0f;
  int iDone = -1; // the quick hold that completed: BTN_QUICKSAVE or BTN_QUICKLOAD
  for (int i = 0; i < IOSTOUCH_MAX_TOUCHES; i++) {
    IOSTouchSlot *s = &_aSlots[i];
    if (!s->touch || s->bFired) continue;
    if (s->role != ROLE_BUTTON) continue;
    if (IOSTouch_IsQuickHold(s->button)) {
      if (!IOSTouch_IsOnButton(s->x, s->y, s->button)) {
        // off it (a finger that slid off is already done, in
        // IOSTouch_TouchMoved; this is the button laid out again away from a
        // finger keeping still): this touch doesn't save or load, even if it
        // comes back on
        s->bFired = 1;
        continue;
      }
      const double hold = (s->button == BTN_QUICKSAVE) ? IOSTOUCH_QUICKSAVE_HOLD : IOSTOUCH_QUICKLOAD_HOLD;
      if (known - s->tDown >= hold) {
        // the ring is full, with the finger still on it. QUICK SAVE and QUICK
        // LOAD both found done in the same tick (one long frame can cover
        // both, whichever was touched first): QUICK SAVE, as only a load
        // throws away the game being played
        if (iDone != BTN_QUICKSAVE) iDone = s->button;
      }
      else {
        const float fRing = (float)fmin((now - s->tDown) / hold, 1.0);
        if (s->button == BTN_QUICKSAVE) fSaveRing = fmaxf(fSaveRing, fRing);
        else fLoadRing = fmaxf(fLoadRing, fRing);
      }
    }
    else if (s->button == BTN_CAMERA && _iMode == IOSTOUCH_GAMEPLAY) {
      // held still (a slide already fired: a burst, Action Freeze, the
      // cinematic burst): known to be held IOSTOUCH_SELFIE_HOLD, a selfie;
      // until then the ring fills
      if (known - s->tDown >= IOSTOUCH_SELFIE_HOLD) {
        s->bFired = 1;
        _fCameraRing = 0.0f;
        if (_aButtonHeld[BTN_CAMERA] > 0) _aButtonHeld[BTN_CAMERA]--;
        s->role = ROLE_IGNORED;
        iosCamera_Selfie();
        continue;
      }
      _fCameraRing = (float)fmin(fmax(0.0, (now - s->tDown) / IOSTOUCH_SELFIE_HOLD), 1.0);
    }
    else if (s->button == BTN_TRAYCAM) {
      // the tray's CAMERA held: its options open (the lift then does nothing)
      if (!IOSTouch_IsOnButton(s->x, s->y, BTN_TRAYCAM)) {
        s->bFired = 1;
        _fCamSwitchRing = 0.0f;
        continue;
      }
      const double progress = (now - s->tDown) / IOSTOUCH_MENU_HOLD;
      if (progress >= 1.0) {
        s->bFired = 1;
        _fCamSwitchRing = 0.0f;
        IOSTouch_SetTrayOpen(0);
        iosCamera_ShowOptions();
      }
      else {
        _fCamSwitchRing = (float)progress;
      }
    }
    else if (s->button == BTN_TRAYOPACITY) {
      // the tray's OPACITY held: back to 100%, as the controls always were
      // (the lift then does nothing)
      if (!IOSTouch_LiftsOnButton(s->x, s->y, BTN_TRAYOPACITY)) {
        s->bFired = 1;
        _fOpacityRing = 0.0f;
        continue;
      }
      const double progress = (now - s->tDown) / IOSTOUCH_MENU_HOLD;
      if (progress >= 1.0) {
        s->bFired = 1;
        _fOpacityRing = 0.0f;
        _fOpacity = 1.0f;
        _bOpacityOpen = 0;
        _ctOpacityResets++;
        IOS_ShowCameraMessage("Opacity back to the default, 100%");
      }
      else {
        _fOpacityRing = (float)progress;
      }
    }
    else if (s->button == BTN_TRAYFPS) {
      // the tray's FPS held: 60 or 120 frames a second (the lift then does
      // nothing)
      if (!IOSTouch_LiftsOnButton(s->x, s->y, BTN_TRAYFPS)) {
        s->bFired = 1;
        _fFpsRing = 0.0f;
        continue;
      }
      const double progress = (now - s->tDown) / IOSTOUCH_MENU_HOLD;
      if (progress >= 1.0) {
        s->bFired = 1;
        _fFpsRing = 0.0f;
        _iMaxFps = (_iMaxFps == 120) ? 60 : 120;
        _ctMaxFpsChanges++;
        IOS_ShowCameraMessage(_iMaxFps == 120 ? "120 FPS: smoother, uses more battery" : "60 FPS: cooler, uses less battery");
      }
      else {
        _fFpsRing = (float)progress;
      }
    }
    else if (s->button == BTN_TRAYLOOK) {
      // the tray's LOOK held: back to 1x (the lift then does nothing)
      if (!IOSTouch_LiftsOnButton(s->x, s->y, BTN_TRAYLOOK)) {
        s->bFired = 1;
        _fLookRing = 0.0f;
        continue;
      }
      const double progress = (now - s->tDown) / IOSTOUCH_MENU_HOLD;
      if (progress >= 1.0) {
        s->bFired = 1;
        _fLookRing = 0.0f;
        _fLookScale = 1.0f;
        _ctLookResets++;
        IOS_ShowCameraMessage("Look sensitivity back to the default, 1x");
      }
      else {
        _fLookRing = (float)progress;
      }
    }
    else if (s->button == BTN_MENU) {
      if (!IOSTouch_IsOnButton(s->x, s->y, BTN_MENU)) {
        // slid off: no tray, and no menu either
        s->bFired = 1;
        _fMenuRing = 0.0f;
        continue;
      }
      const double progress = (now - s->tDown) / IOSTOUCH_MENU_HOLD;
      if (progress >= 1.0) {
        s->bFired = 1;
        _fMenuRing = 0.0f;
        IOSTouch_SetTrayOpen(1);
      }
      else {
        _fMenuRing = (float)progress;
      }
    }
  }
  if (iDone >= 0) {
    // One save or load, once: it ends every hold on QUICK SAVE and QUICK LOAD,
    // so two fingers on one button ask once, and the two buttons held together
    // save or load, whichever is found done first, never both (both would only
    // load back the game just saved, or save again the one just loaded)
    for (int j = 0; j < IOSTOUCH_MAX_TOUCHES; j++) {
      IOSTouchSlot *o = &_aSlots[j];
      if (o->touch && o->role == ROLE_BUTTON && IOSTouch_IsQuickHold(o->button)) o->bFired = 1;
    }
    fSaveRing = fLoadRing = 0.0f;
    _iRequests |= _aButtons[iDone].ulAction;
  }
  _fSaveRing = fSaveRing;
  _fLoadRing = fLoadRing;
}

// Once per frame while shown: the FPS readout counts the frames the game
// drew (ulFrames, the game's own count) over IOSTOUCH_FPS_PERIOD or so. It
// starts over whenever the game's count does, and after the overlay was
// hidden (time spent in a menu or loading doesn't count).
static void IOSTouch_CountFrames(unsigned int ulFrames, double now)
{
  if (!_bShowFps) return;
  if (!_bFpsBase || ulFrames < _ulFpsFrames) {
    _bFpsBase = 1;
    _ulFpsFrames = ulFrames;
    _tFpsBase = now;
  }
  else if (now - _tFpsBase >= IOSTOUCH_FPS_PERIOD) {
    _iFpsShown = (int)lround((double)(ulFrames - _ulFpsFrames) / (now - _tFpsBase));
    _ulFpsFrames = ulFrames;
    _tFpsBase = now;
  }
}

// Whether the FPS readout is under the open tray's backing (it keeps clear
// of the FPS and keyboard buttons' part, not of GYRO's and SENS's): it
// hides while the tray is open
static int IOSTouch_FpsUnderTray(void)
{
  const IOSTouchRect *r = &_rTrayBack;
  if (!r->bValid) return 0;
  const double dx = fmax(fmax(r->x0 - (_fFpsX + IOSTOUCH_FPS_W * 0.5), (_fFpsX - IOSTOUCH_FPS_W * 0.5) - r->x1), 0.0);
  const double dy = fmax(fmax(r->y0 - (_fFpsY + IOSTOUCH_FPS_H * 0.5), (_fFpsY - IOSTOUCH_FPS_H * 0.5) - r->y1), 0.0);
  return hypot(dx, dy) < 4.0;
}

// The app's version (the view sets its words), shown while the tray is open:
// the middle of its line (fHalfW wide each way), centred just below the
// tray's backing. It is only words: not a button, nothing finds it, and it
// moves nothing.
#define IOSTOUCH_VERSION_H 12.0
static void IOSTouch_VersionCentre(double fHalfW, double *px, double *py)
{
  (void)fHalfW;
  *px = (_rTrayBack.x0 + _rTrayBack.x1) * 0.5;
  *py = _rTrayBack.y1 + 4.0 + IOSTOUCH_VERSION_H * 0.5;
}

// ---------------------------------------------------------------- tilt aiming
// The view starts and stops CoreMotion's updates (IOSTouch_GyroRunUpdates)
// and hands each sample to IOSTouch_GyroSample, on the samples' own queue;
// IOSTouch_GyroFrame runs once a frame on the main thread, after the
// frame's touches came in, and hands what may aim to the game's
// IOSTouch_TakeGyro (either game thread). The two locks are never held
// together.

static void IOSTouch_GyroRunUpdates(int bRun); // the view's (CoreMotion)

// One sample of device motion, on the samples' queue: the rotation rate w
// (rad/s) and gravity g (toward the ground) in the device's own axes (x
// right, y up, z out of the screen, as if held upright), taken at time t.
// Adds how far it turns and tilts the view.
static void IOSTouch_GyroSample(double wx, double wy, double wz, double gx, double gy, double gz, double t)
{
  os_unfair_lock_lock(&_gyroLock);
  const double dt = _tGyroLastSample > 0.0 ? t - _tGyroLastSample : 0.0;
  _tGyroLastSample = t;
  const double s = _iGyroSide;
  const double gn = sqrt(gx * gx + gy * gy + gz * gz);
  if (s != 0.0 && dt > 0.0 && dt <= IOSTOUCH_GYRO_MAX_DT && gn > 0.1) {
    // The screen's axes as the player sees it: right, up, toward them. How
    // fast the phone turns about each (the right-hand way round: + about up
    // turns left), and how far each points up.
    const double rx = s * wy, ry = -s * wx, rz = wz;
    const double ux = -s * gy / gn, uy = s * gx / gn, uz = -gz / gn;
    // Not while held upside down for the way round the screen is turned
    // (rolled more than 120 degrees either way, unless within 30 of flat):
    // the phone is on its way round to the other landscape side
    const double tilt = sqrt(ux * ux + uy * uy);
    if (tilt < 0.5 || uy > -0.5 * tilt) {
      double yaw = ry, pitch = rx;
      if (uz >= 0.0 && (tilt < 0.5 || uy > 0.5 * tilt)) {
        // Player space, while the screen faces up and is held the way round
        // it is turned (rolled less than 60 degrees either way) or about
        // flat: turning is about up, from the screen's up and
        // toward-the-player axes as far as each points up
        yaw = uy * ry + uz * rz;
        const double mag = sqrt(ry * ry + rz * rz);
        yaw = copysign(fmin(fabs(yaw) * IOSTOUCH_GYRO_YAW_RELAX, mag), yaw);
      }
      // (Otherwise local space: facing down, or rolled further over --
      // which also leaves out the roll of a phone on its way round.)
      yaw *= 180.0 / M_PI;
      pitch *= 180.0 / M_PI;

      // Smoothed only where it is slow
      double m = sqrt(yaw * yaw + pitch * pitch);
      double direct = (m - IOSTOUCH_GYRO_SMOOTH * 0.5) / (IOSTOUCH_GYRO_SMOOTH * 0.5);
      direct = direct < 0.0 ? 0.0 : (direct > 1.0 ? 1.0 : direct);
      _afGyroSmooth[_iGyroSmoothNext][0] = yaw * (1.0 - direct);
      _afGyroSmooth[_iGyroSmoothNext][1] = pitch * (1.0 - direct);
      _iGyroSmoothNext = (_iGyroSmoothNext + 1) % IOSTOUCH_GYRO_SMOOTH_N;
      double sumYaw = 0.0, sumPitch = 0.0;
      for (int i = 0; i < IOSTOUCH_GYRO_SMOOTH_N; i++) {
        sumYaw += _afGyroSmooth[i][0];
        sumPitch += _afGyroSmooth[i][1];
      }
      yaw = yaw * direct + sumYaw / IOSTOUCH_GYRO_SMOOTH_N;
      pitch = pitch * direct + sumPitch / IOSTOUCH_GYRO_SMOOTH_N;

      // The soft dead zone
      m = sqrt(yaw * yaw + pitch * pitch);
      if (m < IOSTOUCH_GYRO_SOFT) {
        yaw *= m / IOSTOUCH_GYRO_SOFT;
        pitch *= m / IOSTOUCH_GYRO_SOFT;
      }
      _fGyroQueueYaw += yaw * dt;
      _fGyroQueuePitch += pitch * dt;
    }
  }
  os_unfair_lock_unlock(&_gyroLock);
}

// A sample came back refused (the samples' queue): no tilt aiming from the
// next frame on
static void IOSTouch_GyroRefusedOnQueue(void)
{
  os_unfair_lock_lock(&_gyroLock);
  _bGyroRefusedOnQueue = 1;
  os_unfair_lock_unlock(&_gyroLock);
}

// Starts or stops the motion updates
static void IOSTouch_GyroRun(int bRun)
{
  bRun = bRun != 0;
  if (bRun == _bGyroRunning) return;
  _bGyroRunning = bRun;
  if (!bRun) {
    IOSTouch_GyroRunUpdates(0);
    return;
  }
  // From scratch: nothing from before it stopped, the smoothing empty
  os_unfair_lock_lock(&_gyroLock);
  _tGyroLastSample = 0.0;
  _fGyroQueueYaw = _fGyroQueuePitch = 0.0;
  memset(_afGyroSmooth, 0, sizeof(_afGyroSmooth));
  os_unfair_lock_unlock(&_gyroLock);
  IOSTouch_GyroRunUpdates(1);
}

// Whether either thumb is down on the game, for TOUCH: the left one on the
// move stick (pushed or resting), or a right one where it aims -- on the
// look area (resting or dragging), or on one of the buttons a drag on also
// looks (FIRE, the secondary button, CROUCH, USE, JUMP). So with the left
// thumb on the stick, the right one can hop from the look area onto FIRE
// (and is in the air for a moment) without the aiming stopping. Not ITEM,
// the top row, the tray, or a touch being ignored.
static int IOSTouch_GyroThumbDown(void)
{
  for (int i = 0; i < IOSTOUCH_MAX_TOUCHES; i++) {
    const IOSTouchSlot *s = &_aSlots[i];
    if (!s->touch) continue;
    if (s->role == ROLE_STICK || s->role == ROLE_LOOK
        || (s->role == ROLE_BUTTON && _aButtons[s->button].bLookWhileHeld)) return 1;
  }
  return 0;
}

// Once per frame, after the frame's touches came in (bShown: whether the
// overlay is up; bActive: whether the app is in front; side: which way round
// the screen is turned, +1 landscape left, -1 landscape right, 0 neither).
// The motion updates run only while the game is being played with the
// overlay up, the app in front, tilt aiming on and the screen turned either
// landscape way. What the phone turned since the last frame goes to the
// game, for the player's rotation (IOSTouch_TakeGyro) -- if it could aim
// both then and now, so in TOUCH lifting the last thumb freezes the view
// where it is (the frame it lifted in counts for nothing, as does the frame
// the first one lands in) and nothing springs back, and touching again
// carries on from there, from however the phone is held by then. Never
// while MENU's tray or the weapon wheel is open (the frame it closes in
// counts for nothing either, so nothing jumps), just after the screen turned round to the
// other landscape side, nor after a frame that took too long; and only
// while the game reads the touch controls, so nothing is left waiting for
// it across a pause.
static void IOSTouch_GyroFrame(int bShown, int bActive, int side, double now)
{
  if (side != 0 && _iGyroLastSide != 0 && side != _iGyroLastSide) _tGyroTurnedRound = now;
  if (side != 0) _iGyroLastSide = side;
  // (hidden for a game controller: only ALWAYS aims -- no thumbs are down)
  IOSTouch_GyroRun(bShown && (!_bPadHidden || _iGyroMode == IOSTOUCH_GYRO_ALWAYS) && _iMode == IOSTOUCH_GAMEPLAY && bActive && side != 0 && _iGyroMode != IOSTOUCH_GYRO_OFF
                   && IOSTouch_GyroAvailable());

  os_unfair_lock_lock(&_gyroLock);
  _iGyroSide = side;
  const double yaw = _fGyroQueueYaw, pitch = _fGyroQueuePitch;
  _fGyroQueueYaw = _fGyroQueuePitch = 0.0;
  _bGyroRefused |= _bGyroRefusedOnQueue; // (stops it next frame)
  os_unfair_lock_unlock(&_gyroLock);

  const int bOk = _bGyroRunning && (_iGyroMode == IOSTOUCH_GYRO_ALWAYS || IOSTouch_GyroThumbDown()) && !_bTrayOpen
                  && now - _tGyroTurnedRound >= IOSTOUCH_GYRO_TURN_HOLD && !IOSTouch_HoldsGame();
  const int bUse = bOk && _bGyroWasOk && now - _tGyroLastFrame <= IOSTOUCH_GYRO_MAX_FRAME;
  _bGyroWasOk = bOk;
  _tGyroLastFrame = now;
  if (!bUse) return;

  // Degrees, straight into the player's view angles (IOSGame.cpp): the
  // game's mouse settings never apply, so at 1.0x the view turns as far as
  // the phone
  const float k = _afGyroSens[_iGyroSens];
  os_unfair_lock_lock(&_lock);
  if (_bReading) {
    _fGyroYaw += (float)yaw * k;
    _fGyroPitch += (float)pitch * k;
  }
  os_unfair_lock_unlock(&_lock);
}

static void IOSTouch_ResetTouches(int bReading);

void IOSTouch_SetPadHidden(int bHidden)
{
  bHidden = bHidden != 0;
  if (bHidden == _bPadHidden) return;
  _bPadHidden = bHidden;
  if (bHidden) IOSTouch_ResetTouches(_iMode == IOSTOUCH_GAMEPLAY);
}

// Lets go of every touch and closes the tray and the weapon wheel (on every
// change of mode);
// bReading: whether the game gets input now
static void IOSTouch_ResetTouches(int bReading)
{
  IOSTouch_SetTrayOpen(0);
  memset(_aSlots, 0, sizeof(_aSlots));
  memset(_aButtonHeld, 0, sizeof(_aButtonHeld));
  _bStickActive = 0;
  _fStickX = _fStickY = 0.0f;
  _iRequests &= IOSTOUCH_REQ_CHEATON | IOSTOUCH_REQ_CHEATOFF | IOSTOUCH_REQ_NOCLIP | IOSTOUCH_REQ_FLY; // (the cheat's own still go)
  _fSaveRing = _fLoadRing = _fMenuRing = 0.0f;
  _tLastTick = 0.0;
  _bFpsBase = 0;
  _bGyroWasOk = 0; // the next frame's motion doesn't count
  // the weapon wheel closes, picking nothing (the game no longer held)
  _bWheelOpen = _bWheelTapMode = 0;
  _iWheelHot = -1;
  _ctWheelTicks = 0;
  _afWheelRing[0] = _afWheelRing[1] = 0.0f;
  _fCameraRing = _fCamSwitchRing = 0.0f;
  // and the cheat's holds end, and its list of levels closes (picking nothing)
  _fCheatRing = 0.0f;
  _afCheatActRing[0] = _afCheatActRing[1] = 0.0f;
  _bLevelListOpen = 0;
  _fLookRing = 0.0f;
  _fFpsRing = 0.0f;
  _fOpacityRing = 0.0f;
  IOSTouch_ResetShared(bReading);
}

// ---------------------------------------------------------------- the game's reads

// Called once per game tick. Held buttons report down for as long as they're
// held; a queued quick tap is reported down for IOSTOUCH_PULSE_READS ticks
// and then up for one, so the game sees each one as its own press. The
// weapon wheel's pick goes in the select field the same way, for
// IOSTOUCH_PULSE_READS ticks and then 0 for one (two picks in a row would
// otherwise run together: the game takes only the field's new bits); and
// never in a tick NEXT or PREV is read in, nor the tick after it (the game
// does the field first, then NEXT/PREV on top), whichever came first: a NEXT
// or PREV tap still waiting goes after a pick waiting or being read (it can
// only have come after the pick: opening the wheel drops the taps waiting),
// and a pick waits for a tap already being read and its gap.
void IOSTouch_ReadInput(IOSTouchInput *pInput)
{
  memset(pInput, 0, sizeof(*pInput));
  pInput->iSelectWeapon = -1;
  os_unfair_lock_lock(&_lock);
  if (_bReading) {
    pInput->fMoveX = _fMoveX;
    pInput->fMoveY = _fMoveY;
    const unsigned int ulWeaponKeys = IOSTOUCH_NEXTWEAPON | IOSTOUCH_PREVWEAPON;
    const int bPickBusy = _iPickPending || _iPickReads > 0 || _bPickGap; // (a NEXT/PREV tap waits)
    int bKeysBusy = 0;                                  // NEXT/PREV read now, or this is the tick after
    for (int i = 0; i < IOSTOUCH_NUMBUTTONS; i++) {
      const unsigned int ul = 1u << i;
      const int bHeld = (_ulHeld & ul) != 0;
      int bDown = bHeld;
      if (bHeld) _ulSeen |= ul;
      if ((ul & ulWeaponKeys) && (_aPulseReads[i] || _aPulseGap[i])) bKeysBusy = 1;
      if (_aPulseReads[i]) {
        if (--_aPulseReads[i] == 0) _aPulseGap[i] = 1;
        bDown = 1;
      }
      else if (_aPulseGap[i]) {
        _aPulseGap[i] = 0;
      }
      else if (_aPulseQueue[i] && !((ul & ulWeaponKeys) && bPickBusy)) {
        _aPulseQueue[i]--;
        _aPulseReads[i] = IOSTOUCH_PULSE_READS - 1;
        if (!_aPulseReads[i]) _aPulseGap[i] = 1;
        bDown = 1;
      }
      if ((ul & ulWeaponKeys) && (bDown || _aPulseReads[i] || _aPulseGap[i])) bKeysBusy = 1;
      if (bDown) pInput->ulButtons |= ul;
    }
    if (_iPickReads > 0) {
      if (--_iPickReads == 0) _bPickGap = 1;
      pInput->iSelectWeapon = _iPickNow - 1;
    }
    else if (_bPickGap) {
      _bPickGap = 0;
    }
    else if (_iPickPending && !bKeysBusy) {
      _iPickNow = _iPickPending;
      _iPickPending = 0;
      _iPickReads = IOSTOUCH_PULSE_READS - 1;
      if (!_iPickReads) _bPickGap = 1;
      pInput->iSelectWeapon = _iPickNow - 1;
    }
  }
  os_unfair_lock_unlock(&_lock);
}

void IOSTouch_ReadMove(float *pfMoveX, float *pfMoveY)
{
  os_unfair_lock_lock(&_lock);
  *pfMoveX = _bReading ? _fMoveX : 0.0f;
  *pfMoveY = _bReading ? _fMoveY : 0.0f;
  os_unfair_lock_unlock(&_lock);
}

void IOSTouch_TakeLook(float *pfDX, float *pfDY)
{
  os_unfair_lock_lock(&_lock);
  *pfDX = _bReading ? _fLookX : 0.0f;
  *pfDY = _bReading ? _fLookY : 0.0f;
  _fLookX = _fLookY = 0.0f;
  os_unfair_lock_unlock(&_lock);
}

void IOSTouch_TakeGyro(float *pfYaw, float *pfPitch)
{
  os_unfair_lock_lock(&_lock);
  *pfYaw = _bReading ? _fGyroYaw : 0.0f;
  *pfPitch = _bReading ? _fGyroPitch : 0.0f;
  _fGyroYaw = _fGyroPitch = 0.0f;
  os_unfair_lock_unlock(&_lock);
}

#ifndef IOSTOUCH_RIG
// ---------------------------------------------------------------- overlay view

// Kept in the app's settings: whether the FPS readout shows; tilt aiming's
// mode (0 OFF, 1 TOUCH, 2 ALWAYS; never set or not one of those: OFF) and
// sensitivity (the nearest of _afGyroSens; never set: 1.5x)
#define IOSTOUCH_FPS_DEFAULTS_KEY @"iosTouchShowFps"
#define IOSTOUCH_GYRO_DEFAULTS_KEY @"iosTouchGyroMode"
#define IOSTOUCH_GYRO_SENS_DEFAULTS_KEY @"iosTouchGyroSens"
// ...and whether CAMERA shows (never set: it does; the camera system keeps
// its own options). The same key as the Jedi Knight and Serious Sam ports'.
#define IOSTOUCH_CAMERA_DEFAULTS_KEY @"iosTouchShowCamera"
// ...and whether CHEAT shows (never set: it doesn't). The cheat itself is
// never kept: it is off each time the app opens. The Jedi Knight port's key.
#define IOSTOUCH_CHEAT_DEFAULTS_KEY @"iosTouchShowCheat"
// ...and the look speed (MENU's tray's LOOK; never set: 1x)
#define IOSTOUCH_LOOKSCALE_DEFAULTS_KEY @"iosTouchLookScale"
#define IOSTOUCH_MAXFPS_DEFAULTS_KEY @"iosTouchMaxFps"
#define IOSTOUCH_OPACITY_DEFAULTS_KEY @"iosTouchOpacity"
#define IOSTOUCH_OPACITY_W 260.0
#define IOSTOUCH_OPACITY_H 44.0

// The app's version as its Info.plist says (source/CMakeLists.txt sets
// both from RAZE_IOS_VERSION): "v0.1.57", with the build number after it,
// "v0.1.57 (57)", when that is there and says something else
static NSString *IOSTouch_VersionText(void)
{
  NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
  id ver = [info objectForKey:@"CFBundleShortVersionString"];
  id build = [info objectForKey:@"CFBundleVersion"];
  if (![ver isKindOfClass:[NSString class]] || [ver length] == 0) ver = @"?";
  // (a version that already ends in the build number, 0.1.<run>, doesn't
  // get it again in brackets)
  if ([build isKindOfClass:[NSString class]] && [build length] > 0 && ![build isEqualToString:ver] &&
      ![ver hasSuffix:[@"." stringByAppendingString:build]]) {
    return [NSString stringWithFormat:@"v%@ (%@)", ver, build];
  }
  return [NSString stringWithFormat:@"v%@", ver];
}

// Tilt aiming's motion manager (one for the app, as Apple asks) and the
// queue its samples are handled on
static CMMotionManager *_pMotion = nil;
static NSOperationQueue *_pMotionQueue = nil;

// Whether an error the motion updates hand back is iOS refusing the motion
// data (no permission: none is asked for today, but iOS could start to)
static int IOSTouch_GyroIsRefusal(NSError *err)
{
  if (![err.domain isEqualToString:CMErrorDomain]) return 0;
  return err.code == CMErrorNotAuthorized || err.code == CMErrorNotEntitled
         || err.code == CMErrorMotionActivityNotAuthorized || err.code == CMErrorMotionActivityNotEntitled;
}

// Starts or stops CoreMotion's updates (IOSTouch_GyroRun decides when)
static void IOSTouch_GyroRunUpdates(int bRun)
{
  if (!bRun) {
    [_pMotion stopDeviceMotionUpdates];
    return;
  }
  _pMotion.deviceMotionUpdateInterval = 1.0 / IOSTOUCH_GYRO_HZ;
  // (the reference frame that needs no compass: the attitude isn't used)
  [_pMotion startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXArbitraryZVertical
                                                toQueue:_pMotionQueue
                                            withHandler:^(CMDeviceMotion *dm, NSError *err) {
    if (err && IOSTouch_GyroIsRefusal(err)) IOSTouch_GyroRefusedOnQueue();
    if (!dm || err) return;
    const CMRotationRate w = dm.rotationRate;
    const CMAcceleration g = dm.gravity;
    IOSTouch_GyroSample(w.x, w.y, w.z, g.x, g.y, g.z, dm.timestamp);
  }];
}

// Once, as the overlay is made: the motion manager and the queue for its
// samples (nothing runs yet), and the settings -- OFF and 1.5x unless set
static void IOSTouch_GyroSetup(void)
{
  if (_pMotion) return;
  _pMotion = [[CMMotionManager alloc] init];
  _pMotionQueue = [[NSOperationQueue alloc] init];
  _pMotionQueue.maxConcurrentOperationCount = 1; // in order, one at a time
  _pMotionQueue.qualityOfService = NSQualityOfServiceUserInteractive;
  _bGyroAvailable = _pMotion.deviceMotionAvailable ? 1 : 0;

  NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
  if ([d objectForKey:IOSTOUCH_GYRO_DEFAULTS_KEY]) {
    const NSInteger m = [d integerForKey:IOSTOUCH_GYRO_DEFAULTS_KEY];
    _iGyroMode = (m >= 0 && m < IOSTOUCH_GYRO_NUM_MODES) ? (int)m : IOSTOUCH_GYRO_OFF;
  }
  if ([d objectForKey:IOSTOUCH_GYRO_SENS_DEFAULTS_KEY]) {
    const float k = [d floatForKey:IOSTOUCH_GYRO_SENS_DEFAULTS_KEY];
    for (int i = 0; i < IOSTOUCH_GYRO_NUM_SENS; i++) {
      if (fabsf(_afGyroSens[i] - k) < fabsf(_afGyroSens[_iGyroSens] - k)) _iGyroSens = i;
    }
  }
}

static IOSTouchRect _rScoreFrac, _rHiScoreFrac, _rMessagesFrac; // the last boxes the HUD showed (fractions)
// What the current layout was made for
static IOSTouchRect _rLayoutScore, _rLayoutHiScore, _rLayoutMessages; // in points
static int _iLayoutCutoutRight = -1;
static unsigned int _ulFramesDrawn = 0; // the game's frame count at the last IOSTouch_Update

// Which way round the screen is turned: +1 landscape left (the top of the
// phone on the right), -1 landscape right (the top on the left), 0 neither
// or not known yet. SDL2 makes its window without a scene, so ask SDL (which
// follows the status bar) if there is none: its LANDSCAPE is landscape
// right, LANDSCAPE_FLIPPED landscape left.
static int IOSTouch_ScreenSide(UIView *v)
{
  UIWindowScene *scene = v.window.windowScene;
  if (scene) {
    const UIInterfaceOrientation o = scene.interfaceOrientation;
    return (o == UIInterfaceOrientationLandscapeLeft) ? 1 : ((o == UIInterfaceOrientationLandscapeRight) ? -1 : 0);
  }
  const SDL_DisplayOrientation o = SDL_GetDisplayOrientation(0);
  return (o == SDL_ORIENTATION_LANDSCAPE_FLIPPED) ? 1 : ((o == SDL_ORIENTATION_LANDSCAPE) ? -1 : 0);
}

// Whether the camera cutout may be on the right of the screen. Landscape right
// has the bottom of the phone on the right, so the cutout (at the top) is on
// the left; landscape left puts it on the right. Not known yet: assume it can
// be.
static int IOSTouch_CutoutMayBeRight(UIView *v)
{
  return IOSTouch_ScreenSide(v) != -1;
}

// What the open weapon wheel was last drawn for
typedef struct {
  int iMap;
  double cx, cy, R1;
  int iHot, bCancel, bTapMode, iWanted;
  unsigned int ulOwned, ulReady;
  int bInfinite;
  int aiAmmo[IOSTOUCH_WPN_MAX], aiMax[IOSTOUCH_WPN_MAX];
} IOSTouchWheelKey;

// The cheat's list of levels sits on this, which keeps the touches on it
// (UIKit would hand those the list doesn't take on up to the overlay, which
// would take them for touches outside it)
@interface IOSTouchLevelPanel : UIView
@end

@implementation IOSTouchLevelPanel
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}
@end

@interface IOSTouchOverlay : UIView <UITableViewDataSource, UITableViewDelegate> {
  UIView *stickBase;
  UIView *stickKnob;
  UILabel *aButtonViews[IOSTOUCH_NUM_BUTTONS];
  CAShapeLayer *saveRing; // QUICK SAVE's hold progress
  CAShapeLayer *loadRing; // QUICK LOAD's
  CAShapeLayer *menuRing; // MENU's
  UIView *trayBack;       // behind MENU's tray
  UILabel *versionLabel;  // the app's version, under the open tray
  UILabel *fpsLabel;      // the FPS readout...
  int iFpsLabel;          // ...the number it says (-1: none yet)
  int bFpsSaved;          // whether the app's settings say it shows
  int iSecondaryShown;    // what the secondary button says (IOSTOUCH_SEC_*, -1: not yet set)
  int iGyroModeSaved;     // tilt aiming's mode and sensitivity as the app's settings have them
  int iGyroSensSaved;
  int iGyroLabels;        // what GYRO's and SENS's labels say (-1: not yet set)
  CAShapeLayer *aWheelRings[2]; // NEXT WPN's and PREV WPN's holds (they open the weapon wheel)
  // The weapon wheel (makeWheel): the dim and its disc, each slice, its icon
  // (the second layer unused here), count and name, the needle, the middle's
  // lines, "cancel"; the haptic tick; the icons as images (each weapon's,
  // for each tint), whether it shows, what it was drawn for
  UIView *wheelView;
  CAShapeLayer *wheelDisc;
  // the game's look (IOSTouchWheelTheme): the rim, its marks, the middle's
  // motif in two colours; the map it was drawn for (-1: none yet)
  CAShapeLayer *wheelRim;
  CAShapeLayer *wheelRimMarks;
  CAShapeLayer *wheelMotif2;
  CAShapeLayer *wheelMotif;
  CAShapeLayer *aSliceLayers[IOSTOUCH_WHEEL_MAX];
  CALayer *aIconLayers[IOSTOUCH_WHEEL_MAX][2];
  UILabel *aCountLabels[IOSTOUCH_WHEEL_MAX];
  UILabel *aNameLabels[IOSTOUCH_WHEEL_MAX];
  CAShapeLayer *wheelNeedle;
  UILabel *aMiddleLabels[IOSTOUCH_MIDDLE_LINES];
  UILabel *wheelCancelLabel;
  UISelectionFeedbackGenerator *wheelTick;
  id aIconImages[IOSTOUCH_WPN_MAX][WICON_NUM];
  int bWheelShown;
  int bWheelRebuild;
  int iWheelLifted; // the button lifted above the dim, + 1 (0: none)
  IOSTouchWheelKey wheelKey;
  // CAMERA: its selfie hold's ring and the tray CAMERA's (held for the
  // options); the message line (and when what it says came); whether CAMERA
  // shows as the app's settings have it, and whether it looked busy
  CAShapeLayer *cameraRing;
  CAShapeLayer *camSwitchRing;
  UILabel *camMessageLabel;
  // Hidden for a game controller: a mask over the whole overlay that lets
  // only the message line through (a mask doesn't change where touches go,
  // so a touch anywhere still reaches the overlay and brings it back)
  CALayer *padMask;
  CALayer *padMaskHole;
  double tCamMessageShown;
  int bShowCameraSaved;
  int bCameraBusyShown;
  // The cheat: CHEAT's emblem (a bomb: its body and cap, its fuse and spark)
  // and ring; JUMP's and USE's rings and small red labels (FLY, NOCLIP);
  // whether the tray's buttons were moved for LEVEL; whether CHEAT looks on;
  // the haptic ticks already felt; whether CHEAT showing is in the app's
  // settings
  CAShapeLayer *cheatBody;
  CAShapeLayer *cheatFuse;
  CALayer *cheatPicture;  // the game's picture for it, when there is one (the emblem hides)
  id cheatImages[2];      // ...on and off
  int iCheatEmblem;       // which drawn emblem shows: 0 the bomb, 1 Exhumed's ankh
  CAShapeLayer *cheatRing;
  CAShapeLayer *aCheatActRings[2];
  UILabel *aCheatActLabels[2];
  // The cheat's list of levels (the tray's LEVEL): its panel, title and
  // list; the levels' names and files as the game gives them, and the one
  // being played (1.., 0: none of them)
  IOSTouchLevelPanel *levelPanel;
  UILabel *levelTitle;
  UIButton *levelClose;
  UITableView *levelTable;
  NSArray<NSString *> *aLevelNames;
  NSArray<NSString *> *aLevelFiles;
  int iLevelNow;
  // The tray's LOOK: its hold's ring, the speed its label says and the app's
  // settings have, the times it went back to 1x already felt (a thump each)
  CAShapeLayer *lookRing;
  // The tray's FPS: its hold's ring, the frame rate its label says, the
  // app's settings have and the screen was asked for (a display link)
  CAShapeLayer *fpsRing;
  CAShapeLayer *opacityRing; // the tray's OPACITY: held back to 100%...
  UIView *opacityBack;       // ...its slider's backing, a row under the tray...
  UISlider *opacitySlider;   // ...and the slider
  float fOpacityLabel;
  int ctOpacityResetsFelt;
  int iMaxFpsLabel;
  int iMaxFpsSaved;
  int ctMaxFpsFelt;
  CADisplayLink *frameRateLink;
  int ctRefreshTicks;
  double tRefreshStart;
  float fLookLabel;
  float fLookSaved;
  int ctLookResetsFelt;
  UIImpactFeedbackGenerator *lookThump;
  int bTrayLevelViews;
  int bCheatLookOn;
  int ctCheatTicksFelt;
  int bShowCheatSaved;
  UISelectionFeedbackGenerator *cheatTick;
  double tLastTick;
}
- (void)resetAll;
- (void)tick;
- (void)refreshPadMask;
- (void)syncLevels;
- (void)refreshButtonLooks;
- (void)refreshStick;
- (void)syncWheel;
@end

@implementation IOSTouchOverlay

static UIView *IOSTouch_MakeCircle(CGFloat radius, CGFloat alpha)
{
  UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, radius * 2, radius * 2)];
  v.backgroundColor = [UIColor colorWithWhite:1.0 alpha:alpha];
  v.layer.cornerRadius = radius;
  v.layer.borderWidth = 1.5;
  v.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.45].CGColor;
  v.userInteractionEnabled = NO;
  return v;
}

static CGFloat IOSTouch_FontSize(const char *label, CGFloat radius)
{
  if (strchr(label, '\n')) return radius >= 28 ? 10 : 9; // two-line labels
  if (radius < 40 && strlen(label) > 5) return 12;      // CROUCH: stays on one line
  return radius >= 40 ? 16 : (radius >= 25 ? 13 : 10);
}

// SENS's and GYRO's font: condensed (as in the Jedi Knight port) so "ALWAYS"
// fits a circle this small. Before iOS 16 the system font has no condensed
// width, so it is a point smaller instead.
static UIFont *IOSTouch_TrayFont(CGFloat size)
{
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 160000
  if (@available(iOS 16.0, *)) return [UIFont systemFontOfSize:size weight:UIFontWeightBold width:UIFontWidthCondensed];
#endif
  return [UIFont boldSystemFontOfSize:size - 1];
}

// A ring round a button of radius r that fills (strokeEnd) while it is held
static CAShapeLayer *IOSTouch_MakeHoldRing(CGFloat r)
{
  CAShapeLayer *ring = [CAShapeLayer layer];
  ring.frame = CGRectMake(0, 0, r * 2, r * 2);
  ring.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(r, r) radius:r - 2.5
                                         startAngle:-M_PI_2 endAngle:3 * M_PI_2 clockwise:YES].CGPath;
  ring.fillColor = [UIColor clearColor].CGColor;
  ring.strokeColor = [UIColor colorWithRed:0.47 green:0.78 blue:1.0 alpha:0.95].CGColor;
  ring.lineWidth = 3.0;
  ring.strokeEnd = 0.0;
  return ring;
}

- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.multipleTouchEnabled = YES;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    for (int i = 0; i < IOSTOUCH_NUM_BUTTONS; i++) {
      const IOSTouchButton *b = &_aButtons[i];
      UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, b->radius * 2, b->radius * 2)];
      l.text = [NSString stringWithUTF8String:b->label];
      l.textAlignment = NSTextAlignmentCenter;
      l.textColor = [UIColor colorWithWhite:1.0 alpha:0.85];
      l.font = [UIFont boldSystemFontOfSize:IOSTouch_FontSize(b->label, b->radius)];
      l.numberOfLines = 2;
      l.adjustsFontSizeToFitWidth = YES;
      l.minimumScaleFactor = 0.6;
      l.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.22];
      l.layer.cornerRadius = b->radius;
      l.layer.borderWidth = 1.5;
      l.layer.borderColor = (i == BTN_FIRE) ? [UIColor colorWithRed:1.0 green:0.55 blue:0.45 alpha:0.6].CGColor
                                            : [UIColor colorWithWhite:1.0 alpha:0.4].CGColor;
      l.clipsToBounds = YES;
      l.userInteractionEnabled = NO;
      aButtonViews[i] = l;
      [self addSubview:l];
    }

    // Rings that fill while QUICK SAVE, QUICK LOAD and MENU are held. QUICK
    // SAVE's and QUICK LOAD's look the same, and fill as quickly.
    saveRing = IOSTouch_MakeHoldRing(_aButtons[BTN_QUICKSAVE].radius);
    [aButtonViews[BTN_QUICKSAVE].layer addSublayer:saveRing];
    loadRing = IOSTouch_MakeHoldRing(_aButtons[BTN_QUICKLOAD].radius);
    [aButtonViews[BTN_QUICKLOAD].layer addSublayer:loadRing];
    menuRing = IOSTouch_MakeHoldRing(_aButtons[BTN_MENU].radius);
    [aButtonViews[BTN_MENU].layer addSublayer:menuRing];
    // ...and NEXT WPN's and PREV WPN's, held still to open the weapon wheel to tap
    for (int k = 0; k < 2; k++) {
      aWheelRings[k] = IOSTouch_MakeHoldRing(_aButtons[k ? BTN_PREVWPN : BTN_NEXTWPN].radius);
      [aButtonViews[k ? BTN_PREVWPN : BTN_NEXTWPN].layer addSublayer:aWheelRings[k]];
    }

    // MENU's tray: its buttons on a dark backing, hidden until a hold on
    // MENU opens it. The keyboard button shows the keyboard symbol.
    trayBack = [[UIView alloc] initWithFrame:CGRectZero];
    trayBack.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    trayBack.layer.cornerRadius = 26.0;
    trayBack.layer.borderWidth = 1.5;
    trayBack.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.4].CGColor;
    trayBack.userInteractionEnabled = NO;
    trayBack.hidden = YES;
    [self insertSubview:trayBack belowSubview:aButtonViews[BTN_TRAYLOOK]];
    // ...and the app's version, small and dim under it while it is open
    // (placed in refreshButtonLooks; touches go through it)
    versionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    versionLabel.textAlignment = NSTextAlignmentCenter;
    versionLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.55];
    versionLabel.font = [UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightMedium];
    versionLabel.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.6];
    versionLabel.shadowOffset = CGSizeMake(0, 1);
    versionLabel.text = IOSTouch_VersionText();
    [versionLabel sizeToFit];
    versionLabel.bounds = CGRectMake(0, 0, versionLabel.bounds.size.width + 8, IOSTOUCH_VERSION_H);
    versionLabel.userInteractionEnabled = NO;
    versionLabel.hidden = YES;
    [self insertSubview:versionLabel aboveSubview:trayBack];
    // GYRO and SENS say what they are set to on a second line (labels set
    // in refreshButtonLooks), sized for the longest
    IOSTouch_GyroSetup();
    iGyroModeSaved = _iGyroMode;
    iGyroSensSaved = _iGyroSens;
    iGyroLabels = -1;
    for (int i = BTN_TRAYLOOK; i <= BTN_TRAYOPACITY; i++) { // (FPS and OPACITY too: "FPS\n120")
      aButtonViews[i].font = IOSTouch_TrayFont(IOSTouch_FontSize("GYRO\nALWAYS", _aButtons[i].radius));
    }
    // LOOK says the look speed on its second line too (set in
    // refreshLookLabel), and goes back to 1x held (its ring)
    NSUserDefaults *dLook = [NSUserDefaults standardUserDefaults];
    if ([dLook objectForKey:IOSTOUCH_LOOKSCALE_DEFAULTS_KEY]) {
      _fLookScale = fminf(fmaxf([dLook floatForKey:IOSTOUCH_LOOKSCALE_DEFAULTS_KEY], IOSTOUCH_LOOKSCALE_MIN), IOSTOUCH_LOOKSCALE_MAX);
    }
    fLookSaved = _fLookScale;
    fLookLabel = -1.0f;
    lookRing = IOSTouch_MakeHoldRing(_aButtons[BTN_TRAYLOOK].radius);
    [aButtonViews[BTN_TRAYLOOK].layer addSublayer:lookRing];
    lookThump = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    ctLookResetsFelt = _ctLookResets;
    // The tray's FPS says the frame rate asked for ("FPS\n60"), switched held
    const NSInteger iMaxFps = [dLook integerForKey:IOSTOUCH_MAXFPS_DEFAULTS_KEY];
    _iMaxFps = (iMaxFps == 120) ? 120 : 60;
    iMaxFpsSaved = _iMaxFps;
    iMaxFpsLabel = -1;
    ctMaxFpsFelt = _ctMaxFpsChanges;
    fpsRing = IOSTouch_MakeHoldRing(_aButtons[BTN_TRAYFPS].radius);
    [aButtonViews[BTN_TRAYFPS].layer addSublayer:fpsRing];
    // The tray's OPACITY: the strength kept (100% unless changed), its ring,
    // and its slider under the tray (hidden until a tap on OPACITY)
    if ([dLook objectForKey:IOSTOUCH_OPACITY_DEFAULTS_KEY]) _fOpacity = IOSTouch_OpacityStep([dLook floatForKey:IOSTOUCH_OPACITY_DEFAULTS_KEY]);
    fOpacityLabel = -1.0f;
    ctOpacityResetsFelt = _ctOpacityResets;
    opacityRing = IOSTouch_MakeHoldRing(_aButtons[BTN_TRAYOPACITY].radius);
    [aButtonViews[BTN_TRAYOPACITY].layer addSublayer:opacityRing];
    opacityBack = [[UIView alloc] initWithFrame:CGRectMake(0, 0, IOSTOUCH_OPACITY_W, IOSTOUCH_OPACITY_H)];
    opacityBack.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    opacityBack.layer.cornerRadius = IOSTOUCH_OPACITY_H * 0.5;
    opacityBack.layer.borderWidth = 1.5;
    opacityBack.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.4].CGColor;
    opacityBack.hidden = YES;
    opacitySlider = [[UISlider alloc] initWithFrame:CGRectMake(16, 7, IOSTOUCH_OPACITY_W - 32, 30)];
    opacitySlider.minimumValue = IOSTOUCH_OPACITY_MIN;
    opacitySlider.maximumValue = 1.0;
    opacitySlider.value = _fOpacity;
    opacitySlider.minimumTrackTintColor = [UIColor colorWithRed:1.0 green:0.75 blue:0.3 alpha:0.95];
    [opacitySlider addTarget:self action:@selector(opacitySlid:) forControlEvents:UIControlEventValueChanged];
    [opacitySlider addTarget:self action:@selector(opacityLifted:)
            forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [opacityBack addSubview:opacitySlider];
    [self addSubview:opacityBack];
    [self applyMaxFps];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
    UIImage *kb = [UIImage systemImageNamed:@"keyboard" withConfiguration:cfg];
    if (kb) {
      NSTextAttachment *att = [[NSTextAttachment alloc] init];
      att.image = [kb imageWithTintColor:[UIColor colorWithWhite:1.0 alpha:0.85] renderingMode:UIImageRenderingModeAlwaysOriginal];
      aButtonViews[BTN_TRAYKEYS].attributedText = [NSAttributedString attributedStringWithAttachment:att];
    }
    else {
      aButtonViews[BTN_TRAYKEYS].text = @"TYPE";
    }

    // The FPS readout, shown if it was left on
    fpsLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, IOSTOUCH_FPS_W, IOSTOUCH_FPS_H)];
    fpsLabel.textAlignment = NSTextAlignmentCenter;
    fpsLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.85];
    fpsLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightSemibold];
    fpsLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];
    fpsLabel.layer.cornerRadius = 9.0;
    fpsLabel.clipsToBounds = YES;
    fpsLabel.userInteractionEnabled = NO;
    fpsLabel.text = @"-- FPS";
    iFpsLabel = -1;
    bFpsSaved = [[NSUserDefaults standardUserDefaults] boolForKey:IOSTOUCH_FPS_DEFAULTS_KEY] ? 1 : 0;
    IOSTouch_SetShowFps(bFpsSaved);
    fpsLabel.hidden = !_bShowFps;
    [self addSubview:fpsLabel];
    iSecondaryShown = -1;

    stickBase = IOSTouch_MakeCircle(IOSTOUCH_STICK_RADIUS, 0.08);
    stickKnob = IOSTouch_MakeCircle(24, 0.30);
    stickBase.hidden = YES;
    stickKnob.hidden = YES;
    [self addSubview:stickBase];
    [self addSubview:stickKnob];

    [self makeWheel];
    [self makeCamera];
    [self makeCheat];
    [self makeLevelPanel];
    [self refreshButtonLooks];
  }
  return self;
}

// A label showing an SF Symbol (white, as the labels' text), or its text
// where there is no such symbol
static void IOSTouch_SetSymbol(UILabel *l, NSString *name, CGFloat size, NSString *fallback)
{
  UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightSemibold];
  UIImage *img = [UIImage systemImageNamed:name withConfiguration:cfg];
  if (!img) {
    l.text = fallback;
    return;
  }
  NSTextAttachment *att = [[NSTextAttachment alloc] init];
  att.image = [img imageWithTintColor:[UIColor colorWithWhite:1.0 alpha:0.85] renderingMode:UIImageRenderingModeAlwaysOriginal];
  l.attributedText = [NSAttributedString attributedStringWithAttachment:att];
}

// CAMERA and what goes with it (see the ivars), and whether it shows
- (void)makeCamera
{
  IOSTouch_SetSymbol(aButtonViews[BTN_CAMERA], @"camera.fill", 15, @"PHOTO");
  IOSTouch_SetSymbol(aButtonViews[BTN_TRAYCAM], @"camera", 14, @"CAM");
  cameraRing = IOSTouch_MakeHoldRing(_aButtons[BTN_CAMERA].radius);
  [aButtonViews[BTN_CAMERA].layer addSublayer:cameraRing];
  camSwitchRing = IOSTouch_MakeHoldRing(_aButtons[BTN_TRAYCAM].radius);
  [aButtonViews[BTN_TRAYCAM].layer addSublayer:camSwitchRing];

  camMessageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
  camMessageLabel.textAlignment = NSTextAlignmentCenter;
  camMessageLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.95];
  camMessageLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
  camMessageLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.5];
  camMessageLabel.layer.cornerRadius = 11.0;
  camMessageLabel.clipsToBounds = YES;
  camMessageLabel.userInteractionEnabled = NO;
  camMessageLabel.hidden = YES;
  tCamMessageShown = -1.0;
  [self addSubview:camMessageLabel];

  NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
  if ([d objectForKey:IOSTOUCH_CAMERA_DEFAULTS_KEY]) _bShowCamera = [d boolForKey:IOSTOUCH_CAMERA_DEFAULTS_KEY] ? 1 : 0;
  bShowCameraSaved = _bShowCamera;
  bCameraBusyShown = -1;
}

// ---- the cheat's parts

// CHEAT's emblem: a round bomb with its cap at the top right, the fuse
// curling up out of it and a spark at its end, in a box r across centred on
// (cx, cy). Our own drawing.
static void IOSTouch_CheatEmblemPaths(CGFloat cx, CGFloat cy, CGFloat r, UIBezierPath **ppBody, UIBezierPath **ppFuse)
{
  const CGFloat k = r * 0.5;
  UIBezierPath *body = [UIBezierPath bezierPathWithArcCenter:CGPointMake(cx - 0.12 * k, cy + 0.16 * k) radius:0.62 * k
                                                  startAngle:0 endAngle:2 * M_PI clockwise:YES];
  // the cap: a little block tilted towards the top right
  UIBezierPath *cap = [UIBezierPath bezierPathWithRect:CGRectMake(-0.17 * k, -0.11 * k, 0.34 * k, 0.22 * k)];
  CGAffineTransform t = CGAffineTransformMakeTranslation(cx + 0.30 * k, cy - 0.30 * k);
  t = CGAffineTransformRotate(t, -M_PI_4);
  [cap applyTransform:t];
  [body appendPath:cap];
  *ppBody = body;
  UIBezierPath *fuse = [UIBezierPath bezierPath];
  [fuse moveToPoint:CGPointMake(cx + 0.40 * k, cy - 0.40 * k)];
  [fuse addQuadCurveToPoint:CGPointMake(cx + 0.72 * k, cy - 0.78 * k) controlPoint:CGPointMake(cx + 0.72 * k, cy - 0.45 * k)];
  // the spark: four short rays round the fuse's end
  const CGPoint sp = CGPointMake(cx + 0.78 * k, cy - 0.86 * k);
  for (int i = 0; i < 4; i++) {
    const CGFloat a = M_PI_4 + i * M_PI_2;
    [fuse moveToPoint:CGPointMake(sp.x + cos(a) * 0.10 * k, sp.y + sin(a) * 0.10 * k)];
    [fuse addLineToPoint:CGPointMake(sp.x + cos(a) * 0.28 * k, sp.y + sin(a) * 0.28 * k)];
  }
  *ppFuse = fuse;
}

// Exhumed's CHEAT (the game has no picture for it): an ankh, in lines
static UIBezierPath *IOSTouch_AnkhPath(CGFloat cx, CGFloat cy, CGFloat r)
{
  const CGFloat k = r * 0.5;
  UIBezierPath *p = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx - 0.30 * k, cy - 0.95 * k, 0.60 * k, 0.72 * k)];
  [p moveToPoint:CGPointMake(cx, cy - 0.23 * k)];
  [p addLineToPoint:CGPointMake(cx, cy + 0.95 * k)];
  [p moveToPoint:CGPointMake(cx - 0.62 * k, cy - 0.05 * k)];
  [p addLineToPoint:CGPointMake(cx + 0.62 * k, cy - 0.05 * k)];
  return p;
}

- (void)makeCheat
{
  const CGFloat r = _aButtons[BTN_CHEAT].radius;
  UIBezierPath *body = nil, *fuse = nil;
  IOSTouch_CheatEmblemPaths(r, r, r * 1.25, &body, &fuse);
  cheatBody = [CAShapeLayer layer];
  cheatBody.frame = CGRectMake(0, 0, r * 2, r * 2);
  cheatBody.path = body.CGPath;
  cheatFuse = [CAShapeLayer layer];
  cheatFuse.frame = cheatBody.frame;
  cheatFuse.path = fuse.CGPath;
  cheatFuse.fillColor = [UIColor clearColor].CGColor;
  cheatFuse.lineWidth = 1.6;
  cheatFuse.lineCap = kCALineCapRound;
  [aButtonViews[BTN_CHEAT].layer addSublayer:cheatBody];
  [aButtonViews[BTN_CHEAT].layer addSublayer:cheatFuse];
  // the game's picture (IOSTouch_SetCheatIcon), fitted inside the circle
  cheatPicture = [CALayer layer];
  cheatPicture.frame = CGRectInset(CGRectMake(0, 0, r * 2, r * 2), r * 0.30, r * 0.30);
  cheatPicture.contentsGravity = kCAGravityResizeAspect;
  cheatPicture.magnificationFilter = kCAFilterLinear;
  cheatPicture.hidden = YES;
  [aButtonViews[BTN_CHEAT].layer addSublayer:cheatPicture];
  iCheatEmblem = 0;
  cheatRing = IOSTouch_MakeHoldRing(r);
  [aButtonViews[BTN_CHEAT].layer addSublayer:cheatRing];
  static const char *const astrAct[2] = { "FLY", "NOCLIP" };
  static const int aiAct[2] = { BTN_JUMP, BTN_USE };
  for (int k = 0; k < 2; k++) {
    const CGFloat ra = _aButtons[aiAct[k]].radius;
    aCheatActRings[k] = IOSTouch_MakeHoldRing(ra);
    [aButtonViews[aiAct[k]].layer addSublayer:aCheatActRings[k]];
    // small red letters half a radius under the button's middle
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, ra * 2, 10)];
    l.center = CGPointMake(ra, ra * 1.5);
    l.text = [NSString stringWithUTF8String:astrAct[k]];
    l.textAlignment = NSTextAlignmentCenter;
    l.font = [UIFont boldSystemFontOfSize:7.5];
    l.textColor = [UIColor colorWithRed:1.0 green:0.58 blue:0.52 alpha:0.95];
    l.userInteractionEnabled = NO;
    l.hidden = YES;
    [aButtonViews[aiAct[k]] addSubview:l];
    aCheatActLabels[k] = l;
  }
  cheatTick = [[UISelectionFeedbackGenerator alloc] init];
  bTrayLevelViews = _bTrayLevelPlaced;
  bCheatLookOn = -1;
  ctCheatTicksFelt = _ctCheatTicks;
  NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
  _bShowCheat = [d boolForKey:IOSTOUCH_CHEAT_DEFAULTS_KEY] ? 1 : 0;
  bShowCheatSaved = _bShowCheat;
}

// The cheat's parts as the state says, once a frame
- (void)refreshCheat
{
  [self setRing:cheatRing progress:_fCheatRing];
  for (int k = 0; k < 2; k++) [self setRing:aCheatActRings[k] progress:_afCheatActRing[k]];
  // the red labels while the holds do the cheat's things
  const int bActs = _bCheatOn && _hud.bCheatAllowed && _iMode == IOSTOUCH_GAMEPLAY;
  for (int k = 0; k < 2; k++) {
    const int bShow = bActs && (k == 1 || _hud.bCanFly); // (FLY only in the game that flies)
    if (aCheatActLabels[k].hidden == bShow) aCheatActLabels[k].hidden = !bShow;
  }
  // the tray's buttons where they now are, with LEVEL in the row or not
  // (IOSTouch_PlaceTray: CAMERA's options under the tray's CAMERA move too)
  if (bTrayLevelViews != _bTrayLevelPlaced) {
    bTrayLevelViews = _bTrayLevelPlaced;
    for (int i = BTN_TRAYLOOK; i <= BTN_TRAYKEYS; i++) {
      aButtonViews[i].center = CGPointMake(_aButtons[i].x, _aButtons[i].y);
    }
    trayBack.frame = CGRectMake(_rTrayBack.x0, _rTrayBack.y0, _rTrayBack.x1 - _rTrayBack.x0, _rTrayBack.y1 - _rTrayBack.y0);
  }
  // CHEAT: the game's picture once it has come (as it is while on, grey
  // while off); without one, the drawn emblem (Exhumed's an ankh)
  int bPictureNew = 0;
  if (_bCheatIconNew) {
    _bCheatIconNew = 0;
    cheatImages[0] = CFBridgingRelease(IOSTouch_MakeIconImage(_cheatIcon.aub[WICON_READY], _cheatIcon.w, _cheatIcon.h));
    cheatImages[1] = CFBridgingRelease(IOSTouch_MakeIconImage(_cheatIcon.aub[WICON_NOTFOUND], _cheatIcon.w, _cheatIcon.h));
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    cheatPicture.hidden = NO;
    cheatBody.hidden = cheatFuse.hidden = YES;
    [CATransaction commit];
    bPictureNew = 1;
  }
  // Exhumed's drawn ankh: latched once the weapon data says Exhumed (one game
  // per run; between valid frames _wpn is empty and would flip it back)
  static int bExhumed = 0;
  if (_wpn.bValid && _wpn.iMap == IOSTOUCH_WHEEL_EXHUMED) bExhumed = 1;
  const int iEmblem = (bExhumed && !_cheatIcon.bHave) ? 1 : 0;
  if (iEmblem != iCheatEmblem) {
    iCheatEmblem = iEmblem;
    const CGFloat r = _aButtons[BTN_CHEAT].radius;
    UIBezierPath *body = nil, *fuse = nil;
    IOSTouch_CheatEmblemPaths(r, r, r * 1.25, &body, &fuse);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    cheatBody.path = iEmblem ? NULL : body.CGPath;
    cheatFuse.path = iEmblem ? IOSTouch_AnkhPath(r, r, r * 1.25).CGPath : fuse.CGPath;
    cheatFuse.lineWidth = iEmblem ? 2.6 : 1.6;
    [CATransaction commit];
  }
  const int bLookOn = _bCheatOn && _hud.bCheatAllowed;
  if (bLookOn != bCheatLookOn || bPictureNew) {
    bCheatLookOn = bLookOn;
    // (the fuse and spark brighter than the bomb, as if lit)
    UIColor *c = bLookOn ? [UIColor colorWithRed:1.0 green:0.68 blue:0.18 alpha:0.95] : [UIColor colorWithWhite:0.55 alpha:0.85];
    UIColor *cFuse = bLookOn ? [UIColor colorWithRed:1.0 green:0.92 blue:0.55 alpha:1.0] : c;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (_cheatIcon.bHave) cheatPicture.contents = cheatImages[bLookOn ? 0 : 1];
    cheatPicture.opacity = bLookOn ? 1.0f : 0.45f; // (off: grey and faded)
    cheatBody.fillColor = c.CGColor;
    cheatFuse.strokeColor = cFuse.CGColor;
    [CATransaction commit];
    [self refreshButtonLooks]; // (the gold fill, border and glow: there)
  }
  // a tick felt for each flight or noclip started or ended
  if (ctCheatTicksFelt != _ctCheatTicks) {
    ctCheatTicksFelt = _ctCheatTicks;
    [cheatTick selectionChanged];
  }
  if (bShowCheatSaved != _bShowCheat) {
    bShowCheatSaved = _bShowCheat;
    [[NSUserDefaults standardUserDefaults] setBool:(_bShowCheat ? YES : NO) forKey:IOSTOUCH_CHEAT_DEFAULTS_KEY];
  }
}

// CAMERA's parts as the state says: the rings, dimmed while the camera is
// busy, the message line (for as long as it was asked to show), and the
// app's settings when CAMERA was shown or hidden
- (void)refreshCamera
{
  [self setRing:cameraRing progress:_fCameraRing];
  [self setRing:camSwitchRing progress:_fCamSwitchRing];
  const int bBusy = IOSTouch_CameraBusy();
  if (bBusy != bCameraBusyShown) {
    bCameraBusyShown = bBusy;
    [self refreshButtonLooks];
  }

  const double now = CACurrentMediaTime();
  const int bMessage = _strCamMessage[0] && now - _tCamMessage < _fCamMessageTime;
  if (bMessage && tCamMessageShown != _tCamMessage) {
    tCamMessageShown = _tCamMessage;
    camMessageLabel.text = [NSString stringWithUTF8String:_strCamMessage];
    CGSize sz = [camMessageLabel sizeThatFits:CGSizeMake(self.bounds.size.width - 40, 22)];
    const CGFloat w = fmin(sz.width + 24, self.bounds.size.width - 24);
    camMessageLabel.bounds = CGRectMake(0, 0, w, 22);
    camMessageLabel.center = CGPointMake(_fCamMessageX, _fCamMessageY);
  }
  if (camMessageLabel.hidden == bMessage) camMessageLabel.hidden = !bMessage;

  if (bShowCameraSaved != _bShowCamera) {
    bShowCameraSaved = _bShowCamera;
    [[NSUserDefaults standardUserDefaults] setBool:(_bShowCamera ? YES : NO) forKey:IOSTOUCH_CAMERA_DEFAULTS_KEY];
  }
}

- (void)refreshPadMask
{
  if (!_bPadHidden) {
    if (self.layer.mask) self.layer.mask = nil;
    return;
  }
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  if (!padMask) {
    padMask = [CALayer layer];
    padMaskHole = [CALayer layer];
    padMaskHole.backgroundColor = [UIColor blackColor].CGColor;
    padMaskHole.cornerRadius = 11.0;
    [padMask addSublayer:padMaskHole];
  }
  padMask.frame = self.bounds;
  padMaskHole.frame = camMessageLabel.hidden ? CGRectZero : camMessageLabel.frame;
  if (self.layer.mask != padMask) self.layer.mask = padMask;
  [CATransaction commit];
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  CGRect b = self.bounds;
  const double W = b.size.width, H = b.size.height;
  UIEdgeInsets in = self.safeAreaInsets;

  // The HUD boxes this layout keeps clear of; IOSTouch_Update lays out again
  // whenever they move, or the cutout changes sides
  _rLayoutScore = IOSTouch_RectInPoints(&_rScoreFrac, W, H);
  _rLayoutHiScore = IOSTouch_RectInPoints(&_rHiScoreFrac, W, H);
  _rLayoutMessages = IOSTouch_RectInPoints(&_rMessagesFrac, W, H);
  _iLayoutCutoutRight = IOSTouch_CutoutMayBeRight(self);
  IOSTouch_LayoutButtons(W, H, in.left, in.top, in.right, in.bottom, _iLayoutCutoutRight,
                         &_rLayoutScore, &_rLayoutHiScore, &_rLayoutMessages);

  for (int i = 0; i < IOSTOUCH_NUM_BUTTONS; i++) {
    aButtonViews[i].center = CGPointMake(_aButtons[i].x, _aButtons[i].y);
  }
  trayBack.frame = CGRectMake(_rTrayBack.x0, _rTrayBack.y0, _rTrayBack.x1 - _rTrayBack.x0, _rTrayBack.y1 - _rTrayBack.y0);
  fpsLabel.center = CGPointMake(_fFpsX, _fFpsY);
  camMessageLabel.center = CGPointMake(_fCamMessageX, _fCamMessageY);

  if (!levelPanel.hidden) [self placeLevelPanel];
  // the open weapon wheel round the new middle
  bWheelRebuild = 1;
  if (bWheelShown) [self refreshWheel];
}

- (void)setRing:(CAShapeLayer *)ring progress:(CGFloat)progress
{
  if (ring.strokeEnd == progress) return;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  ring.strokeEnd = progress;
  [CATransaction commit];
}

// The stick under the left thumb, while it is down
- (void)refreshStick
{
  if (!_bStickActive) {
    stickBase.hidden = YES;
    stickKnob.hidden = YES;
    return;
  }
  stickBase.alpha = stickKnob.alpha = _fOpacity; // (OPACITY's)
  stickBase.center = CGPointMake(_fStickOriginX, _fStickOriginY);
  stickKnob.center = CGPointMake(_fStickOriginX + _fStickX * IOSTOUCH_STICK_RADIUS,
                                 _fStickOriginY + _fStickY * IOSTOUCH_STICK_RADIUS);
  stickBase.hidden = NO;
  stickKnob.hidden = NO;
}

// What the tray's GYRO and SENS say: the mode and the sensitivity (NO GYRO
// without one)
- (void)refreshGyroLabels
{
  static const char *const astrMode[IOSTOUCH_GYRO_NUM_MODES] = { "OFF", "TOUCH", "ALWAYS" };
  const int bGyro = IOSTouch_GyroAvailable();
  const int iLabels = (bGyro ? 1 : 0) + 2 * (_iGyroMode + IOSTOUCH_GYRO_NUM_MODES * _iGyroSens);
  if (iLabels == iGyroLabels) return;
  iGyroLabels = iLabels;
  aButtonViews[BTN_TRAYGYRO].text = bGyro ? [NSString stringWithFormat:@"GYRO\n%s", astrMode[_iGyroMode]] : @"NO\nGYRO";
  aButtonViews[BTN_TRAYSENS].text = [NSString stringWithFormat:@"SENS\n%.1fx", (double)_afGyroSens[_iGyroSens]];
}

// The frame rate asked of the screen: a display link that does nothing but
// say what rate the app wants (ProMotion screens give an app 60 unless it
// asks; Info.plist's CADisableMinimumFrameDurationOnPhone lets it ask 120).
// The game's frames follow the screen (vsync).
- (void)applyMaxFps
{
  if (!frameRateLink) {
    frameRateLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(frameRateTick:)];
    [frameRateLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
  }
  const float f = (float)_iMaxFps;
  frameRateLink.preferredFrameRateRange = CAFrameRateRangeMake(_iMaxFps == 120 ? 80.0f : 60.0f, f, f);
  // (for the log: what the screen can do, and whether Low Power Mode caps it)
  printf("iOS: asked the screen for %d Hz (it can do %ld; Low Power Mode %s)\n", _iMaxFps,
         (long)[UIScreen mainScreen].maximumFramesPerSecond, [NSProcessInfo processInfo].lowPowerModeEnabled ? "on: 60 at most" : "off");
  fflush(stdout);
  ctRefreshTicks = 0;
  tRefreshStart = 0.0;
}

// (for the log: the rate the screen really runs at, once after each change)
- (void)frameRateTick:(CADisplayLink *)link
{
  if (tRefreshStart == 0.0) { tRefreshStart = link.timestamp; return; }
  if (ctRefreshTicks < 0) return;
  ctRefreshTicks++;
  if (link.timestamp - tRefreshStart >= 5.0) {
    printf("iOS: the screen runs at %.0f Hz\n", ctRefreshTicks / (link.timestamp - tRefreshStart));
    fflush(stdout);
    ctRefreshTicks = -1;
  }
}

// OPACITY's slider: the controls follow it as it slides, the strength is
// kept as it lifts
- (void)opacitySlid:(UISlider *)slider
{
  if (!_bOpacityOpen || !_bTrayOpen) {
    slider.value = _fOpacity;
    return;
  }
  _fOpacity = IOSTouch_OpacityStep(slider.value);
  [self refreshButtonLooks];
  [self refreshStick];
}

- (void)opacityLifted:(UISlider *)slider
{
  [self opacitySlid:slider];
  slider.value = _fOpacity;
  [[NSUserDefaults standardUserDefaults] setFloat:_fOpacity forKey:IOSTOUCH_OPACITY_DEFAULTS_KEY];
}

// What the tray's FPS says: the frame rate asked for ("FPS\n60")
- (void)refreshMaxFpsLabel
{
  if (iMaxFpsLabel == _iMaxFps) return;
  iMaxFpsLabel = _iMaxFps;
  aButtonViews[BTN_TRAYFPS].text = [NSString stringWithFormat:@"FPS\n%d", _iMaxFps];
}

// What the tray's LOOK says: the look speed ("LOOK\n1x", "LOOK\n0.75x")
- (void)refreshLookLabel
{
  if (fLookLabel == _fLookScale) return;
  fLookLabel = _fLookScale;
  aButtonViews[BTN_TRAYLOOK].text = [NSString stringWithFormat:@"LOOK\n%gx", (double)_fLookScale];
}

// Which buttons show and how; the tray and the FPS readout
- (void)refreshButtonLooks
{
  [self refreshGyroLabels];
  [self refreshLookLabel];
  [self refreshMaxFpsLabel];
  if (fOpacityLabel != _fOpacity) {
    fOpacityLabel = _fOpacity;
    aButtonViews[BTN_TRAYOPACITY].text = [NSString stringWithFormat:@"OPACITY\n%d%%", (int)lroundf(_fOpacity * 100.0f)];
  }
  // OPACITY's slider: a row under the tray, under OPACITY (kept on screen),
  // while it's open
  {
    const int bShow = _bOpacityOpen && _bTrayOpen;
    if (bShow) {
      const CGFloat w = IOSTOUCH_OPACITY_W, h = IOSTOUCH_OPACITY_H;
      const CGFloat cx = fmax(fmin(_aButtons[BTN_TRAYOPACITY].x, self.bounds.size.width - self.safeAreaInsets.right - 8 - w * 0.5),
                              self.safeAreaInsets.left + 8 + w * 0.5);
      opacityBack.frame = CGRectMake(round(cx - w * 0.5), round(_aButtons[BTN_TRAYOPACITY].y + 52 - h * 0.5), w, h);
      [self bringSubviewToFront:opacityBack];
    }
    if (opacityBack.hidden == bShow) opacityBack.hidden = !bShow;
  }
  const int bGyro = IOSTouch_GyroAvailable();
  for (int i = 0; i < IOSTOUCH_NUM_BUTTONS; i++) {
    UILabel *l = aButtonViews[i];
    const int bShown = IOSTouch_IsShown(i);
    if (l.hidden == bShown) l.hidden = !bShown;
    int bHeld = _aButtonHeld[i] != 0 || (_bWheelOpen && i == _iWheelButton); // (the weapon wheel's opener, lit)
    // A thumb still on MENU after its tray opened lights the tray button it is over
    for (int t = 0; t < IOSTOUCH_MAX_TOUCHES && !bHeld; t++) {
      const IOSTouchSlot *s = &_aSlots[t];
      bHeld = s->touch && s->role == ROLE_BUTTON && s->button == BTN_MENU && s->bFired && s->trayButton == i;
    }
    // CHEAT on: filled with gold, with a thick gold border (and its picture in
    // full colour, refreshCheat), so on and off can't be mistaken in any game
    const int bCheatLit = (i == BTN_CHEAT) && _bCheatOn && _hud.bCheatAllowed;
    l.backgroundColor = bCheatLit ? [UIColor colorWithRed:1.0 green:0.62 blue:0.12 alpha:(bHeld ? 0.55 : 0.38)]
                                  : [UIColor colorWithWhite:(bHeld ? 1.0 : 0.0) alpha:(bHeld ? 0.30 : 0.22)];
    // The open console (on MENU and the tray's keyboard), the FPS readout
    // being on (on the tray's FPS) and tilt aiming being on (on the tray's
    // GYRO) stand out in yellow, at full strength (and the tray's CAMERA
    // while CAMERA shows, the tray's CHEAT while CHEAT shows)
    const int bOn = ((i == BTN_TRAYKEYS || i == BTN_MENU) && _iMode == IOSTOUCH_CONSOLE)
                    || (i == BTN_TRAYFPS && _bShowFps)
                    || (i == BTN_TRAYGYRO && bGyro && _iGyroMode != IOSTOUCH_GYRO_OFF)
                    || (i == BTN_TRAYCAM && _bShowCamera)
                    || (i == BTN_TRAYCHEAT && _bShowCheat);
    const int bTray = IOSTouch_IsTrayButton(i); // only there while the tray is open
    CGFloat alpha = (bHeld || bOn || bTray || bCheatLit) ? 1.0 : IOSTOUCH_IDLE_ALPHA;
    if (i == BTN_TRAYGYRO && !bGyro) alpha *= 0.45;                                       // no gyro here
    if (i == BTN_TRAYSENS && (!bGyro || _iGyroMode == IOSTOUCH_GYRO_OFF)) alpha *= 0.45; // ...or it's off
    if (i == BTN_CAMERA && IOSTouch_CameraBusy()) alpha *= 0.45;                         // the camera is busy
    if (!bTray) alpha *= _fOpacity; // (OPACITY: the controls in play; the tray at full)
    l.alpha = alpha;
    if (bCheatLit) {
      l.layer.borderColor = [UIColor colorWithRed:1.0 green:0.75 blue:0.2 alpha:1.0].CGColor;
      l.layer.borderWidth = 3.0;
    }
    else if (i != BTN_FIRE) {
      l.layer.borderColor = bOn ? [UIColor colorWithRed:1.0 green:0.85 blue:0.3 alpha:0.95].CGColor
                                : [UIColor colorWithWhite:1.0 alpha:0.4].CGColor;
      if (i == BTN_CHEAT) l.layer.borderWidth = 1.5;
    }
  }
  if (trayBack.hidden == _bTrayOpen) trayBack.hidden = !_bTrayOpen;
  // the version, with the tray (aside from CAMERA's options when they are open)
  if (_bTrayOpen) {
    double vx, vy;
    IOSTouch_VersionCentre(versionLabel.bounds.size.width * 0.5, &vx, &vy);
    const CGPoint c = CGPointMake(vx, vy);
    if (!CGPointEqualToPoint(versionLabel.center, c)) versionLabel.center = c;
  }
  if (versionLabel.hidden == _bTrayOpen) versionLabel.hidden = !_bTrayOpen;

  // The FPS readout (not while the open tray lies over it), and the app's
  // settings when it, or tilt aiming's mode or sensitivity, was changed
  const int bFpsShown = _bShowFps && !(_bTrayOpen && IOSTouch_FpsUnderTray());
  if (fpsLabel.hidden == bFpsShown) fpsLabel.hidden = !bFpsShown;
  if (bFpsSaved != _bShowFps) {
    bFpsSaved = _bShowFps;
    [[NSUserDefaults standardUserDefaults] setBool:(_bShowFps ? YES : NO) forKey:IOSTOUCH_FPS_DEFAULTS_KEY];
  }
  if (iGyroModeSaved != _iGyroMode) {
    iGyroModeSaved = _iGyroMode;
    [[NSUserDefaults standardUserDefaults] setInteger:_iGyroMode forKey:IOSTOUCH_GYRO_DEFAULTS_KEY];
  }
  if (iMaxFpsSaved != _iMaxFps) {
    iMaxFpsSaved = _iMaxFps;
    [[NSUserDefaults standardUserDefaults] setInteger:_iMaxFps forKey:IOSTOUCH_MAXFPS_DEFAULTS_KEY];
  }
  if (fLookSaved != _fLookScale) {
    fLookSaved = _fLookScale;
    [[NSUserDefaults standardUserDefaults] setFloat:_fLookScale forKey:IOSTOUCH_LOOKSCALE_DEFAULTS_KEY];
  }
  if (iGyroSensSaved != _iGyroSens) {
    iGyroSensSaved = _iGyroSens;
    [[NSUserDefaults standardUserDefaults] setFloat:_afGyroSens[_iGyroSens] forKey:IOSTOUCH_GYRO_SENS_DEFAULTS_KEY];
  }
  if (iFpsLabel != _iFpsShown) {
    iFpsLabel = _iFpsShown;
    fpsLabel.text = (_iFpsShown < 0) ? @"-- FPS" : [NSString stringWithFormat:@"%d FPS", _iFpsShown];
  }
}

- (void)refreshAll
{
  [self refreshButtonLooks];
  [self refreshStick];
  [self setRing:saveRing progress:_fSaveRing];
  [self setRing:loadRing progress:_fLoadRing];
  [self setRing:menuRing progress:_fMenuRing];
  [self setRing:lookRing progress:_fLookRing];
  [self setRing:fpsRing progress:_fFpsRing];
  [self setRing:opacityRing progress:_fOpacityRing];
  [self setRing:aWheelRings[0] progress:_afWheelRing[0]];
  [self setRing:aWheelRings[1] progress:_afWheelRing[1]];
  [self syncWheel];
  [self refreshCamera];
  [self refreshPadMask];
  [self syncLevels];
}

// ------------------------------------------------------------ weapon wheel

// The middle's fonts (IOSTouch_WheelMiddleLayout measures with these)
static UIFont *IOSTouch_MiddleFont(int iKind, CGFloat size)
{
  if (iKind == WLINE_TITLE) return [UIFont boldSystemFontOfSize:size];
  return [UIFont systemFontOfSize:size weight:UIFontWeightSemibold];
}

static double IOSTouch_MiddleTextWidth(const char *str, int iKind, double fSize, void *pUser)
{
  (void)pUser;
  NSString *s = [NSString stringWithUTF8String:str];
  return [s sizeWithAttributes:@{ NSFontAttributeName : IOSTouch_MiddleFont(iKind, fSize) }].width;
}

static UIColor *IOSTouch_Colour(const float af[4])
{
  return [UIColor colorWithRed:af[0] green:af[1] blue:af[2] alpha:af[3]];
}

// A slice's shape: from deg0 round to deg1 (counter-clockwise), radius r0 to r1
static UIBezierPath *IOSTouch_WedgePath(CGPoint c, CGFloat deg0, CGFloat deg1, CGFloat r0, CGFloat r1)
{
  // UIKit's angles go clockwise (y points down)
  const CGFloat a0 = -deg1 * M_PI / 180.0, a1 = -deg0 * M_PI / 180.0;
  UIBezierPath *p = [UIBezierPath bezierPathWithArcCenter:c radius:r1 startAngle:a0 endAngle:a1 clockwise:YES];
  [p addArcWithCenter:c radius:r0 startAngle:a1 endAngle:a0 clockwise:NO];
  [p closePath];
  return p;
}

// An icon (RGBA, not premultiplied) as an image; its owner releases it
static CGImageRef IOSTouch_MakeIconImage(const unsigned char *pub, int w, int h)
{
  CFDataRef data = CFDataCreate(NULL, pub, (CFIndex)w * h * 4);
  CGDataProviderRef dp = CGDataProviderCreateWithCFData(data);
  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  CGImageRef im = CGImageCreate(w, h, 8, 32, (size_t)w * 4, cs, (CGBitmapInfo)kCGBitmapByteOrderDefault | (CGBitmapInfo)kCGImageAlphaLast,
                                dp, NULL, true, kCGRenderingIntentDefault);
  CGColorSpaceRelease(cs);
  CGDataProviderRelease(dp);
  CFRelease(data);
  return im;
}

static UIColor *IOSTouch_ThemeUIColour(const unsigned char aub[4])
{
  float af[4];
  IOSTouch_ThemeColour(aub, af);
  return IOSTouch_Colour(af);
}

// A star of n points round c (radius r, its inner corners at ri), the first
// point at deg (degrees, counter-clockwise from the right); with ri 0 the
// points are joined every other one (a pentagram's lines)
static UIBezierPath *IOSTouch_StarPath(CGPoint c, int n, CGFloat r, CGFloat ri, CGFloat deg)
{
  UIBezierPath *p = [UIBezierPath bezierPath];
  const int ct = ri > 0.0 ? 2 * n : n;
  for (int i = 0; i <= ct; i++) {
    CGFloat a, rr;
    if (ri > 0.0) {
      a = (deg + i * 180.0 / n) * M_PI / 180.0;
      rr = (i & 1) ? ri : r;
    }
    else {
      a = (deg + (i * 2 % n) * 360.0 / n) * M_PI / 180.0;
      rr = r;
    }
    const CGPoint q = CGPointMake(c.x + rr * cos(a), c.y - rr * sin(a));
    if (i == 0) [p moveToPoint:q];
    else [p addLineToPoint:q];
  }
  [p closePath];
  return p;
}

static void IOSTouch_AddCircle(UIBezierPath *p, CGPoint c, CGFloat r)
{
  [p appendPath:[UIBezierPath bezierPathWithArcCenter:c radius:r startAngle:0.0 endAngle:2.0 * M_PI clockwise:YES]];
}

// The game's look round the wheel at c (the hole R0, the slices out to R1;
// the disc goes 14 pt further, the rim is its outer 8 pt) and its motif in
// the middle, behind the words
static void IOSTouch_DrawWheelTheme(const IOSTouchWheelTheme *t, CGPoint c, double R0, double R1, CAShapeLayer *disc,
                                    CAShapeLayer *rim, CAShapeLayer *marks, CAShapeLayer *motif2, CAShapeLayer *motif)
{
  const CGFloat rRim = R1 + 10.0;
  disc.path = [UIBezierPath bezierPathWithArcCenter:c radius:R1 + 14.0 startAngle:0.0 endAngle:2.0 * M_PI clockwise:YES].CGPath;
  disc.fillColor = IOSTouch_ThemeUIColour(t->aubDisc).CGColor;
  UIBezierPath *ring = [UIBezierPath bezierPathWithArcCenter:c radius:rRim startAngle:0.0 endAngle:2.0 * M_PI clockwise:YES];
  rim.path = ring.CGPath;
  rim.lineWidth = 8.0;
  rim.strokeColor = IOSTouch_ThemeUIColour(t->aubRim).CGColor;
  marks.lineDashPattern = nil;
  marks.fillColor = [UIColor clearColor].CGColor;
  marks.strokeColor = IOSTouch_ThemeUIColour(t->aubRim2).CGColor;
  marks.lineWidth = 1.5;
  UIBezierPath *pm = [UIBezierPath bezierPath];
  switch (t->iRim) {
  case WRIM_HAZARD: {
    // black stripes across the yellow band, as on a hazard sign
    const int n = 48;
    for (int i = 0; i < n; i += 2) {
      const CGFloat a0 = 2.0 * M_PI * i / n, a1 = 2.0 * M_PI * (i + 1) / n, sk = 2.0 * M_PI / n * 0.6;
      [pm moveToPoint:CGPointMake(c.x + (rRim - 4.0) * cos(a0), c.y + (rRim - 4.0) * sin(a0))];
      [pm addLineToPoint:CGPointMake(c.x + (rRim + 4.0) * cos(a0 + sk), c.y + (rRim + 4.0) * sin(a0 + sk))];
      [pm addLineToPoint:CGPointMake(c.x + (rRim + 4.0) * cos(a1 + sk), c.y + (rRim + 4.0) * sin(a1 + sk))];
      [pm addLineToPoint:CGPointMake(c.x + (rRim - 4.0) * cos(a1), c.y + (rRim - 4.0) * sin(a1))];
      [pm closePath];
    }
    marks.fillColor = marks.strokeColor;
    marks.lineWidth = 0.0;
    break;
  }
  case WRIM_RIVETS:
    for (int i = 0; i < 24; i++) {
      const CGFloat a = 2.0 * M_PI * (i + 0.5) / 24;
      IOSTouch_AddCircle(pm, CGPointMake(c.x + rRim * cos(a), c.y + rRim * sin(a)), 1.8);
    }
    marks.fillColor = marks.strokeColor;
    marks.lineWidth = 0.0;
    break;
  case WRIM_TICKS:
    // a thin bone line either side of the band, short marks across it
    IOSTouch_AddCircle(pm, c, rRim - 4.0);
    IOSTouch_AddCircle(pm, c, rRim + 4.0);
    for (int i = 0; i < 36; i++) {
      const CGFloat a = 2.0 * M_PI * i / 36;
      [pm moveToPoint:CGPointMake(c.x + (rRim - 2.5) * cos(a), c.y + (rRim - 2.5) * sin(a))];
      [pm addLineToPoint:CGPointMake(c.x + (rRim + 2.5) * cos(a), c.y + (rRim + 2.5) * sin(a))];
    }
    marks.lineWidth = 1.2;
    break;
  case WRIM_DOTS:
    for (int i = 0; i < 36; i++) {
      const CGFloat a = 2.0 * M_PI * i / 36;
      IOSTouch_AddCircle(pm, CGPointMake(c.x + rRim * cos(a), c.y + rRim * sin(a)), (i % 3 == 0) ? 1.9 : 1.1);
    }
    marks.fillColor = marks.strokeColor;
    marks.lineWidth = 0.0;
    break;
  default:
    // a dark line along the band's middle
    IOSTouch_AddCircle(pm, c, rRim);
    marks.lineWidth = 1.5;
    break;
  }
  marks.path = pm.CGPath;
  // the motif, inside the hole
  const CGFloat r = R0 * 0.86;
  UIBezierPath *p = [UIBezierPath bezierPath], *p2 = nil;
  motif.fillColor = IOSTouch_ThemeUIColour(t->aubMotif).CGColor;
  motif.strokeColor = [UIColor clearColor].CGColor;
  motif.lineWidth = 0.0;
  switch (t->iMotif) {
  case WMOTIF_TREFOIL:
    // the radiation sign: a dot and three blades
    IOSTouch_AddCircle(p, c, r * 0.16);
    for (int i = 0; i < 3; i++) {
      const CGFloat d = 30.0 + i * 120.0; // (one blade down, as the sign is)
      [p appendPath:IOSTouch_WedgePath(c, d - 30.0, d + 30.0, r * 0.26, r)];
    }
    break;
  case WMOTIF_STAR:
    // a sheriff's star: five points, a ball on each
    [p appendPath:IOSTouch_StarPath(c, 5, r * 0.88, r * 0.42, 90.0)];
    for (int i = 0; i < 5; i++) {
      const CGFloat a = (90.0 + i * 72.0) * M_PI / 180.0;
      IOSTouch_AddCircle(p, CGPointMake(c.x + r * 0.9 * cos(a), c.y - r * 0.9 * sin(a)), r * 0.09);
    }
    motif.fillRule = kCAFillRuleNonZero;
    break;
  case WMOTIF_PENTACLE:
    // a circle and a five-pointed star in lines, a point down
    IOSTouch_AddCircle(p, c, r);
    [p appendPath:IOSTouch_StarPath(c, 5, r, 0.0, -90.0)];
    motif.fillColor = [UIColor clearColor].CGColor;
    motif.strokeColor = IOSTouch_ThemeUIColour(t->aubMotif).CGColor;
    motif.lineWidth = 2.0;
    break;
  case WMOTIF_YINYANG: {
    // the yin-yang: its light half under, the dark half and the two dots over
    p2 = [UIBezierPath bezierPathWithArcCenter:c radius:r startAngle:0.0 endAngle:2.0 * M_PI clockwise:YES];
    [p moveToPoint:CGPointMake(c.x, c.y - r)];
    [p addArcWithCenter:c radius:r startAngle:-M_PI_2 endAngle:M_PI_2 clockwise:YES];
    [p addArcWithCenter:CGPointMake(c.x, c.y + r * 0.5) radius:r * 0.5 startAngle:M_PI_2 endAngle:-M_PI_2 clockwise:YES];
    [p addArcWithCenter:CGPointMake(c.x, c.y - r * 0.5) radius:r * 0.5 startAngle:M_PI_2 endAngle:-M_PI_2 clockwise:NO];
    [p closePath];
    IOSTouch_AddCircle(p, CGPointMake(c.x, c.y + r * 0.5), r * 0.14);
    IOSTouch_AddCircle(p, CGPointMake(c.x, c.y - r * 0.5), r * 0.14);
    motif.fillRule = kCAFillRuleEvenOdd;
    break;
  }
  case WMOTIF_SUN:
    // the sun disc: a ring and its rays
    IOSTouch_AddCircle(p, c, r * 0.42);
    for (int i = 0; i < 16; i++) {
      const CGFloat a = 2.0 * M_PI * (i + 0.5) / 16;
      [p moveToPoint:CGPointMake(c.x + r * 0.58 * cos(a), c.y + r * 0.58 * sin(a))];
      [p addLineToPoint:CGPointMake(c.x + r * ((i & 1) ? 0.84 : 1.0) * cos(a), c.y + r * ((i & 1) ? 0.84 : 1.0) * sin(a))];
    }
    motif.fillColor = [UIColor clearColor].CGColor;
    motif.strokeColor = IOSTouch_ThemeUIColour(t->aubMotif).CGColor;
    motif.lineWidth = 2.5;
    break;
  default:
    break;
  }
  if (t->iMotif == WMOTIF_TREFOIL) motif.fillRule = kCAFillRuleNonZero;
  motif.path = p.CGPath;
  motif2.path = p2 ? p2.CGPath : NULL;
  motif2.fillColor = IOSTouch_ThemeUIColour(t->aubMotif2).CGColor;
}

// The wheel's parts, made once, hidden until it opens: a dim over the game,
// the dark disc, the slices on it, each slice's icon (twice for the two
// colts), its count and its name (shown instead of an icon the game couldn't
// give), the needle, the middle's lines and "cancel" in the gap
- (void)makeWheel
{
  wheelView = [[UIView alloc] initWithFrame:self.bounds];
  wheelView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  wheelView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
  wheelView.userInteractionEnabled = NO; // touches are the overlay's
  wheelView.hidden = YES;
  wheelDisc = [CAShapeLayer layer];
  wheelDisc.fillColor = [UIColor colorWithWhite:0.0 alpha:0.85].CGColor;
  [wheelView.layer addSublayer:wheelDisc];
  wheelRim = [CAShapeLayer layer];
  wheelRim.fillColor = [UIColor clearColor].CGColor;
  [wheelView.layer addSublayer:wheelRim];
  wheelRimMarks = [CAShapeLayer layer];
  [wheelView.layer addSublayer:wheelRimMarks];
  wheelMotif2 = [CAShapeLayer layer];
  [wheelView.layer addSublayer:wheelMotif2];
  wheelMotif = [CAShapeLayer layer];
  wheelMotif.fillRule = kCAFillRuleEvenOdd;
  wheelMotif.lineJoin = kCALineJoinRound;
  wheelMotif.lineCap = kCALineCapRound;
  [wheelView.layer addSublayer:wheelMotif];
  for (int i = 0; i < IOSTOUCH_WHEEL_MAX; i++) {
    CAShapeLayer *sl = [CAShapeLayer layer];
    sl.lineJoin = kCALineJoinRound;
    sl.hidden = YES;
    aSliceLayers[i] = sl;
    [wheelView.layer addSublayer:sl];
  }
  for (int i = 0; i < IOSTOUCH_WHEEL_MAX; i++) {
    for (int k = 1; k >= 0; k--) { // [1] (the two colts' back one) under [0]
      CALayer *l = [CALayer layer];
      l.zPosition = 2.0;
      l.hidden = YES;
      l.contentsGravity = kCAGravityResizeAspect; // (fitted in its box, its shape kept)
      l.magnificationFilter = kCAFilterLinear;
      l.minificationFilter = kCAFilterLinear;
      aIconLayers[i][k] = l;
      [wheelView.layer addSublayer:l];
    }
    UILabel *c = [[UILabel alloc] initWithFrame:CGRectZero];
    c.textAlignment = NSTextAlignmentCenter;
    c.layer.zPosition = 2.0;
    c.hidden = YES;
    aCountLabels[i] = c;
    [wheelView addSubview:c];
    UILabel *n = [[UILabel alloc] initWithFrame:CGRectZero];
    n.textAlignment = NSTextAlignmentCenter;
    n.numberOfLines = 2;
    n.adjustsFontSizeToFitWidth = YES;
    n.minimumScaleFactor = 0.5;
    n.layer.zPosition = 2.0;
    n.hidden = YES;
    aNameLabels[i] = n;
    [wheelView addSubview:n];
  }
  wheelNeedle = [CAShapeLayer layer];
  wheelNeedle.lineWidth = 3.0;
  wheelNeedle.lineCap = kCALineCapRound;
  wheelNeedle.fillColor = [UIColor clearColor].CGColor;
  wheelNeedle.zPosition = 2.0;
  wheelNeedle.hidden = YES;
  [wheelView.layer addSublayer:wheelNeedle];
  for (int i = 0; i < IOSTOUCH_MIDDLE_LINES; i++) {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.textAlignment = NSTextAlignmentCenter;
    l.layer.zPosition = 2.0;
    l.hidden = YES;
    aMiddleLabels[i] = l;
    [wheelView addSubview:l];
  }
  wheelCancelLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 80, 14)];
  wheelCancelLabel.textAlignment = NSTextAlignmentCenter;
  wheelCancelLabel.font = [UIFont systemFontOfSize:9 weight:UIFontWeightSemibold];
  wheelCancelLabel.textColor = [UIColor colorWithWhite:0.59 alpha:1.0];
  wheelCancelLabel.text = @"cancel";
  wheelCancelLabel.layer.zPosition = 2.0;
  [wheelView addSubview:wheelCancelLabel];
  [self addSubview:wheelView];
  wheelTick = [[UISelectionFeedbackGenerator alloc] init];
  memset(&wheelKey, 0, sizeof(wheelKey));
}

// The icons the game has handed over since, as images: as they are, and
// greyed for no ammo and for not found yet
- (void)makeIconImages
{
  const unsigned int ulNew = _ulIconsNew;
  _ulIconsNew = 0;
  for (int w = 0; w < IOSTOUCH_WPN_MAX; w++) {
    if (!(ulNew & (1u << w))) continue;
    const IOSTouchIcon *pi = &_aIcons[w];
    for (int st = 0; st < WICON_NUM; st++) {
      aIconImages[w][st] = pi->bHave ? CFBridgingRelease(IOSTouch_MakeIconImage(pi->aub[st], pi->w, pi->h)) : nil;
    }
  }
  if (ulNew) bWheelRebuild = 1;
}

// Draws the open wheel as the core says: made again only when something
// changed (what is pointed at, the slices' states, an icon, the layout); the
// needle follows the thumb every time
- (void)refreshWheel
{
  IOSTouchWheelKey key;
  memset(&key, 0, sizeof(key));
  key.iMap = _iWheelMap;
  key.cx = _fWheelCX;
  key.cy = _fWheelCY;
  key.R1 = _fWheelR1;
  key.iHot = IOSTouch_WheelPointed(&key.bCancel, NULL);
  key.bTapMode = _bWheelTapMode;
  key.iWanted = _wpn.iWanted;
  key.ulOwned = _wpn.ulOwned;
  key.ulReady = _wpn.ulReady;
  key.bInfinite = _wpn.bInfiniteAmmo;
  memcpy(key.aiAmmo, _wpn.aiAmmo, sizeof(key.aiAmmo));
  memcpy(key.aiMax, _wpn.aiMaxAmmo, sizeof(key.aiMax));
  const IOSTouchWheelMap *m = IOSTouch_WheelMapOf(_iWheelMap);
  const CGPoint c = CGPointMake(_fWheelCX, _fWheelCY);
  const double R0 = _fWheelR0, R1 = _fWheelR1;

  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  if (bWheelRebuild || memcmp(&key, &wheelKey, sizeof(key)) != 0) {
    bWheelRebuild = 0;
    wheelKey = key;
    wheelView.frame = self.bounds;
    IOSTouch_DrawWheelTheme(IOSTouch_WheelThemeOf(_iWheelMap), c, R0, R1, wheelDisc, wheelRim, wheelRimMarks, wheelMotif2, wheelMotif);
    const IOSTouchWheelFit *f = IOSTouch_WheelFit();
    for (int i = 0; i < IOSTOUCH_WHEEL_MAX; i++) {
      const int bOn = i < m->ctSlots;
      aSliceLayers[i].hidden = !bOn;
      aCountLabels[i].hidden = aNameLabels[i].hidden = YES;
      aIconLayers[i][0].hidden = aIconLayers[i][1].hidden = YES;
      if (!bOn) continue;
      IOSTouchWheelLook look;
      IOSTouch_WheelSlotLook(i, key.iHot, &look);
      const double deg = IOSTouch_WheelSlotDeg(m, i), half = m->fSliceDeg * 0.5 - 1.0; // a degree in from each edge
      CAShapeLayer *L = aSliceLayers[i];
      L.path = IOSTouch_WedgePath(c, deg - half, deg + half, R0, R1 + (look.bPopped ? IOSTOUCH_WHEEL_POP : 0.0)).CGPath;
      L.fillColor = IOSTouch_Colour(look.afFill).CGColor;
      L.strokeColor = IOSTouch_Colour(look.afEdge).CGColor;
      L.lineWidth = look.fLine;
      L.zPosition = look.bPopped ? 1.0 : 0.0;
      IOSTouchRect rIcon, rRow;
      IOSTouch_WheelSlotRects(i, look.bPopped, look.iCount >= 0, &rIcon, &rRow);
      const CGRect ri = CGRectMake(rIcon.x0, rIcon.y0, rIcon.x1 - rIcon.x0, rIcon.y1 - rIcon.y0);
      const int w = m->aSlots[i].iWeapon;
      id image = aIconImages[IOSTouch_WheelIconOf(w)][look.iIcon];
      if (image) {
        aIconLayers[i][0].frame = ri;
        aIconLayers[i][0].contents = image;
        aIconLayers[i][0].hidden = NO;
      }
      else {
        // no icon (yet): the name
        UILabel *n = aNameLabels[i];
        n.text = [[NSString stringWithUTF8String:m->aSlots[i].strName] stringByReplacingOccurrencesOfString:@" " withString:@"\n"];
        n.font = [UIFont systemFontOfSize:9.0 * f->k weight:UIFontWeightSemibold];
        n.textColor = IOSTouch_Colour(look.afText);
        n.bounds = CGRectMake(0, 0, ri.size.width, ri.size.height); // (the fitted block's width: it shrinks to fit)
        n.center = CGPointMake(CGRectGetMidX(ri), CGRectGetMidY(ri));
        n.hidden = NO;
      }
      if (look.iCount >= 0) {
        UILabel *cl = aCountLabels[i];
        cl.text = [NSString stringWithFormat:@"%d", look.iCount];
        cl.font = [UIFont monospacedDigitSystemFontOfSize:IOSTOUCH_WHEEL_AMMO_FONT * f->k weight:UIFontWeightSemibold];
        cl.textColor = IOSTouch_Colour(look.afText);
        cl.bounds = CGRectMake(0, 0, rRow.x1 - rRow.x0 + 6.0, ceil(IOSTOUCH_WHEEL_AMMO_FONT * f->k * 1.25)); // (a whole line)
        cl.center = CGPointMake((rRow.x0 + rRow.x1) * 0.5, (rRow.y0 + rRow.y1) * 0.5); // (the digits about centred in it)
        cl.hidden = NO;
      }
    }
    // the middle
    IOSTouchWheelMiddle mid;
    IOSTouch_WheelMiddleState(&mid);
    IOSTouchMiddleLine aLines[IOSTOUCH_MIDDLE_LINES];
    const int ct = IOSTouch_WheelMiddleLayout(R0, &mid, IOSTouch_MiddleTextWidth, NULL, aLines);
    for (int j = 0; j < IOSTOUCH_MIDDLE_LINES; j++) {
      UILabel *l = aMiddleLabels[j];
      l.hidden = j >= ct;
      if (j >= ct) continue;
      const IOSTouchMiddleLine *ln = &aLines[j];
      l.text = [NSString stringWithUTF8String:ln->str];
      l.font = IOSTouch_MiddleFont(ln->iKind, ln->fSize);
      if (ln->iKind == WLINE_TITLE) {
        float af[4];
        if (mid.iTitleLook == WTITLE_SLOT) IOSTouch_WheelMix(mid.iColour, 1.0, af);
        else if (mid.iTitleLook == WTITLE_WHITE) {
          // (the game's own title colour)
          const unsigned char *t = IOSTouch_WheelThemeOf(_iWheelMap)->aubTitle;
          for (int k = 0; k < 3; k++) af[k] = t[k] / 255.0f;
          af[3] = 1.0f;
        }
        else IOSTouch_Grey(0.63, 1.0, af);
        l.textColor = IOSTouch_Colour(af);
      }
      else {
        l.textColor = [UIColor colorWithWhite:(ln->iKind == WLINE_COUNT ? 0.9 : 0.8) alpha:1.0];
      }
      l.bounds = CGRectMake(0, 0, 2.0 * R0, ceil(ln->fSize * 1.18) + 2.0);
      l.center = CGPointMake(c.x, c.y + ln->fDY);
    }
    wheelCancelLabel.center = CGPointMake(c.x, c.y + R1 - 22.0);
    wheelCancelLabel.hidden = key.iHot == IOSTOUCH_WHEEL_CANCEL;
  }
  double x0, y0, x1, y1;
  float af[4];
  if (IOSTouch_WheelNeedle(&x0, &y0, &x1, &y1, af)) {
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(x0, y0)];
    [p addLineToPoint:CGPointMake(x1, y1)];
    wheelNeedle.path = p.CGPath;
    wheelNeedle.strokeColor = IOSTouch_Colour(af).CGColor;
    wheelNeedle.hidden = NO;
  }
  else {
    wheelNeedle.hidden = YES;
  }
  [CATransaction commit];
}

// The opener's button (NEXT WPN or PREV WPN) lifted above the wheel's dim
// (b), or put back where it was made, just above the button before it
// (-1), so the stick, the FPS readout and the tray draw over it again
- (void)liftWheelButton:(int)b
{
  if (iWheelLifted > 0) [self insertSubview:aButtonViews[iWheelLifted - 1] aboveSubview:aButtonViews[iWheelLifted - 2]];
  iWheelLifted = 0;
  if (b >= 0) {
    [self insertSubview:aButtonViews[b] aboveSubview:wheelView];
    iWheelLifted = b + 1;
  }
}

// After every touch, frame and reset: the wheel shows while the core has it
// open (the opener's button lifted above the dim), and ticks as the thumb
// moves onto another slice
- (void)syncWheel
{
  if (_ulIconsNew) [self makeIconImages];
  if (_bWheelOpen && !bWheelShown) {
    bWheelShown = 1;
    bWheelRebuild = 1;
    [self bringSubviewToFront:wheelView];
    [self liftWheelButton:_iWheelButton];
    [wheelTick prepare];
    wheelView.hidden = NO;
    [self refreshButtonLooks];
    [self refreshStick];
  }
  else if (!_bWheelOpen && bWheelShown) {
    bWheelShown = 0;
    wheelView.hidden = YES;
    [self liftWheelButton:-1];
    [self refreshButtonLooks];
  }
  else if (bWheelShown && iWheelLifted != _iWheelButton + 1) {
    // (closed and opened again from the other button between two syncs)
    [self liftWheelButton:_iWheelButton];
    [self refreshButtonLooks];
  }
  if (bWheelShown) [self refreshWheel];
  if (_ctWheelTicks > 0) {
    if (bWheelShown) [wheelTick selectionChanged];
    _ctWheelTicks = 0;
  }
}

// ------------------------------------------------------------ touches

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
  const double now = CACurrentMediaTime();
  const double W = self.bounds.size.width;
  // hidden for a game controller: every touch that comes with the one that
  // brings the controls back is ignored too (each finds them still hidden)
  const int bRevealing = _bPadHidden;
  for (UITouch *t in touches) {
    CGPoint p = [t locationInView:self];
    if (bRevealing) _bPadHidden = 1;
    IOSTouch_TouchBegan((__bridge const void *)t, p.x, p.y, W, now, t.timestamp);
  }
  [self refreshAll];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
  int bLooksChanged = 0;
  for (UITouch *t in touches) {
    // the places UIKit merged into this move (the last one is t's own)
    for (UITouch *c in [event coalescedTouchesForTouch:t]) {
      CGPoint q = [c locationInView:self];
      IOSTouch_TouchPassed((__bridge const void *)t, q.x, q.y);
    }
    CGPoint p = [t locationInView:self];
    if (IOSTouch_TouchMoved((__bridge const void *)t, p.x, p.y)) bLooksChanged = 1;
  }
  if (bLooksChanged) [self refreshButtonLooks];
  [self refreshStick];
  [self syncWheel];
}

- (void)endTouches:(NSSet<UITouch *> *)touches cancelled:(int)bCancelled
{
  for (UITouch *t in touches) {
    CGPoint p = [t locationInView:self];
    IOSTouch_TouchEnded((__bridge const void *)t, p.x, p.y, bCancelled, t.timestamp);
  }
  [self refreshAll];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self endTouches:touches cancelled:0]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self endTouches:touches cancelled:1]; }

// Once per frame while shown: the NEXT WPN, PREV WPN, QUICK SAVE, QUICK
// LOAD and MENU holds, the weapon wheel, the context buttons and the FPS
// readout
- (void)tick
{
  const double now = CACurrentMediaTime();
  const int bTrayWasOpen = _bTrayOpen;
  const int iFpsWas = _iFpsShown;
  const int iCamWas = _bShowCamera * 8 + (_hud.bNoSaves != 0) * 16 + _bShowCheat * 32;
  IOSTouch_TickHolds(now);
  tLastTick = now;
  [self refreshCamera];
  [self refreshCheat];
  [self refreshPadMask];
  IOSTouch_CountFrames(_ulFramesDrawn, now);
  [self setRing:saveRing progress:_fSaveRing];
  [self setRing:loadRing progress:_fLoadRing];
  [self setRing:menuRing progress:_fMenuRing];
  [self setRing:lookRing progress:_fLookRing];
  [self setRing:fpsRing progress:_fFpsRing];
  [self setRing:opacityRing progress:_fOpacityRing];
  [self setRing:aWheelRings[0] progress:_afWheelRing[0]];
  [self setRing:aWheelRings[1] progress:_afWheelRing[1]];
  [self syncWheel]; // (a hold may have opened the weapon wheel, or the game closed it)
  [self syncLevels]; // (the list of levels closes once LEVEL is gone)
  // LOOK held back to 1x: a thump, and its label says so
  if (ctLookResetsFelt != _ctLookResets) {
    ctLookResetsFelt = _ctLookResets;
    [lookThump impactOccurred];
    [self refreshButtonLooks];
  }
  // OPACITY held: back to 100% (a thump, the controls, the slider)
  if (ctOpacityResetsFelt != _ctOpacityResets) {
    ctOpacityResetsFelt = _ctOpacityResets;
    [lookThump impactOccurred];
    opacitySlider.value = _fOpacity;
    [[NSUserDefaults standardUserDefaults] setFloat:_fOpacity forKey:IOSTOUCH_OPACITY_DEFAULTS_KEY];
    [self refreshButtonLooks];
    [self refreshStick];
  }
  // FPS held: 60 or 120 (a thump, its label, the screen asked)
  if (ctMaxFpsFelt != _ctMaxFpsChanges) {
    ctMaxFpsFelt = _ctMaxFpsChanges;
    [lookThump impactOccurred];
    [self applyMaxFps];
    [self refreshButtonLooks];
  }

  // The secondary button says what it is in this game (ALT FIRE, KICK)
  const int iSecondary = _hud.bValid ? _hud.iSecondary : IOSTOUCH_SEC_NONE;
  if (iSecondary != iSecondaryShown) {
    iSecondaryShown = iSecondary;
    const char *str = (iSecondary == IOSTOUCH_SEC_KICK) ? "KICK" : "ALT\nFIRE";
    UILabel *l = aButtonViews[BTN_SECONDARY];
    l.text = [NSString stringWithUTF8String:str];
    l.font = [UIFont boldSystemFontOfSize:IOSTouch_FontSize(str, _aButtons[BTN_SECONDARY].radius)];
  }
  // the secondary button, ITEM and the tray's LEVEL come and go, the tray opens, the readout counts
  const int iCamNow = _bShowCamera * 8 + (_hud.bNoSaves != 0) * 16 + _bShowCheat * 32;
  if (aButtonViews[BTN_SECONDARY].hidden == IOSTouch_IsShown(BTN_SECONDARY) || aButtonViews[BTN_ITEM].hidden == IOSTouch_IsShown(BTN_ITEM)
      || aButtonViews[BTN_TRAYLEVEL].hidden == IOSTouch_IsShown(BTN_TRAYLEVEL)
      || _bTrayOpen != bTrayWasOpen || _iFpsShown != iFpsWas || iCamNow != iCamWas
      || opacityBack.hidden == (_bOpacityOpen && _bTrayOpen)) {
    [self refreshButtonLooks];
  }
}

// ------------------------------------------------------- the cheat's levels
// The tray's LEVEL opens this over the game (which holds still meanwhile):
// the game's own levels in order, as the game lists them (numbered, the
// level's name, its file under it), the one being played ticked. A tap on
// one goes there; the X, or a touch anywhere off the panel, closes it. In
// the cheat's colours (CHEAT's gold on the tray's dark backing, its
// condensed bold letters).

static UIColor *IOSTouch_CheatGold(CGFloat alpha)
{
  return [UIColor colorWithRed:1.0 green:0.68 blue:0.18 alpha:alpha];
}

- (void)makeLevelPanel
{
  levelPanel = [[IOSTouchLevelPanel alloc] initWithFrame:CGRectZero];
  levelPanel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.82];
  levelPanel.layer.cornerRadius = 18.0;
  levelPanel.layer.borderWidth = 1.5;
  levelPanel.layer.borderColor = IOSTouch_CheatGold(0.8).CGColor;
  levelPanel.clipsToBounds = YES;
  levelPanel.hidden = YES;
  levelTitle = [[UILabel alloc] initWithFrame:CGRectZero];
  levelTitle.text = @"LEVEL";
  levelTitle.font = IOSTouch_TrayFont(17);
  levelTitle.textColor = IOSTouch_CheatGold(1.0);
  levelTitle.adjustsFontSizeToFitWidth = YES;
  levelTitle.minimumScaleFactor = 0.6;
  [levelPanel addSubview:levelTitle];
  levelClose = [UIButton buttonWithType:UIButtonTypeSystem];
  UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightBold];
  UIImage *x = [UIImage systemImageNamed:@"xmark" withConfiguration:cfg];
  if (x) [levelClose setImage:x forState:UIControlStateNormal];
  else [levelClose setTitle:@"X" forState:UIControlStateNormal];
  levelClose.tintColor = [UIColor colorWithWhite:1.0 alpha:0.85];
  [levelClose addTarget:self action:@selector(closeLevelsTapped) forControlEvents:UIControlEventTouchUpInside];
  [levelPanel addSubview:levelClose];
  levelTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
  levelTable.backgroundColor = [UIColor clearColor];
  levelTable.separatorColor = [UIColor colorWithWhite:1.0 alpha:0.12];
  levelTable.indicatorStyle = UIScrollViewIndicatorStyleWhite;
  levelTable.dataSource = self;
  levelTable.delegate = self;
  [levelPanel addSubview:levelTable];
  [self addSubview:levelPanel];
  aLevelNames = @[];
  aLevelFiles = @[];
  iLevelNow = 0;
}

// Middle of the screen, inside the safe area, as tall as it allows
- (void)placeLevelPanel
{
  const CGRect b = self.bounds;
  const UIEdgeInsets in = self.safeAreaInsets;
  const CGFloat w = fmin(440.0, b.size.width - in.left - in.right - 40.0);
  const CGFloat h = fmax(120.0, b.size.height - fmax(in.top, 8.0) - fmax(in.bottom, 8.0) - 16.0);
  const CGFloat left = in.left + (b.size.width - in.left - in.right - w) * 0.5;
  levelPanel.frame = CGRectMake(left, fmax(in.top, 8.0) + 8.0, w, h);
  levelTitle.frame = CGRectMake(18, 10, w - 70, 26);
  levelClose.frame = CGRectMake(w - 46, 4, 42, 38);
  levelTable.frame = CGRectMake(0, 46, w, h - 46);
}

// The panel as the state says: shown (the levels read from the game) while
// the list is open, hidden once it closes
- (void)syncLevels
{
  if (_bLevelListOpen && levelPanel.hidden) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    for (int i = 1; i <= _hud.ctLevels; i++) {
      char strName[128], strFile[256];
      if (!IOSGame_LevelInfo(i, strName, sizeof(strName), strFile, sizeof(strFile))) break;
      NSString *name = [NSString stringWithUTF8String:strName];
      NSString *file = [NSString stringWithUTF8String:strFile];
      // (names and files are the game's, in its own 8-bit letters)
      if (!name) name = [NSString stringWithCString:strName encoding:NSWindowsCP1252StringEncoding];
      if (!file) file = [NSString stringWithCString:strFile encoding:NSWindowsCP1252StringEncoding];
      [names addObject:(name ?: @"")];
      [files addObject:(file ?: @"")];
    }
    if (names.count == 0) {
      IOSTouch_CloseLevelList();
      IOS_ShowCameraMessage("No levels found");
      return;
    }
    aLevelNames = names;
    aLevelFiles = files;
    iLevelNow = IOSGame_CurrentLevel();
    levelTitle.text = [NSString stringWithFormat:@"LEVEL  (%d)", (int)names.count];
    [self placeLevelPanel];
    [levelTable reloadData];
    levelPanel.hidden = NO;
    [self bringSubviewToFront:levelPanel];
    [levelTable layoutIfNeeded];
    // the level being played in view
    if (iLevelNow >= 1 && iLevelNow <= (int)names.count) {
      [levelTable scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:iLevelNow - 1 inSection:0]
                        atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
    }
    else {
      [levelTable setContentOffset:CGPointZero animated:NO];
    }
    [self refreshButtonLooks];
  }
  else if (!_bLevelListOpen && !levelPanel.hidden) {
    levelPanel.hidden = YES;
  }
}

- (void)closeLevelsTapped
{
  IOSTouch_CloseLevelList();
  [self syncLevels];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
  return (NSInteger)aLevelNames.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"level"];
  if (!cell) {
    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"level"];
    cell.backgroundColor = [UIColor clearColor];
    cell.textLabel.font = IOSTouch_TrayFont(16);
    cell.textLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.92];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:11];
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.5];
    cell.tintColor = IOSTouch_CheatGold(1.0);
    UIView *sel = [[UIView alloc] init];
    sel.backgroundColor = IOSTouch_CheatGold(0.3);
    cell.selectedBackgroundView = sel;
  }
  const NSInteger row = indexPath.row;
  if (row < 0 || row >= (NSInteger)aLevelNames.count) return cell;
  // the number in CHEAT's gold, then the name
  NSString *num = [NSString stringWithFormat:@"%d.  ", (int)row + 1];
  UIFont *font = IOSTouch_TrayFont(16);
  NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:num
                                       attributes:@{ NSFontAttributeName: font, NSForegroundColorAttributeName: IOSTouch_CheatGold(1.0) }];
  [text appendAttributedString:[[NSAttributedString alloc] initWithString:aLevelNames[row]
                                  attributes:@{ NSFontAttributeName: font,
                                                NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.92] }]];
  cell.textLabel.attributedText = text;
  cell.detailTextLabel.text = aLevelFiles[row];
  cell.accessoryType = (row + 1 == iLevelNow) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
  return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
  [tableView deselectRowAtIndexPath:indexPath animated:NO];
  [cheatTick selectionChanged];
  IOSTouch_PickLevel((int)indexPath.row + 1);
  [self syncLevels];
}

- (void)resetAll
{
  IOSTouch_ResetTouches(_iMode == IOSTOUCH_GAMEPLAY && !self.hidden && self.superview != nil);
  tLastTick = 0.0;
  [self refreshAll];
}

@end

// ---------------------------------------------------------------- C API

static IOSTouchOverlay *_pOverlay = nil;

// The view SDL draws the game in: the overlay goes on top of it
static UIView *IOSTouch_GetHostView(SDL_Window *pWindow)
{
  SDL_SysWMinfo info;
  SDL_VERSION(&info.version);
  if (pWindow == NULL || !SDL_GetWindowWMInfo(pWindow, &info) || info.subsystem != SDL_SYSWM_UIKIT) return nil;
  UIWindow *w = info.info.uikit.window;
  if (!w) return nil;
  return w.rootViewController.view ? w.rootViewController.view : w;
}

// Switches what shows; every change starts clean (touches on a hidden view
// never end, and MENU's tray closes)
static void IOSTouch_SetMode(int iMode)
{
  const int iOld = _iMode;
  _iMode = iMode;
  if (_pOverlay) {
    _pOverlay.hidden = (iMode == IOSTOUCH_HIDDEN);
    [_pOverlay resetAll];
  }
  else {
    IOSTouch_ResetTouches(0);
  }
  // The console gets the iOS keyboard (SDL's text input shows it); it goes
  // again as the console closes
  if (iMode == IOSTOUCH_CONSOLE && iOld != IOSTOUCH_CONSOLE) {
    SDL_StartTextInput();
  }
  else if (iOld == IOSTOUCH_CONSOLE && iMode != IOSTOUCH_CONSOLE) {
    SDL_StopTextInput();
  }
}

// The console's iOS keyboard, while the console is open. iOS hides it when
// the app goes to the background (and an iPad's keyboard has a hide key);
// SDL takes that as the end of text input, so nothing brings it back by
// itself. Asked again at most twice a second, and only while the app is in
// front.
static void IOSTouch_KeepConsoleKeyboard(SDL_Window *pWindow)
{
  static double tAsked = 0.0;
  if (_iMode != IOSTOUCH_CONSOLE || SDL_IsScreenKeyboardShown(pWindow)) return;
  if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
  const double now = CACurrentMediaTime();
  if (now - tAsked < 0.5) return;
  tAsked = now;
  SDL_StartTextInput();
}

static int IOSTouch_UpdateOverlay(void *pSDLWindow, int iMode, const IOSTouchHud *pHud, unsigned int ulFramesDrawn)
{
  // what was asked for since the last frame (the game checks it still fits)
  const int iRequests = _iRequests;
  _iRequests = 0;
  _ulFramesDrawn = ulFramesDrawn;

  if (pHud) _hud = *pHud;

  UIView *host = IOSTouch_GetHostView((SDL_Window *)pSDLWindow);
  // the HUD's frame, from the game's view: also while the overlay hides and
  // before it exists
  if (host) {
    const UIEdgeInsets in = host.safeAreaInsets;
    IOSTouch_SetHudFrame(host.bounds.size.width, host.bounds.size.height, in.left, in.top, in.right, in.bottom);
  }
  if (!_pOverlay) {
    if (iMode == IOSTOUCH_HIDDEN || !host) {
      _iMode = IOSTOUCH_HIDDEN;
      return iRequests;
    }
    _pOverlay = [[IOSTouchOverlay alloc] initWithFrame:host.bounds];
    _pOverlay.hidden = YES;
    [host addSubview:_pOverlay];
  }
  else if (host && _pOverlay.superview != host) {
    // SDL's window was recreated (a display mode change): the overlay is
    // still sitting in the old, no longer shown one -- move it across
    [_pOverlay removeFromSuperview];
    _pOverlay.frame = host.bounds;
    [host addSubview:_pOverlay];
    IOSTouch_SetMode(_iMode);
  }

  // keep it on top of anything SDL adds later (its text field, for the keyboard)
  if (_pOverlay.superview && _pOverlay.superview.subviews.lastObject != _pOverlay) {
    [_pOverlay.superview bringSubviewToFront:_pOverlay];
  }

  if (iMode != _iMode) {
    IOSTouch_SetMode(iMode);
  }
  IOSTouch_KeepConsoleKeyboard((SDL_Window *)pSDLWindow);

  if (iMode != IOSTOUCH_HIDDEN) {
    // Turning the phone the other way up changes neither the size nor the
    // insets, but moves the cutout to the other side: lay out again
    if (IOSTouch_CutoutMayBeRight(_pOverlay) != _iLayoutCutoutRight) {
      [_pOverlay setNeedsLayout];
    }
    [_pOverlay tick];
  }

  // Tilt aiming, after the frame's touches came in: only while the overlay
  // is up and the app in front (the samples' side from the screen's)
  const int bHadGyro = IOSTouch_GyroAvailable();
  IOSTouch_GyroFrame(!_pOverlay.hidden && _pOverlay.superview != nil,
                     [UIApplication sharedApplication].applicationState == UIApplicationStateActive,
                     IOSTouch_ScreenSide(_pOverlay), CACurrentMediaTime());
  if (IOSTouch_GyroAvailable() != bHadGyro) {
    [_pOverlay refreshButtonLooks]; // iOS refused the motion data: the tray's GYRO says NO GYRO
  }
  return iRequests;
}

// These two run in the game's own loop, which SDL_main never leaves and
// where no autorelease pool is drained (SDL's event pumping drains only its
// own): each drains what it makes, or it would pile up while the game runs.
int IOSTouch_Update(void *pSDLWindow, int iMode, const IOSTouchHud *pHud, unsigned int ulFramesDrawn)
{
  int iRequests;
  @autoreleasepool {
    iRequests = IOSTouch_UpdateOverlay(pSDLWindow, iMode, pHud, ulFramesDrawn);
  }
  return iRequests;
}

void IOSTouch_Hide(void)
{
  @autoreleasepool {
    if (_iMode != IOSTOUCH_HIDDEN) IOSTouch_SetMode(IOSTOUCH_HIDDEN);
    IOSTouch_GyroRun(0); // no motion updates while loading or in the background
  }
}

#endif // IOSTOUCH_RIG
