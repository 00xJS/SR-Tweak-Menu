# Saints Tweaks

A mod for [Saints Reborn](https://github.com/whompay/SaintsReborn) (Saints
Row, Xbox 360, recompiled for PC and Mac): supercar handling for every
vehicle, tank mode, rapid fire with the guns' own sounds, near-perfect aim,
heavy damage, high jumps with safe landings, and hotkeys with on-screen
messages. Every number is a setting.

Not made by or connected to the Saints Reborn project, Volition or Deep
Silver. Contains no game files.

## Install

1. Download this repository (Code > Download ZIP) and unzip it.
2. Copy the `SaintsTweaks` folder into `dist\mods` of your Saints Reborn
   install (on Mac, `~/SaintsReborn/dist/mods`).
3. Run Whompay's Mod Loader, tick **Saints Tweaks**, press Play.

Like every gameplay mod it is private play only: story co-op and private
parties, not public matches.

## What it does

**Vehicles**
- Every ordinary vehicle gets the engine and gearbox of the game's fastest
  car and a 140 mph top speed, so a station wagon pulls away like the
  exotic. The train and trailers are left alone.
- Your own car gets extra torque on top (1.5x) through the game's own
  torque-multiplier field, so traffic doesn't.
- Tank mode: the car you drive is immovable in collisions, the game's own
  "infinite mass" mission effect. Other cars bounce off you.
- 10x hitpoints for every vehicle, nitrous everywhere, extra downforce.

**Weapons**
- 2x fire rate (shotguns 4x), spread cut to 5 percent, one-shot guns get an
  8-round magazine.
- Auto fire: hold the trigger and single-shot guns (pistols, shotguns, RPG)
  keep firing with their own sound and animation. Done by tapping the
  trigger where the game reads the controller; automatic guns are left
  alone so their loop sound stays clean.
- 10x damage from your guns and melee. Enemies have one fifth of their
  health; you have 3x and can't be knocked down. Homies are untouched.

**On foot**
- 1.5x running speed, 4x jump, near-instant crouch, 2x sprint length.
- Soft landing: no fall damage, no stumble, no ragdoll, from any height.

## Keys

| Key | Does |
|---|---|
| B | every runtime tweak off / on |
| 1 | run boost |
| 2 | high jump |
| 3 | soft landing |
| 4 | tank mode |
| 5 | engine boost on your car |
| 6 | auto fire |
| 0 | shows what is on and off |

Each press shows a message on screen. Keys and all numbers are in
`SaintsTweaks/mod.ini` under `[settings]`; restart the game after changing
them. Table changes (vehicles, weapons, health) always apply while the mod
is ticked.

## How it works

`patch.lua` edits the game's own tables inside your packfiles before the
game starts (vehicles, weapons, melee, ranks, camera, sprint, constants).
Nothing is shipped from the game; the loader rebuilds the tables from your
copy and caches them.

`main.lua` runs while you play. It hooks the game update to measure your
movement and add to it, scales the jump impulse on the physics body, sets
the infinite-mass flag and torque multiplier on your vehicle, taps the right
trigger in the controller read, shields you while falling, reads the
equipped weapon the way the game's own `inv_item_is_equipped` does, and
shows messages through the game's `message` path.

Addresses were found in the recompiled source Saints Reborn builds on your
own machine, so no game code is included here. `tools/script_functions.txt`
lists the game's 643 script functions with their addresses, recovered from
the registration code, for anyone writing their own mod.

## Tools

- `tools/vpp.py <pack.vpp_xbox2> [outdir]` lists or extracts a Saints Row
  packfile (Python 3, no dependencies).
- `tools/harness.lua <src> <out> <mod.ini> <patch.lua>` runs a patch script
  offline against extracted tables, with a fake `wml` table (Lua 5.4).

## Credits

- Saints Reborn by Whompay, and its mod loader and trainer, whose
  conventions this mod follows.
- Volition, for the game.

MIT license, see `LICENSE`.
