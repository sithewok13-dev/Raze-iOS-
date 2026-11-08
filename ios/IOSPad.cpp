/* Game controllers on iOS. See IOSPad.h. */

#include <math.h>
#include <SDL.h>

#include "IOSPad.h"
#include "IOSTouch.h"

#include "basics.h"
#include "cmdlib.h"
#include "m_joy.h"
#include "keydef.h"
#include "c_bind.h"
#include "c_cvars.h"
#include "c_console.h"
#include "c_dispatch.h"
#include "d_event.h"
#include "d_eventbase.h"
#include "d_gui.h"
#include "menu.h"
#include "printf.h"
#include "gamecontrol.h"
#include "i_interface.h"

// Turning speeds up while the look stick is held right over: past
// IOSPAD_ACCEL_PUSH for IOSPAD_ACCEL_DELAY s, then up to 1 + IOSPAD_ACCEL_GAIN
// times as fast over IOSPAD_ACCEL_RAMP s (the Jedi Knight port's values)
CVARD(Bool, ios_padaccel, true, CVAR_ARCHIVE | CVAR_GLOBALCONFIG, "game controller: turning speeds up while the look stick is held right over")
// The look stick's response: its push (past the dead zone) to this power
// (1 linear; the Jedi Knight port's SMOOTH, its default, 1.6)
CVARD(Float, ios_padcurve, 1.6f, CVAR_ARCHIVE | CVAR_GLOBALCONFIG, "game controller: the look stick's response curve (1: linear)")
// Once: the joystick turned on (the engine's default is off, and earlier
// builds saved that)
CVAR(Int, ios_padsetup, 0, CVAR_ARCHIVE | CVAR_GLOBALCONFIG | CVAR_NOSET)

#define IOSPAD_ACCEL_PUSH 0.9f
#define IOSPAD_ACCEL_DELAY 0.2
#define IOSPAD_ACCEL_RAMP 0.4
#define IOSPAD_ACCEL_GAIN 0.8f
#define IOSPAD_STICK_OUTER 0.95f  // a stick this far over is full
#define IOSPAD_STICK_KEYS 0.5f    // a stick this far over presses its direction's key (LStickUp...: the menus)
#define IOSPAD_TRIGGER_DOWN 0.3f  // a trigger is down from here...
#define IOSPAD_TRIGGER_UP 0.2f    // ...until back under here
#define IOSPAD_ACTIVE_PUSH 0.3f   // a stick or trigger pushed past this: the pad is being played
#define IOSPAD_BACK_HOLD 0.3      // Back held this long in a level: quick save (as QUICK SAVE's hold)

enum { AX_LX, AX_LY, AX_RX, AX_RY, AX_LT, AX_RT, NUM_AX };

static const char* const axisNames[NUM_AX] = {
	"Left Stick X", "Left Stick Y", "Right Stick X", "Right Stick Y", "Left Trigger", "Right Trigger"
};
static const SDL_GameControllerAxis sdlAxes[NUM_AX] = {
	SDL_CONTROLLER_AXIS_LEFTX, SDL_CONTROLLER_AXIS_LEFTY, SDL_CONTROLLER_AXIS_RIGHTX, SDL_CONTROLLER_AXIS_RIGHTY,
	SDL_CONTROLLER_AXIS_TRIGGERLEFT, SDL_CONTROLLER_AXIS_TRIGGERRIGHT
};
// Dead zone, game axis, scale. At full push the view turns Raze's
// running keyboard speed (about 270 degrees a second) times the scale.
static const struct { float deadZone; EJoyAxis map; float scale; } axisDefaults[NUM_AX] = {
	{ 0.15f, JOYAXIS_Side, 1.f },
	{ 0.15f, JOYAXIS_Forward, 1.f },
	{ 0.12f, JOYAXIS_Yaw, 0.6f },
	{ 0.12f, JOYAXIS_Pitch, 0.4f },
	{ 0.1f, JOYAXIS_None, 1.f },
	{ 0.1f, JOYAXIS_None, 1.f },
};

