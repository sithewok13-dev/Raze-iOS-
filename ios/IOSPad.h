/* Game controllers on iOS (Xbox, PlayStation, Backbone-style and the other
   pads Apple's GameController framework knows, through SDL's MFi driver),
   for every game Raze plays. Built with RAZE_TOUCH (the iOS app and the
   Linux test rig), in place of the SDL backend's own joystick code
   (i_joystick.cpp, which reads raw joysticks with no buttons layout).

   A pad goes through the engine's own controls, so Options > Controls
   (rebinding) and Options > Controller (sensitivity, invert, dead zones)
   change it, and the menus take it as they do any gamepad:
     - the sticks are read as SDL's game controller axes: the left one
       moves and strafes, the right one looks (a round dead zone, the rest
       of the push rescaled to reach full; the look stick through a
       response curve, and turning speeds up while it is held right over,
       ios_padaccel); the triggers and the sticks' directions also act as
       keys (RTrigger, LTrigger, LStickUp...), which is what the menus
       move with
     - the buttons are the engine's pad keys (Pad_A, LShoulder, DPadUp...)
       and do what they are bound to. The defaults (IOSPad_DefaultBinds),
       every game:
         RT fire                        LT kick (Duke Nukem 3D, Redneck
                                           Rampage), alt fire (Blood);
                                           nothing in the others
         RB next weapon, LB previous     A jump, B crouch, X use (open),
                                           Y use the inventory item
         D-pad left / right: previous / next inventory item,
           up: centre the view, down: turn around
         L3 run / walk (autorun on or off), R3 third person view
         Back (View, Share, -): a tap: the automap; held 0.3 s in a
           level: quick save (with D-pad down held too: quick load)
         Start (Menu, Options, +): the game's menu, as Escape (not a
           binding: it also closes the menus and the console)
   The touch controls hide while a pad is played and come back at a
   touch (which does nothing else) or when the last pad goes. Pads can come
   and go at any time. One set of controller settings ("Game controller")
   is kept for every pad, also while none is connected. */

#pragma once

#include <SDL.h>

// i_input.cpp's MessagePump, every SDL event first: true if the pad took it
// (pads coming and going, their buttons; the raw joystick events of pads)
bool IOSPad_Event(const SDL_Event& ev);

// c_bind.cpp's C_SetDefaultKeys: the default pad bindings for the game
// being played, over the engine's common ones
void IOSPad_DefaultBinds();

// gameconfigfile.cpp's DoKeySetup, after a game's bindings are read: a
// game whose pad bindings are still all the engine's old defaults (as every
// earlier build saved them) gets this build's defaults; any changed, kept
void IOSPad_UpgradeBinds();

// IOSGame.cpp: the game side of the pad's quick save and quick load
// (the touch controls' own), and whether a level is being played
void IOSGame_PadQuickSave();
void IOSGame_PadQuickLoad();
bool IOSGame_PadInLevel();
