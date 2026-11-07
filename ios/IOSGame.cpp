/*
** IOSGame.cpp: the touch controls' game side (see IOSGame.h, IOSTouch.h)
**
** Once a frame it tells the overlay what the game is doing (playing, the
** console, paused, or nothing to show), what the player has for the weapon
** wheel, and carries out what the player asked for (the menu, the console,
** quick save and load, the cheat). In the input it puts the stick, the
** buttons, the look and the tilt aiming straight into the input bits the
** games read, whatever keys are bound.
*/

#include "IOSGame.h"

#include <SDL.h>

#include "gamecontrol.h"
#include "gameinput.h"
#include "inputstate.h"
#include "c_console.h"
#include "c_dispatch.h"
#include "c_cvars.h"
#include "d_event.h"
#include "d_eventbase.h"
#include "menu.h"
#include "mapinfo.h"
#include "filesystem.h"
#include "savegamemanager.h"
#include "cmdlib.h"
#include "printf.h"
#include "keydef.h"
#include "dikeys.h"
#include "gamestate.h"
#include "savegamehelp.h"
#include "i_interface.h"

EXTERN_CVAR(Float, m_sensitivity_x)
EXTERN_CVAR(Float, m_sensitivity_y)
EXTERN_CVAR(Bool, invertmouse)
EXTERN_CVAR(Bool, invertmousex)
EXTERN_CVAR(Int, quicksavenum)

extern TArray<TPointer<MapRecord>> mapList;
extern bool pausedWithKey;
extern int chatmodeon;
extern int gametic;

static const IOSGamePart* Part()
{
	if (isDukeEngine()) return &iosDukePart;
	if (isBlood()) return &iosBloodPart;
	if (isSWALL()) return &iosSWPart;
	if (isExhumed()) return &iosExhumedPart;
	return nullptr;
}

// What the overlay shows: the game being played (no menu, no console, no
// typing a message), the console over it, the game paused with the pause
// key, or nothing (menus, cutscenes, the title screen, loading)
static int TouchMode()
{
	if (gamestate != GS_LEVEL || M_Active()) return IOSTOUCH_HIDDEN;
	if (ConsoleState == c_down || ConsoleState == c_falling) return IOSTOUCH_CONSOLE;
	if (chatmodeon) return IOSTOUCH_HIDDEN;
	if (pausedWithKey) return IOSTOUCH_PAUSED;
	return IOSTOUCH_GAMEPLAY;
}

//---------------------------------------------------------------------------
//
// The cheat's list of levels: the game's own, in their order, the ones
// whose map is there (no user maps)
//
//---------------------------------------------------------------------------

static TArray<MapRecord*> cheatLevels;

static void FindLevels()
{
	cheatLevels.Clear();
	for (auto& map : mapList)
	{
		if (map.Data() == nullptr || (map->flags & MI_USERMAP) || map->levelNumber <= 0 || map->fileName.IsEmpty()) continue;
		if (fileSystem.FindFile(map->fileName.GetChars()) < 0) continue;
		cheatLevels.Push(map.Data());
	}
	// (in the game's order: by episode, then level)
	std::stable_sort(cheatLevels.begin(), cheatLevels.end(), [](MapRecord* a, MapRecord* b) { return a->levelNumber < b->levelNumber; });
}

int IOSGame_LevelInfo(int iLevel, char* strName, int ctName, char* strFile, int ctFile)
{
	if (iLevel < 1 || iLevel > (int)cheatLevels.Size()) return 0;
	auto map = cheatLevels[iLevel - 1];
	snprintf(strName, ctName, "%s", map->DisplayName());
	snprintf(strFile, ctFile, "%s", map->fileName.GetChars());
	return 1;
}

int IOSGame_CurrentLevel()
{
	for (unsigned i = 0; i < cheatLevels.Size(); i++)
	{
		if (cheatLevels[i] == currentLevel) return i + 1;
	}
	return 0;
}

//---------------------------------------------------------------------------
//
// The cheat, on Raze's own: god mode and "give all", again at each new
// level while it is on, and the ammo kept full
//
//---------------------------------------------------------------------------

static bool cheatOn = false;
static MapRecord* cheatLevel = nullptr;
static int cheatLevelCount = 0; // frames into the level (it gives once the level is going)
static int ammoTimer = 0;

static bool CheatAllowed()
{
	return !netgame && gamestate == GS_LEVEL && currentLevel != nullptr && Part() != nullptr;
}

static void CheatGive()
{
	C_DoCommand("godon");
	C_DoCommand("give all");
}

