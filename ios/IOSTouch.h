/* On-screen touch controls for iOS, for every game Raze plays (Duke Nukem
   3D, Blood, Shadow Warrior, Redneck Rampage, Exhumed): the controls
   standard of the Jedi Knight and Serious Sam ports, ported from Serious
   Sam's IOSTouch.m.

   A UIKit overlay (IOSTouch.m) sits on top of SDL's game view while a level
   is being played. It turns touches into:
     - a floating move stick under the left thumb (anywhere in the left 42%
       of the screen): analog movement, up the screen is forward
     - drag-to-look anywhere else, fed in as mouse movement (so the game's
       mouse sensitivity and invert settings apply)
     - tilt aiming (MENU's tray's GYRO: OFF, TOUCH, ALWAYS; SENS 1.0x, 1.5x,
       2.0x, 3.0x), straight into the player's view angles
     - buttons. Bottom right: FIRE, with CROUCH / USE / JUMP on an arc
       around it, a secondary button beside FIRE (ALT FIRE in Blood, KICK
       in Duke Nukem 3D, none in the others) and ITEM beside JUMP (uses the
       inventory item the HUD shows; a slide sideways on it picks the
       previous / next item instead). Dragging on FIRE, the arc and the
       secondary button also looks. Top left: NEXT WPN and PREV WPN. Top
       right: QUICK SAVE, QUICK LOAD (0.3 s holds with a ring) and MENU (a
       tap: the game's menu; held 0.45 s: the tray). CAMERA and CHEAT in
       the top row (CAMERA's work is iosCamera.h's; CHEAT shows a picture
       from the game's own art, and a sound of the game's own, its hero's
       line, plays as the cheat comes on).
     - NEXT WPN and PREV WPN: a quick tap is the next / previous weapon; a
       10 pt slide opens the weapon wheel at once, a 0.3 s hold opens it to
       tap. One slice per weapon of the game being played, in its own NEXT
       order, with its picture (from the game's own art, IOSGame.cpp) and
       its ammo, on a wheel with that game's own look. The game holds still
       while it is open.
     - MENU's tray: LOOK, SENS, GYRO, FPS, CAMERA, CHEAT, LEVEL (the cheat
       on), the keyboard (the console, for typing cheats and commands).
   Buttons act on the player directly (the input bits Raze's games read),
   whatever keys are bound. In menus, cutscenes and while a level loads the
   overlay hides and touches reach SDL as mouse clicks.

   Threads: Raze runs its game and its input on the main thread, so every
   call here is the main thread's. */

#ifndef RAZE_IOSTOUCH_H
#define RAZE_IOSTOUCH_H

