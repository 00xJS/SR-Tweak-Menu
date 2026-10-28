# SR Tweak Menu - changes

## 2.6.4

- **Save tweaks for next time** saves every setting now, the same ones
  Show active tweaks lists. Before, it missed the choices (weather, filter,
  render mode, aim style and button, Precise Aim turning, free camera mode,
  character dialogue, animation fallback, cloth physics, punch blast, the
  weapon D-pad and tap), Hide HUD, Letterbox, Auto-teleport to waypoint,
  and the sliders that go with a switch (run speed, high jump boost, the
  shoulder camera's offset and closeness, money gun cash, money rain rate
  and bill, bounce strength, spin damping, repeat interval).
- Rows whose change does the work (the weather, Hide HUD, the filter ...)
  are put back once you've been playing a couple of seconds after loading.
- Choices are saved by name, so a list that gains an entry keeps your pick.
- Not saved, as before: live readouts (notoriety, time of day), the free
  camera itself, and pickers like Give item. Movement and the menu look
  keep saving to their own files as you pick them.

## 2.6.3

- Fixed the menu's game pictures (the Menu background box, the game style
  menu's boxes and buttons, the screen effects) not drawing on some PCs:
  where a build keeps the game's textures or drawing buffers in high
  memory, the menu took them for bad pointers and quietly skipped them.
  Weapon skins had the same check and could miss textures the same way.
- A picture the menu can't draw now says why in wml.log, once
  ("menu picture ... skipped: ..."), so a report shows what's missing.

## 2.6.2

- The game style menu (itsMJQ's look) matches the plain text one: lists
  show where you are in them ("3/12"), the controller hints include the
  close buttons (RB + D-pad Down), and Settings > Menu background works in
  it too, setting how solid its boxes are (60% is their usual look).
  Every row, page and option was already the same in both; the menu test
  now draws every page in the game style.

## 2.6.1

- Settings > **Menu background**: a dark box behind the plain text menu, so
  it reads on any background, Off to 100% (mod.ini menu_background, 60 at
  start). It's drawn in the game's own frame under the overlay text, sized
  to the menu's lines.
- Visual > Camera > **Over-the-shoulder camera**: on foot the camera sits
  over your shoulder like GTA, you to one side and the aim in the middle,
  with **Shoulder offset** (left or right) and **Shoulder camera closer**.
  It eases in and out; aiming, cars, cutscenes, first person and the free
  camera keep their own.

## 2.6.0

- Weapons > **Give item**: weed, booze, drinks and food as the stores sell
  them (Spliff, Blunt, Pipe, Bong, 40 oz., Gin N' Juice, Cognac, Bubbly,
  Big Swallow, Chicken Bazooms, The Twins, The Fist), with **How many**
  (1 to 10), through the game's own inv_item_add.
- Settings > **Show active tweaks** is now a page of every setting that isn't
  the game's own: switches that are on, sliders off their default (field of
  view, aim camera, skins ...) and the choices that stay set (aim style,
  filter, weather ...), grouped by the tab and page they're on. Change any
  of them right there, or put them all back at once.
