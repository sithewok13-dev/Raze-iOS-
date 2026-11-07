# Raze for iOS: notes for Claude Code sessions

An unofficial iPhone/iPad build of Raze, the Build-engine source port (Duke
Nukem 3D, Blood, Shadow Warrior, Redneck Rampage, and PowerSlave/Exhumed), with
touch controls. One app, **Raze**, plays them all. The owner plays it on an
iPhone, isn't a programmer, and reads everything on a phone.

- **Build branch:** `ios`. Upstream's `master` is left alone. Work in progress
  goes on its own branch (`ios-touch`, `ios-camera`, `ios-docs`, ...); runs there
  publish nothing.
- **App:** name **Raze**, bundle id `io.github.sithewok13.raze`, IPA `Raze.ipa`,
  iOS 15 or newer, version `0.1.<CI run number>` (`source/CMakeLists.txt`, the
  `RAZE_IOS` block near `IOS_FRAMEWORKS`; `ios/Info.plist.in`).
- **iOS code** is in `ios/`: `i_ios.mm` (the game picker and fatal-error alerts as
  UIKit alerts; the engine's log to `raze-log.txt` in Files), `build_deps.sh`
  (SDL2, OpenAL Soft, ZMusic without FluidSynth, libvpx), the icon
  (`make_icon.py` draws `AppIcon-1024.png`; the build scales it for
  `CFBundleIcons`). Engine changes sit under `#ifdef RAZE_IOS`: the SDL backend
  with an OpenGL ES 3.0 context and SDL's frame buffer, and the game search path
  (`core/gameconfigfile.cpp`: Documents, one and two folder levels down).
- **Not merged yet** (branches `ios-touch`, `ios-camera`; check them before
  relying on this):
  - TOUCH (`RAZE_TOUCH`, on iOS and in the rig): `ios/IOSTouch.m` / `IOSTouch.h`
    (the overlay, ported from Serious Sam's: a C core plus a UIKit view),
    `ios/IOSGame.cpp` and a part per game, `source/games/*/src/ios_*.cpp`
    (Raze's input bits, the weapon wheel's weapons, the cheat). The HUD keeps
    clear of the corners in `base_sbar.cpp`. Engine changes are marked `Added:`.
  - CAMERA (`ios/iosCamera.h` is what the overlay calls; a stub until merged):
    `source/core/ioscamera.cpp`, `ios/iosCapture.cpp`, `ios/iosPhotos.mm`, pose
    hooks per game (`ios_pose_*.cpp`), console commands `ioscam_*`.
- **CI:** `.github/workflows/ios.yml` (macOS; builds the dependencies once and
  caches them, then host tools, then the app; checks the icon). A push to `ios`
  updates the public **`ios-latest`** prerelease (`Raze.ipa`). Other branches can
  be built by hand (`workflow_dispatch`) and keep the IPA as an artifact only.
  There is no `release` input yet: add one modelled on Serious Sam's
  (`ios-vX.Y` tags, notes check, `RELEASE_TITLE`) before the first release.
- **Docs:** `ios/RELEASE_NOTES.md` (the release text and full player guide).
- **Games in Files > On My iPhone > Raze**, one folder each (the app searches two
  folder levels): `Duke Nukem 3D` (20th Anniversary World Tour), `Duke Nukem 3D
  Atomic` (Atomic Edition plus the add-ons D.C., Nuclear Winter, Caribbean,
  Duke!Zone II, Duke Xtreme), `Blood`, `Shadow Warrior`, `Redneck Rampage`
  (Rides Again in its `AGAIN` subfolder). With more than one game found, the app
  asks which to play.
- **Linux rig:** the real engine on Linux with the iOS renderer path
  (`-DRAZE_GLES_RIG=ON`: GLAD loader, ES 3.0 context) and, on `ios-touch`, the
  real overlay core through `-DRAZE_TOUCH_RIG_SOURCE=<a C file that includes
  ios/IOSTouch.m>` (scripted touches, mock UIKit). The rig lives in the session's
  scratchpad, not in the repo.

**First, read the house style guide** in the owner's private files repo
(`docs/HOUSE_STYLE.md`), if you have access. The rules below apply even without it.

## Rules

- **Pushing publishes.** A push to `ios` updates the public `ios-latest`
  prerelease. Push only reviewed work, when the owner wants a test build. Back up
  unreviewed work as a patch in the owner's private files repo (that also answers
  the uncommitted-changes stop hook).
- **Releases:**
  - `ios-vX.Y` tags, made by a manual run of `ios.yml` on `ios` with input
    `release=<tag>` (once it has one). Never push tags by hand. The notes need the
    exact line `### What's in <tag>`, one line per paragraph or list item, and
    absolute links. Commit and push them only after the owner's go.
  - **Before any public release or public text,** build a preview (phone and
    desktop widths) and wait for the owner's explicit go, such as "Publish
    ios-v0.1".
  - After publishing, download the IPA and verify: bundle id, no game data (only
    the app's own `raze.pk3` and its files), the new code present, Latest marked,
    the tag on the built commit.
- **Game data:** never commit, upload, bundle or publish game files (installers,
  `.grp`/`.rff`/`.art` files, add-ons, extracted folders, zips), here or anywhere
  public. Work on local copies only.
- **Icon:** original art only (no game logos, characters or screenshots: this is
  an unofficial engine port).
- **Commits:**
  - Identity `Claude <noreply@anthropic.com>` (already configured); never the
    owner's email or name. Subject `iOS: ...`, then a plain wrapped body.
  - End with the attribution trailer lines your session provides. Apart from
    those, no AI model names in commits, code or docs.
  - No PRs unless asked. Never stash, reset or check out over a working tree that
    another job may be editing.
- **Touch controls standard** (shared with the owner's other ports; keep it the
  same; the Raze version is on `ios-touch`, not merged yet):
  - Move stick where the left thumb lands; drag elsewhere to look.
  - Bottom right: FIRE, CROUCH / USE / JUMP on an arc, a secondary button (ALT
    FIRE in Blood, KICK in Duke Nukem 3D) and ITEM (uses the HUD's inventory item;
    slid sideways, the previous / next item). Buttons set Raze's input bits
    directly, whatever keys are bound.
  - QUICK SAVE / QUICK LOAD: a 0.3 s hold with a ring. Sliding off cancels; QUICK
    SAVE wins a tie.
  - MENU: tap = game menu; hold 0.45 s = tray with LOOK, SENS, GYRO, FPS, CAMERA,
    CHEAT, LEVEL (only while the cheat is on), keyboard (the console).
  - GYRO: OFF (default) / TOUCH (aims while either thumb is down; lifting both
    freezes the view) / ALWAYS. SENS 1.0/1.5/2.0/3.0, default 1.5. Remembered.
  - NEXT WPN / PREV WPN: tap = next/previous; a 10 pt slide opens the weapon
    wheel at once; a 0.3 s hold opens it to tap. One slice per weapon of the game
    played, with its ammo; the bottom gap cancels; the game holds still while it's
    open; a haptic tick per slice.
  - CHEAT (`sithewok`, the tray's CHEAT or typed in the console): god mode plus
    everything given (again each level), ammo kept full; USE held = noclip, JUMP
    held = fly (Shadow Warrior); LEVEL lists the game's levels.
  - CAMERA (on `ios-camera`): tap = photo, hold = selfie, slide sideways = burst,
    down = Action Freeze, up = cinematic burst, as in the other ports. Nothing in
    the game is changed by a selfie, freeze or burst.
  - HUD and buttons stay clear of the corners, the notch or Dynamic Island, and
    the home bar.
- **Testing:** a real-engine Linux rig with the real data (local only) and the
  real overlay (scripted touches, mock UIKit), plus the iOS build in CI. Then
  independent reviews and a fix pass. The owner tests on the device. Say plainly
  what was and wasn't tested.
- **Lean mode:** small contexts, no full log or file dumps (use grep/sed/head/
  tail), reuse builds, one full final run.
- **Talking to the owner:** plain words, short messages, direct links, and
  honesty about mistakes and untested things. If they skip a question, choose a
  sensible default and say what you chose.
