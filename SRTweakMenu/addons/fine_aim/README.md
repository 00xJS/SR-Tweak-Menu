# SaintsReborn – Fine Aim & Precision Gunplay

**Version 1.5.0 · Author: car123609!**

Bring a Saints Row 2-inspired fine aim feel to SaintsReborn. Aim more precisely with smooth camera zoom, adjustable mouse and controller sensitivity, and tighter bullet spread. Keep your gun raised while walking, strafing or crouching.

## Features

- Smooth zoom when entering and leaving fine aim.
- Adjustable aiming sensitivity for both mouse and controller.
- Reduced random bullet spread while fine aiming.
- A raised weapon stance that follows the camera while you move.
- Walking and crouching remain available while aiming; sprinting cancels aim.
- A shorter hold after firing, including normal hip fire.
- Existing weapon scopes retain their original controls.

## Installation

Requires SaintsReborn with **Whompay's Mod Loader (WML)**. This version was built for the supplied SaintsReborn build.

1. Close the game.
2. Copy the **FineAim** folder from the mod download into the **dist\mods** folder.
3. If updating, back up your settings, remove the old FineAim folder, then copy in the new one. Reapply your preferred settings to the new `mod.ini`.
4. Open `WhompaysModLoader.exe`, enable **Fine Aim - Precision Gunplay**, and press **Play**.

In the source project's usual layout, the two mod files should be:

```text
dist\mods\FineAim\main.lua
dist\mods\FineAim\mod.ini
```

No game rebuild is needed.

## Controls

These controls apply with the standard right mouse and RS/R3 bindings.

| Input | Action |
| --- | --- |
| Hold right mouse button | Fine aim; release to stop |
| Left mouse button | Fire |
| Hold Alt | Use the gun's original secondary attack |
| Click RS / R3 | Toggle controller fine aim on or off |
| Right stick | Look and aim |
| RT / R2 | Fire |
| LT / L2 | Original secondary attack with the RS/R3 aim binding |
| Shift or RB / R1 | Sprint and cancel fine aim |
| F8 | Turn the mod on or off |

RS/R3 means clicking the right stick. Mouse and controller aiming can both be used during the same session.

## Walking and sprinting

Normal WASD or left-stick movement keeps fine aim available, including full left-stick movement. You can also strafe and crouch while aiming.

With `cancel_when_running = true`, the faster sprint action cancels aim:

- **Controller toggle:** stop sprinting, then release and click RS/R3 again to resume aiming.
- **Mouse hold:** aiming resumes after sprinting if you are still holding right mouse.
- **Mouse toggle:** click the aim button again after sprinting to resume aiming.

Controller aim also resets when entering menus, vehicles, cutscenes or other situations where fine aim is unavailable. Click the aim control again when you return to normal gunplay.

## Settings

Close the game, edit `mods\FineAim\mod.ini`, save it, and restart the game. **F8 switches the mod on or off; it does not reload settings.**

### Aim feel

| Setting | Example value | What it does |
| --- | --- | --- |
| `sensitivity_multiplier` | `0.40` | Uses 40% of normal look speed while aiming, for mouse and controller. Lower values make aiming slower. Range: 0.05–1. |
| `fov_multiplier` | `0.75` | Zooms to 75% of your normal field of view. A 60° view becomes 45°. Lower values zoom closer; 1 removes the zoom. |
| `spread_multiplier` | `0.25` | Uses 25% of the normal random shot-spread angle while fine aiming. 0 removes random aiming spread; 1 uses normal spread. |
| `aim_in_time` | `0.12` | Controls how quickly the camera eases into zoom, in seconds. Lower is faster; 0 is instant. |
| `aim_out_time` | `0.10` | Controls how quickly the camera eases out of zoom, in seconds. Lower is faster; 0 is instant. |
| `post_shot_hold_ms` | `150` | Adds 0.15 seconds of raised-gun time after the firing animation, including hip fire. 0 removes the extra hold; 2500 restores the original extra delay. |

The spread adjustment affects random aiming spread. Shotguns keep their normal pellet cone. Hip fire keeps its normal accuracy.

### Mouse and keyboard

| Setting | Value | What it does |
| --- | --- | --- |
| `aim_key` | `2` | Right mouse button. Keyboard key names can also be used. |
| `toggle_aim` | `false` | Hold to aim. Set to true to click once to aim and again to stop. |
| `enable_key` | `F8` | Key used to switch the mod on or off. |
| `secondary_key` | `ALT` | Key held to use the original secondary attack with normal guns. |

### Controller

| Setting | Value | What it does |
| --- | --- | --- |
| `controller_enabled` | `true` | Enables controller fine aim. |
| `controller_toggle` | `true` | Press once to aim and again to stop. Set to false to hold the aim control instead. |
| `controller_button` | `RS` | Uses right-stick click / R3. Change to LT to use the left trigger / L2. |
| `controller_trigger_threshold` | `120` | How far LT/L2 must be pressed to activate aim. Lower values activate sooner. Applies only when LT is selected. |

If you select `controller_button = LT`, LT/L2 becomes the fine aim control for normal guns, and RS/R3 returns to its original game function.

### Movement and other options

| Setting | Value | What it does |
| --- | --- | --- |
| `enabled` | `true` | Starts the mod enabled. |
| `cancel_when_running` | `true` | Cancels aim during sprinting. Set to false to allow fine aim while sprinting too. |
| `raise_weapon` | `true` | Keeps the gun raised while fine aiming and moving. Reloads and scripted actions keep their own animations. |
| `face_camera_while_aiming` | `true` | Turns the character and gun toward the camera's horizontal aim direction, including while strafing. |
| `preserve_native_scopes` | `true` | Preserves the original controls for weapons with their own scope or zoom. |
| `include_launchers` | `true` | Allows fine aim with rocket launchers. |
| `debug` | `false` | Set to true to log aim changes and shots affected by the accuracy adjustment. |

## Compatibility

Fine aim supports pistols, SMGs, rifles, shotguns and launchers while on foot. It is unavailable in vehicles, menus and cutscenes, and with melee or thrown weapons. Weapons with their own scope keep their original zoom when `preserve_native_scopes` is enabled.

The raised stance uses the game's existing weapon animations. The character follows horizontal camera direction, while the game handles gun and arm pitch.

The mod can be used with the built-in First Person mod. If using other camera mods, place Fine Aim later in the WML load order and check for camera conflicts.

WML currently marks this version as **private play only**. Use it in single-player or private sessions.

## Troubleshooting

- **The mod does not start:** check that `main.lua` and `mod.ini` are directly inside `mods\FineAim`, and that the mod is enabled in WML.
- **A setting seems unchanged:** close and restart the game after saving `mod.ini`. Toggling F8 does not reload it.
- **Controller aim stops after sprinting:** release and click RS/R3 again. This is the intended toggle behaviour.
- **A scoped weapon uses its original zoom:** this is controlled by `preserve_native_scopes`.
- **Aim or sensitivity still fails:** check `mods\wml.log`. Set `debug = true`, restart, reproduce the issue, and include the log when reporting it.
- **The log reports an unsupported executable:** use the compatible SaintsReborn build. This version checks compatibility and stays inactive if the game layout differs.

## Uninstall

Close the game, then disable the mod in WML or remove the `mods\FineAim` folder. Start the game again.

## Credits

Fine Aim mod author: **car123609!**

SaintsReborn and Whompay's Mod Loader: **Whompay**.
