# Raze for iOS: notes for Claude Code sessions

An unofficial iPhone/iPad build of Raze playing the Build engine games:
Duke Nukem 3D (Atomic, World Tour, add-ons), Redneck Rampage (and Rides
Again), Blood, Shadow Warrior and PowerSlave / Exhumed. App name **Raze**,
bundle id `io.github.sithewok13.raze` (`source/CMakeLists.txt`). The owner
plays it on an iPhone, isn't a programmer, and reads everything on a phone.
Their game data is private: local copies for the rig only, never in the
repository or anywhere public.

- **Build branch:** `ios`. `master` is left as upstream (Raze).
- **Renderer:** Vulkan on Metal (MoltenVK, bundled), OpenGL ES as the
  fallback; SDL2 backend. Game files go anywhere in Files > On My iPhone >
  Raze; the log is `raze-log.txt` there.
- **Game picker** (`ios/IOSPicker.mm`): a card for each game family found
  (held 0.5 s: its other games and add-ons), LAN multiplayer from it. The
  tray's GAMES ("Switch game") keeps the pick, writes the settings, asks
  for a "Tap to start <game>" notification and closes the app (Raze plays
  one game a run); the next start within 10 minutes goes straight to it.
- **LAN games** (`ios/IOSNet.c`, `source/core/netgame.cpp`, notes in
  `ios/NET_PLAN.md`): host or join after the game is picked; Duke, Redneck,
  Blood and Shadow Warrior. No saving or loading in a network game.
- **Game controllers** (`ios/IOSPad.cpp`): through the engine's own pad
  bindings; a pad hides the touch controls until a touch.
