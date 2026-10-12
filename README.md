# SR Tweak Menu

A mod for [Saints Reborn](https://github.com/whompay/SaintsReborn) (Saints
Row, Xbox 360, recompiled for PC and Mac) with an in-game menu: god mode,
wanted level, infinite ammo and no reload, every weapon, vehicle god mode,
nitrous in every car, any of the game's 84 vehicles spawned in front of you,
crowds of people, 21 teleport spots, weather, time, visual filters and more,
on top of handling, weapon and on-foot tweaks. Every number is a setting.

Formerly Saints Tweaks.

Not made by or connected to the Saints Reborn project, Volition or Deep
Silver. Contains no game files.

## Install

1. Download this repository (Code > Download ZIP) and unzip it.
2. Copy the `SRTweakMenu` folder into `dist\mods` of your Saints Reborn
   install (on Mac, `~/SaintsReborn/dist/mods`).
3. Run Whompay's Mod Loader, tick **SR Tweak Menu**, press Play.
4. In the game press **F5**.

Like every gameplay mod it is private play only: story co-op and private
parties, not public matches.

## The menu

**F5** opens and closes it, or on a controller **hold RB and press D-pad
down** (R1 + D-pad down on a PlayStation pad). Up and Down move, Left and
Right change a value or browse a list, Enter switches a feature on or off or
runs it, PgUp and PgDn change tab, Backspace closes. On a controller: D-pad,
A selects, B goes back or closes, LB/RB change tab. The hints at the bottom
follow whichever you last used.

Every controller (Xbox, PlayStation, Switch and others) reaches the game as
an Xbox pad, so the buttons are named the Xbox way. The combo is
`menu_pad` in `mod.ini` (for example `LB+RB+DOWN`, or PlayStation names such
as `R1+DOWN`). While RB is held, D-pad down is kept from the game, so the
combo never cancels an activity. While the menu is open the game gets no
input, so you stand still. Keys and rows per page are in `mod.ini`.

| Tab | What is there |
|---|---|
| Player | God mode, refill health, never wanted, police and gang notoriety levels, max notoriety, no cops, no gangs, never busted, no ragdoll, perfect aim, run boost and run speed, high jump and jump boost, soft landing, the game's own jump height, swim speed, fall damage, infinite sprint, money, max respect |
| Weapons | Infinite ammo, no reload, auto fire, one-hit kill, give a weapon, give every weapon, refill all ammo |
| Vehicles | Vehicle god mode, repair, tank mode, bulletproof glass, never flat tyres, no explosion fling, nitrous strength, extra top speed, blow up my car, spawn any of the game's 84 vehicles in front of you (hidden ones too) or deliver it to your garage, remove what you spawned |
| World | Weather, time of day, freeze the clock, clear traffic and peds, everybody drop (every ped ragdolls), spawn a crowd of random people, remove them again |
| Visual | Hide HUD, saturation, letterbox, wireframe world |
| Teleport | 21 places from the game's own level data: the four cribs, every district, the hospital, the police station, the airport, the docks and more. Your car and homies come along |
| Settings | Master switch, what is on |

Every row has a help line saying what it changes; sliders also show the
game's default. Items marked experimental rest on reading the game's code
and have not been confirmed in play yet.

## What else it does

**Vehicles**
- Nitrous pushes your own car 1.5x harder (the game's own multiplier field,
  which only acts while boosting), so traffic doesn't.
- Tank mode: the car you drive is immovable in collisions, the game's own
  "infinite mass" mission effect. Other cars bounce off you.
- Every car has nitrous (Shift), so a random car off the street has it too
  (`vehicle_nitrous_everywhere`).
- Optional (`vehicle_uniform = true`, off by default): every ordinary vehicle
  gets the engine and gearbox of the game's fastest car and a 140 mph top
  speed, nitrous and extra downforce. This buffs cop and gang cars too, so it
  is off; the train and trailers are always left alone. Vehicle hitpoints
  are a setting too (`vehicle_hitpoints_multiplier`, 1 by default).

