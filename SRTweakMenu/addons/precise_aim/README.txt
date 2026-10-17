PRECISE AIM 1.0 for Saints Reborn
=================================

Over-the-shoulder aiming for Saints Row 1 on PC, on keyboard and mouse or a
controller. Aim any gun, grenade or melee weapon, on foot or from a vehicle.
The camera moves over your shoulder and zooms in, and your shots tighten. When
you stand still or slow walk, your character shoulders the gun and strafes in
every direction while facing where you aim.


INSTALL
-------
Needs Saints Reborn with Whompay's Mod Loader.

  1. Copy the Precise_Aim folder into Saints Reborn's dist\mods folder, so
     you end up with  ...\dist\mods\Precise_Aim\main.lua
  2. Run WhompaysModLoader.exe, tick Precise Aim, and press Play.

Updating: replace main.lua, presets.ini and README.txt. You can keep your own
mod.ini, but new settings only appear in the new one. Your saved cameras
(camera.cfg, my_presets.ini) are kept either way.

Uninstall: untick it in the mod loader, or delete the Precise_Aim folder.

Turn off other mods that change aiming, the aim camera or walking (for example
Fine Aim, Walk Toggle or Alt Camera Modes). They fight over the same controls.
Free Cam reads the mouse every frame too: while both are on, the sensitivity
settings have no effect.


HOW AIMING WORKS
----------------
Aim         Press aim (right mouse / LT). The gun comes up, the camera moves
            over your shoulder and zooms in, and your shots tighten. Aim is a
            toggle: press once to aim, again to stop (aim_toggle = 0 in
            mod.ini to hold instead).

Precise     Stand still while aiming for half a second, fire while standing
aim         still, or aim with slow walk on. Your character shoulders the gun,
            strafes in every direction and faces the aim. Pushing the stick
            or keys fully (without slow walk) goes back to normal aim. On a
            controller, walking with the stick pushed gently also counts.
            Pistols, revolvers and SMGs have no shoulder pose and keep their
            normal aim.

Slow walk   Caps Lock / a quick tap of LB. It only slows you down. Aim while
            slow walking to go straight into precise aim.

Sprint      Sprinting while aiming lowers your weapon (and ends a toggled aim).
            Pressing aim while sprinting stops the sprint.

Grenades    Aim to hold the grenade up and line up the throw, left click / RT
            to throw. The quick toss is on X / right stick click.

Melee       Aim to ready the weapon, left click / RT to swing. The weapon's
weapons     other attack is on X / right stick click.

Vehicles    Aim (right mouse / LB) to raise your gun for a drive-by. The view
            zooms in slightly and your shots tighten. Shoot as usual.

Sniper      The sniper rifle keeps the game's own scope on right mouse / LT.


CONTROLS: KEYBOARD AND MOUSE
----------------------------
Right mouse       aim
Left mouse        shoot / throw / swing
X                 melee while a gun is out (moved off right mouse),
                  quick grenade toss, a melee weapon's other attack
Caps Lock         slow walk on / off
C                 crouch, also while moving
Shift             sprint (lowers the weapon)

Camera tuning while you play (saved automatically):
  - / +              zoom in / out
  Page Up / Down     field of view wider / narrower
  Home / End         camera lower / higher
  Ctrl+I / Ctrl+O    shoulder left / right
  Ctrl+K / Ctrl+Y    previous / next preset
  Ctrl+J             reset to the preset's own values
  Ctrl+U             save the current camera as a preset
  Ctrl+G             delete the selected saved preset


CONTROLS: CONTROLLER
--------------------
LT                aim
RT                shoot / throw / swing
Right stick click melee while a gun is out (LT is now aim),
                  quick grenade toss, a melee weapon's other attack
LB (quick tap)    slow walk on / off
LB (in vehicles)  aim a drive-by (LB no longer looks left in vehicles)
Crouch button     crouch, also while moving
Sprint button     sprint (lowers the weapon)

Sprint, crouch and the weapon menu follow the controller scheme picked in the
game's options (A, B or C).

The mod turns the camera from the right stick itself: one small deadzone, a
smooth curve and no acceleration, at the same speed on foot, while aiming and
in vehicles. Your game options still apply (invert X / Y, look sensitivity,
stick layout). Holding the stick fully left or right speeds up turning after
a moment.

Camera tuning: hold LB and press
  Y / A              zoom in / out
  B / X              field of view wider / narrower
  D-pad up / down    camera higher / lower
  D-pad left / right shoulder left / right
  RB                 next preset
  Right stick click  reset to the preset's own values
  Start              save the current camera as a preset
  Back               delete the selected saved preset
A quick tap of LB on its own toggles slow walk. Hold LT at the same time to
tune while looking through the aim camera.

Keyboard and controller work at the same time.