- Settings > **Restore menu defaults** (every row as mod.ini starts it, and
  the saved tweaks forgotten) and **Restore game defaults** (every switch off,
  every value the game's own). Both ask first.

## 2.5.1

- The menu starts on every PC again. When the mod loader couldn't hook one
  of the game functions the menu uses (which ones depends on the build of
  saintsrow.exe a PC runs; one player's refused the HUD notoriety meter at
  0x82481990), the error stopped the whole menu from loading, so F5 and
  R1 + D-pad Down did nothing. Every hook now switches off only what needs
  it, logged as "couldn't hook ...", and the rest of the menu works. The
  menu test simulates that refused hook.

## 2.5.0

New rows after Saints Row (2006) mods on saintsrowmods.com. Each one is
switched live in the menu and puts the game's own back when off; none of
those mods' files are used.

- Weapons > **Skins**: a colour for each of 18 weapons (gold, black,
  gunmetal, silver, white, tan, olive, green, red, blue, purple, pink). The
  game's own textures are recoloured in memory, wood left as wood on the
  guns that have some, and every copy of the gun changes, NPCs' too.
  All back to the original undoes them.
- Player > Health & damage: **No health regen** (Hardcore Edition) and
  **Heal on D-pad down** (multiplayer's heal).
- Player > Movement: **Sprint**: the game's own, Multiplayer (3 s), Pimp
  (2 s) or Short (1 s, jumping costs half) (Stamina Mod).
- Player > Notoriety: **Gang you side with** while Saints are enemies is on:
  Vice Kings, Los Carnales, Rollerz, Police or Neutral.
- Emotes: **D-pad taunts**: multiplayer's three taunts on D-pad left and
  right, and up too if you like.
- Vehicles > Handling: **Bouncy cars** (Bouncy Cars) and **Less stiff cars**
  (Simply Less Damping), each with a strength.
- World: **Stores open 24/7**; People: **Gangs drive ordinary cars** and
  **Gangs and police without guns** (Saints of Rage); Drops: **Money rain**;
  a new **Districts** page: hand any district or the whole city to a gang,
  or back to the starting owners, and reveal the whole map.
- Settings > Unlocks: **Unlock multiplayer clothing** and **Unlock reward
  clothing**, and rewards kept in your save (free shopping, bulletproof,
  explosion-proof, crash-proof, police or gangs forget fast; More Unlockable
  Unlock Rewards). They ask first: they can't be taken back.
- The Give weapon list uses the game's own weapon names (the K6 Krukov was
  listed as the AR-40 Xtnd, the Vice 9 and NR4 were swapped, ...).
- Weapon switch D-pad's second choice is now called "Left to the game": it
  leaves left/right to the radio in a car and to D-pad taunts on foot.
- patch.lua adds the reward rows to unlockables.xtbl (restart once after
  installing before picking one).
- The Emotes tab sits between Customize and Settings.
- Visual > Camera: **First person field of view**, 50 to 120 degrees, for
  Saints Reborn's built-in First Person (V). It starts at First Person's own.
- Teleport > **Saved places**: save any spot (and the way you face), go
  back to it with your car and homies, rename it (type on the keyboard, or
  pick letters with the pad), move it to where you are, or delete it. Up to
  50, kept in saved_places.txt.
- Visual > Camera: **First person** switches it from the menu, and shows when
  V has switched it. Needs First Person 1.4; with an older one it says to
  press V.

## 2.4.4

- Visual > Camera > Field of view works in cars, and keeps working after you
  get out. The game eases the camera's FOV in cars and never stops easing
  after the first car, which the old way (widening the final FOV only when
  it matched the wanted one) gave up on. The FOV is now widened where the
  follow camera sets it, so on foot and driving (top speed included) get the
  same widening.
- A hook the mod loader refuses now switches off only its own tweak (logged
  as "juiced: couldn't hook ...") instead of stopping the whole menu.
- Free camera in cars is on the Driving camera page again (since 2.4 it had
  ended up at the bottom of the Vehicles tab).

## 2.4.3

- Holding Back (Select/Share) no longer opens the menu: it got in the way
  of the game's own Back. Open the menu with F5, or RB (R1) + D-pad Down.
  (`menu_hold_back` and `menu_hold_seconds` are gone from `mod.ini`.)

## 2.4.2

- The camera reset rows have new names in `mod.ini`
  (`car_camera_reset_after`, `car_camera_reset_after_stopped`) and in
  saved tweaks, so a `mod.ini` or saved tweaks from 2.2 / 2.3 (a 1 second
  hold, which made the camera go back to following right away) can't
  override the free camera any more. Both start at Always.
- A warning (log and on screen) when the old standalone SR Juiced mod is
  still ticked in the mod loader: it fights these rows over the camera.
- Free camera in cars, Camera follows the nose and Free drive-by camera
  exclude each other: switching the free camera on switches the other two
  off, switching either of them on switches the free camera off, with a
  message saying so. Follows the nose and the drive-by camera now start off;
  if `mod.ini` or saved tweaks have them on with the free camera, the free
  camera wins.
- The first time you drive, `mods/wml.log` gets one line (even with debug
  off) with the driving camera settings in effect, the menu's version and
  whether the old SR Juiced mod is ticked - send it if the camera still
  swings back.

## 2.4.1

- Free camera in cars with **Camera resets after** at Always (the default)
  is fully free: the camera no longer slowly swings back behind the car
  before you've moved it, or after getting into a car. With a reset time
  set it works as in 2.4.

## 2.4

- Vehicles > Driving camera: **Free camera in cars** (on by default). Move
  the camera with the mouse or right stick and it keeps looking that way:
  the car turns under it, instead of the game locking it to the car for a
  few seconds and then pulling it back behind.
- **Camera resets after** (moving, and standing still): how long after you
  stop moving it before it goes back to following the car - up to
  **Always**, never, which is where both start.
- Looking up and down stays where you tilt it while the camera is free (the
  game would otherwise level it back every frame).
- Swing-back speed starts at the game's own (x1) again; 2.2's x2 and 1 s
  hold made the camera feel stiff.

## 2.3

- Settings: **Menu look**, switched live: the plain text menu, or itsMJQ's
  game look from 1.9.11 (the menu drawn with the game's own fonts, gold
  selection bar, menu box and fleur-de-lis, with its menu sounds). Kept in
  `mod.ini` as `menu_style`; `menu_x`, `menu_y` and `menu_scale` place the
  game look. Messages wrap there too.

## 2.2

Quality of life rows after the Saints Row 2 Juiced Patch (Kobraworks
Modding), written for Saints Row 1 (no Juiced code). They were the separate
SR Juiced mod; untick it if you had it.

- Player: **Crouch while moving** (keyboard too; on by default) and **No
  melee lock-on**.
- Vehicles, **Driving camera**: camera hold time (moving and standing
  still), swing-back speed, **Camera follows the nose** in a handbrake slide
  and **Free drive-by camera** (both on by default), no camera swing getting
  in, field of view at top speed. **Driving**: brake lights when stopped,
  reload in cars (R).
- Visual: **Field of view** (x1.2 by default; eases in, scopes and
  cutscenes keep the game's own), no fog, map arrow shows where you face.
- Settings: **Save tweaks for next time** (every row starts the way it is
  now, in `saved_tweaks.ini`) and **Forget saved tweaks**. **Start-up and
  saving**: skip intro, load last save (any key or button in the wait stays
  on the menu), quick save (F12), pause cutscenes (Back / Tab), no tutorial
  popups.
- Every one has a start value in `mod.ini`.

**New layout** (`layout.lua` places every row; ids, `mod.ini` keys and saved
tweaks are unchanged):

- Tabs: Player, Emotes, Weapons, Vehicles, World, Visual, Teleport, then
  Models, Customize and Settings.
- Rows go where they act, not where they came from: the everyday switches
  on the tab, the rest on pages named by what they change.
- Player: Logic is split into **Health & damage** and **Movement**;
  **Unlocks** moved here from Settings; Voice Lines moved to Emotes.
- Weapons: **Special ammo** (rocket, fire, money gun, explosive punches) and
  **Aiming & switching** (aim style and its camera, the aim button and
  turning, weapon switch: the rows from Settings > Controls). Perfect aim
  moved here from Logic.
- Vehicles: **Toughness**, **Handling**, **Look** (customize, paint, brake
  lights) and **Driving camera** pages; god mode, repair, spawn, garage and
  destroy stay on the tab.
- World: **People** and **Drops** pages; No fog sits by Weather.
- Visual: **Camera** (field of view, camera turn speed), **Free camera**
  (with freeze world) and **UI+** (from Settings).
- Models gets Animation fallback and Cloth physics, Customize gets Restore
  outfit and Customization pose (from Settings > Tweak Settings).
- Settings: All tweaks, show active tweaks, save / forget saved tweaks and a
  **Game & saving** page. The Controls and Tweak Settings pages are gone.
- Messages (Show active tweaks and others) wrap over up to 4 lines instead
  of running off the screen, and the tab bar is tighter so all ten tabs fit.

## 2.1

- Spawn vehicle lists the game's own blinged versions after each plain car
  ("Slingshot", "Slingshot Blinged"): 20 cars, plus the Hollywood from the
  Blinged Out Ride mode in four colours. Deliver to garage keeps the plain
  list.
- Weapons: **Money gun**. Each shot throws a bill from your gun that lands
  where the bullet hit; pick it up again. Bill value $100 to $10,000.
- Weapons: **Explosive punches**. Punches and melee hits blow up whoever
  (or whichever car) you hit (Small, Grenade, Rocket or Huge blast); your own blast can't hurt you.
- Give weapon and Drop weapons have the multiplayer **Pimp Slap**.
- World: **Drop cash around me**, **Drop weapons around me** (any weapon or
  a random mix) and **Cash drop chance** (how often the dead drop cash).

## 2.0

itsMJQ's 1.1 to 1.9.11 (below) brought together with SR Tweak Menu's add-ons
and controls from the same starting point. Everything in 1.1 to 1.9.11 -
features, fixes and the findings behind them - is itsMJQ's work.

- The menu keeps its plain text look; the pages, saving prompts, hold-Back
  shortcut and moving with the menu open work in it as they did. (The
  game-interface look and its menu sounds are left out.)
- From SR Tweak Menu: Precise Aim, Fine Aim and Weapon Switch (Eazeepz,
  car123609) in the Weapons tab; a **Controls** page in Settings (camera turn
  speed, aim button, turning while aiming, weapon switch D-pad and wheel
  tap); rows ordered with the switches first.
- itsMJQ's renames kept, but Extra grip is **Extra car grip** again; the jump
  rows are **High jump boost** and **Game jump height**.
- Tidier tabs: Precise Aim's camera rows are one **Precise Aim camera** page,
  and aim rows only show for the aim style picked; the weapon switch buttons
  only show with Weapon switch on; Money and Respect sit on the Player tab;
  Show active tweaks is back on the Settings tab; Free camera mode sits under
  Free camera; the UI+ rows are on/off switches.
- The UI+ screen effects and low health sound echo start off, like every
  other row.
- hud_images.bin (pictures made from the game's HUD sheets) is not in the
  repository, as it holds game data; install HomieHeads for the HUD heads.

The entries 1.1 to 1.9.11 below are itsMJQ's.

## 1.9.11

Movement
- Melee & Throw Run applies to walking, running and standing, not just
  sprinting. With a melee weapon or something to throw out, the game walks,
  runs and stands with its "ready" moves (walk ready, run ready, stand ready,
  combat stand), which the part didn't cover.
- Combat and Melee Combat previews stand you still: coming from a row that
  had you running on the spot, you ran in place before the moves played.

Menu
- Holding Back (Xbox) or Select (PlayStation) opens the menu after 0.8
  seconds (was 1). `menu_hold_seconds` in mod.ini still changes it.
## 1.9.10

Movement previews
- Combat and Melee Combat preview every choice, not only Default. Choices
  other than Default played the kit's animation files on their own, which
  your standing animation overrode - you stood still and snapped back to
  standing. Every choice now plays the game's own moves, answered from the
  kit under the cursor - exactly what you get in play - with the files only
  as a fallback.
- A kit is shown with its own moves only: steps it has no move for are
  skipped instead of showing a default move in between.
- Melee Combat waits for the melee weapon to be in your hand before its
  first move.
- One move every 1.1 seconds (was 1.5).
## 1.9.9

- Combat and Melee Combat previews start each move 1.5 seconds apart. Ending
  a move early no longer skips the interval, and changing styles restarts the preview.
- Previewing fists no longer sets the game's persistent weapon lock. Your
  original weapon returns when you leave the preview, including when moving
  between Combat and Melee Combat. Reload Character also clears an old holster
  lock left by earlier versions; use it on foot if the wheel is already stuck.
- Actions now replace the previous animation cleanly and wait for their own
  track to finish before repeating. Player control state is saved before an
  animation changes it and restored when it ends or fails to start.
- Poses and Actions hide animations whose files are not actually loaded,
  along with empty categories. Availability is checked again when opening a
  category and playing a row, so the list follows the current game session.
- Added hold Xbox Back/View or PlayStation Select/Share for one second to
  open or close the menu (the controller must map that button to Back).
  Short taps retain the game's Back function on release. F5 and RB/R1 +
  D-pad Down still work. Holding the button does not repeatedly toggle.

Validation: offline regression suite only; controller mappings, visuals and
weapon-wheel behavior still need an in-game check.

## 1.9.8 (hotfix)

Fixes
- Setting movement back to Default works again, and emotes keep playing.
  When a pause or phone screen came up during an emote, the emote was dropped
  without handing back the animation set it had borrowed; from then on the
  menu kept waiting for that emote to end, so movement changes (Default
  included) no longer reached your character and later emotes misbehaved.
  The emote is now ended properly, and a borrowed set left behind is given
  back.
- If an emote can't start because every animation track is taken, the held
  ones are let go and it's tried again.
- Combat previews no longer take out a melee weapon: moving off the melee
  rows puts away a weapon the preview took out when you had none, and the
  Combat row previews with empty hands (your weapon comes back after).
- The Default row of Combat and Melee Combat previews your real default
  moves instead of the first kit in the list.

Models
- **Reload Character**: rebuilds your character as they are, behind a short
  fade, with a fresh animation player - for animations that are stuck or
  won't play.
## 1.9.7 (hotfix)

Movement
- Your styles carry over to weapons. Stance, Walk, Run and Sprint only
  applied with nothing in your hands; with a pistol, rifle or melee weapon
  out the game's own moves came back (which is why a sprint with a gun out
  looked like the default run). Now, with a weapon out, the chosen set's own
  move for that weapon is used (the female pistol run), or else its
  empty-handed one.
- Melee & Throw Run no longer replaces your walk, run, sprint and stance: each
  part keeps its own choice.
- Melee Combat follows the kit you pick with any melee weapon: when the kit
  has no attacks for the weapon in your hand (Cop with a bat), its attacks
  for another melee weapon are used.

Emotes
- An emote you already played plays again: each emote held on its last pose
  stayed in the animation player for good (the game's stop skips held
  animations), so going back to one competed with its frozen copy, and after
  nine nothing new could start. Each one is now let go before the next one
  plays and when you stop.
## 1.9.6

Music
- The next song plays by itself. The game hands the music player one song
  at a time and only moves on when the player says it stopped, which it
  didn't always say - a song ended and nothing came next until you skipped.
  Each song's length is now read from its MP3; if nothing has come next 2 s
  after a song ends, the game's own next track is run (shuffle and
  repeat-one as you set them). A pause holds the count.
- The music follows the volume set in the pause menu. With the slider at
  its top the game sends "full volume", which the music player took for a
  default and ignored, keeping the last volume it had been given - so the
  music stayed quieter until the slider was moved. Full volume now goes
  through, and the volume is sent again a second after each song starts.

Settings
- **UI+**: Low health visuals, Low sprint visuals and Low health sound echo
  are together on their own page.
## 1.9.5

- Low health sound echo in sync: it starts exactly as each warning ends,
  whatever the pace (1.9.4 moved it earlier from an average of the last few
  beats, which lagged - most of all as health recovered and the warnings
  slowed). Each echo goes on the game update nearest its time.

## 1.9.4

- Low health sound echo is smooth: one softer echo as the warning ends
  (it lasts 1.32 s) instead of two copies over it, keeping to the beat -
  as the warnings come faster at lower health, the echo comes in sooner.

## 1.9.3

- Lin's chosen voice now talks: as a story model her lines were held to the
  Character dialogue rate (meant for a model's own few lines), so only pain
  and screams got through. A voice you choose for a model, and any line you
  play from the menu (Voice Lines, samples), is no longer held back.

## 1.9.2

- Models > **Voice** when you play as Lin: Default (her own), or any of the
  Caucasian and Asian women's gang voices (18). Moving onto one plays it; A
  keeps it. Kept for her in model_voice.txt, apart from your Playa's voice,
  and put back whenever you're Lin.

## 1.9.1

Fixes
- Model swap crash in cutscenes (Tanya and Tony as Aisha): when a cutscene
  unloaded the model you were wearing, the menu loaded it again while your
  body still pointed at the old copy - invisible, then a crash. Now, if the
  model you wear is ever unloaded, you're put back in your own body at once
  (checked every update during cutscenes), and the model goes back on once
  the cutscene is over and you're in control. Cutscenes that leave the model
  alone keep it. A reference to the model the game gives back is also taken
  again at once (and logged), so it can't run out while you wear it.
- Hair colour no longer turns blonde now and then while browsing hairstyles:
  the colour you wear goes on every style you try, and on the style put back
  when you go back.
- Melee Combat choices now apply (the kit's attacks are actions; they were
  looked up as states, filling the log with "unknown animation state").

Emotes
- Came to the Emotes tab while moving: you keep moving, and the game's
  camera follows you. Came standing still: you stay put and the stick turns
  the camera round you, as before. While an emote plays you're held either
  way.

Player
- Voice Lines lists only what your character's voice has: situations it has
  no line for, and kinds with none, are left out.

Settings
- **Low health sound echo** (on by default): the game's low health warning is
  heard again twice just after, softer each time, as in Saints Row 2 and 3.
## 1.9

Fixes
- Melee & Throw Run and Melee Combat previews no longer take your weapon
  away. They use the melee weapon in your hand; with none, one you carry
  (bat, nightstick, tire iron, knife, cane); only with none at all is a
  baseball bat given, and it's yours to keep. Your previous weapon goes back
  in your hand afterwards.
- Combat and Melee Combat previews play again: when the moves' animation
  files aren't in memory they're played as the game's own actions, one into
  the next.
- Animation files are looked up each time they're played instead of being
  remembered, so a file that has left memory is never played by a stale id.
- With the menu open outside Customize, the buttons that close it no longer
  reach the game.

Menu
- You can move with the menu open: on every tab but Customize, walk, run,
  drive and look around while you use the menu with the D-pad (or the arrow
  keys), A / Enter and B / Backspace. In Emotes the camera goes round you
  only while you stand still; moving, the game's camera follows you.
- **Player** is in submenus: **Logic**, **Notoriety**, **Bodyguards**,
  **Extras** and **Voice Lines**.
- **Settings** is in submenus: **Unlocks** (music, collectibles, clothing)
  and **Tweak Settings** (restore outfit, show active tweaks, customization
  pose, animation fallback, cloth physics).
- Customize: the box's heading reads CHARACTER, and the Personalization
  divider uses the same font as the tab titles.

Customize
- Style > **Remove Clothing** (below Saved Outfits, asks first): everything
  off but your underwear and jewelry, with a plain pair of socks so your
  feet stay.
- Personalization > **Facial Expressions**: Angry, Disgust, Fear, Joy, Sad,
  Surprise (the game's own emotions) held on your face, or None; kept in
  expression.txt.
- With a voice chosen, you scream in that voice when you die (unless the
  game already did).

Player
- **Voice Lines**: every situation the game has lines for (combat, taunts,
  threats, observing, pain and screams, activities...), in your character's
  voice - the one you chose, your own, or the model's you play as. A line
  that voice doesn't have plays the error sound.
## 1.8.1

Fixes
- You could be left unable to move after the menu: the Combat preview's
  punches held you and nothing let go. Leaving a fighting part (or the
  page, or the menu) now frees you.
- Stance idle variants (and the other variants) are taken from the set that
  has them, so they all play.

Customize
- New layout: **Face & Body** (Saved Presets, Head, Eyes, Hair, Body, Skin)
  and **Style** (Saved Outfits, Clothes, Jewelry, Tattoos), then
  **Personalization**: Voice and Movement.
- Skin is just its sliders.
- Movement: a choice that plays the same animation as one before it is left
  out. **Melee Combat** added (the attacks in a melee kit). The previews:
  Combat loops left and right punches then the running ones, never back to
  standing; Melee Combat loops every attack in the kit; Melee & Throw Run
  and Melee Combat put a baseball bat in your hand while you look (taken
  away after unless you had one).

Emotes
- An action plays from its animation file held to the end: one that loops
  carries on, one that doesn't stays on its last pose - as people do when
  nothing interrupts them - until you move or press RB + D-pad Up.

Settings
- **Animation Fallback** and **Cloth physics** are here now.

## 1.8

Movement (Customize > Movement as your Playa; Models when you're someone else)
- Split into parts, each Default or any animation set that has that move, or
  one of the game's own variants of it: **Stance** (standing and idles),
  **Walk Style** (every walk, variants included), **Run Style**, **Sprint
  Style**, **Melee & Throw Run** (running with a melee weapon or something to
  throw) and **Combat** (standing and running punches). The rest of how you
  move is untouched. Kept between sessions (movement.txt). The part under
  the cursor plays on the spot (punches for Combat).

Emotes
- Actions loop: each plays again as it ends, until you move or press RB +
  D-pad Up (Repeat action adds a pause between plays).
- More of them, and more props: some animation sets list their weapon group
  after their moves, and those sets were being missed (80 poses, 197
  actions, 52 with props).

Customize
- Jewelry (piercings, rings ...): only the piece under the cursor shows; what
  you tried before comes off as you move on. A still keeps it.

Visual
- **Render mode** now: Default, No Sky, No Textures, No People, People Only.
  The game's console commands for these do nothing in the retail game (they
  only run with a debug flag set), so the renderer's own flags are set
  directly. Wireframe, polygon, collision and box views have no code left in
  the retail renderer, so they're gone.

Settings
- Low sprint visuals follow the sprint meter the HUD shows (refill included),
  from 40% down.

## 1.7.3

- Low sprint visuals start once your sprint drops below 40% and deepen as it
  empties, like the health one. Sprinting again while it refills carries the
  shade on from where it is - no jump.

## 1.7.2

- Low health and low sprint visuals are soft and round: shaded from the
  corners in, gentle along the edges and clear in the middle, blending
  smoothly with no visible steps.
- They're drawn under the game's HUD, so the minimap, neighbourhood names,
  mission text and subtitles stay on top.
- Low sprint fades away as your sprint refills. (The game only writes how
  much is left while you sprint, so the refill in between is followed by the
  menu itself, and the game's own figure takes over again when you sprint.)

## 1.7.1

- Low health and low sprint visuals redone: they come in from the screen
  edges (nested frames, the outermost darkest), never cover the middle,
  creep in slowly as health or sprint drops and ease back to nothing once it
  recovers. Drawn with the HUD's plain white swatch picture (the square used
  before wasn't plain, which made the ring).
- Customize: Movement style and the walk and run variants are on a
  **Movement** page below Voice. The walk preview stays on the spot like
  the run.

## 1.7

Customize
- **None** no longer takes anything off when you just move past it - only
  when you press it.
- Clothes that would clip through each other switch between tucked and
  untucked by themselves (when no way of the same name fits what's around
  it, any way that does is used).
- **Movement style**, **Walk variant** and **Run variant** moved: in
  Customize below Voice as your Playa, in Models when you play as someone
  else. In Customize the cursor on one of them shows a preview - your Playa
  walks (or runs) on the spot with the one shown; A keeps it.

Emotes
- An emote is played through whichever animation set has it with its file
  in memory, or straight from its animation file - and an emote whose
  animation isn't loaded anywhere right now is left out of the page (pages
  are checked each time they open), so what's listed plays.

Settings
- **Low health visuals**: a see-through dark red vignette that pulses like a
  heartbeat when your health is low, deeper, quicker and more solid the
  lower it gets.
- **Low sprint visuals**: a see-through black vignette that darkens as your
  sprint runs out and fades away as it refills.

## 1.6

Emotes
- Every pose and action listed is one your Playa can do: each borrows, while
  it plays, the animation set that has it (the one for your build first, and
  the one holding its prop when there is one). Entries no animation set in
  the game has are gone, and a move listed twice under two names is listed
  once (64 poses, 165 actions). Props show in your hand as they do on NPCs.

Settings
- **Unlock all music**: every song in the music store is yours, for your
  playlists (as the game's own unlock-all does it).
- **Unlock all collectibles**: all 60 hidden CDs found, with the six bonus
  songs they unlock and the "CDs found" statistic.

Visual
- **Render mode** (replaces Wireframe): Wireframe, Wireframe + Textures,
  Debug (no lighting or sky), Debug (no textures), No Sky, Polygons,
  Collision and Bounding Boxes - the renderer's own debug views.
- The free camera works in cutscenes.

Other
- **Switch to Model** (was Apply player model).
- Tattoos: your socks stay on (a plain pair is lent if you wore none), so
  your feet don't vanish.

## 1.5

Fixes
- Cutscenes with a swapped model: a cutscene starring the character you're
  playing as (Aisha in Aisha's scenes) gave back every reference to that
  model when it ended, unloading it under you - invisible, then a crash. That
  release now gives back only the cutscene's own reference, and if the model
  is ever unloaded anyway it's loaded again at once (logged).
- Jewelry, tops and bottoms follow your layers: wear options the game picks
  from what else you wear (a chain inside or outside the shirt, a shirt
  tucked over high or low pants) are no longer offered as separate choices;
  the right one is put on, and changes when you change the clothes around it.

Customize
- **Saved Presets** (above Head): save up to 10 looks - face and body, skin,
  eyes, hair and facial hair with their colours, and tattoos. **Saved
  Outfits** (top of Clothes): up to 10 outfits, clothes and jewelry. Load,
  Overwrite or Delete any of them (overwriting and deleting ask first); Save
  Current tells you when all 10 are used.
- Tattoos: you're down to your underwear while you choose, like at the
  parlor, and dressed again when you leave.

Player
- **No Clip**: fly through anything. Left stick / WASD moves, RT / Space up,
  LT / Ctrl down, A / Shift faster.
- **Kill Yourself**: die and respawn - also clears invulnerability left on
  by mistake.
- Renamed: **Animation Fallback**, **Restore Playa Model**.

Emotes
- **Poses** and **Actions** list every pose and action the game has for
  people on foot (95 poses, 250 actions), by the game's categories. Poses
  with a prop (40oz, blunt, beer, magazine, newspaper, wine bottle,
  jackhammer ...) put it in your hand as they do for NPCs.

Vehicles
- **Customize Vehicle**: every part your vehicle can have (hood, body kit,
  spoiler, rims, interior, nitrous, hydraulics ...) and every color for its
  color slots (rim color, window tint, interior ...), free. The camera goes
  round the car.

World
- **Ragdoll all NPCs** (was Knock everyone down), and **Kill Everyone** below
  it (your homies are spared).

Teleport
- **Stores** (every clothing, jewelry, hair, plastic surgeon, tattoo, gun,
  liquor and music store and mechanic) and **Activities** (every activity's
  start), besides the cribs.

## 1.4

Fixes
- Customize: **None** now takes the piece off, and the list opens on what
  you're wearing instead of on None. (1.3 read the wrong field of the
  game's worn table, so nothing you wore was recognised.)
- The Customize and Emotes camera starts in front of your character
  instead of behind them.

Changes
- **Voice** is one row that opens a list: **None** (your character's own
  sounds only), then every voice by the game's race names - African
  American Male 1-6, Caucasian Male 1-12, Asian Male 1-6, Hispanic Male 1-6,
  then the same for women - taken from the Vice Kings, Los Carnales,
  Westside Rollerz and the Saints. Moving onto a voice plays a sample;
  A accepts it.
- A accepts, B goes back. Pressing B with a change you haven't accepted asks
  "Do you want to save your changes before exiting?" (Yes / No), like the
  game's own customization screens.
- The highlighted row's text is black on the gold bar, as in the game's
  menus.
- Clearer wording throughout: every description rewritten in plain terms,
  and none where the row speaks for itself. Some rows renamed (for
  example: Animation compatibility, Cloth physics, Character dialogue,
  Restore outfit, Customization pose); "Game's own" options now read
  Default.

## 1.3

Fixes
- Changing back from an NPC model no longer leaves you without hair, eyes or
  clothes. Pieces taken off for a model change stayed listed in the game's
  worn table, so the game thought their slots were still filled and quietly
  skipped putting your outfit back on (and a save made then kept you
  undressed). Pieces now come off the way the game takes them off.
- Settings > **Put my outfit back on**: puts back the last outfit the menu
  took off for a model change (kept in player_outfit_last.txt). It can't
  bring back an outfit lost in an earlier version (no copy was kept then);
  dress again in Customize, or load a save from before.
- Customize: **None** really takes the piece off.
- Customize: trying colours (the baseball cap's) no longer says you can't
  wear it: whatever is in that slot comes off first, and a try-on that
  doesn't fit just doesn't show instead of a message.

Changes
- Sliders glide like Image As Designed's and the pause menu's: hold Left /
  Right and they start slowly and speed up the longer you hold (Shift:
  faster), with one sound as they start instead of one per step.
- After choosing a colour, the cursor goes to **Wear Option** at the top of
  the colours, and the way you pick is kept (Back doesn't undo it).
- Lip sync: your character's mouth moves when they speak, like everyone
  else's - with a gang voice, your own voice or a model's. (The game left
  the player out of the talking face animation.)

## 1.2

- Customize as yourself in the game's own pages: Head, Eyes, Hair (with
  colour), Body, Skin, Clothes, Jewelry, Tattoos; try on, Enter keeps, Back
  puts back.
- The Emotes tab has the Customize camera (turn, zoom, slide).

## 1.1

- Customize as yourself in the menu, free; every gang voice for your
  character (out of breath stays your own).
- The Customize camera puts you on the right of the screen; the left stick /
  left-drag slides it.