#ifdef __cplusplus
extern "C" {
#endif

/* What the game is doing (IOSTouch_Update), which decides what shows */
enum {
  IOSTOUCH_HIDDEN = 0, /* menus, cutscenes, loading: touches are mouse clicks */
  IOSTOUCH_GAMEPLAY,   /* a level is being played */
  IOSTOUCH_CONSOLE,    /* the console is open over the game: only MENU (and its tray) */
  IOSTOUCH_PAUSED,     /* the game is paused (the pause key): RESUME and MENU */
};

/* What the game says each frame besides the weapons */
typedef struct IOSTouchHud {
  int bValid;
  int iSecondary;      /* the secondary button: IOSTOUCH_SEC_* */
  int bItem;           /* the game has an inventory item to use (ITEM shows) */
  int bNoSaves;        /* no QUICK SAVE / QUICK LOAD (the game can't save now) */
  int bCheatAllowed;   /* the cheat works here (single player, a level being played, the game's cheats allowed) */
  const char *strCheatRefusal; /* ...and if not, why (a static string, or NULL) */
  int bCanFly;         /* the cheat's fly (Shadow Warrior's) */
  int bNoclip;         /* the game's noclip is on now */
  int bFlying;         /* the game's flying is on now (Shadow Warrior) */
  int ctLevels;        /* the levels the tray's LEVEL lists (0: none) */
  unsigned int uWorld; /* changes with every level started or loaded */
  float afHudFrame[4]; /* (filled by the overlay: IOSTouch_GetHudFrame) */
} IOSTouchHud;

enum { IOSTOUCH_SEC_NONE = 0, IOSTOUCH_SEC_ALTFIRE, IOSTOUCH_SEC_KICK };

/* What the player asked for, carried out by the game (IOSTouch_Update's result) */
enum {
  IOSTOUCH_REQ_MENU      = 1 << 0, /* Escape: the menu (with the console open: just close the console) */
  IOSTOUCH_REQ_CONSOLE   = 1 << 1, /* open or close the console (MENU's tray) */
  IOSTOUCH_REQ_QUICKSAVE = 1 << 2,
  IOSTOUCH_REQ_QUICKLOAD = 1 << 3,
  IOSTOUCH_REQ_RESUME    = 1 << 4, /* unpause */
  IOSTOUCH_REQ_CHEATON   = 1 << 5, /* the cheat came on: god mode on, everything given */
  IOSTOUCH_REQ_CHEATOFF  = 1 << 6, /* the cheat went off: god mode off (what it gave is kept) */
  IOSTOUCH_REQ_LEVEL     = 1 << 7, /* the cheat's list of levels: go to IOSTouch_TakeLevelPick() */
  IOSTOUCH_REQ_NOCLIP    = 1 << 8, /* the cheat: toggle the game's noclip */
  IOSTOUCH_REQ_FLY       = 1 << 9, /* the cheat: toggle flying (Shadow Warrior) */
  IOSTOUCH_REQ_INVPREV   = 1 << 10, /* ITEM slid left: the previous inventory item */
  IOSTOUCH_REQ_INVNEXT   = 1 << 11, /* ITEM slid right: the next one */
};

/* Buttons as the game reads them (IOSTouchInput.ulButtons) */
enum {
  IOSTOUCH_FIRE       = 1 << 0,
  IOSTOUCH_USE        = 1 << 1, /* open / use */
  IOSTOUCH_JUMP       = 1 << 2,
  IOSTOUCH_CROUCH     = 1 << 3,
  IOSTOUCH_NEXTWEAPON = 1 << 4,
  IOSTOUCH_PREVWEAPON = 1 << 5,
  IOSTOUCH_SECONDARY  = 1 << 6, /* ALT FIRE or KICK (IOSTouchHud.iSecondary) */
  IOSTOUCH_ITEM       = 1 << 7, /* use the inventory item (one press per tap) */
  IOSTOUCH_NUMBUTTONS = 8
};
typedef struct IOSTouchInput {
  float fMoveX;           /* move stick: -1..1, right is + */
  float fMoveY;           /* -1..1, forward is + */
  unsigned int ulButtons; /* IOSTOUCH_FIRE... held (or a quick tap) for this read */
  int iSelectWeapon;      /* -1 none, else the wheel's pick (a weapon number of the game's, see IOSTouchWeapons):
                             reported for two reads, then -1 for at least one, never in a read with
                             NEXT/PREV or the read after one */
} IOSTouchInput;

/* The weapon wheel: what the player has, as the game tells it every frame
   (before IOSTouch_Update). Weapon numbers are the game's own (Duke's
   curr_weapon, Blood's curWeapon, ...), 0..IOSTOUCH_WPN_MAX-1. */
#define IOSTOUCH_WPN_MAX 17
enum {
  IOSTOUCH_WHEEL_NONE = 0, /* no wheel (the taps still step through the weapons) */
  IOSTOUCH_WHEEL_DUKE,     /* Duke Nukem 3D (Atomic: + the expander) */
  IOSTOUCH_WHEEL_DUKEWT,   /* Duke Nukem 3D: 20th Anniversary World Tour (+ the incinerator) */
  IOSTOUCH_WHEEL_RR,       /* Redneck Rampage */
  IOSTOUCH_WHEEL_RRRA,     /* Redneck Rampage Rides Again (+ the sling blade and the chicken bow) */
  IOSTOUCH_WHEEL_BLOOD,
  IOSTOUCH_WHEEL_SW,       /* Shadow Warrior */
  IOSTOUCH_WHEEL_EXHUMED,
  IOSTOUCH_WHEEL_NUM
};
typedef struct IOSTouchWeapons {
  int bValid;            /* the player and its weapons exist */
  int bCanSelect;        /* alive, not driving or in a cutscene: it would take a pick now */
  int iMap;              /* IOSTOUCH_WHEEL_*: which game's wheel */
  int iWanted;           /* the weapon in hand, or being switched to */
  unsigned int ulOwned;  /* bit w: weapon w owned */
  unsigned int ulReady;  /* bit w: owned and it has ammo for it -- what the game would switch to */
  int bInfiniteAmmo;     /* no counts shown */
  int aiAmmo[IOSTOUCH_WPN_MAX];     /* the ammo count for weapon w, -1: none to show */
  int aiMaxAmmo[IOSTOUCH_WPN_MAX];
} IOSTouchWeapons;

/* The pictures (IOSGame.cpp makes them from the game's own art, as RGBA,
   not premultiplied, at most IOSTOUCH_ICON_MAX square): the weapons whose
   wheel icon the overlay still wants (bit w; each asked for once, until it
   comes), each one handed over (NULL: there is none, the slice shows the
   name), and CHEAT's (NULL: its drawn emblem stays) */
#define IOSTOUCH_ICON_MAX 128
unsigned int IOSTouch_WantedIcons(void);
void IOSTouch_SetWeaponIcon(int iWeapon, const unsigned char *pubRGBA, int iWidth, int iHeight);
int IOSTouch_WantsCheatIcon(void);
void IOSTouch_SetCheatIcon(const unsigned char *pubRGBA, int iWidth, int iHeight);

/* Once per frame: shows or hides the overlay for iMode, follows the SDL
   window (an SDL_Window *). ulFramesDrawn: the game's count of frames drawn,
   which the FPS readout counts. Returns the IOSTOUCH_REQ_* the player asked
   for since the last call. */
int IOSTouch_Update(void *pSDLWindow, int iMode, const IOSTouchHud *pHud, unsigned int ulFramesDrawn);
/* Where the HUD lays itself out: the screen less its rounded corners, the
   home indicator and a notch, as x0, y0, x1, y1 fractions of the screen. The
   whole screen until IOSTouch_Update has seen SDL's view. */
void IOSTouch_GetHudFrame(float afFrame[4]);
/* Hide now (a level is loading, or the app is going to the background), and
   stop tilt aiming's motion updates; the next update shows it again */
void IOSTouch_Hide(void);
/* Once per game tick: the stick and the buttons. A button tapped too
   quickly for any tick to see it is reported for two reads, then up for
   one. */
void IOSTouch_ReadInput(IOSTouchInput *pInput);
/* The stick alone (any number of times a tick: Raze reads movement every
   frame) */
void IOSTouch_ReadMove(float *pfMoveX, float *pfMoveY);
/* Look movement since the last call, in mouse counts (+x right, +y down) */
void IOSTouch_TakeLook(float *pfDX, float *pfDY);
/* Tilt aiming since the last call, in degrees for the view to turn (+ left)
   and tilt (+ up), straight into the player's view angles */
void IOSTouch_TakeGyro(float *pfYaw, float *pfPitch);

/* Every frame before IOSTouch_Update: what the player has, for the weapon
   wheel. A wheel open while the game couldn't take a pick closes, picking
   nothing. */
void IOSTouch_SetWeapons(const IOSTouchWeapons *pw);
/* Whether the weapon wheel (or the cheat's list of levels) is open in a
   level being played: the game holds still (as under the menu: game sounds
   pause, the music plays on, no "Paused") */
int IOSTouch_HoldsGame(void);
/* The cheat (sithewok): the word typed in the console (it switches the
   cheat on or off), and the level picked (1..ctLevels; 0: none) once
   IOSTOUCH_REQ_LEVEL comes */
void IOSTouch_CheatTyped(void);
int IOSTouch_CheatOn(void);
int IOSTouch_TakeLevelPick(void);
void IOSTouch_CheatLevelFailed(void); /* the level picked couldn't be started */
/* A line of news over the game for fSeconds */
void IOSTouch_ShowMessage(const char *str, double fSeconds);

/* Provided by the game (IOSGame.cpp): the cheat's list of levels (iLevel
   1..ctLevels: its name and its file; 0 if there is none), and the one being
   played (1.., 0: none of them) */
int IOSGame_LevelInfo(int iLevel, char *strName, int ctName, char *strFile, int ctFile);
int IOSGame_CurrentLevel(void);

#ifdef __cplusplus
}
#endif

#endif /* RAZE_IOSTOUCH_H */