static void CheatFrame()
{
	if (!cheatOn || !CheatAllowed()) return;
	if (cheatLevel != currentLevel)
	{
		cheatLevel = currentLevel;
		cheatLevelCount = 0;
	}
	// a new level (or the same one again, after dying): everything again,
	// once it has run a moment (the player is made as the level starts)
	if (cheatLevelCount >= 0 && ++cheatLevelCount > 10)
	{
		cheatLevelCount = -1;
		CheatGive();
	}
	// the ammo, kept full (a few times a second)
	if (++ammoTimer >= 15)
	{
		ammoTimer = 0;
		auto part = Part();
		if (part && part->FillAmmo && !paused) part->FillAmmo();
	}
}

// The word typed in the console: "sithewok" switches the cheat, "sithewok
// on" / "sithewok off" set it (the overlay says so, and shows or hides CHEAT)
CCMD(sithewok)
{
	bool want = !IOSTouch_CheatOn();
	if (argv.argc() >= 2) want = !stricmp(argv[1], "on");
	if (want != (IOSTouch_CheatOn() != 0)) IOSTouch_CheatTyped();
}

//---------------------------------------------------------------------------
//
// Quick save and quick load: the rotating quick saves (no menu, no
// question), and the newest of them
//
//---------------------------------------------------------------------------

static void QuickSave()
{
	if (!gi->CanSave())
	{
		IOSTouch_ShowMessage("Can't save now", 2.0);
		return;
	}
	C_DoCommand("rotatingquicksave");
	IOSTouch_ShowMessage("Quick save", 1.5);
}

static void QuickLoad()
{
	if (netgame) return;
	auto name = G_BuildSaveName(FStringf("quick%04d", (int)quicksavenum).GetChars());
	if (!FileExists(name))
	{
		IOSTouch_ShowMessage("No quick save yet (hold QUICK SAVE)", 3.0);
		return;
	}
	G_LoadGame(name.GetChars());
	IOSTouch_ShowMessage("Quick load", 1.5);
}

//---------------------------------------------------------------------------
//
// Once a frame
//
//---------------------------------------------------------------------------

static void PostKey(int key)
{
	event_t ev = {};
	ev.type = EV_KeyDown;
	ev.data1 = key;
	D_PostEvent(&ev);
	ev.type = EV_KeyUp;
	D_PostEvent(&ev);
}

static unsigned int worldCount = 0;
static MapRecord* worldLevel = nullptr;
static int worldTic = -1;
static unsigned int framesDrawn = 0;

void IOSGame_Frame()
{
	framesDrawn++;
	const int mode = TouchMode();
	const IOSGamePart* part = Part();

	// a new level, or one loaded: the world changed (a load can bring back
	// the same level, so a jump back in the game's clock counts too)
	if (currentLevel != worldLevel || gametic < worldTic)
	{
		worldLevel = currentLevel;
		worldCount++;
		if (cheatLevels.Size() == 0) FindLevels();
		cheatLevel = nullptr; // (the cheat gives again)
	}
	worldTic = gametic;

	IOSTouchWeapons wpn = {};
	IOSTouchHud hud = {};
	if (mode != IOSTOUCH_HIDDEN && part)
	{
		part->Weapons(&wpn);
		part->State(&hud);
		hud.bValid = 1;
	}
	hud.bNoSaves = !gi->CanSave();
	hud.bCheatAllowed = CheatAllowed();
	if (hud.bCheatAllowed && cheatLevels.Size() == 0) FindLevels();
	hud.ctLevels = hud.bCheatAllowed ? cheatLevels.Size() : 0;
	hud.uWorld = worldCount;
	if (part && part->PickTick) part->PickTick();
	IOSTouch_SetWeapons(&wpn);

	const int req = IOSTouch_Update(SDL_GL_GetCurrentWindow(), mode, &hud, framesDrawn);

	if (req & IOSTOUCH_REQ_MENU)
	{
		if (mode == IOSTOUCH_CONSOLE) C_ToggleConsole();
		else PostKey(KEY_ESCAPE);
	}
	if (req & IOSTOUCH_REQ_CONSOLE) C_ToggleConsole();
	if ((req & IOSTOUCH_REQ_QUICKSAVE) && mode == IOSTOUCH_GAMEPLAY) QuickSave();
	else if ((req & IOSTOUCH_REQ_QUICKLOAD) && mode == IOSTOUCH_GAMEPLAY) QuickLoad();
	if ((req & IOSTOUCH_REQ_RESUME) && pausedWithKey) C_DoCommand("pause");
	if (req & IOSTOUCH_REQ_INVPREV) gameInput.SendAction(SB_INVPREV);
	if (req & IOSTOUCH_REQ_INVNEXT) gameInput.SendAction(SB_INVNEXT);
	if (req & IOSTOUCH_REQ_CHEATON)
	{
		cheatOn = true;
		cheatLevel = nullptr;
	}
	if (req & IOSTOUCH_REQ_CHEATOFF)
	{
		cheatOn = false;
		if (CheatAllowed()) C_DoCommand("godoff");
	}
	if (CheatAllowed())
	{
		if (req & IOSTOUCH_REQ_NOCLIP) C_DoCommand("noclip");
		if (req & IOSTOUCH_REQ_FLY) C_DoCommand("fly");
		if (req & IOSTOUCH_REQ_LEVEL)
		{
			const int i = IOSTouch_TakeLevelPick();
			if (i >= 1 && i <= (int)cheatLevels.Size() && gameaction == ga_nothing)
			{
				// straight there, as the game's own next level (no summary
				// screen, no cutscene; what the player has is kept)
				g_nextmap = cheatLevels[i - 1];
				g_nextskill = -1;
				gameaction = ga_nextlevel;
			}
			else IOSTouch_CheatLevelFailed();
		}
	}
	CheatFrame();
}