SENSITIVITY
-----------
Your turn speed comes from the game's own options, and it is the same on foot
and in vehicles, aiming or not.

  Mouse Sensitivity (OPTIONS > DISPLAY)
      the base speed of the mouse.
  Look sensitivity (OPTIONS > CONTROLS)
      applies on top, left / right and up / down, for mouse and controller.
      The slider goes from half speed (lowest) through normal (middle) to
      double speed (highest).
  aim_sensitivity (mod.ini)
      the speed while aiming only: 1.0 = the same as not aiming, 0.5 = half.

While the aim camera zooms in, turning slows by the zoom, so a movement moves
the view the same distance on screen as when not aiming (aim_zoom_match = 0
turns this off).

While you aim, the camera turns only with your mouse or stick. Your character
turns to face the aim, and that turn never moves the camera.


SETTINGS
--------
Open mod.ini (in the Precise_Aim folder) with Notepad. Every setting has a
short note above it. Save the file and the change applies straight away, even
with the game running. The sections, most useful first:

  Main                      aim_toggle, preset (the starting camera), walk_start
  Sensitivity               aim_sensitivity, aim_zoom_match, following the
                            game's look sensitivity
  Keyboard and mouse        aim, slow walk, melee, grenade toss and crouch keys
  Controller                buttons, right stick speed, deadzone, curve, boost
  Precise aim and movement  when precise aim starts and ends, body turning,
                            slow walk speed, strafe animation blending
  Grenades and melee        aiming and raising them
  Vehicles and crosshair    drive-by zoom, crosshair size
  Accuracy                  spread in every stance (cone_..., smaller = more
                            accurate; cone_model = 0 = the game's own)
  Camera tuning in game     the tuning keys and buttons

If a key or button name is wrong, the mod writes a line starting with
"Precise Aim:" to dist\mods\wml.log and leaves that control off.


CHANGING KEYBINDS
-----------------
Every key and button is a line in mod.ini. Change the value after the = and
save. Leave a value empty to turn that control off.

Keyboard keys:
  A-Z, 0-9, SPACE, ENTER, ESC, TAB, BACKSPACE, SHIFT, CTRL, ALT, UP, DOWN,
  LEFT, RIGHT, INSERT, DELETE, HOME, END, PAGEUP, PAGEDOWN, PLUS, MINUS,
  F1-F24, NUMPAD0-NUMPAD9, or a Windows key code number
  (1 = left mouse, 2 = right mouse, 4 = middle mouse, 20 = Caps Lock).
  Camera tuning keys can also take a modifier: CTRL+I, ALT+K, SHIFT+O.

Controller buttons:
  A B X Y LB RB LT RT LS RS BACK START DPAD_UP DPAD_DOWN DPAD_LEFT DPAD_RIGHT

Examples:
  aim_key = 2              ; right mouse
  walk_toggle_key = 20     ; Caps Lock
  melee_key = V
  pad_walk_toggle = BACK   ; slow walk back on the Back button
  key_zoom_in = CTRL+MINUS


CAMERA PRESETS
--------------
presets.ini holds the cameras that come with the mod:

  SR1      Saints Row 1's own aim camera (default)
  SR2      Saints Row 2 style
  SR3      Saints Row: The Third style
  SR4      Saints Row IV style
  SR2022   Saints Row (2022) style
  TPA      gentle third-person aim

Switch with Ctrl+K / Ctrl+Y (LB + RB on a controller), then fine-tune with the
camera tuning keys. Ctrl+U (LB + Start) saves your camera as custom1,
custom2, ... in my_presets.ini.

A preset is a short block like this:

    [My Camera]
    style = orbit
    zoom = -0.50
    fov = 0.70
    height = 1.60
    shoulder = 0.40

To share one, copy its block and send it. To use one somebody sent you, paste
it at the end of presets.ini and restart the game. presets.ini explains every
value.


FILES
-----
main.lua          the mod
mod.ini           settings
presets.ini       camera presets that come with the mod
README.txt        this file

Made by the mod while you play:
camera.cfg        the camera you are using now. It takes over from preset in
                  mod.ini; delete it to go back.
my_presets.ini    cameras you saved in game
pool_backup.txt   the game's original walk animations, put back when precise
                  aim ends


TROUBLESHOOTING
---------------
A control does nothing        check dist\mods\wml.log for a "Precise Aim:"
                              line; a misspelt key or button is switched off.
Aiming fights another mod     turn off other aiming, camera or walking mods.
The camera is not the preset  camera.cfg takes over once you tune the camera
in mod.ini                    in game. Delete it.
Sensitivity does nothing      turn off Free Cam.


ONLINE
------
Script mods are private play only: story co-op and Private Party work,
public matches do not.


Made by Eazzy, with AI assistance.
