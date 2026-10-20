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
   - **Xbox controller:** hold Back/View for 0.8 seconds, or hold RB and press D-pad Down
   - **PlayStation controller:** hold Select/Share for 0.8 seconds, or hold R1 and press D-pad Down

## Controls

| | Keyboard | Xbox | PlayStation |
|---|---|---|---|
| Open / close menu | F5 | Hold Back/View, or RB + D-pad Down | Hold Select/Share, or R1 + D-pad Down |
| Move | Up / Down | D-pad Up / Down | D-pad Up / Down |
| Change value / browse list | Left / Right | D-pad Left / Right | D-pad Left / Right |
| Select / open a page | Enter | A | Cross |
| Change tab | PgUp / PgDn | LB / RB | L1 / R1 |
| Back a page / close | Backspace | B | Circle |
| Stop a pose or repeating action | Shift + Up | RB + D-pad Up | R1 + D-pad Up |

Outside the Customize tab you can still walk, drive and look around with the
menu open. A short tap of Back still does the game's Back.

## Features

| Tab | |
|---|---|
| Player | Pages: **Logic** (god mode, no clip, health multiplier, refill health, kill yourself, no ragdoll, run boost, high jump boost, game jump height, soft landing, quick crouch, swim speed, fall damage, infinite sprint, perfect aim), **Notoriety** (never wanted, Saints are enemies, police, gang and Saints notoriety, max notoriety, no cops, no gangs, never busted), **Bodyguards** (bodyguards, character homies, squad, dismiss homies, homie limit 1 to 10), **Voice Lines**; +$50,000, +5,000 respect |
| Models | Play as any character model, live: switch, restore your Playa, reload your character; dialogue, animation fallback, cloth physics |
| Customize | The game's character creator, free, as yourself: head, eyes, hair, body, skin, clothes, jewelry, tattoos, 10 saved looks and outfits, voice, facial expressions, movement styles (stance, walk, run, sprint, melee and throw run, combat, melee combat) |
| Emotes | Poses and actions by the game's categories (with props), staged scenes (dance pairs, strip club, house party), repeat |
| Weapons | Infinite ammo, no reload, rapid fire, heavy knockback, one-hit kill, rocket ammo, fire ammo, weapon switch (keys 1 to 8, mouse wheel, D-pad, move with the weapon wheel open), aim style: the game's own, Precise Aim (over-the-shoulder camera, accuracy by stance, slow walk) or Fine Aim (zoom, slower turning, tighter shots), give any weapon, give every weapon, refill all ammo, a **Precise Aim camera** page (6 styles plus your own), Fine Aim's zoom and spread (aim rows show for the aim style you pick) |
| Vehicles | Vehicle god mode, repair, tank mode, bulletproof glass, bulletproof tires, no explosion fling, extra car grip, nitrous in every vehicle, spawn any of 79 vehicles, deliver to garage, customize vehicle (every part and colour), paint, destroy, extra top speed |
| World | Weather, time of day, freeze time, clear / restore streets, ragdoll all NPCs, kill everyone, everybody dance or pose, spawn any of 188 people, spawn crowds |
| Visual | Hide HUD, letterbox, free camera (fly it, or leave it in place and play from that shot, also in cutscenes), freeze world, filters, render mode (no sky, no textures, no people, people only), saturation |
| Teleport | Cribs, every store, every activity, teleport to map waypoint |
| Settings | Master switch, show active tweaks; **Controls** (camera turn speed, aim button hold or toggle, Precise Aim turning, turn speed while aiming, weapon switch D-pad and wheel tap, shown when Weapon switch is on); **UI+** (low health and low sprint visuals, low health sound echo); **Unlocks** (music, collectibles, clothing); **Tweak Settings** (restore outfit, customization pose, animation fallback, cloth physics) |

Everything starts off. Every menu row has a help line. See
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
- **itsMJQ**: the Models and Customize tabs, movement styles, the emotes
  pages, voice lines and voices, character homies, customize vehicle, store
  and activity teleports, unlocks, render modes, the UI+ screen effects, the
  music fixes, the menu's pages, hold-Back shortcut and moving with the menu
  open, and the findings behind them (see the changelog).
- [Precise Aim](https://github.com/Eazeepz/Precise-Aim) and
  [Weapon Switch](https://github.com/Eazeepz/Weapon-Switch) by Eazzy (Eazeepz),
  and [Fine Aim](https://github.com/car123609/SaintsReborn-Fine-Aim-Precision-Gunplay)
  by car123609, included with their permission.
- Weapon Switch uses [MinHook](https://github.com/TsudaKageyu/minhook) by Tsuda
  Kageyu (BSD 2-clause, `SRTweakMenu/addons/weapon_switch/MINHOOK_LICENSE.txt`).

SR Tweak Menu's own code is MIT licensed, see `LICENSE`. The add-ons in
`SRTweakMenu/addons` remain their authors' work.