//---------------------------------------------------------------------------
//
// The input
//
//---------------------------------------------------------------------------

static bool useWasDown = false;

void IOSGame_Input(float* joyAxes, bool bTic)
{
	const IOSGamePart* part = Part();

	// the stick, as a gamepad's left stick (forward +, the side axis - to the right)
	float mx, my;
	IOSTouch_ReadMove(&mx, &my);
	joyAxes[JOYAXIS_Forward] += my;
	joyAxes[JOYAXIS_Side] -= mx;

	// the look, as the mouse (its sensitivity and invert settings apply)
	float dx, dy;
	IOSTouch_TakeLook(&dx, &dy);
	if (dx != 0.f || dy != 0.f)
	{
		float x = dx * m_sensitivity_x, y = -dy * m_sensitivity_y;
		if (invertmousex) x = -x;
		if (invertmouse) y = -y;
		gameInput.MouseAddToPos(x, y);
	}

	if (!bTic) return;

	IOSTouchInput in;
	IOSTouch_ReadInput(&in);
	ESyncBits actions = ESyncBits::FromInt(0);
	const unsigned b = in.ulButtons;
	if (b & IOSTOUCH_FIRE) actions |= SB_FIRE;
	if (b & IOSTOUCH_JUMP) actions |= SB_JUMP;
	if (b & IOSTOUCH_CROUCH) actions |= SB_CROUCH;
	// USE: held, or one press for the games that take it so
	const bool useDown = (b & IOSTOUCH_USE) != 0;
	if (useDown && (!part || !part->bUseOnce || !useWasDown)) actions |= SB_OPEN;
	useWasDown = useDown;
	if (b & IOSTOUCH_SECONDARY)
	{
		if (isBlood()) actions |= SB_ALTFIRE;
		else if (isDuke() || isNam() || isWW2GI()) actions |= SB_QUICK_KICK;
	}
	if (b & IOSTOUCH_ITEM) actions |= SB_INVUSE;
	if (b & IOSTOUCH_NEXTWEAPON) gameInput.SendWeapon(WeaponSel_Next);
	else if (b & IOSTOUCH_PREVWEAPON) gameInput.SendWeapon(WeaponSel_Prev);
	if (actions) gameInput.SendAction(actions);
	if (in.iSelectWeapon >= 0 && part) part->Pick(in.iSelectWeapon);
}

void IOSGame_TakeGyro(double* pYaw, double* pPitch)
{
	float yaw, pitch;
	IOSTouch_TakeGyro(&yaw, &pitch);
	// (the overlay's + left and + up; the game's + right and + down)
	*pYaw = -yaw;
	*pPitch = -pitch;
}

bool IOSGame_HoldsGame()
{
	return IOSTouch_HoldsGame() != 0;
}

void IOSGame_HudFrame(double w, double h, double* pFrame)
{
	float f[4];
	IOSTouch_GetHudFrame(f);
	pFrame[0] = f[0] * w;
	pFrame[1] = f[1] * h;
	pFrame[2] = f[2] * w;
	pFrame[3] = f[3] * h;
}

#ifndef RAZE_IOS
//---------------------------------------------------------------------------
//
// The Linux test rig's own (RAZE_TOUCH_RIG_SOURCE): a console command from
// its script, and where the player is, for its log
//
//---------------------------------------------------------------------------

extern "C" void IOSGame_RigCommand(const char* cmd)
{
	C_DoCommand(cmd);
}

CCMD(ios_rigpos)
{
	auto pl = PlayerArray[myconnectindex];
	auto act = pl ? pl->GetActor() : nullptr;
	if (!act) return;
	Printf("rigpos tic %d pauseext %d active %d menu %d gs %d %.1f %.1f %.1f yaw %.2f pitch %.2f paused %d level %s\n", gametic, (int)pauseext, (int)AppActive, (int)M_Active(), (int)gamestate, act->spr.pos.X, act->spr.pos.Y, act->spr.pos.Z,
		act->spr.Angles.Yaw.Degrees(), act->spr.Angles.Pitch.Degrees(), paused, currentLevel ? currentLevel->labelName.GetChars() : "-");
}
#endif