// The pad buttons, as the engine's keys (Start is the menu's, below)
static int KeyOfButton(int b)
{
	switch (b)
	{
	case SDL_CONTROLLER_BUTTON_A: return KEY_PAD_A;
	case SDL_CONTROLLER_BUTTON_B: return KEY_PAD_B;
	case SDL_CONTROLLER_BUTTON_X: return KEY_PAD_X;
	case SDL_CONTROLLER_BUTTON_Y: return KEY_PAD_Y;
	case SDL_CONTROLLER_BUTTON_BACK: return KEY_PAD_BACK;
	case SDL_CONTROLLER_BUTTON_LEFTSTICK: return KEY_PAD_LTHUMB;
	case SDL_CONTROLLER_BUTTON_RIGHTSTICK: return KEY_PAD_RTHUMB;
	case SDL_CONTROLLER_BUTTON_LEFTSHOULDER: return KEY_PAD_LSHOULDER;
	case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: return KEY_PAD_RSHOULDER;
	case SDL_CONTROLLER_BUTTON_DPAD_UP: return KEY_PAD_DPAD_UP;
	case SDL_CONTROLLER_BUTTON_DPAD_DOWN: return KEY_PAD_DPAD_DOWN;
	case SDL_CONTROLLER_BUTTON_DPAD_LEFT: return KEY_PAD_DPAD_LEFT;
	case SDL_CONTROLLER_BUTTON_DPAD_RIGHT: return KEY_PAD_DPAD_RIGHT;
	default: return 0;
	}
}

static void PostKey(int key, bool down)
{
	event_t ev = {};
	ev.type = down ? EV_KeyDown : EV_KeyUp;
	ev.data1 = key;
	D_PostEvent(&ev);
}

//---------------------------------------------------------------------------
//
// The controller settings (one for every pad) and what the pads are doing
//
//---------------------------------------------------------------------------

class IOSPadConfig : public IJoystickConfig
{
public:
	struct Axis
	{
		float deadZone, scale;
		EJoyAxis map;
		float value;
	};
	Axis axes[NUM_AX];
	float sensitivity = 1.f;
	bool enabled = true;
	FString name;

	IOSPadConfig() { SetDefaultConfig(); }

	FString GetName() override { return name.IsEmpty() ? FString("Game controller (none connected)") : name; }
	float GetSensitivity() override { return sensitivity; }
	void SetSensitivity(float scale) override { sensitivity = scale; }
	int GetNumAxes() override { return NUM_AX; }
	float GetAxisDeadZone(int axis) override { return axes[axis].deadZone; }
	EJoyAxis GetAxisMap(int axis) override { return axes[axis].map; }
	const char* GetAxisName(int axis) override { return axisNames[axis]; }
	float GetAxisScale(int axis) override { return axes[axis].scale; }
	void SetAxisDeadZone(int axis, float zone) override { axes[axis].deadZone = clamp(zone, 0.f, 0.9f); }
	void SetAxisMap(int axis, EJoyAxis gameaxis) override { axes[axis].map = gameaxis; }
	void SetAxisScale(int axis, float scale) override { axes[axis].scale = scale; }
	bool GetEnabled() override { return enabled; }
	void SetEnabled(bool on) override { enabled = on; }
	bool AllowsEnabledInBackground() override { return false; }
	bool GetEnabledInBackground() override { return false; }
	void SetEnabledInBackground(bool) override {}
	bool IsSensitivityDefault() override { return sensitivity == 1.f; }
	bool IsAxisDeadZoneDefault(int axis) override { return axes[axis].deadZone == axisDefaults[axis].deadZone; }
	bool IsAxisMapDefault(int axis) override { return axes[axis].map == axisDefaults[axis].map; }
	bool IsAxisScaleDefault(int axis) override { return axes[axis].scale == axisDefaults[axis].scale; }
	void SetDefaultConfig() override
	{
		for (int i = 0; i < NUM_AX; i++)
		{
			axes[i].deadZone = axisDefaults[i].deadZone;
			axes[i].map = axisDefaults[i].map;
			axes[i].scale = axisDefaults[i].scale;
			axes[i].value = 0.f;
		}
		sensitivity = 1.f;
	}
	FString GetIdentifier() override { return "IOSPad"; }
};

