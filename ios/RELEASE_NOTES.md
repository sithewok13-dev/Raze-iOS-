<!--
  The GitHub release text for a release run of .github/workflows/ios.yml: a
  manual run of branch ios with "release" set to a tag such as ios-v0.1
  (gh workflow run ios.yml --ref ios -f release=ios-v0.1). The run stops
  before building unless this file has a "### What's in <tag>" heading line
  for that tag, written exactly like that and on a line of its own. A '-' in
  the version after "ios-" (ios-v0.1-beta1) makes a prerelease; without one
  the release is marked as the latest release. Links must be absolute:
  relative links don't resolve on a release page. Keep each paragraph and
  list item on one line: a release page turns every line break into a
  visible one. The owner must see a preview (phone and desktop widths) and
  say "Publish ios-v0.1" before the release run.
-->

**Raze for iOS v0.1**: an unofficial iPhone and iPad build of [Raze](https://github.com/ZDoom/Raze), the source port that plays the classic Build engine shooters (*Duke Nukem 3D*, *Blood*, *Shadow Warrior*, *Redneck Rampage* and *PowerSlave* / *Exhumed*), with on-screen touch controls made for them. One app plays them all.

**You need your own copies of the games; no game files are included.** You copy each game's folder from your PC copy (for example from GOG or Steam) onto your iPhone (see *Install*).

**One app, every game:** **Raze** (`Raze.ipa`) finds every game you copy into its folder and shows a card for each one when you open it.

**New here?** *Known limitations*, *Requirements* and *Install* are near the bottom of this page, just above the download.

### What's in ios-v0.1

The first numbered release. Everything here is new:

- **Five games in one app:** *Duke Nukem 3D* (the Atomic Edition with its add-ons *Duke It Out in D.C.*, *Nuclear Winter*, *Duke Caribbean: Life's a Beach* and *Duke!Zone II*, or the *20th Anniversary World Tour*), *Blood* (with *Cryptic Passage*), *Shadow Warrior* (with *Twin Dragon* and *Wanton Destruction*), *Redneck Rampage* (with *Rides Again*) and *PowerSlave* (*Exhumed*). A picker shows a card for each game you have; hold a card for its add-ons.
- **An app icon of its own:** an orange "R" on a floor grid, drawn for the port.
- **Touch controls made for these games:** a move stick under your left thumb, drag to look, FIRE with CROUCH, USE and JUMP round it, KICK in *Duke Nukem 3D* and ALT FIRE in *Blood*.
- **A weapon wheel** on NEXT WPN and PREV WPN, with each weapon's own picture from your game and its ammo.
- **A button for every item you carry:** Duke's medkit, steroids, HoloDuke, jetpack and night vision, Blood's doctor's bag and crystal ball, Lo Wang's smoke bombs and caltrops, and so on, each with the item's own picture and a ring that shows how much is left.
- **Duke's jetpack flies where you look:** push the stick while looking up to rise, down to sink.
- **Six HUD looks:** two small panels in the bottom corners in the game's own digits (to start with), one panel in the middle, the game's own status bar split into the two corners or whole in the middle, the classic full status bar, or nothing at all. Size and see-through are yours to set.
- **Quick save and quick load** on a short hold of SAVE and LOAD; a tap opens the game's own Save or Load menu.
- **60 or 120 frames a second** (120 on ProMotion iPhones and iPads), drawn with Vulkan on Metal.
- **GRAPHICS:** sharp or smooth pixels, and smoother textures (2x or 4x) if you like them.
- **Tilt aiming** (off unless you switch it on).
- **CAMERA:** photos, bursts, selfies with the enemies around you posing, Action Freeze (stop the game and move the camera round it) and a cinematic burst. Photos go to your Photos app.
- **The cheat** (`sithewok`): god mode, every weapon and item, ammo kept full, walk through walls, fly in *Shadow Warrior*. **LEVEL** lists every level of the game you're playing: tap one to go there.
- **LAN multiplayer** on Wi-Fi for *Duke Nukem 3D*, *Redneck Rampage*, *Blood* and *Shadow Warrior*: host or join from the picker. Not yet tried between two real iPhones: see *Known limitations*.
- **Game controllers** work through the game's own controller settings; the touch controls hide until you touch the screen.
- **A log file** (`raze-log.txt` in the app's folder) that says what the game was doing, for bug reports.

**This is the first release, so it has had little testing:** see *Known limitations*.

---

### How to play: every control explained

The touch controls appear while you're playing a level, and hide in the menus, cutscenes and while a level loads (there you just tap, as you'd click with a mouse). The game runs in landscape, either way round.

Where everything is (on a phone, turn it sideways to see the whole picture):

```
 NEXT  PREV   [item] [item] [item]   CAMERA CHEAT   SAVE  LOAD  MENU
 WPN   WPN
   [LOOK][SENS][GYRO][FPS][HUD][GRAPHICS][camera][CHEAT][LEVEL][GAMES][keyboard]
                       (MENU's tray, while it's open)

                                                         JUMP
                                                 USE
     ( o )  move stick: appears                              KICK /
            where your left thumb lands       CROUCH    FIRE  ALT FIRE

   [ health, armour ]                               [ ammo, keys ]
```

Exact positions shift a little to fit your screen and the camera cutout. A touch just beside a button still counts.

#### Moving and looking

- **Move:** put your left thumb down anywhere in the left part of the screen and a stick appears under it. Push it the way you want to go: up the screen is forward.
- **Look:** drag anywhere else that isn't a button. The game's own mouse settings (sensitivity, invert) apply. Dragging on FIRE and the buttons round it also looks, so you can fire and aim with one thumb.

#### Buttons

- **FIRE:** fires while held.
- **CROUCH, USE, JUMP:** the arc round FIRE. USE opens doors and presses switches.
- **The button beside FIRE:** **KICK** in *Duke Nukem 3D*, **ALT FIRE** in *Blood* (each weapon's second attack). The other games don't have one.
- **The item buttons** (top row, in the middle): one for each item you can use, with its picture. Tap to use it. A ring round it shows how much is left (gold, red when low); a number shows how many you have; a dim button can't be used right now (for example a medkit at full health). Items the game uses by itself, like Duke's scuba gear, have no button.
- The buttons work whatever keys are set in the game's own controls menu.

#### The weapon wheel (NEXT WPN and PREV WPN)

- **Tap** NEXT WPN or PREV WPN for the next or previous weapon.
- **Slide** from either one and the weapon wheel opens at once: keep sliding toward a weapon and lift to take it.
- **Hold still** about a third of a second: a ring fills and the wheel opens and stays open, so you can tap a weapon.
- One slice per weapon of the game you're playing, with its picture and ammo. Weapons with no ammo are greyed, ones you haven't found yet are faint, and neither can be taken. The gap at the bottom cancels.
- The game holds still while the wheel is open.

#### SAVE and LOAD: why the short hold

**Tap SAVE** or **LOAD** for the game's own Save Game or Load Game menu. **Hold SAVE** about a **third of a second** for a quick save, **hold LOAD** for a quick load: a ring fills round the button, and when it's full the game saves or loads, once, with your finger still down.

**Why the hold?** So a stray touch can't save over your quick save, or throw away your progress by loading an old one. Sliding your finger off before the ring is full cancels.

#### MENU and its hidden tray

**Tap MENU** for the game's menu. **Hold MENU** until its ring fills (about half a second) and a tray opens under it instead, from left to right:

- **LOOK:** how fast dragging turns the view. Each tap steps up (0.5x to 3x); hold it to go back to 1x.
- **SENS:** how far the view turns for a tilt of the phone (1.0x, 1.5x, 2.0x, 3.0x; 1.5x to start).
- **GYRO:** tilt aiming, see below.
- **FPS:** tap to show or hide the frame rate; hold to switch between 60 and 120 frames a second.
- **HUD:** opens a panel to pick the HUD's look and size, and how see-through the HUD and the buttons are. Tap a row's name to put that row back; hold HUD to put everything back.
- **GRAPHICS:** opens a panel: PIXELS (SMOOTH or SHARP) and DETAIL (ORIGINAL, or smoother textures at 2X or 4X).
- **The camera symbol:** shows or hides CAMERA; hold it for the camera's options.
- **CHEAT:** see *The cheat*.
- **LEVEL:** every level of the game you're playing (single player): tap one to go there.
- **GAMES:** switch to another game. Raze plays one game at a time, so the app closes; tap the notification (or open the app within 10 minutes) and it starts the game you picked.
- **The keyboard:** opens the game's console with the iOS keyboard.

A touch anywhere else closes the tray. The app remembers these settings. The build number shows under the tray.

#### Tilt aiming (gyro)

GYRO steps through **OFF** (to start with), **TOUCH** and **ALWAYS**. With **TOUCH**, tilting the phone aims only while a thumb is on the screen; lift both thumbs and the view stays where it is, so you can rest the phone. With **ALWAYS**, tilting always aims.

#### The camera: photos, selfies, bursts and Action Freeze

**CAMERA** sits in the top row. The first time, iOS asks whether the app may **add photos** to your library: say yes and the photos go straight into your Photos app (the app can't see the ones already there).

- **Tap** for a photo. **Hold** half a second for a **selfie**, with the nearest enemies posing (not in *PowerSlave*, which has no one to pose).
- **Slide sideways** for a **burst** of photos.
- **Slide down** for **Action Freeze**: the game stops and you move the camera round it.
- **Slide up** for the **cinematic burst**: photos as the camera sweeps round the action.
- A selfie, a freeze or a burst changes nothing in your game.

#### The cheat (sithewok)

Hold MENU and tap **CHEAT** in the tray, or type `sithewok` in the console. A CHEAT button appears in the top row, with a picture from the game, and the game's hero says a line. While it's on: god mode, every weapon and item (again at each new level), ammo kept full. **Hold USE** half a second to walk through walls (noclip; hold again to stop). In *Shadow Warrior*, **hold JUMP** half a second to fly (JUMP rises, CROUCH sinks, tap JUMP twice to land). **Hold the CHEAT button** half a second to switch the cheat off or on. The cheat works in single player only.

#### Network games (LAN)

In the picker, tap **LAN multiplayer**, pick the game, then host or join. Everyone needs the same game files and the same Wi-Fi. Saving and loading are off in a network game, and the cheat, selfies and Action Freeze are single player only.

#### Menus, leaving the app, and the console

In the menus, tap as you'd click. **Leaving the app doesn't save your game**: quick save first. The console (the tray's keyboard) takes Raze's own commands.

### Known limitations

**Sorry about the bugs.** This is an unofficial fan-made beta, and it's the first release: expect rough edges, and back up your saves. If something breaks, please tell us (see the end of *Install*), and thank you for your patience.

- **What was tested where:** test builds are played on one iPhone; not every game, add-on and feature has been tried there yet. The touch controls, the HUD, the cheat and the camera were also tested on a computer, with the real game files and simulated touches.
- **Multiplayer is the weakest part, sorry.** LAN games have only been tried between copies of the game on one computer, never between two iPhones or iPads on real Wi-Fi. Expect it not to find the other phone, to drop out, or for the games to drift out of step. *PowerSlave* has no multiplayer. It's being worked on.
- **Not tried yet:** iPads (the app is marked for them); keyboards and mice; *NAM* and *WWII GI*, which Raze also plays; user maps and mods.
- **Music:** MIDI music plays through the app's own synthesizers (like an old sound card), so it may sound different from a PC.

### Requirements

- An **iPhone or iPad on iOS 15 or newer.** iPads haven't been tried.
- **Your own copies of the games**, on the computer they're installed on, to copy them to your iPhone. The copies this was made with:
  - *Duke Nukem 3D: 20th Anniversary World Tour* (Steam), and the *Atomic Edition* with its add-ons;
  - *Blood: One Unit Whole Blood* (GOG);
  - *Shadow Warrior Classic Complete* (GOG);
  - *Redneck Rampage Collection* (GOG: *Redneck Rampage* and *Rides Again*);
  - *PowerSlave* (GOG).
- A **sideloading tool or signing service** (something that installs apps from outside the App Store): SideStore, AltStore, Feather, Sideloadly or a paid signing service. `Raze.ipa` isn't signed for your iPhone, so it can't be installed without one. With a free Apple ID, SideStore and AltStore must refresh the app every 7 days.

### Install

1. Download **`Raze.ipa`**, below. Or add the app's source to SideStore or AltStore (*Sources*, **+**): https://raw.githubusercontent.com/sithewok13-dev/Raze-iOS-/ios/ios/altstore-source.json
2. Install it with your sideloading tool or signing service, following that tool's own instructions. On your home screen the app is called **Raze**. Its version shows as 0.1 followed by a build number: that's expected.
3. **Open the app once.** With no games yet, it shows a *Raze: fatal error* box saying *Unable to find any game data. Please verify your settings.* Tap Exit. That's expected: by then the app has made its folder, *On My iPhone > Raze* in the Files app.
4. In the Files app's **On My iPhone > Raze**, make a folder for each game you have, and copy the game's files into it from its folder on your computer (you don't need the `.exe` and `.dll` files):
   - **`Duke Nukem 3D`**: the World Tour's game folder (the one with `DUKE3D.GRP`).
   - **`Duke Nukem 3D Atomic`**: the Atomic Edition's `DUKE3D.GRP`, plus any add-ons you have: `DUKEDC.GRP` (D.C.), `NWINTER.GRP` (Nuclear Winter), `VACATION.GRP` (Caribbean), and for Duke!Zone II its `.GRP` file with `DZ-GAME.CON`, `DZ-DEFS.CON` and `DZ-USER.CON`.
   - **`Blood`**: the game folder (the one with `BLOOD.RFF`), with Cryptic Passage's files if you have it.
   - **`Shadow Warrior`**: the game folder (the one with `SW.GRP`), with `WT.GRP` (Wanton Destruction) and the `dragon` folder (Twin Dragon) if you have them.
   - **`Redneck Rampage`**: the game folder (the one with `REDNECK.GRP`), with Rides Again in its `AGAIN` folder inside it, as GOG has it.
   - **`PowerSlave`**: the game folder (the one with `STUFF.DAT`).

   Copy the folders as they are, not as `.zip` files. Use whatever way you like to get files into the Files app, for example iCloud Drive: copy them into iCloud Drive on your computer, then move them into *On My iPhone > Raze*. The app looks in its folder and two folder levels down, so the folder names above are a suggestion, but keep each game in a folder of its own.
5. **Open the app again.** Tap a game's card.

**Updating:** install the new version with the same tool and the same Apple ID, over the old one, and your games and saves stay.

**Your saves** are in the Files app, in *On My iPhone > Raze > raze > Savegames*. **Back up** that folder now and then (for example to iCloud Drive), and always before you delete or reinstall the app: deleting the app deletes its folder, games and saves included. Your settings are kept by iOS, not in the app's folder.

**If something goes wrong:** `raze-log.txt`, directly in *On My iPhone > Raze*, says what the game was doing. Copy it out before you open the app again, because each start replaces it. **Found a bug?** Please report it here, not to the upstream Raze project, and say you're on **ios-v0.1** (the app shows 0.1 and a build number): https://github.com/sithewok13-dev/Raze-iOS-/issues. Attach `raze-log.txt`, and say which game, which iPhone and iOS version, and what you were doing.

**Download:** `Raze.ipa`, under *Assets* below. The *iOS latest build* prerelease, also on the Releases page, is rebuilt automatically after every code change, before anyone has tried it: use this release.

---

**Thank you** to the people whose work this stands on. Raze is by **Christoph Oelckers** and **Mitchell Richters**, with the ZDoom and GZDoom teams (https://github.com/ZDoom/Raze). Its games come from years of work by others: **Ken Silverman's** Build engine (http://www.advsys.net/ken); **Jonathon Fowler's** JFDuke3D; **EDuke32** by Richard Gobeille (TerminX), Evan Ramos (Hendricks266), pogokeen, Plagman and Helixhorned (https://eduke32.com/); **NBlood** by Nuke.YKT, NoOne and sirlemonhead, and Nuke.YKT's reconstructed Redneck Rampage source; **VoidSW** and SWP; **PCExhumed** by sirlemonhead, Nuke.YKT and NY00123; and BuildGDX by M210. The games themselves are by 3D Realms (*Duke Nukem 3D*, *Shadow Warrior*), Monolith Productions (*Blood*), Xatrix Entertainment (*Redneck Rampage*) and Lobotomy Software (*PowerSlave*). The full list of Raze's authors: https://github.com/sithewok13-dev/Raze-iOS-/blob/ios/AUTHORS.md

Unofficial build, not affiliated with or endorsed by any of them, or by the Raze project. No game files are included.

Raze's own code is free software under the GNU GPL v2 (https://www.gnu.org/licenses/old-licenses/gpl-2.0.html); the Build engine code is under Ken Silverman's BUILD licence (https://github.com/sithewok13-dev/Raze-iOS-/blob/ios/build-doc/buildlic.txt), which allows only non-commercial use. The source code, iOS changes included, is the `ios` branch: https://github.com/sithewok13-dev/Raze-iOS-/tree/ios (this release is the tag `ios-v0.1`: https://github.com/sithewok13-dev/Raze-iOS-/tree/ios-v0.1).

The app also includes libraries under their own licences: SDL2 (zlib licence, https://github.com/libsdl-org/SDL/blob/release-2.32.8/LICENSE.txt), OpenAL Soft (GNU LGPL v2, https://github.com/kcat/openal-soft/blob/1.24.3/COPYING), ZMusic (https://github.com/ZDoom/ZMusic/tree/d3b730795784bff3f97571446101c57c1c6ac9bc/licenses), libvpx (BSD licence, https://github.com/webmproject/libvpx/blob/v1.15.2/LICENSE) and MoltenVK (Apache licence 2.0, https://github.com/KhronosGroup/MoltenVK/blob/v1.4.2/LICENSE). The picker's pictures: https://github.com/sithewok13-dev/Raze-iOS-/blob/ios/ios/art/CREDITS.txt
