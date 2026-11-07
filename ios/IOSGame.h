/* The touch controls' game side (IOSGame.cpp): what Raze's main loop and
   input call, and what each game's own file (source/games/<game>/src/
   ios_<game>.cpp) tells it about the player. Built with RAZE_TOUCH (the iOS
   app, and the Linux test rig). */
#pragma once

#include "IOSTouch.h"

// Each game's part: the player's weapons for the wheel; a weapon picked on
// the wheel (sent through the game's own weapon selection, gameInput);
// called every frame for picks that take two steps (a weapon's alternate);
// what the HUD struct needs (ITEM, the cheat's noclip and flying); the
// cheat's ammo kept full
struct IOSGamePart
{
	void (*Weapons)(IOSTouchWeapons* pw);
	void (*Pick)(int iWeapon);
	void (*PickTick)();
	void (*State)(IOSTouchHud* pHud);
	void (*FillAmmo)();
	bool bUseOnce;   // the game takes USE as one press (Blood, Exhumed: it clears the open key)
};
extern const IOSGamePart iosDukePart, iosBloodPart, iosSWPart, iosExhumedPart;

// The main loop, once a frame before it draws
void IOSGame_Frame();
// GameInput::getInput: the stick into joyAxes, and the buttons and the
// wheel's pick into the input bits (bTic: the read for a game tick; the
// others, made every frame for smooth turning, only take the stick and the
// look)
void IOSGame_Input(float* joyAxes, bool bTic);
// GameInput::processMovement: tilt aiming, in degrees (+ right, + down: the
// game's own way round)
void IOSGame_TakeGyro(double* pYaw, double* pPitch);
// updatePauseStatus: the game holds still (the weapon wheel or the cheat's
// list of levels is open)
bool IOSGame_HoldsGame();
// The status bar: where the HUD's screen edges are, in pixels of the 2D
// drawer (x0, y0, x1, y1): the screen less its rounded corners, the home
// indicator and a notch
void IOSGame_HudFrame(double w, double h, double* pFrame);