- **Frame rate** (all five games: one main loop, `source/core/mainloop.cpp`,
  and one Vulkan present): FPS in the tray (held: 60 <-> 120). The games
  tick at 30 Hz and the renderer interpolates. The pace (`ios/IOSPacer.h`,
  from the DOOM port, called as `IOS_FrameCap` at the top of the loop,
  before `I_SetFrameTime` and the touches are read): at 60 a frame starts
  every 1/60 s and asks the screen to show it one period later
  (VK_GOOGLE_display_timing: MoltenVK's presentAtTime, in
  `vk_framebuffer.cpp`), the starts steered onto the screen's refreshes by
  the real shown times; at 120 plain vsync; OpenGL ES only sleeps. Build 86
  slept at the bottom of the loop, after the time and the touches were
  read, and vsync on a 120 Hz screen showed a frame at one refresh or the
  next: choppy turning at "60.0 fps". The look is resampled by the
  touches' own timestamps (`IOSTouch_LookTake`). While the game is held
  still (wheel, LEVEL, CAMERA, GAMES) or paused, frames don't wait for a
  tic (`TryRunTics`). Log every 5 s of play (`IOS_PerfFrame`, `i_ios.mm`):
  fps and a frame's ms (its turn's wait, tics, input, drawing, Vulkan's
  waits), "shown every ... ms (min, max, spread): n uneven, n late", the
  screen's real present times, and a look line while dragging.
  `ios/rig/IOSPacerSim.cpp` runs the pacer against a pretend screen; the
  rig's `frames` and `lookstats` commands print its frame rate and the
  look line. (The display link's ticks can't measure the screen: build
  86's "the screen runs at 5 Hz" was that.)
- **Touches held back (Nov 2026, fixed):** the pace's wait between frames
  must run the main run loop (`CFRunLoopRunInMode` until the frame's time,
  in `IOS_FrameCap`), never sleep the main thread (`nanosleep`). Asleep,
  UIKit never saw the main thread idle and held touches back for seconds,
  up to a minute, in the menus and the first minute after a level started,
  then let them all through at once (the game kept drawing at 60 fps and
  asking SDL for events every frame). Signs: touches arriving seconds
  late in bursts, "moved but no turn", menus not answering. A touch log
  (each touch's lateness, `UITouch.timestamp` vs now) found it: branch
  `ios-touchlog`. Every build keeps a light check of it (`i_ios.mm`,
  `UIApplication sendEvent:`, every screen): "touch check: a touch N ms
  late" for each one 150 ms late or more, and a summary every 5 s with
  touches.
- **iOS code:** `ios/`: `i_ios.mm` (main, paths, the log, alerts, the frame
  pace `IOS_FrameCap`), `IOSPacer.h`, `IOSPicker.mm`, `IOSTouch.m`/`.h` (the overlay: a C
  core plus a UIKit view), `IOSGame.cpp`/`.h` (the game side for every
  game), `IOSPad.cpp`, `IOSNet.c`, `iosCamera.h`, `iosCapture.cpp`,
  `iosPhotos.mm`, `Info.plist.in`, `build_deps.sh`, `rig/IOSTouchRig.c`.
  Each game's part is `source/games/<game>/src/ios_<game>.cpp` (an
  `IOSGamePart`: weapons for the wheel, a pick, the HUD struct, the item
  buttons, icons, the cheat's ammo and sound). Engine changes are
  `#ifdef RAZE_IOS` (the app), `RAZE_TOUCH` (the touch controls: iOS and
  the rig), `RAZE_IOSCAMERA` (the CAMERA) or `RAZE_GLES_RIG` (the rig's
  real OpenGL ES), marked "Added".

## Touch controls (`ios/IOSTouch.m`)

Modes: GAMEPLAY, CONSOLE (only MENU and its tray), PAUSED (RESUME), HIDDEN
(menus, cutscenes, loading: touches are SDL's mouse clicks). Buttons act on
the input bits the games read (`IOSGame_Input`), whatever keys are bound;
the look goes in as mouse counts (so the mouse sensitivity and invert
apply), tilt aiming straight into the view's angles.

- Duke's jetpack also flies by the view: the stick pushed while looking
  up rises, looking down sinks (`Soar` in the game part; 8 degrees each
  way stay level; JUMP / CROUCH still work).
- Bottom right: FIRE, CROUCH / USE / JUMP on an arc round it, the
  secondary button (KICK in Duke, ALT FIRE in Blood, none in the others).
  Dragging on them also looks. In the HUD SPLIT and STRIP they sit 14 pt
  above the pills; in CLASSIC, CLASSIC SPLIT and CLASSIC STRIP 10 pt above
  the game's status bar (its top as drawn told by the game each frame,
  `IOSTouchHud.fBarTop`); laid out again as that changes
  (`IOSTouch_LayoutKey`).
- The top row, left to right: NEXT WPN, PREV WPN; a wider gap; the **item
  buttons**; a wider gap; CAMERA, CHEAT (just left of SAVE, 60 pt apart;
  CAMERA takes CHEAT's place while CHEAT doesn't show); SAVE, LOAD, MENU.
  The FPS readout is under SAVE.
- The weapon wheel: one slice per weapon of the game, its pickup picture
  from the player's data, ammo counts, the game's own look.

### Item buttons (the ITEM button is gone)

One full-size round button per usable item the player has, in the game's
fixed order, closing up as items come and go (`IOSTouchItems`, each game's
`Items`): its picture from the player's data (`ItemIcon`), the world
pickup as it lies in the levels, made once as fed by `ios/IOSIconLook.cpp`
(`ItemPictures`: hq4x, Lanczos, brighter, more contrast and colour, a thin
light outline, the larger side 3/4 of the button, `IOSTouch_SetItemPicture`;
PowerSlave's lifted less, `fItemEnhance` 0.35): Duke FIRSTAID 53, STEROIDS
55, HOLODUKE 1348, JETPACK 57, HEATSENSOR 59; Redneck whiskey 53, moonshine
55, beer 51, cow pie 57; Blood 519, 760, 839, 827 (the same art as its pack
icons); Shadow Warrior ICON_MEDKIT, ICON_CLOAK (smoke bomb),
ICON_NIGHT_VISION, ICON_CHEMBOMB, ICON_FLASHBOMB, and the status bar's
caltrops (their pickup is a shop sign); PowerSlave the status bar's (the
pickups' own art). NAM / WW2GI keep the plain icons. Drawn at
full strength (dimmed 0.4), a tap uses it directly (the game's `useitem N`: `SB_ITEM_BIT_1 << (N-1)`).
No hold action. Charge items: the ring is a gauge filling clockwise from
12 o'clock (gold, red under 25%), glowing (ring and picture) while the
item is on or its effect runs. Count items: the plain outline and a
number top right from 2. Items that can't be used now are dimmed (grey,
0.4) and a tap does nothing. Items the games use by themselves have no
button (Duke's scuba gear and boots, Redneck's snorkel and hip waders,
Blood's diving suit, Shadow Warrior's repair kit; Redneck's slot 5 is
"Yeehaa", not an item).

- Duke: medkit (1, charge of 100, dim at full health), steroids (2, of
  400: usable only whole, then they run and glow), HoloDuke (3, 2400),
  jetpack (4, 1600), night vision (5, 1200), the last three on/off.
- Redneck: whiskey (1, of 100), moonshine (2, as the steroids), beer (3,
  count = amount / 400), cow pies (4, count = amount / 100); the healing
  ones dim at full health.
- Blood: doctor's bag (1), crystal ball (2), beast vision (3), jump boots
  (4): charges of 100; the last three on/off.
- Shadow Warrior: medkit (1), smoke bomb (3, runs and can't be stopped),
  night vision (4, on/off): charges; gas bomb (5), flash bombs (6),
  caltrops (7): counts.
- PowerSlave: heart, scarab, torch, hand, eye, Sobek mask (1..6): counts
  up to 5, dimmed without their mana (500, 1000, 100, 500, 400, 200 of
  1000) and the heart at full health, glowing while their effect runs.

Placing (`IOSTouch_PlaceItems`): after PREV WPN a 32 pt gap, the items 12
pt apart, at least 32 pt again before CAMERA; where six don't fit the gaps
shrink (to 20/8 on 874 and 844 pt phones with CHEAT shown), then the
buttons (r 17 on a 667 pt iPhone SE).

### The HUD (MENU's tray: HUD and its panel)

Six looks (`IOSTOUCH_HUD_*`, kept values: SPLIT 0, STRIP 1, CLASSIC 2, NONE
3, CLASSIC SPLIT 4, CLASSIC STRIP 5), in the panel's order SPLIT, STRIP,
CLASSIC SPLIT, CLASSIC STRIP, CLASSIC, NONE (default SPLIT). SIZE: the
pills small / medium / large (30.6, 39.8, 51.7 pt at 440 pt high; default
medium), the classic bars small / medium / large (0.6, 0.75 of the game's
own scale, or it; default medium); CLASSIC and NONE one size. FACE (default on) only for
the pills, and only where the game's own status bar has a face: Redneck
(Leonard's head; Duke's face doesn't go in the HUD, the owner's call); the
classic bars always show their face. Remembered (`iosTouchHud`,
`iosTouchHudFace`, `iosTouchHudSize` 0-2, `iosTouchHudBarSize` 0-2,
`iosTouchHudOpacity`, `iosTouchOpacity`; the rig's `$HOME/.iosrig-hud`).

- The tray's HUD (its label the look: "HUD\nSPLIT", "CLASSIC\nSPLIT"...,
  lit while its panel is open): tap = a panel under the tray (the shared
  standard, from the DOOM port): dark, rounded, a 1.5 pt white border at
  40%, up to 560 pt wide inside the safe area, 40 pt rows, the row's name
  at the left (78 pt): LOOK (six chips), SIZE (not for CLASSIC or NONE),
  FACE (ON / OFF: the pills, in Redneck), HUD (the HUD's opacity;
  not for CLASSIC, always at full, the owner's call, nor NONE) and
  BUTTONS (the controls', always shown), each a slider, 20-100% in 5%
  steps, live, kept on lift, the value at its right. Hidden rows close up. Chips: radius 15,
  the chosen gold (fill 1, 0.75, 0.24 at 45%, a solid gold border), the
  others white 10% with a 45% white border; a tap applies at once (a light
  haptic, the buttons laid out again). A row's name tapped = that row back
  to its default (toast, haptic); HUD held 0.45 s (ring) = everything back
  (split, medium, face on, both 100%: a toast) and the panel closes. The
  tray and the wheel stay at full. Core: `IOSTouch_HudPick`,
  `IOSTouch_HudRowReset`, `IOSTouch_HudResetAll`, `IOSTouch_HudRowShown`,
  `IOSTouch_OpacityPanel`; view: `layoutHudPanel`, `hudChipTapped:`,
  `hudRowNameTapped:`.
- SPLIT, STRIP, CLASSIC SPLIT, CLASSIC STRIP and NONE give the 3D view the
  whole screen (`hud_size` set each frame from the HUD: `Hud_Nothing`;
  CLASSIC `Hud_Stbar`, the game's status bar). SPLIT: two dark rounded pills
  at the bottom, the player's at the left (health, armour or what stands
  for it), the ammo in hand and the keys at the right. STRIP: one pill in
  the middle, as wide as it needs up to the HUD frame (FIRE and its arc sit
  above it, as with SPLIT). NONE: nothing.
- CLASSIC STRIP and CLASSIC SPLIT (`DrawIOSBar` in `ioshud.zs`): the game's
  own status bar as CLASSIC draws it (each game's `IOSBarDraw`; hud_size
  read as `Hud_Stbar` through `IOSHudSize()`, its clip kept while
  `mIOSBar`), clipped to its 320 wide core (no side filler: that is the
  engines' `UpdateFrame`, not drawn), its bottom at the pills' bottom.
  STRIP: whole in the middle. SPLIT: two corner pieces, the left at the
  HUD frame's left edge, the right at its right, as SPLIT's pills, each
  made of parts of the bar put side by side in whole pixels
  (`IOSBarPieces`/`IOSBarPiece`: side, from-to across, top; the default
  cuts at `IOSBarCut`), the weapons' list and the item box left out (the
  wheel shows the ammo, the item buttons the items; the owner's calls), in
  the bar's 320 units: Duke two whole arches (the owner's design): its left
  end, HEALTH, ARMOR to the post after ARMOR (-12-81.6) | the right arch from
  the post before INV (225.9-332), INV's box showing AMMO: AMMO's label laid
  over it (`IOSBarOverlay`: a part drawn shifted, 41.4 across; the digits
  drawn there by the bar itself, so three fit;
  the bar's item box left empty while split, `mIOSNoInv`), then KEYS and the
  end. Duke's bar runs 12 past its
  320 core at each end, STRIP too (`IOSBarSpan`, as CLASSIC shows the wider
  picture), so the curves at the ends land on the flat metal (the owner's
  call; cut at the core they ended in mid-air); Shadow Warrior HEALTH + ARMOR with both ends | an end, AMMO, the pillar, KEYS, an end (0-87.5 +
  300-320 = 107.5 | 0-18 + 187-222.5 + 268-320 = 105.5); Blood gargoyle,
  armour, health and its skull (0-123.5) | the other skull, ammo, keys,
  gargoyle (192.5-254 + 276-320 = 105.5); Redneck without the weapon row
  along its top (the piece's top is the wood bar's; Rides Again's bar is
  the same) Leonard, HEALTH, AMMO (0-128, half way to KEYS) | KEYS, the
  gauges (128-170 + 229-320 = 133; 170 is just past KEYS' box shadow, so
  the join is wood to wood); PowerSlave cut at 145, before
  the compass (145 | 175: its four glyphs are the keys, and the item shows
  on the magic pool, so nothing is left out). FIRE keeps 10 pt above the pieces' real top. SIZE small / medium: the status bar's scale
  times 0.6 / 0.75 while it is drawn (`Raze.IOSBarScale`, `iosBarScale` in
  `base_sbar.cpp`). Its top as drawn goes to the overlay
  (`Raze.IOSBarTop`, `IOSGame_SetBarTop`). The HUD slider fades it, numbers
  and all (the status bar's `Alpha`; its text follows it too:
  `DStatusBarCore::DrawString`). Plain CLASSIC is always at full.
- The pills: MEDIUM (the owner's earlier LARGE) 39.8 pt high on a 440 pt screen (83 px at
  2000x921; SMALL 30.6, LARGE 51.7), scaled with the screen's height (0.8-1.25x), the bottom 16.3
  pt above the screen's bottom (where the mockups' was), 2.4 pt inside the
  HUD frame's sides. The overlay computes the layout
  (`IOSTouch_PillGeometry`, `IOSTouch_GetHudLayout`); the game only reads it
  (`IOSGame_HudValue`, `Raze.IOSHud` in ZScript).
- Drawn in ZScript: the shared drawer `wadsrc/static/zscript/games/ioshud.zs`
  (`DrawIOSHud`, called from `statusbar2.cpp` after the game's own status
  bar) draws the parts each game's status bar lists in `IOSHudParts`
  (`sbar_d.zs`, `sbar_r.zs`, `blood/ui/sbar.zs`, `sw/ui/sbar.zs`,
  `exhumed/ui/sbar.zs`), in the digits of the game's own status bar
  (CLASSIC), so the pills look like pieces of it: Duke and Redneck the
  red digital DigiFont, Shadow Warrior the green `PANEL_FONT_G`, Blood
  `SBarHealthAmount` (red) for health, `SBarNumberAmmo` (blue) for ammo
  and each armour's grey `SBarAmmoAmount` on a plate of its colour (red,
  blue, green, as the bar's), PowerSlave the ammo counter's stone tablets
  (status sequence 46, frame 3 x digit: the counter rolls) and its pools
  (red health under the ankh, blue magic). Digit pictures are spaced one
  of their own pixels apart, as the bars do; no leading zeros (Shadow
  Warrior's bar pads to three). Duke's access cards big and side by side.
  Warnings: health under 25 pulses red (twice a second); ammo red strictly
  below 25% of its maximum, or at 0: the same digits in red (a red copy of
  their own brightness over them) with a red glow round them, so the
  games' red digits show it too.
- The game's messages (`c_notifybuffer.cpp`): at the games' own size for
  the screen's height, below the top row of buttons; the ones at the left
  start at NEXT WPN's left edge (`IOSGame_MessagePlace`), the centred ones
  stay centred.

### The cheat, LEVEL, CAMERA

- **CHEAT** (`sithewok`): the tray's CHEAT shows the button and switches
  the cheat on, or leaves cheat mode; CHEAT held 0.5 s = on/off; a tap does
  nothing. Its picture is the game's own, its
  hero's line plays as it comes on. Duke's is his worn radiation sign
  (tile 3392, `CheatSign`) made into the whole button by
  `IOSIconLook_CheatSign` (cropped to its yellow circle, hq4x, a black
  rim; off grey and dim, the button at 0.8; on its yellow orange-hot with
  a wide orange halo, the rim crisp over it): `IOSTouch_SetCheatPictures`,
  216 px covering 72/44 of the button; the nuke button if 3392 isn't the
  sign (another edition). The others the same way with a style
  (`CheatSignStyle`, `IOSIconLook_CheatSignStyled`: on lit and warmed, a
  halo of the game's colour, the rim crisp; off grey and dim): Redneck the
  Dairy Air Farm sign's cow (2700, cropped to 0.68), Rides Again the No. 20
  pig sign (7910), amber; Blood the trapped soul (820), red; Shadow Warrior
  the fortune cookie (ICON_BOOSTER 1810, the owner's pick over the
  yin-yang), inset on a dark disc as before (`bEmblem`, 0.84 of the disc),
  in its own colour on (`fOnColour` 1.0), an amber glow;
  PowerSlave the gold pharaoh mask (590, the owner's pick over the gold
  ankh 798) on a lapis disc (0.86 of it), a gold glow. Where the sign
  isn't there, CheatIcon's picture is made into the button in that style
  (PowerSlave: the drawn ankh). Rig dumps: `<dump>.cheatpic.rgba` (on, off). While on (single
  player, where the game's cheats work): god mode, "give all" at each
  level, ammo kept full; JUMP / USE holds for fly (Shadow Warrior) and
  noclip.
- **LEVEL** (tray, any single-player level): the game's levels; a tap goes
  there.
- **CAMERA** (top row): tap = photo, hold 0.5 s = selfie, slide sideways =
  burst, down = Action Freeze, up = the cinematic burst; the tray's CAMERA
  shows/hides it, held its options. `source/core/ioscamera.cpp` and each
  game's `ios_pose_*.cpp`.

## Testing without a Mac (the Linux rig)

- Configure a desktop build with `-DRAZE_TOUCH_RIG_SOURCE=$PWD/ios/rig/IOSTouchRig.c`
  and `-DCMAKE_C_FLAGS=-DRAZE_GLES_RIG -DCMAKE_CXX_FLAGS=-DRAZE_GLES_RIG`
  (ZMusic from a local build: `ZMUSIC_INCLUDE_DIR`, `ZMUSIC_LIBRARIES`);
  `make raze` and `make raze_pk3` (the ZScript is in the pk3).
- Run under Xvfb (`-screen 0 2000x921x24`, the owner's phone's screenshots)
  with `HOME=<scratch>` (its `raze.ini` points at the data; set `win_w`,
  `win_h` there for the window's size), `TOUCHRIG_SCRIPT=<script>`,
  `TOUCHRIG_LOG=<log>`, `TOUCHRIG_SCREEN="956 440 62 21"` (points wide,
  high, side and bottom insets; default the iPhone 14's 844 x 390) and
  `TOUCHRIG_DUMP=<file>`; `./raze -nosound -stdout -gamegrp DUKE3D.GRP -map
  E1L1` (REDNECK.GRP E1L1, SW.GRP `$bullet`, BLOOD.RFF E1M1, STUFF.DAT LEV1).
- Script lines are `<seconds> <command>`, seconds from the first frame of
  play; all lines due run in one frame, so leave a few seconds after a
  `cmd give all` or an `xshot` (it takes over a second). Commands: `down /
  move / up <id> <x|@BUTTON> <y|@BUTTON>` (`@QUICKSAVE`, `@MENU`,
  `@TRAYHUD`, `@ITEM0`...), `log`, `buttons`, `items`, `hud <split|strip|
  csplit|cstrip|classic|none> [face]`, `hudsize <small|medium|large|normal>`,
  `hudpick <row> <choice>` and `hudreset <row>` (HUD's panel), `hudopacity`,
  `opacity`, `frames`, `lookstats`, `dump <name>`, `xshot <png>`, `cmd <console
  command>` (`give all`, `ios_rigpos`, `ios_riginv_duke`, `ios_rigset_duke
  health|ammo <n>`), `picklevel`, `quit`.
- The rig draws no overlay: `dump` writes its state (buttons, items, HUD)
  and the items' pictures, to draw it over an `xshot` outside the rig.
- Objective-C (the overlay's view, `i_ios.mm`, the picker, `iosPhotos.mm`)
  only compiles in CI. Gameplay on the phone is only tested by the owner.

## CI

`.github/workflows/ios.yml` (macos-15, newest Xcode): deps cached, host
tools, the iOS build, `Raze.ipa`, a check that no game data is in the app.
Pushes to `ios` publish the public `ios-latest` prerelease (body's first
line "Build <run> · <YYYY-MM-DD>"); a manual run on another branch (`gh
workflow run ios.yml --ref <branch>`) builds without publishing: use one to
compile-check Objective-C. The build stamp ("build 80 · Nov 9") shows under
the open MENU tray.

## Rules

- **Game data:** never commit, upload, bundle or publish game files (GRP,
  RFF, ART, MAP, STUFF.DAT, installers, zips), here or anywhere public. Work
  on local copies only, outside the repository.
- **Commits:**
  - Identity `Claude <noreply@anthropic.com>` (already configured); never
    the owner's email or name. Subject `iOS: ...`, then a plain wrapped
    body.
  - End with the attribution trailer lines your session provides. Apart from
    those, no AI model names in commits, code or docs.
  - No PRs unless asked. Never stash, reset or check out over a working tree
    that another job may be editing. Push with `git push -u origin ios`
    (pull first); never force-push, never push tags.
- **Releases:** no versioned release yet; each push to `ios` updates the
  public `ios-latest` prerelease (the owner's go). Before any other public
  release or public text, build a preview and wait for the owner's explicit
  go.
- **Touch controls standard** (shared with the owner's other ports; keep it
  the same):
  - Move stick where the left thumb lands; drag elsewhere to look.
  - SAVE / LOAD: tap = the game's Save Game / Load Game menu; a 0.3 s hold
    with a ring = quick save / quick load. Sliding off cancels; SAVE wins a
    tie (LOAD's tap does nothing while SAVE is held); only a finished hold
    saves or loads, a tap never does.
  - MENU: tap = game menu; hold 0.45 s = tray with LOOK, SENS, GYRO, FPS,
    HUD, CAMERA, CHEAT, LEVEL, GAMES, keyboard, and the build stamp under
    it.
  - LOOK: the drag's look speed ("LOOK 1x"); a tap steps 0.5, 0.75, 1,
    1.25, 1.5, 2, 2.5, 3x; held 0.45 s (ring) back to 1x. Remembered.
  - GYRO: OFF (default) / TOUCH (aims while either thumb is down) / ALWAYS.
    SENS 1.0/1.5/2.0/3.0, default 1.5. Remembered.
  - HUD: tap = its panel (LOOK, SIZE, FACE, HUD and BUTTONS opacity, see
    "The HUD"); a row's name = that row's default; held 0.45 s = all the
    defaults.
  - FPS: tap = show/hide the readout; held 0.45 s (ring) = 60 <-> 120.
    Remembered.
  - NEXT WPN / PREV WPN: tap = next/previous; a 10 pt slide opens the
    weapon wheel at once; a 0.3 s hold opens it to tap. The gap at the
    bottom cancels. The game holds still while a wheel is open. A haptic
    tick per slice.
  - HUD and buttons stay clear of the corners, the notch or Dynamic Island,
    and the home bar (Raze's own status bar, CLASSIC, goes to the very
    bottom: the owner's choice).
- **Testing:** say plainly what was and wasn't tested. The owner tests on
  the device.
- **Lean mode:** small contexts, no full log or file dumps
  (grep/sed/head/tail), reuse builds.
- **Talking to the owner:** plain words, short messages, direct links, and
  honesty about mistakes and untested things. If they skip a question,
  choose a sensible default and say what you chose.
