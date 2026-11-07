<!--
  DRAFT for ios-v0.1: not published. The owner must see a preview (phone and
  desktop widths) and say "Publish ios-v0.1" first.

  The GitHub release text for a release run of .github/workflows/ios.yml: a
  manual run of branch ios with "release" set to a tag such as ios-v0.1 (the
  workflow doesn't have that input yet: add it, modelled on Serious Sam's).
  The run must stop before building unless this file has a
  "### What's in <tag>" heading line for that tag, written exactly like that
  and on a line of its own. A '-' in the version after "ios-"
  (ios-v0.1-beta1) makes a prerelease; without one the release is marked as
  the latest release. Links must be absolute: relative links don't resolve on
  a release page. Keep each paragraph and list item on one line: a release
  page turns every line break into a visible one.

  Still to settle before the preview (search for "TO CHECK"):
  - the controls section follows the ios-touch branch as it stands; check it
    against the code once ios-touch and ios-camera are merged;
  - what was tested on an iPhone;
  - the exact "no game data" message on a phone;
  - Duke Xtreme (Raze doesn't know it by itself: it needs a .grpinfo file);
  - the licence notices (Raze, BUILD licence, SDL2, OpenAL Soft, ZMusic,
    libvpx): check each (and every link) and add the full texts.
-->

**Raze for iOS v0.1**: an unofficial iPhone build of [Raze](https://github.com/ZDoom/Raze), the source port that plays the classic Build-engine shooters (*Duke Nukem 3D*, *Blood*, *Shadow Warrior* and *Redneck Rampage*), with on-screen touch controls made for them. One app plays them all.

**You need your own copies of the games; no game files are included.** You copy each game's folder from your PC copy (for example from GOG or Steam) onto your iPhone (see *Install*).

**One app, every game:** **Raze** (`Raze.ipa`) finds every game you copy into its folder and asks which one to play each time you open it.

**New here?** *Known limitations*, *Requirements* and *Install* are near the bottom of this page, just above the download.

### What's in ios-v0.1

The first release. Everything here is new:

- **The games:** *Duke Nukem 3D* (the 20th Anniversary World Tour, or the Atomic Edition with its add-ons *Duke It Out in D.C.*, *Nuclear Winter*, *Duke Caribbean: Life's a Beach* and *Duke!Zone II*), *Blood* (with *Cryptic Passage*), *Shadow Warrior* (with *Twin Dragon* and *Wanton Destruction*) and *Redneck Rampage* (with *Rides Again*).
- **Touch controls** like the other ports': a move stick under your left thumb, drag to look, FIRE with CROUCH, USE and JUMP around it, a weapon wheel on NEXT WPN and PREV WPN, quick save and quick load with a short hold, and MENU with a hidden tray (look speed, tilt aiming, FPS, the camera, the cheat, the console).
- **Tilt aiming** (off unless you switch it on).
- **CAMERA:** photos, bursts, selfies with the enemies around you posing, Action Freeze and the cinematic burst, as in the Jedi Knight and Serious Sam ports.
- **The cheat** (`sithewok`): god mode, every weapon and item, ammo kept full, walk through walls, and a list of every level to jump to.
- **A log file** (`raze-log.txt` in the app's folder) that says what the game was doing, for bug reports.

**This is the first release, so it has had little testing:** see *Known limitations*.

---

### How to play: every control explained

<!-- TO CHECK: this section follows the ios-touch and ios-camera branches as they stand (not merged yet). Check every line against the code once they are. -->

The touch controls appear while you're playing a level, and hide in the menus, cutscenes and while a level loads (there you just tap, as you'd click with a mouse). The game runs in landscape, either way round.

Where everything is (on a phone, turn it sideways to see the whole picture):

```
 NEXT  PREV           CHEAT  CAMERA                  QUICK  QUICK  MENU
 WPN   WPN                                           SAVE   LOAD
         [LOOK] [SENS] [GYRO] [FPS] [camera] [CHEAT] [LEVEL] [keyboard]
                              (MENU's tray, while it's open)

                                                            ITEM
                                                    JUMP
                                           USE
     ( o )  move stick: appears                          ALT FIRE / KICK
            where your left thumb lands    CROUCH      FIRE
```

Exact positions shift a little to fit your screen and the camera cutout. Buttons are slightly see-through until you touch them, and a touch just beside a button still counts.

#### Moving and looking

- **Move:** put your left thumb down anywhere in the left part of the screen and a stick appears under it. Push it the way you want to go: up the screen is forward.
- **Look:** drag anywhere else that isn't a button. The game's own mouse settings (sensitivity, invert) apply. Dragging on FIRE, the arc of buttons around it and the secondary button also looks, so you can fire and aim with one thumb.

#### Buttons

- **FIRE:** fires while held.
- **CROUCH, USE, JUMP:** the arc around FIRE. USE opens doors and presses switches.
- **The secondary button** beside FIRE: **ALT FIRE** in *Blood* (each weapon's second attack), **KICK** in *Duke Nukem 3D*. The other games don't have one.
- **ITEM:** uses the inventory item the HUD shows (medkit, night vision and so on). Slide sideways on it to pick the previous or next item instead.
- The buttons work whatever keys are set in the game's own controls menu.

#### The weapon wheel (NEXT WPN and PREV WPN)

- **Tap** NEXT WPN or PREV WPN for the next or previous weapon.
- **Slide** from either one and the weapon wheel opens at once: keep sliding toward a weapon and lift to take it.
- **Hold still** about a third of a second: a ring fills and the wheel opens and stays open, so you can tap a weapon.
- One slice per weapon of the game you're playing, with its ammo. Weapons with no ammo are greyed, ones you haven't found yet are faint, and neither can be taken. The gap at the bottom cancels.
- The game holds still while the wheel is open (the music plays on).

#### Quick save and quick load: why the short hold

**QUICK SAVE** makes a quick save and **QUICK LOAD** loads your latest one. Both need you to **hold** the button for about a **third of a second**: a ring fills round it, and when it's full the game saves or loads, once, with your finger still down.

**Why the hold?** So a stray touch can't save over your quick save, or throw away your progress by loading an old one. Sliding your finger off before the ring is full cancels.

#### MENU and its hidden tray

**Tap MENU** for the game's menu. **Hold MENU** until its ring fills (about half a second) and a small tray opens under it instead, from left to right:

- **LOOK:** how fast dragging turns the view. Each tap steps up; hold it to go back to 1x.
- **SENS:** how far the view turns for a tilt of the phone (1.0x, 1.5x, 2.0x, 3.0x; 1.5x to start).
- **GYRO:** tilt aiming, see below.
- **FPS:** shows the frame rate next to QUICK SAVE.
- **The camera symbol:** shows or hides CAMERA; hold it for the camera's options.
- **CHEAT:** see *The cheat*.
- **LEVEL:** only while the cheat is on: every level of the game, to jump to.
- **The keyboard:** opens the game's console with the iOS keyboard.

A touch anywhere else closes the tray. The app remembers these settings.

#### Tilt aiming (gyro)

GYRO steps through **OFF** (to start with), **TOUCH** and **ALWAYS**. With **TOUCH**, tilting the phone aims only while a thumb is on the screen (the stick, the look area or FIRE's buttons); lift both thumbs and the view stays where it is, so you can rest the phone. With **ALWAYS**, tilting always aims.

#### The camera: photos, selfies, bursts and Action Freeze

**CAMERA** sits in the top row. The first time, iOS asks whether the app may **add photos** to your library: say yes and the photos go straight into your Photos app (the app can't see the ones already there). Without that, they go to the app's *Screenshots* folder in the Files app.

- **Tap** for a photo. **Hold** half a second for a **selfie** (1, 3 or 5 photos, with the nearest enemies posing).
- **Slide sideways** for a **burst** of photos.
- **Slide down** for **Action Freeze**: the game stops and you move the camera round it (one finger turns, two move and pinch to zoom), with a shutter button and an X to leave.
- **Slide up** for the **cinematic burst**: photos as the camera sweeps round the action.
- A selfie, a freeze or a burst changes nothing in your game.

#### The cheat (sithewok)

Hold MENU and tap **CHEAT** in the tray, or type `sithewok` in the console. While it's on: god mode, every weapon and item (again at each new level), ammo kept full. **Hold USE** to walk through walls (noclip). In *Shadow Warrior*, **hold JUMP** to fly. **LEVEL**, in MENU's tray, lists every level of the game you're playing: tap one to go there. Tap CHEAT in the tray again to switch it off.

#### Menus, leaving the app, and the console

In the menus, tap as you'd click. **Leaving the app doesn't save your game**: quick save first. The console (the tray's keyboard) takes Raze's own commands.

### Known limitations

<!-- TO CHECK: fill in what was tested on an iPhone before the preview. -->

- **First release, little testing so far.** The touch controls, the cheat and the camera were tested on a computer, with the real game files and simulated touches. TO CHECK: what has been tried on an iPhone.
- **Music:** MIDI music plays through the app's own synthesizers (OPL, like an old sound card, or TiMidity), not FluidSynth, which isn't in the iPhone build. It may sound different from a PC.
- **Not tried yet:** iPads (the app is marked for them); game controllers, keyboards and mice; *PowerSlave* (*Exhumed*), which Raze also plays; editions other than the ones named under *Requirements*; user maps and mods; multiplayer.
- **Duke Xtreme** isn't one of the add-ons Raze knows by itself. TO CHECK: whether to support it, and how.

### Requirements

- An **iPhone on iOS 15 or newer.** The app is also marked for iPad, but hasn't been tried on one.
- **Your own copies of the games**, on the computer they're installed on, to copy them to your iPhone. The copies this was tested with:
  - *Duke Nukem 3D: 20th Anniversary World Tour* (Steam), and the *Atomic Edition* with its add-ons from CD;
  - *Blood: One Unit Whole Blood* (GOG);
  - *Shadow Warrior Classic Complete* (GOG);
  - *Redneck Rampage Collection* (GOG: *Redneck Rampage* and *Rides Again*).
- A **sideloading tool or signing service** (something that installs apps from outside the App Store) that can install an app file (`.ipa`) you give it. `Raze.ipa` isn't signed for your iPhone, so it can't be installed without one.

### Install

1. Download **`Raze.ipa`**, below.
2. Install it with your sideloading tool or signing service, following that tool's own instructions. On your home screen the app is called **Raze**. Its version shows as 0.1 followed by a build number: that's expected.
3. **Open the app once.** With no games yet, it shows a *Raze: fatal error* box saying *Unable to find any game data. Please verify your settings.* (TO CHECK on a phone). Tap Exit. That's expected: by then the app has made its folder, *On My iPhone > Raze* in the Files app.
4. In the Files app's **On My iPhone > Raze**, make a folder for each game you have, and copy the game's files into it from its folder on your computer (you don't need the `.exe` and `.dll` files):
   - **`Duke Nukem 3D`**: the World Tour's game folder (the one with `DUKE3D.GRP`).
   - **`Duke Nukem 3D Atomic`**: the Atomic Edition's `DUKE3D.GRP`, plus any add-ons you have: `DUKEDC.GRP` (D.C.), `NWINTER.GRP` (Nuclear Winter), `VACATION.GRP` (Caribbean), and for Duke!Zone II its `.GRP` file with `DZ-GAME.CON`, `DZ-DEFS.CON` and `DZ-USER.CON`.
   - **`Blood`**: the game folder (the one with `BLOOD.RFF`), with Cryptic Passage's files if you have it.
   - **`Shadow Warrior`**: the game folder (the one with `SW.GRP`), with `WT.GRP` (Wanton Destruction) and the `dragon` folder (Twin Dragon) if you have them.
   - **`Redneck Rampage`**: the game folder (the one with `REDNECK.GRP`), with Rides Again in its `AGAIN` folder inside it, as GOG has it.

   Copy the folders as they are, not as `.zip` files, with their names unchanged. Use whatever way you like to get files into the Files app, for example iCloud Drive: copy them into iCloud Drive on your computer, then move them into *On My iPhone > Raze*. The app looks in its folder and two folder levels down, so the folder names above are a suggestion, but keep each game in a folder of its own.
5. **Open the app again.** Choose a game from the list.

**Your saves** are in the Files app, in *On My iPhone > Raze > raze > Savegames*. **Back up** that folder now and then (for example to iCloud Drive), and always before you delete or reinstall the app: deleting the app deletes its folder, games and saves included. Your settings are kept by iOS, not in the app's folder.

**If something goes wrong:** `raze-log.txt`, directly in *On My iPhone > Raze*, says what the game was doing. Copy it out before you open the app again, because each start replaces it. **Found a bug?** Please report it here, not to the upstream Raze project, and say you're on **ios-v0.1** (the app shows 0.1 and a build number): https://github.com/sithewok13-dev/Raze-iOS-/issues. Attach `raze-log.txt`, and say which game, which iPhone and iOS version, and what you were doing.

**Download:** `Raze.ipa`, under *Assets* below. The *iOS latest build* prerelease, also on the Releases page, is rebuilt automatically after every code change, before anyone has tried it: use this release.

---

Unofficial build. Raze is by the ZDoom team and contributors (https://github.com/ZDoom/Raze), built on GZDoom's technology and on JFDuke, EDuke32, Nuke.YKT's Redneck Rampage source, NBlood, SWP, VoidSW, PCExhumed and Ken Silverman's Build engine. Duke Nukem 3D and Shadow Warrior are by 3D Realms, Blood by Monolith Productions, Redneck Rampage by Xatrix Entertainment. This build is not affiliated with or endorsed by any of them, or by the Raze project. No game files are included.

<!-- TO CHECK: every licence below against the code and the libraries' own files, and add the full notices (as Serious Sam's notes do) in a <details> block. -->

Raze's own code is free software under the GNU GPL v2 (https://www.gnu.org/licenses/old-licenses/gpl-2.0.html); the Build engine code is under Ken Silverman's BUILD licence (https://github.com/sithewok13-dev/Raze-iOS-/blob/ios/build-doc/buildlic.txt), which allows only non-commercial use. The source code, iOS changes included, is the `ios` branch: https://github.com/sithewok13-dev/Raze-iOS-/tree/ios (this release is the tag `ios-v0.1`: https://github.com/sithewok13-dev/Raze-iOS-/tree/ios-v0.1).

The app also includes libraries under their own licences: SDL2 (zlib licence, https://github.com/libsdl-org/SDL/blob/release-2.32.8/LICENSE.txt), OpenAL Soft (GNU LGPL v2, https://github.com/kcat/openal-soft/blob/1.24.3/COPYING), ZMusic (https://github.com/ZDoom/ZMusic/tree/d3b730795784bff3f97571446101c57c1c6ac9bc/licenses) and libvpx (BSD licence, https://github.com/webmproject/libvpx/blob/v1.15.2/LICENSE).