static IOSPadConfig* padConfig;
static bool padConfigLoaded;
static TArray<SDL_GameController*> pads;

static struct
{
	int stickKeys[2];      // LStick*/RStick* keys down (Joy_XYAxesToButtons bits)
	int triggerKeys[2];    // LTrigger, RTrigger down
	bool pushed[4];        // the sticks and triggers over IOSPAD_ACTIVE_PUSH (the pad played: the touch controls hide)
	double accelHeld;      // how long the look stick has been held right over (s)
	uint64_t lastTicks;
	// Back: in a level its press waits (a tap is its binding, the automap;
	// held, quick save or load)
	bool backDown, backUsed, backPassed;
	uint64_t backTicks;
	bool startDown;
	bool startEscapeGui;  // Start's Escape went to the menus (a GUI key)
} pad;

static IOSPadConfig* Config()
{
	if (!padConfig) padConfig = new IOSPadConfig;
	if (!padConfigLoaded && sysCallbacks.GetConfig && sysCallbacks.GetConfig())
	{
		// (the settings are read once the config file is there)
		padConfigLoaded = true;
		M_LoadJoystickConfig(padConfig);
	}
	return padConfig;
}

static void PadPlayed()
{
	IOSTouch_SetPadHidden(1);
}

// Every key the pad holds let go (the last pad gone, the joystick turned off)
static void ReleaseAll()
{
	for (int s = 0; s < 2; s++)
	{
		Joy_GenerateButtonEvents(pad.stickKeys[s], 0, 4, s ? KEY_PAD_RTHUMB_RIGHT : KEY_PAD_LTHUMB_RIGHT);
		pad.stickKeys[s] = 0;
		if (pad.triggerKeys[s]) PostKey(s ? KEY_PAD_RTRIGGER : KEY_PAD_LTRIGGER, false);
		pad.triggerKeys[s] = 0;
	}
	for (int b = 0; b < SDL_CONTROLLER_BUTTON_MAX; b++)
	{
		const int key = KeyOfButton(b);
		if (key && key != KEY_PAD_BACK) PostKey(key, false);
	}
	if (pad.backDown && pad.backPassed) PostKey(KEY_PAD_BACK, false);
	pad.backDown = false;
	if (pad.startDown && !pad.startEscapeGui) PostKey(KEY_ESCAPE, false);
	pad.startDown = false;
	if (padConfig)
	{
		for (auto& a : padConfig->axes) a.value = 0.f;
	}
}

static void UpdateName()
{
	auto c = Config();
	c->name = "";
	for (auto g : pads)
	{
		const char* n = SDL_GameControllerName(g);
		if (!c->name.IsEmpty()) c->name += ", ";
		c->name += n ? n : "Game controller";
	}
}

static void OpenPad(int deviceIndex)
{
	if (!SDL_IsGameController(deviceIndex)) return;
	const SDL_JoystickID id = SDL_JoystickGetDeviceInstanceID(deviceIndex);
	for (auto g : pads)
	{
		if (SDL_JoystickInstanceID(SDL_GameControllerGetJoystick(g)) == id) return; // (already open)
	}
	SDL_GameController* g = SDL_GameControllerOpen(deviceIndex);
	if (!g) return;
	pads.Push(g);
	UpdateName();
	const char* n = SDL_GameControllerName(g);
	Printf(PRINT_MEDIUM | PRINT_NOTIFY, "Controller connected: %s\n", n ? n : "game controller");
	event_t ev = { EV_DeviceChange };
	D_PostEvent(&ev);
}

