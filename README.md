# SR Tweak Menu

An in-game cheat menu for Saints Reborn
([Windows](https://github.com/whompay/SaintsReborn) /
[Mac](https://github.com/00xJS/SaintsReborn-Mac)).

## Install

1. Download this repository (**Code > Download ZIP**) and unzip it.
2. Copy the `SRTweakMenu` folder into your mods folder:
   - **Windows:** `dist\mods\` inside your Saints Reborn folder
   - **Mac:** `~/SaintsReborn/dist/mods/`
3. Start Whompay's Mod Loader, tick **SR Tweak Menu** and press **Play**.
4. In game, open the menu:
   - **Keyboard:** F5
   - **Xbox controller:** hold RB, press D-pad Down
   - **PlayStation controller:** hold R1, press D-pad Down

## Controls

| | Keyboard | Xbox | PlayStation |
|---|---|---|---|
| Open / close menu | F5 | RB + D-pad Down | R1 + D-pad Down |
| Move | Up / Down | D-pad Up / Down | D-pad Up / Down |
| Change value / browse list | Left / Right | D-pad Left / Right | D-pad Left / Right |
| Select | Enter | A | Cross |
| Change tab | PgUp / PgDn | LB / RB | L1 / R1 |
| Back / close | Backspace | B | Circle |
| Stop a pose or repeating action | Shift + Up | RB + D-pad Up | R1 + D-pad Up |

## Features

| Tab | |
|---|---|
| Player | God mode, health multiplier, refill health, never wanted, wanted levels, max wanted, no cops, no gangs, never busted, no ragdoll, perfect aim, run and jump boosts, soft landing, quick crouch, swim speed, fall damage, infinite sprint, +$50,000, +5,000 respect, homie limit 1 to 10, dismiss homies, bodyguards |
| Emotes | Poses, actions (once or on repeat), staged scenes (dance pairs, strip club, house party) |
| Weapons | Infinite ammo, no reload, rapid fire, weapon switch (keys 1 to 8, mouse wheel, D-pad, move with the weapon wheel open), harder hits, one-hit kill, rocket ammo, fire ammo, give any weapon, give every weapon, refill all ammo; aim style: the game's own, Precise Aim (over-the-shoulder camera, accuracy by stance, slow walk) or Fine Aim (zoom, slower turning, tighter shots), Precise Aim's camera (6 styles plus your own, zoom, field of view, height, shoulder), Fine Aim's zoom and spread |
| Vehicles | Vehicle god mode, repair, tank mode, bulletproof glass, no flat tyres, no explosion fling, extra car grip, nitrous in every car, extra top speed, paint, blow up, spawn any of 79 vehicles, deliver to garage |
| World | Weather, time of day, freeze clock, clear / restore traffic, everybody drop, everybody dance or pose, spawn any of 188 people, spawn crowds |
| Visual | Hide HUD, saturation, letterbox, filters, free camera (fly it, or leave it in place and play from that shot), freeze world, wireframe |
| Teleport | Cribs, Saints Row church, teleport to map waypoint |
| Settings | Master switch, show what is on, camera turn speed, aim button (hold or toggle), Precise Aim turning, turn speed while aiming (Precise Aim and Fine Aim), weapon switch D-pad and wheel tap |

Everything starts off. Every menu row has a help line.

## Settings

Every number is in `SRTweakMenu/mod.ini`, and the add-ons' own settings
(keys, sensitivity, accuracy) are in `SRTweakMenu/addons/<add-on>/settings.ini`.
Restart the game after changing them.

Don't tick the standalone Precise Aim, Fine Aim or Weapon Switch mods as well:
SR Tweak Menu already includes them.

## Notes

- Private play only: story co-op and private parties, not public matches.
- Contains no game files.

## Credits

- Saints Reborn and its mod loader by Whompay. Saints Row by Volition.
- [Precise Aim](https://github.com/Eazeepz/Precise-Aim) and
  [Weapon Switch](https://github.com/Eazeepz/Weapon-Switch) by Eazzy (Eazeepz),
  and [Fine Aim](https://github.com/car123609/SaintsReborn-Fine-Aim-Precision-Gunplay)
  by car123609, included with their permission.
- Weapon Switch uses [MinHook](https://github.com/TsudaKageyu/minhook) by Tsuda
  Kageyu (BSD 2-clause, `SRTweakMenu/addons/weapon_switch/MINHOOK_LICENSE.txt`).

SR Tweak Menu's own code is MIT licensed, see `LICENSE`. The add-ons in
`SRTweakMenu/addons` remain their authors' work.
