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
   The first time, restart the game once so it loads the menu's player
   animation set (used by Movement styles).
4. In game, open the menu:
   - **Keyboard:** F5
   - **Xbox controller:** hold RB and press D-pad Down
   - **PlayStation controller:** hold R1 and press D-pad Down

## Controls

| | Keyboard | Xbox | PlayStation |
|---|---|---|---|
| Open / close menu | F5 | RB + D-pad Down | R1 + D-pad Down |
| Move | Up / Down | D-pad Up / Down | D-pad Up / Down |
| Change value / browse list | Left / Right | D-pad Left / Right | D-pad Left / Right |
| Select / open a page | Enter | A | Cross |
| Change tab | PgUp / PgDn | LB / RB | L1 / R1 |
| Back a page / close | Backspace | B | Circle |
| Stop a pose or repeating action | Shift + Up | RB + D-pad Up | R1 + D-pad Up |

Outside the Customize tab you can still walk, drive and look around with the
menu open.

## Features

| Tab | |
|---|---|
| Player | Pages: **Health & damage** (god mode, no ragdoll, health multiplier, fall damage, no health regen, heal on D-pad down, refill health, kill yourself), **Movement** (no clip, infinite sprint, sprint presets, run boost, high jump, game jump height, soft landing, quick crouch, crouch while moving, swim speed), **Notoriety** (with the gang you side with), **Bodyguards** (bodyguards, character homies, squad, dismiss, homie limit 1 to 10), **Unlocks** (music, collectibles, clothing, multiplayer and reward clothing, rewards kept in your save); +$50,000, +5,000 respect |
| Emotes | Poses and actions by the game's categories (with props), **Voice Lines**, staged scenes (dance pairs, strip club, house party), repeat, D-pad taunts |
| Weapons | Infinite ammo, no reload, rapid fire, one-hit kill, heavy knockback, perfect aim, no melee lock-on, reload in cars; **Special ammo** (rocket, fire, money gun, explosive punches); **Aiming & switching** (aim style: the game's own, Precise Aim or Fine Aim, the Precise Aim camera page, Fine Aim's zoom and spread, aim button, turning while aiming, weapon switch with its D-pad and wheel tap); **Skins** (a colour for each of 18 weapons); give any weapon (including the Pimp Slap), give every weapon, refill all ammo |
| Vehicles | Vehicle god mode, repair; **Toughness** (tank mode, bulletproof glass and tires, no explosion fling), **Handling** (extra grip, nitrous everywhere, extra top speed, bouncy cars, less stiff cars), **Look** (customize vehicle, paint, secondary colour, brake lights when stopped), **Driving camera** (free camera in cars, reset time up to never, swing-back speed, follows the nose in a slide, free drive-by camera, no swing getting in, field of view at top speed); spawn any of 79 vehicles (plus 24 blinged versions), deliver to garage, destroy |
| World | Weather, no fog, time of day, freeze time, clear / restore streets, stores open 24/7; **People** (spawn any of 188 people, crowds, everybody dance or pose, ragdoll all, kill everyone, gangs in ordinary cars, gangs and police without guns); **Drops** (cash or weapons around you, money rain, cash drop chance); **Districts** (hand any district or the whole city to a gang, reveal the whole map) |
| Visual | Hide HUD, map arrow shows where you face, letterbox, filters, render mode, saturation; **Camera** (field of view, camera turn speed); **Free camera** (fly it, or leave it in place and play from that shot, also in cutscenes; freeze world); **UI+** (low health and low sprint visuals, low health sound echo) |
| Teleport | Cribs, **saved places** (save any spot, go back, rename, delete), every store, every activity, teleport to map waypoint |
| Models | Play as any character model, live: switch, restore your Playa, reload your character; dialogue, animation fallback, cloth physics |
| Customize | The game's character creator, free, as yourself: head, eyes, hair, body, skin, clothes, jewelry, tattoos, 10 saved looks and outfits, voice, facial expressions, movement styles; restore outfit, customization pose |
| Settings | Master switch, **menu look** (plain text or itsMJQ's game look), show active tweaks (every changed setting, by where it is), **save tweaks for next time**, forget saved tweaks, restore menu or game defaults; **Game & saving** (skip intro, load last save, quick save, pause cutscenes, no tutorial popups) |

Cheats start off; a few quality-of-life rows start on (crouch while moving, field of view x1.2, the driving camera), as `mod.ini` sets. **Settings > Save tweaks for next time** makes the menu start the way you've set it. Every menu row has a help line. See
`SRTweakMenu/CHANGELOG.md` for what changed.

## Settings

Every number is in `SRTweakMenu/mod.ini`, and the add-ons' own settings
(keys, sensitivity, accuracy) are in `SRTweakMenu/addons/<add-on>/settings.ini`.
Restart the game after changing them.

Don't tick the standalone Precise Aim, Fine Aim or Weapon Switch mods as well:
SR Tweak Menu already includes them.

## Works with

- **SaintsReborn Music Player** with its `MP3_Stocks` song copies: the next
  song starts by itself and the music follows the pause menu's volume.
- **HomieHeads**: HUD heads for recruited gang members and characters
  without a head picture.

## Notes

- Private play only: story co-op and private parties, not public matches.
- Contains no game files.

## Credits

- Saints Reborn and its mod loader by Whompay. Saints Row by Volition.
- The quality-of-life rows follow ideas from the Saints Row 2
  [Juiced Patch](https://github.com/kobraworksmodding/Saints-Row-2-Juiced-Patch)
  by Kobraworks Modding (Soaa, Tervel, Clippy95, Scanti and contributors);
  they're written for Saints Row 1 and contain none of its code.
- Several rows follow ideas from Saints Row (2006) mods on
  [saintsrowmods.com](https://www.saintsrowmods.com/forum/forums/saints-row-2006.237/):
  the weapon Color Tints, Hardcore Edition and Stilwater+ (Ricsow), the
  Stamina Mod, Saints of Rage, Gangs drive civilian cars, More Unlockable
  Unlock Rewards, Bouncy Cars (Ricsow), Simply Less Damping (B Dawg), Fully
  explored map + 24/7 Stores (Ricsow), Gangs of Stilwater (Jacob_MP) and
  Tervel's "Enable MP actions in SP" patch. None of their files are used:
  the menu does the same live, on the game's own data.
- **itsMJQ**: the Models and Customize tabs, movement styles, the emotes
  pages, voice lines and voices, character homies, customize vehicle, store
  and activity teleports, unlocks, render modes, the UI+ screen effects, the
  music fixes, the menu's pages and moving with the menu open, and the
  findings behind them (see the changelog).
- [Precise Aim](https://github.com/Eazeepz/Precise-Aim) and
  [Weapon Switch](https://github.com/Eazeepz/Weapon-Switch) by Eazzy (Eazeepz),
  and [Fine Aim](https://github.com/car123609/SaintsReborn-Fine-Aim-Precision-Gunplay)
  by car123609, included with their permission.
- Weapon Switch uses [MinHook](https://github.com/TsudaKageyu/minhook) by Tsuda
  Kageyu (BSD 2-clause, `SRTweakMenu/addons/weapon_switch/MINHOOK_LICENSE.txt`).

SR Tweak Menu's own code is MIT licensed, see `LICENSE`. The add-ons in
`SRTweakMenu/addons` remain their authors' work.
