/* The touch controls' game side (IOSGame.cpp): what Raze's main loop and
   input call, and what each game's own file (source/games/<game>/src/
   ios_<game>.cpp) tells it about the player. Built with RAZE_TOUCH (the iOS
   app, and the Linux test rig). */
#pragma once

#include "IOSTouch.h"

// Each game's part: the player's weapons for the wheel; a weapon picked on
// the wheel (sent through the game's own weapon selection, gameInput);
// called every frame for picks that take two steps (a weapon's alternate);
// what the HUD struct needs (the cheat's noclip and flying); the
// cheat's ammo kept full
struct IOSGamePart
{
	void (*Weapons)(IOSTouchWeapons* pw);
	void (*Pick)(int iWeapon);
	void (*PickTick)();
	void (*State)(IOSTouchHud* pHud);
	void (*FillAmmo)();
	bool bUseOnce;   // the game takes USE as one press (Blood, Exhumed: it clears the open key)
	bool (*Alive)();     // the player is there and alive (a quick save needs that)
	bool (*GodOn)();     // the game's god mode is on
	void (*Reset)();     // a level was started, restarted or loaded: drop what was waiting (a two-step pick)
	// The pictures, from the game's own art (IOSGame.cpp makes icons of
	// them): weapon w's on the wheel, and CHEAT's; each a list of textures
	// to try in order (names, or "#<tile number>"), nullptr-ended (nullptr:
	// none: the wheel shows the name, CHEAT its drawn emblem)
	const char* const* (*Icon)(int iWeapon);
	const char* const* (*CheatIcon)();
	// the game's own line (a voice of its hero) as the cheat comes on
	void (*CheatSound)();
	// The item buttons: the usable items the player has, in the game's
	// order (IOSTouchItems), and each one's picture (by its useitem number,
	// as Icon: names to try in order, nullptr-ended)
	void (*Items)(IOSTouchItems* pItems);
	const char* const* (*ItemIcon)(int iUse);
};
extern const IOSGamePart iosDukePart, iosBloodPart, iosSWPart, iosExhumedPart;

// The main loop, once a frame before it draws
void IOSGame_Frame();
// GameTicker's ga_level: a level was started, restarted or loaded
void IOSGame_LevelStarted();
// GameInput::getInput: the stick into joyAxes, and the buttons and the
// wheel's pick into the input bits (bTic: the read for a game tick; the
// others, made every frame for smooth turning, only take the stick and the
// look)
void IOSGame_Input(float* joyAxes, bool bTic);
// GameInput::processMovement: tilt aiming, in degrees (+ right, + down: the
// game's own way round): what IOSGame_Input took this read (taken every
// read, so what isn't used -- paused, a vehicle -- is dropped, not kept)
void IOSGame_TakeGyro(double* pYaw, double* pPitch);
// updatePauseStatus: the game holds still (the weapon wheel or the cheat's
// list of levels is open)
bool IOSGame_HoldsGame();
// The status bar: where the HUD's screen edges are, in pixels of the 2D
// drawer (x0, y0, x1, y1): the screen less its rounded corners, the home
// indicator and a notch
void IOSGame_HudFrame(double w, double h, double* pFrame);

// The touch HUD (MENU's tray's HUD; IOSTouch_GetHudLayout) for the status
// bars' ZScript (Raze.IOSHud, statusbar2.cpp): 0 the style
// (IOSTOUCH_HUD_*), 1 the face on, then in the 2D drawer's pixels (w x h): 2
// a pill's height, 3 the pills' bottom, 4 and 5 SPLIT's outer edges, 6
// STRIP's widest half; 7 how strongly the HUD shows (0.2..1: OPACITY's HUD
// slider); 8 and 9 where the game's messages start (top, left: below the
// top row of buttons)
double IOSGame_HudValue(int which, double w, double h);
// Where the game's messages start, in the units of a vw x vh virtual screen
// drawn scaled to the screen's height (FSMode_ScaleToHeight, kept in ratio:
// x = 0 at the screen's left edge, its pixels 1.2 times as tall as wide): x
// at NEXT WPN's left edge, y below the top row of buttons
void IOSGame_MessagePlace(double vw, double vh, double* pX, double* pY);