static void ClosePad(SDL_JoystickID id)
{
	for (unsigned i = 0; i < pads.Size(); i++)
	{
		if (SDL_JoystickInstanceID(SDL_GameControllerGetJoystick(pads[i])) != id) continue;
		const char* n = SDL_GameControllerName(pads[i]);
		Printf(PRINT_MEDIUM | PRINT_NOTIFY, "Controller disconnected: %s\n", n ? n : "game controller");
		SDL_GameControllerClose(pads[i]);
		pads.Delete(i);
		UpdateName();
		if (pads.Size() == 0)
		{
			ReleaseAll();
			IOSTouch_SetPadHidden(0); // (the touch controls back)
		}
		event_t ev = { EV_DeviceChange };
		D_PostEvent(&ev);
		return;
	}
}

static bool OurPad(SDL_JoystickID id)
{
	for (auto g : pads)
	{
		if (SDL_JoystickInstanceID(SDL_GameControllerGetJoystick(g)) == id) return true;
	}
	return false;
}

//---------------------------------------------------------------------------
//
// Start: the menu, as Escape
//
//---------------------------------------------------------------------------

static void StartPressed()
{
	pad.startDown = true;
	pad.startEscapeGui = false;
	if (ConsoleState == c_down || ConsoleState == c_falling)
	{
		C_ToggleConsole();
		pad.startEscapeGui = true; // (nothing to let go)
		return;
	}
	if (M_Active())
	{
		// the menus take Escape as a GUI key (back, and out of the top one)
		event_t ev = {};
		ev.type = EV_GUI_Event;
		ev.subtype = EV_GUI_KeyDown;
		ev.data1 = GK_ESCAPE;
		D_PostEvent(&ev);
		ev.subtype = EV_GUI_KeyUp;
		D_PostEvent(&ev);
		pad.startEscapeGui = true;
		return;
	}
	PostKey(KEY_ESCAPE, true);
}

static void StartReleased()
{
	if (pad.startDown && !pad.startEscapeGui) PostKey(KEY_ESCAPE, false);
	pad.startDown = false;
}

// Every setting written to the config file now (the game runs on)
static void WriteSettings()
{
	extern void G_WriteConfigNow();
	if (padConfig && padConfigLoaded) M_SaveJoystickConfig(padConfig);
	G_WriteConfigNow();
}

CCMD(ios_writeconfig)
{
	WriteSettings();
}

//---------------------------------------------------------------------------
//
// SDL's events
//
//---------------------------------------------------------------------------

bool IOSPad_Event(const SDL_Event& ev)
{
	switch (ev.type)
	{
	case SDL_CONTROLLERDEVICEADDED:
		OpenPad(ev.cdevice.which);
		return true;
	case SDL_CONTROLLERDEVICEREMOVED:
		ClosePad(ev.cdevice.which);
		return true;
	case SDL_CONTROLLERDEVICEREMAPPED:
		return true;

	case SDL_CONTROLLERBUTTONDOWN:
	case SDL_CONTROLLERBUTTONUP:
	{
		if (!OurPad(ev.cbutton.which)) return true;
		const bool down = ev.type == SDL_CONTROLLERBUTTONDOWN;
		if (!use_joystick || !Config()->enabled)
		{
			// (off: only let go what was down)
			if (!down) ReleaseAll();
			return true;
		}
		if (down) PadPlayed();
		const int b = ev.cbutton.button;
		if (b == SDL_CONTROLLER_BUTTON_START)
		{
			if (down && !pad.startDown) StartPressed();
			else if (!down) StartReleased();
			return true;
		}
		const int key = KeyOfButton(b);
		if (key == 0) return true;
		if (key == KEY_PAD_BACK)
		{
			if (down)
			{
				if (pad.backDown) return true;
				pad.backDown = true;
				pad.backUsed = false;
				pad.backTicks = SDL_GetTicks64();
				// outside a level (the menus: binding a key) it goes at once
				pad.backPassed = !IOSGame_PadInLevel();
				if (pad.backPassed) PostKey(KEY_PAD_BACK, true);
			}
			else if (pad.backDown)
			{
				pad.backDown = false;
				if (pad.backPassed) PostKey(KEY_PAD_BACK, false);
				else if (!pad.backUsed)
				{
					// a tap: what Back is bound to
					PostKey(KEY_PAD_BACK, true);
					PostKey(KEY_PAD_BACK, false);
				}
			}
			return true;
		}
		PostKey(key, down);
		return true;
	}

	case SDL_CONTROLLERAXISMOTION:
		return true; // (read each frame, I_ProcessJoysticks)

	// the raw joystick events of a pad (they would be keys of their own, JOY1...)
	case SDL_JOYAXISMOTION:
	case SDL_JOYBALLMOTION:
	case SDL_JOYHATMOTION:
	case SDL_JOYBUTTONDOWN:
	case SDL_JOYBUTTONUP:
	case SDL_JOYDEVICEADDED:
	case SDL_JOYDEVICEREMOVED:
	case SDL_JOYBATTERYUPDATED:
		return true;

#ifdef RAZE_IOS
	case SDL_APP_DIDENTERBACKGROUND:
		// iOS may end the app from the background without a word: the
		// settings (the controller's among them) are written now
		WriteSettings();
		return false; // (i_input.cpp has its own work to do on it)
#endif
	}
	return false;
}