**Weapons**
- 2x fire rate (shotguns 4x), spread cut to 5 percent, one-shot guns get an
  8-round magazine.
- Auto fire: hold the trigger and single-shot guns (pistols, shotguns, RPG)
  keep firing with their own sound and animation. Done by tapping the
  trigger where the game reads the controller; automatic guns are left
  alone so their loop sound stays clean.
- You have 3x health and can't be knocked down.
- Damage and enemy health multipliers (`damage_multiplier`,
  `npc_health_multiplier`) default to 1. The game's weapon and rank tables
  are shared: a damage multiplier also applies to enemies shooting your
  homies, and street-recruited homies use the gang ranks, so a health cut
  hits them too. Raise these only if you play without homies.

**On foot**
- 4x jump at start and an optional 1.5x run boost (off by default: it
  moves you a little further each update, which can look like a stutter),
  both with sliders in the menu; near-instant crouch, 2x sprint length.
- Soft landing: no fall damage, no stumble, no ragdoll, from any height.

## Keys

The old shortcuts still work beside the menu.

| Key | Does |
|---|---|
| F5 | the menu |
| B | every runtime tweak off / on |
| 1 | run boost |
| 2 | high jump |
| 3 | soft landing |
| 4 | tank mode |
| 5 | nitrous strength on your car |
| 6 | auto fire |
| 7 | max notoriety: cops and every gang to level 5 (`notoriety_teams`, `notoriety_level`) |
| 0 | shows what is on and off |

Each press shows a message on screen. Keys and all numbers are in
`SRTweakMenu/mod.ini` under `[settings]`; restart the game after changing
them. Table changes (vehicles, weapons, health) always apply while the mod
is ticked.

## How it works

`patch.lua` edits the game's own tables inside your packfiles before the
game starts (vehicles, weapons, ranks, camera, sprint, constants).
Nothing is shipped from the game; the loader rebuilds the tables from your
copy and caches them.

`main.lua` runs while you play. It hooks the game update and from there
drives the menu (`menu.lua`) and applies every feature (`features.lua`,
addresses in `game.lua`). Features are flag bits on the player or your car,
the game's own global settings (ammo, densities, swim speed, gravity on
people), direct calls to game functions (notoriety, repair, nitrous), and two
bigger levers: the game's own Lua 5.0 script state, where its 643 mission
script functions (`set_weather`, `inv_item_add`, `teleport` ...) are run by
name, and the debug console Volition left in the game, which still answers
commands such as `super_ragdoll` and `hood_win_all`.

A Lua mod cannot draw on screen, so `menu_overlay.dll` (Windows, source in
`menu_overlay.c`, about a hundred lines) does only that: `main.lua` writes
the menu text into a mailbox in guest memory and the DLL shows it with the
loader's text overlay; on the Mac the game runs as the Windows build under
Wine, so the DLL works there too. Without the DLL every action shows a
one-line HUD message instead. Build it with the clang that ships with Saints
Reborn:

```
clang -shared -O2 -I <SaintsReborn>/modding/include -o menu_overlay.dll menu_overlay.c
```

Addresses were found in the recompiled source Saints Reborn builds on your
own machine, so no game code is included here. `tools/script_functions.txt`
lists the game's 643 script functions with their addresses, recovered from
the registration code, for anyone writing their own mod.

## Tools

- `tools/vpp.py <pack.vpp_xbox2> [outdir]` lists or extracts a Saints Row
  packfile (Python 3, no dependencies).
- `tools/harness.lua <src> <out> <mod.ini> <patch.lua>` runs a patch script
  offline against extracted tables, with a fake `wml` table (Lua 5.4).
- `tools/test_menu.lua` drives the whole runtime mod offline against a fake
  game (`python -I tools/run_lua.py tools/test_menu.lua SRTweakMenu`; needs
  `pip install lupa`).

## Credits

- Saints Reborn by Whompay, and its mod loader and trainer, whose
  conventions this mod follows.
- Volition, for the game.

MIT license, see `LICENSE`.
