# LAN games: state and what's left

Branch `ios-net`. The engine side is `source/core/netgame.cpp` (+ hooks in
`i_net.cpp`, `d_net.cpp`, `mainloop.cpp`, `gamecontrol.cpp`), each game's
`SetupNetGame`, and the phone side is `ios/i_ios.mm` (host / join screens,
the waiting box) and `ios/IOSNet.c` (Wi-Fi address, LAN search).

## How it was tested

Linux rig, two (once three) instances on loopback, each with its own HOME
and Xvfb: host `-host 2 +set net_mode N -map <level>`, guest
`-join 127.0.0.1`; `+set net_checksums 1` logs a checksum of every actor's
place, angle, state and health once a second (2: every tic, with sectors and
walls; 3: actor classes; 4: every actor), and the logs of all machines are
compared. Scripted touches (the touch rig) move, turn and fire on both;
`net_presskey` presses a key for the screens between levels;
`net_scan` runs the phone's LAN search.

## Works on the rig (checksums identical)

- Duke 3D (Atomic, World Tour): DukeMatch, co-op, DukeMatch (no spawn);
  co-op level change; friendly fire hurts when on; 3 players.
- Redneck Rampage: Deathmatch, co-op.
- Blood: co-op (with a level change), BloodBath, teams.
- Shadow Warrior: WangBang (with a level change), WangBang (no respawn),
  co-op.

## Not done / not tested

- Exhumed / PowerSlave: two players spawn, but the second doesn't move and
  the machines differ after about 15 s; the level's end waits for a sound
  (each machine's own). Not offered on the phone.
- Real phones on Wi-Fi: nothing yet (the local-network permission, the
  search on a real /24, the UIKit screens, the box while waiting).
- A player leaving mid-game, dying and coming back in a deathmatch, the
  end of an episode, Redneck Rides Again, Duke's other add-ons: not tested.
- A phone in the background stops sending: the others wait (lockstep).
- The CHEAT button, quick save / load, selfies and Action Freeze stay
  single player; saving and loading are off in a network game.
- A desktop Raze can join only if built from this branch (stock Raze
  crashes in its wait for players), with the same game files.
- Anything else that a machine changes only when it draws (as the laser
  trail and the ladder did) would put machines out of step: the zscript
  `animate` overrides were checked for Duke / Redneck only.