//---------------------------------------------------------------------------
//
// Once a frame: the sticks and the triggers
//
//---------------------------------------------------------------------------

static void ProcessPads()
{
	auto c = Config();
	const uint64_t now = SDL_GetTicks64();
	const double dt = pad.lastTicks ? clamp((now - pad.lastTicks) / 1000.0, 0.0, 0.1) : 0.0;
	pad.lastTicks = now;

	// each axis from the pad pushing it furthest
	float raw[NUM_AX] = {};
	for (auto g : pads)
	{
		for (int a = 0; a < NUM_AX; a++)
		{
			const float v = clamp(SDL_GameControllerGetAxis(g, sdlAxes[a]) / 32767.f, -1.f, 1.f);
			if (fabsf(v) > fabsf(raw[a])) raw[a] = v;
		}
	}

	bool played = false;
	for (int s = 0; s < 2; s++)
	{
		auto& ax = c->axes[2 * s];
		auto& ay = c->axes[2 * s + 1];
		const float x = raw[2 * s], y = raw[2 * s + 1];
		const float m = sqrtf(x * x + y * y);
		const float dz = max(ax.deadZone, ay.deadZone);
		float k = 0.f; // what the push comes to, over the distance it went
		if (m > dz)
		{
			float p = (min(m, IOSPAD_STICK_OUTER) - dz) / (IOSPAD_STICK_OUTER - dz);
			p = clamp(p, 0.f, 1.f);
			if (s == 1 && ios_padcurve > 0.f) p = powf(p, (float)ios_padcurve);
			k = p / m;
		}
		ax.value = x * k;
		ay.value = y * k;

		// the look stick right over: turning speeds up
		if (s == 1)
		{
			if (ios_padaccel && m >= IOSPAD_ACCEL_PUSH) pad.accelHeld += dt;
			else pad.accelHeld = 0.0;
			const double t = pad.accelHeld - IOSPAD_ACCEL_DELAY;
			if (t > 0) ax.value *= 1.f + IOSPAD_ACCEL_GAIN * (float)min(t / IOSPAD_ACCEL_RAMP, 1.0);
		}

		const int keys = m >= IOSPAD_STICK_KEYS ? Joy_XYAxesToButtons(x, y) : 0;
		Joy_GenerateButtonEvents(pad.stickKeys[s], keys, 4, s ? KEY_PAD_RTHUMB_RIGHT : KEY_PAD_LTHUMB_RIGHT);
		pad.stickKeys[s] = keys;

		const bool pushed = m >= IOSPAD_ACTIVE_PUSH;
		if (pushed && !pad.pushed[s]) played = true;
		pad.pushed[s] = pushed;
	}
	for (int t = 0; t < 2; t++)
	{
		auto& a = c->axes[AX_LT + t];
		const float v = max(raw[AX_LT + t], 0.f);
		a.value = v > a.deadZone ? (v - a.deadZone) / (1.f - a.deadZone) : 0.f;
		const int down = pad.triggerKeys[t] ? v >= IOSPAD_TRIGGER_UP : v >= IOSPAD_TRIGGER_DOWN;
		if (down != pad.triggerKeys[t])
		{
			PostKey(t ? KEY_PAD_RTRIGGER : KEY_PAD_LTRIGGER, down);
			pad.triggerKeys[t] = down;
		}
		const bool pushed = v >= IOSPAD_ACTIVE_PUSH;
		if (pushed && !pad.pushed[2 + t]) played = true;
		pad.pushed[2 + t] = pushed;
	}
	if (played) PadPlayed();

	// Back held in a level: quick save (D-pad down held too: quick load)
	if (pad.backDown && !pad.backPassed && !pad.backUsed && (now - pad.backTicks) >= IOSPAD_BACK_HOLD * 1000)
	{
		pad.backUsed = true;
		if (!IOSGame_PadInLevel()) return;
		bool load = false;
		for (auto g : pads)
		{
			if (SDL_GameControllerGetButton(g, SDL_CONTROLLER_BUTTON_DPAD_DOWN)) load = true;
		}
		if (load) IOSGame_PadQuickLoad();
		else IOSGame_PadQuickSave();
		for (auto g : pads) SDL_GameControllerRumble(g, 0x6000, 0x6000, 120);
	}
}

