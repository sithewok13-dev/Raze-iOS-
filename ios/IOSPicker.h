// The game picker (ios/IOSPicker.mm): a card for each main game found, held
// 0.5 s (a ring) for its add-ons; and "Switch game" from MENU's tray, which
// closes the app with a notification to tap to start the game picked.
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef struct
{
	const char* name;	// as Raze names it ("Duke Nukem 3D: Atomic Edition")
	const char* file;	// its main file, the full path (tells it apart at the next start)
	int bAddon;		// an add-on: shown under its main game (iBase)
	int iBase;		// the main game it adds to (-1: none found)
	int flags;		// GAMEFLAG_* (the game's family: colours and emblem)
} IOSPickEntry;

#define IOSPICKER_LAN (-2)	// "LAN multiplayer" tapped

// The games found this run (copied), and the one played last (-1: none)
void IOSPicker_SetEntries(const IOSPickEntry* aEntries, int ctEntries, int iLast);
// The game picked with "Switch game" before the app closed, if it was in the
// last 10 minutes and is still there; -1 otherwise. Clears the notification.
int IOSPicker_TakeNext(void);
// LAN multiplayer was picked in "Switch game" before the app closed: the
// start picker goes straight to its questions (once)
int IOSPicker_StartsWithLan(void);
// At start: the picker until a game is picked (a card a family: Duke, Blood,
// Redneck, Shadow Warrior, PowerSlave; held, its other games and add-ons). Returns its index, or
// IOSPICKER_LAN (bLan: the button shows), or -1 if it couldn't be shown.
int IOSPicker_Run(int bLan);
// The start picker away (after LAN multiplayer's questions: it stays up under
// them; IOSPicker_Run takes it away itself otherwise)
void IOSPicker_Close(void);
// The start picker up without waiting for a pick (under LAN multiplayer's
// questions after "Switch game"); IOSPicker_Run then takes the pick
void IOSPicker_Show(int bLan);
// "Switch game" over the game being played. Cancel: pfnDone(0). A pick (a
// game, or LAN multiplayer, asked at the next start): the settings are
// written, the pick kept and the app closes (with a "Tap to start"
// notification); pfnDone isn't called.
void IOSPicker_PresentSwitch(void (*pfnDone)(int bPicked));

#ifdef __cplusplus
}
#endif
