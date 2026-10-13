# SR Tweak Menu

A mod for Saints Reborn ([Windows](https://github.com/whompay/SaintsReborn) /
[Mac](https://github.com/00xJS/SaintsReborn-Mac)), the Windows and Mac
version of the original Saints Row, with an in-game menu: god mode,
wanted level, infinite ammo and no reload, rocket and fire ammo, every
weapon, vehicle god mode, nitrous in every car, car paint, any of the game's
79 vehicles or 188 people spawned in front of you, bodyguards and up to ten
homies, everybody dance, poses and staged scenes, a free camera that can
also hold a shot while you play, teleports to every crib and to your map
waypoint, weather, time, visual filters and more, on top of handling, weapon
and on-foot tweaks. Every number is a setting.

Formerly Saints Tweaks.

Not made by or connected to the Saints Reborn project, Volition or Deep
Silver. Contains no game files.

## Install

1. Download this repository (Code > Download ZIP) and unzip it.
2. Copy the `SRTweakMenu` folder into your mods folder:
   - **Windows** ([Saints Reborn](https://github.com/whompay/SaintsReborn)): `dist\mods\` inside your Saints Reborn folder
   - **Mac** ([Saints Reborn for Mac](https://github.com/00xJS/SaintsReborn-Mac)): `~/SaintsReborn/dist/mods/`
3. Start Whompay's Mod Loader, tick **SR Tweak Menu**, press **Play**.
4. In the game press **F5**.

**Windows and Mac.** The Mac version runs the same Windows build under Wine,
so the whole mod works on both, menu overlay and keyboard included.

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
combo never cancels an activity. **RB + D-pad up** (Shift + Up) ends a pose
or a repeating action at any time (`stop_pad`). While the menu is open the
game gets no input, so you stand still. Keys and rows per page are in
`mod.ini`.

| Tab | What is there |
|---|---|
| Player | God mode, refill health, homie limit 1 to 10 and dismiss all homies (from the More Homies mod), spawn a bodyguard (12 to pick from, armed, following and fighting as a homie) or a squad of four Saints, never wanted, police and gang notoriety levels, max notoriety, no cops, no gangs, never busted, no ragdoll, perfect aim, run boost and run speed, high jump and jump boost, soft landing, the game's own jump height, swim speed, fall damage, infinite sprint, money (+$50,000 a press), respect (+5,000 a press) |
| Emotes | Pose: strike one of 34 poses the game's characters use (dances, breakdance, pole and stage dance, smoking, drinking, reading the paper, preaching, zombie eat ...) and hold it until you move. Stage a scene: dance pairs, a strip club or a house party, all women, spawned in front of you, everyone holding their part; Clear scene removes them. RB + D-pad Up (Shift + Up) stops a pose or a repeating action. Action: one of 28 one-off moves (flip off, wave, taunts, gang signs, pimp slap, pop and lock ...), once or on repeat for recording. The game's brothel animations are only placeholders in its files (cut before release), so they are not offered |
| Weapons | Infinite ammo, no reload, auto fire, one-hit kill, rocket ammo (any gun fires real RPG rockets, up to ten a second and sixteen in the air; faster shots stay bullets), fire ammo (people you shoot catch fire), give a weapon, give every weapon, refill all ammo |
| Vehicles | Vehicle god mode, repair, tank mode, bulletproof glass, never flat tyres, no explosion fling, nitrous in every car (on/off), extra top speed, paint my car and a second colour (36 paints, the gang colours among them; stays when you garage it), blow up my car, spawn any of the game's vehicles in front of you, alphabetical (hidden ones too) or deliver it to your garage, remove what you spawned |
| World | Weather, time of day, freeze the clock, clear traffic and peds, restore traffic and peds, everybody drop (every ped ragdolls), Everybody... (the people around you dance, breakdance, cower, act drunk and more; each person only does what their own animations allow, so cops and some gang members sit some out), spawn any of the game's 188 people in an arc in front of you (alphabetical, by group; they come as civilians, so gang members don't start a fight, and they stay until you remove them; up to 8 kinds of person at once, as the game only has room for 12 person models and the city needs some, so a ninth kind replaces the oldest), spawn a crowd of random people, remove them again |
| Visual | Hide HUD, saturation, letterbox, filters (Noir, Sepia, Vivid, Cold, Warm, Night vision, Retro), free camera (fly the camera for photos: WASD or left stick, mouse or right stick, E/Q or the triggers up and down, Shift fast, Z/X or LB/RB zoom; your character holds still while you look around), free camera mode (Enter or A while flying leaves the camera where it is and gives you back control: play, drive and fight seen from that shot, either fixed or turning to keep you in frame; the right stick or mouse spins your aim round you like a twin-stick game, level at chest height, so you only pick a direction), freeze world (while the menu is open or the free camera flies), wireframe world |
| Teleport | The four cribs, the penthouse door and the Saints Row church. Teleport on map waypoint (set a waypoint on the pause map and you are there) and Go to my waypoint, from the Teleport to Waypoint mod. Your car and homies come along |
| Settings | Master switch, what is on |

Every row has a help line saying what it changes; sliders also show the
game's default. Items marked experimental rest on reading the game's code
and have not been confirmed in play yet.

## What else it does

**Vehicles**
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