//---------------------------------------------------------------------------
//
// What the engine asks of the platform's joystick code (i_joystick.cpp's,
// which isn't built with RAZE_TOUCH)
//
//---------------------------------------------------------------------------

void I_StartupJoysticks()
{
	if (SDL_InitSubSystem(SDL_INIT_JOYSTICK | SDL_INIT_GAMECONTROLLER) < 0)
	{
		Printf("Game controllers: %s\n", SDL_GetError());
		return;
	}
	SDL_GameControllerEventState(SDL_ENABLE);
	// the pads there now (SDL also sends their DEVICEADDED: opened once)
	for (int i = 0; i < SDL_NumJoysticks(); i++) OpenPad(i);
}

void I_ShutdownInput()
{
	if (padConfig && padConfigLoaded) M_SaveJoystickConfig(padConfig);
	for (auto g : pads) SDL_GameControllerClose(g);
	pads.Clear();
	SDL_QuitSubSystem(SDL_INIT_GAMECONTROLLER | SDL_INIT_JOYSTICK);
}

void I_GetJoysticks(TArray<IJoystickConfig*>& sticks)
{
	sticks.Clear();
	sticks.Push(Config());
}

void I_GetAxes(float axes[NUM_JOYAXIS])
{
	for (int i = 0; i < NUM_JOYAXIS; ++i) axes[i] = 0;
	if (!use_joystick || pads.Size() == 0) return;
	auto c = Config();
	if (!c->enabled) return;
	for (auto& a : c->axes)
	{
		if (a.map != JOYAXIS_None) axes[a.map] -= a.value * c->sensitivity * a.scale;
	}
}

void I_ProcessJoysticks()
{
	if (!use_joystick || pads.Size() == 0) return;
	if (!Config()->enabled) return;
	ProcessPads();
}

IJoystickConfig* I_UpdateDeviceList()
{
	return Config();
}

//---------------------------------------------------------------------------
//
// The default bindings
//
//---------------------------------------------------------------------------

struct PadBind { int key; const char* cmd; };

// The engine's own (engine/commonbinds.txt), which earlier builds saved for
// every game. Several name commands Raze doesn't have (+attack...).
static const PadBind oldDefaults[] = {
	{ KEY_PAD_A, "+open" }, { KEY_PAD_Y, "+jump" }, { KEY_PAD_RTRIGGER, "+attack" }, { KEY_PAD_LTRIGGER, "+altattack" },
	{ KEY_PAD_LSHOULDER, "weapprev" }, { KEY_PAD_RSHOULDER, "weapnext" }, { KEY_PAD_DPAD_LEFT, "invprev" },
	{ KEY_PAD_DPAD_RIGHT, "invnext" }, { KEY_PAD_DPAD_DOWN, "invuse" }, { KEY_PAD_DPAD_UP, "togglemap" },
	{ KEY_PAD_START, "pause" }, { KEY_PAD_BACK, "menu_main" }, { KEY_PAD_LTHUMB, "crouch" },
};

// Every pad key the defaults decide
static const int padKeys[] = {
	KEY_PAD_A, KEY_PAD_B, KEY_PAD_X, KEY_PAD_Y, KEY_PAD_LSHOULDER, KEY_PAD_RSHOULDER, KEY_PAD_LTRIGGER, KEY_PAD_RTRIGGER,
	KEY_PAD_DPAD_UP, KEY_PAD_DPAD_DOWN, KEY_PAD_DPAD_LEFT, KEY_PAD_DPAD_RIGHT, KEY_PAD_START, KEY_PAD_BACK,
	KEY_PAD_LTHUMB, KEY_PAD_RTHUMB,
};

static const char* LeftTriggerCommand()
{
	if (isBlood()) return "+Alt_Fire";
	if (isDukeLike()) return "+Quick_Kick"; // (Duke Nukem 3D and its add-ons, NAM, WWII GI, Redneck Rampage)
	return "";
}

void IOSPad_DefaultBinds()
{
	const PadBind binds[] = {
		{ KEY_PAD_RTRIGGER, "+Fire" },
		{ KEY_PAD_LTRIGGER, LeftTriggerCommand() },
		{ KEY_PAD_RSHOULDER, "weapnext" },
		{ KEY_PAD_LSHOULDER, "weapprev" },
		{ KEY_PAD_A, "+Jump" },
		{ KEY_PAD_B, "+Crouch" },
		{ KEY_PAD_X, "+Open" },
		{ KEY_PAD_Y, "invuse" },
		{ KEY_PAD_DPAD_LEFT, "invprev" },
		{ KEY_PAD_DPAD_RIGHT, "invnext" },
		{ KEY_PAD_DPAD_UP, "centerview" },
		{ KEY_PAD_DPAD_DOWN, "turnaround" },
		{ KEY_PAD_BACK, "togglemap" },
		{ KEY_PAD_START, "" }, // (the menu, IOSPad_Event)
		{ KEY_PAD_LTHUMB, "toggle cl_autorun" },
		{ KEY_PAD_RTHUMB, "third_person_view" },
	};
	for (auto& b : binds) Bindings.SetBind(b.key, b.cmd, true);
}

static void IOSPad_Setup();

void IOSPad_UpgradeBinds()
{
	IOSPad_Setup();
	for (int key : padKeys)
	{
		const char* old = "";
		for (auto& b : oldDefaults)
		{
			if (b.key == key) old = b.cmd;
		}
		if (Bindings.GetBinding(key).CompareNoCase(old) != 0) return; // (changed: kept)
	}
	IOSPad_DefaultBinds();
	Printf("Game controller: this build's default bindings\n");
}

//---------------------------------------------------------------------------
//
// The joystick on, once (the engine's default is off)
//
//---------------------------------------------------------------------------

CCMD(ios_padinfo)
{
	Printf("use_joystick %d, %u controller(s): %s\n", (int)use_joystick, pads.Size(), Config()->GetName().GetChars());
}

// (after the config is read: IOSPad_UpgradeBinds)
static void IOSPad_Setup()
{
	if (ios_padsetup >= 1) return;
	use_joystick = true;
	UCVarValue val;
	val.Int = 1;
	ios_padsetup->ForceSet(val, CVAR_Int);
}
