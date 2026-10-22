-- SR Tweak Menu - quality-of-life rows after the Saints Row 2 Juiced Patch
-- (Kobraworks Modding). The ideas are theirs; none of their code is used,
-- and every address here is Saints Row 1's.
--
-- J.setup(F) adds the rows to the Player, Vehicles, Visual and Settings
-- tabs; J.install() puts in the hooks once the start values are known
-- (saved tweaks applied); J.before(ctx) / J.after(ctx) run around the
-- game's update. Rows follow the menu's usual rules: a toggle's `update`
-- runs every update while it's on and `off` puts the game's value back,
-- and the hooks below pass straight through while their row is off (or
-- All tweaks is). Skip intro and Load last save act while the game starts,
-- before the menu exists, so they take effect from the next start and are
-- saved as soon as they're changed.

local G = require("game")
local read_u8, read_u16, read_u32, read_f32 = wml.read_u8, wml.read_u16, wml.read_u32, wml.read_f32
local write_u8, write_u16, write_u32, write_f32 = wml.write_u8, wml.write_u16, wml.write_u32, wml.write_f32
local S = wml.setting

local J = {}
local F   -- the features table, from setup

local function on(id) return F.enabled and F.items[id].v end
local function log(...) if G.debug then wml.log(...) end end
local fired = {}
local function fired_once(name) if G.debug and not fired[name] then fired[name] = true; wml.log("juiced: " .. name) end end

-- Seconds, wall clock. On Windows os.clock() is time since start; on the
-- Mac it's processor time (faster with several threads busy), so whole
-- seconds from os.time() there.
local windows = package.config:sub(1, 1) == "\\"
local function now() return windows and os.clock() or os.time() end

-- The game's state machine: the current state is entry s32 0x827D5780 of
-- the stack at 0x82B30E78. 1 legal screen, 2 front end, 5 in game.
local STATE_LEGAL, STATE_FRONT_END, STATE_GAME = 1, 2, 5
local function game_state()
  local index = read_u32(0x827D5780)
  if index >= 0x80000000 then return 0 end
  return read_u32(0x82B30E78 + 4 * index)
end

local function key_setting(name, default)
  local v = tostring(S(name, default))
  return v == '""' and "" or v
end

-- ================================================================ camera
-- Each tick the camera manager (0x82109608, inside the game update) runs
-- the current mode, which sets the wanted FOV at +192, then copies it to
-- the final FOV at +188 the frame is drawn with (degrees, 4:3 horizontal).
-- Mode 0 is the follow camera, on foot and driving; 3 scripted, 4
-- cutscene, and free cameras push their own.
local CAM_MODE, CAM_FOV, CAM_WANTED_FOV, FOLLOW_CAMERA, FOV_MAX = 0, 188, 192, 0, 150
-- The widening eases in and out (leaving a cutscene, another mod handing
-- the FOV back) and fades out over ZOOM_RAMP degrees above ZOOM_LIMIT, so
-- aiming never jumps and scopes still zoom.
local FRAME_TIME = 0x827AA6C8   -- float: the last frame's real length, seconds
local EASE_SECONDS, ZOOM_LIMIT, ZOOM_RAMP = 0.2, 40, 15
local blend, written = 0.0, nil

local function multiplier(m, wanted)
  local t = math.max(0, math.min(1, (wanted - ZOOM_LIMIT) / ZOOM_RAMP))
  return 1 + (m - 1) * t * blend
end

-- Scales the frame's FOV from the wanted one (never from the last frame's,
-- so it can't build up). Left alone when another mod (First Person, an aim
-- add-on) set the final FOV itself; while the camera doesn't run (pause
-- menu, map) the final FOV is still what was written here, and kept.
local function apply_fov(m)
  local final = read_f32(G.CAMERA + CAM_FOV)
  if G.in_cutscene() or read_u32(G.CAMERA + CAM_MODE) ~= FOLLOW_CAMERA then blend, written = 0.0, nil return end
  local wanted = read_f32(G.CAMERA + CAM_WANTED_FOV)
  if final ~= wanted then
    if final ~= written then blend, written = 0.0, nil end
    return
  end
  local dt = read_f32(FRAME_TIME)
  if not (dt > 0 and dt < 0.25) then dt = 1 / 30 end
  blend = blend + (1 - blend) * (1 - math.exp(-dt / EASE_SECONDS))
  write_f32(G.CAMERA + CAM_FOV, math.min(wanted * multiplier(m, wanted), FOV_MAX))
  written = read_f32(G.CAMERA + CAM_FOV)
  fired_once("field of view")
end

local SPEED_FOV   = 0x827D9330  -- float: vehicle_camera_fov_at_max_speed (90)
local ENTER_SWING = 0x827AB8D7  -- byte: vehicle_enter_swing_camera (1)
-- camera_free.xtbl asvct_group: seconds the driving camera stays where you
-- turned it, moving and standing still (3.0, 0.5); read every frame by the
-- follow camera (0x8210D518) and loaded again with each level.
local HOLD_TIME, HOLD_TIME_STOPPED = 0x827D9364, 0x827D9368
-- The follow camera swings back by 1 - (1 - C+364 * C+368) ^ (dt * 120)
-- a frame (0x8210C718; +372 / +376 while a timer runs). The vehicle update
-- (0x8253E938) sets those every frame from these floats: forward 0.006
-- (with 0x827AC228), reversing 0.012711, passengers -1 (never swings).
local SWING_FORWARD, SWING_REVERSE = 0x827AC218, 0x827AC224
local SWING_FORWARD_GAME, SWING_REVERSE_GAME = 0.006, 0.012711
local CAMERA_SWING, CAM_RATE, CAM_RATE_TIMED = 0x8210C718, 364, 372
-- The direction the camera follows: 0x8210C198(out*, target, 0) gives the
-- target's velocity; the follow camera's call returns to 0x8210D5C4. An
-- object's forward row is at +56.
local FOLLOW_DIRECTION, FOLLOW_CALL_RETURN, OBJ_FORWARD = 0x8210C198, 0x8210D5C4, 56

-- ================================================================ cars
-- 0x82533DA8(vehicle handle) -> f1 = the engine's brake input. The light
-- update asks it for the player's car (returns to 0x8255A89C); every other
-- car's 10-frame brake average (returns to 0x82527F14) is made from it.
-- Above 0.2 the brake lights come on; with no input a waiting car has none.
local BRAKE_INPUT, BRAKE_SHOWN = 0x82533DA8, 0.3
local BRAKE_CALLERS = { [0x8255A89C] = true, [0x82527F14] = true }
local V_ENGINE, V_ENGINE_OK, V_FLAGS_A, V_MOTION = 224, 50300, 53976, 244
local ENGINE_ON, E_THROTTLE, E_REVERSING = 0x08000000, 404, 180
local MOTION, MOTION_VELOCITY, STOPPED_SPEED2 = 88, 208, 1.0
local OBJ_HANDLE, OBJ_TYPE, TYPE_VEHICLE = 68, 72, 5
local P_DRIVE_BY = 516   -- player +516 == 3 while doing a drive-by

local function vehicle_from_handle(handle)
  if handle == 0 then return nil end
  local index = handle & 0xFFFF
  if index >= 4096 then return nil end
  local v = read_u32(G.OBJECTS + 12 + index * 16)
  if v == 0 or read_u32(v + OBJ_HANDLE) ~= handle or read_u32(v + OBJ_TYPE) ~= TYPE_VEHICLE then return nil end
  if read_u8(v + V_ENGINE_OK) ~= 1 then return nil end
  return v
end

local function waiting(v)
  if (read_u32(v + V_FLAGS_A) & ENGINE_ON) == 0 then return false end
  local e = read_u32(v + V_ENGINE)
  if not G.pointer_ok(e) then return false end
  if read_f32(e + E_THROTTLE) > 0.05 or read_u8(e + E_REVERSING) ~= 0 then return false end
  local body = read_u32(v + V_MOTION)
  if not G.pointer_ok(body) then return false end
  local motion = read_u32(body + MOTION)
  if not G.pointer_ok(motion) then return false end
  local a = motion + MOTION_VELOCITY
  local x, y, z = read_f32(a), read_f32(a + 4), read_f32(a + 8)
  return x * x + y * y + z * z < STOPPED_SPEED2
end

-- (The raw +2496 handle: G.vehicle_object refuses the seated state 9 a
-- drive-by is in.)
local function in_drive_by()
  local p = G.player()
  return p ~= 0 and read_u32(p + P_DRIVE_BY) == 3 and read_u32(p + G.P.VEHICLE) ~= 0
end

-- Free camera in cars. The follow camera's yaw (0x8210CFE0) has two modes.
-- While its hold timer runs - started by camera input for asvct
-- default_time (3 s; stationary_time 0.5 s standing still) - it adds the
-- car's turn to the camera, so the camera is locked to the car and turns
-- with it. Otherwise it swings towards where the car is going (0x8210C718),
-- pulling the camera back behind. Here the hold is set to 0 while in a car,
-- and once the camera's turn inputs (+320 across, +336 up and down: the
-- right stick and the host's mouse look) have moved it, the swing gets a
-- negative rate (as the game gives passengers): the camera keeps looking
-- where you pointed it and the car turns under it. It stays free until the
-- reset time (Camera resets after; Always = never) or until you get out.
local CAM_TURN_H, CAM_TURN_V = 320, 336
local HOLD_ALWAYS, HOLD_FOREVER_GAME = 10.5, 9999
-- Up and down: the pitch (0x8210C9E0) keeps where you tilted the camera only
-- while the hold timer runs; once it has run out it eases the camera back
-- level, every frame - with the hold at 0 that locked looking up and down.
-- Its check (0x82629278(timer) -> 1 when run out; the pitch's call returns
-- to 0x8210CD18) is answered "still running" while the camera is free.
local TIMER_RUN_OUT, PITCH_TIMER_CALL = 0x82629278, 0x8210CD18
local free = { on = false, last = nil }
local function hold_seconds(v) return v >= HOLD_ALWAYS and HOLD_FOREVER_GAME or v end

local function car_speed2(handle)
  local v = vehicle_from_handle(handle)
  if not v then return 0 end
  local body = read_u32(v + V_MOTION)
  if not G.pointer_ok(body) then return 0 end
  local motion = read_u32(body + MOTION)
  if not G.pointer_ok(motion) then return 0 end
  local a = motion + MOTION_VELOCITY
  local x, y, z = read_f32(a), read_f32(a + 4), read_f32(a + 8)
  return x * x + y * y + z * z
end

-- True while the camera should keep its own direction (called from the
-- swing, inside the camera update).
local function free_camera()
  local p = G.player()
  local handle = p ~= 0 and read_u32(p + G.P.VEHICLE) or 0
  if handle == 0 then free.on, free.last = false, nil return false end
  if math.abs(read_f32(G.CAMERA + CAM_TURN_H)) > 1e-4 or math.abs(read_f32(G.CAMERA + CAM_TURN_V)) > 1e-4 then
    free.on, free.last = true, now()
  end
  if not free.on then return false end
  local row = car_speed2(handle) < STOPPED_SPEED2 and F.items.car_cam_hold_stopped or F.items.car_cam_hold
  if row.v < HOLD_ALWAYS and now() - free.last >= row.v then free.on = false end
  return free.on
end

-- ================================================================ on foot
-- Click-to-crouch only takes the click while the left stick is pushed less
-- than this (x^2 + y^2; 0.5). WASD always reads as a full push.
local CROUCH_CLICK_SENSITIVITY, CROUCH_GAME, CROUCH_ANY_SPEED = 0x827D7AB0, 0.5, 4.0
local MELEE_LOCK_DIST, MELEE_LOCK_GAME = 0x827ACF00, 1.4   -- melee_target_lock_dist, unarmed
local TUTORIAL_DISABLE = 0x8370DB6E                        -- byte: Tutorial_disable
local FOG = 0x827D6C96                                     -- byte: fog; 0 skips the fog set-up

-- ================================================================ map arrow
-- Minimap (0x822ECDB0): Mini Map View byte 0x8370E407 is 1 for Static
-- (north up; the arrow turned to the player by 0x8227E720) and 0 for
-- Rotational (the map turns with the camera, heading at 0x8370E438, and
-- the arrow is drawn upright by 0x8227FBC8, returning to 0x822EDB94). Here
-- the Rotational arrow is drawn the Static way, turned by the player's
-- facing relative to the map. Pause map (0x822B3F70): the arrow's turn is
-- 0x8262EB58(rows*, out*) of the camera's rows (returns to 0x822B4754);
-- here it gets the player's rows.
local HEADING_OF, PAUSE_MAP_CALL = 0x8262EB58, 0x822B4754
local ARROW_UPRIGHT, ARROW_TURNED, MINIMAP_CALL = 0x8227FBC8, 0x8227E720, 0x822EDB94
local MAP_STATIC, MAP_HEADING = 0x8370E407, 0x8370E438
local MAP_X, MAP_Y, SCALE_X, SCALE_Y = 0x827AF100, 0x827AF104, 0x82FFB4EC, 0x82FFB4E8
local OFFSET_X, OFFSET_Y, CLIP_ARG = 0x82FFB4F4, 0x82FFB4F0, 84
local P_ROWS, P_FORWARD = 32, 56

local function s32(a) local v = read_u32(a) return v >= 0x80000000 and v - 0x100000000 or v end

-- ================================================================ pad
-- The game's pad read 0x827166D0(user, XINPUT_STATE*): buttons u16 at +4,
-- triggers u8 at +6 / +7. The keyboard reaches the game through it too.
local PAD_STATE = 0x827166D0
local pad_listeners = {}
local function on_pad(fn) pad_listeners[#pad_listeners + 1] = fn end

-- ================================================================ cutscene pause
-- Back (Tab) during a cutscene. The pause menu refuses to open in one
-- (0x822991D0), so the game's world pause is used: 0x8220C778(1) raises
-- the count at 0x8370DAE4, which stops the cutscene clock, the actors, the
-- scripts and the skip logic and pauses every voice; 0x8220C868(1) undoes
-- it. The picture goes grey while paused, since cutscenes hide the HUD.
local PAUSE, UNPAUSE, PAUSE_COUNT = 0x8220C778, 0x8220C868, 0x8370DAE4
local CS_AUDIO, CS_DEFER, CS_FADE = 0x8370D992, 0x8370D998, 0x827D5FAC
local SKIP_ARMED, SKIP_REQUEST, AUDIO_LAG = 0x8370FE66, 0x8370F8A7, 0x8370CF80
local SATURATION, CUTSCENE_CAMERA = 0x827D6C0C, 4
local BACK, HIDDEN_WHILE_PAUSED = 0x0020, 0xF030   -- hidden: A, B, X, Y, Start, Back
-- A voice only counts as paused once the audio thread has handled it;
-- unpausing before that leaves it paused (a silent cutscene).
local MIN_PAUSED_TICKS, GREY = 6, 0.25
local cs = { toggle = false, paused = false, since = 0, saturation = 1.0, tick = 0, previous = 0 }

local function can_pause()
  return G.player() ~= 0 and not G.in_front_end() and not G.screen_up()
    and read_u8(G.CUTSCENE_A) ~= 0 and read_u8(G.CUTSCENE_B) ~= 0 and read_u8(CS_AUDIO) ~= 0
    and read_u32(CS_DEFER) == 0 and s32(CS_FADE) < 0
    and read_u8(SKIP_REQUEST) == 0 and read_u8(SKIP_ARMED) == 0
    and s32(PAUSE_COUNT) == 0 and read_u32(G.CAMERA) == CUTSCENE_CAMERA
end

local function cutscene_before(ctx)
  cs.tick = cs.tick + 1
  if cs.paused and s32(PAUSE_COUNT) <= 0 then
    cs.paused = false   -- something else let go of the pause
    write_f32(SATURATION, cs.saturation)
  end
  if not cs.toggle then return end
  cs.toggle = false
  if not cs.paused then
    if not on("cutscene_pause") or not can_pause() then return end
    local before = s32(PAUSE_COUNT)
    G.call(ctx, PAUSE, { 1 })
    if s32(PAUSE_COUNT) ~= before + 1 then log("juiced: cutscene pause refused") return end
    cs.paused, cs.since, cs.saturation = true, cs.tick, read_f32(SATURATION)
    write_f32(SATURATION, GREY)
    log("juiced: cutscene paused")
  elseif cs.tick - cs.since >= MIN_PAUSED_TICKS then
    write_f32(SATURATION, cs.saturation)
    write_u32(AUDIO_LAG, 0)   -- a hitch measured while paused would hold the clock back
    G.call(ctx, UNPAUSE, { 1 })
    cs.paused = false
    log("juiced: cutscene resumed")
  end
end

-- ================================================================ quick save
-- 0x822081E0(out, 0) puts the game into a new save and starts the write
-- (the 312-byte content record is copied to 0x82B2FC40; u8 0x8370DAC2 set
-- while writing); 0x82207638(0x82B2FC40, *0x82B2FC28) moves the write
-- along each time it's called. Its last step (0x8370DAD4) is 3 when it
-- worked. Each save is a new one, so the quick save before it is deleted
-- afterwards (XamContentDelete, as the game's overwrite does) - only ever
-- one this menu made, remembered in quicksave.dat.
local SAVE_START, SAVE_STEP, SAVE_RECORD, SAVE_ARG = 0x822081E0, 0x82207638, 0x82B2FC40, 0x82B2FC28
local WRITING, QUEUED, LAST_STEP, STEP_DONE, RECORD_SIZE = 0x8370DAC2, 0x8370DAD8, 0x8370DAD4, 3, 312
local CONTENT_DELETE = 0x82716DA8
local MISSION = 0x82B3106C   -- u32: the mission running, 0 none
local DEVICE, USER, PROFILE = 0x827AE154, 0x827ADEC2, 0x8370EC00
local SAVE_DIALOGS = { 0x82FFE434, 0x82FFE43C }
local qs = { pressed = false, saving = false, file = wml.mod_folder .. "/quicksave.dat" }

local function can_save(p)
  if game_state() ~= STATE_GAME or p == 0 or G.in_cutscene() or G.screen_up() then return false, "not now" end
  if read_u32(MISSION) ~= 0 then return false, "not during a mission" end
  if read_u8(WRITING) ~= 0 or read_u8(QUEUED) ~= 0 then return false, "already saving" end
  for _, d in ipairs(SAVE_DIALOGS) do
    if read_u32(d) ~= 0 then return false, "not now" end
  end
  local device = read_u32(DEVICE)
  if device == 0 or device == 0xFFFFFFFF or read_u8(USER) == 0xFF then return false, "no storage device" end
  if read_u32(PROFILE) == 0 and read_u32(PROFILE + 4) == 0 then return false, "no profile" end
  return true
end

local function read_record(addr)
  local bytes = {}
  for i = 0, RECORD_SIZE - 1 do bytes[#bytes + 1] = string.char(read_u8(addr + i)) end
  return table.concat(bytes)
end

local function previous_quicksave()
  local f = io.open(qs.file, "rb")
  if not f then return nil end
  local data = f:read("a")
  f:close()
  return #data == RECORD_SIZE and data or nil
end

local function quicksave_after(ctx)
  if qs.saving then
    if read_u8(WRITING) ~= 0 then
      G.call(ctx, SAVE_STEP, { SAVE_RECORD, read_u32(SAVE_ARG) })
      return
    end
    qs.saving = false
    if read_u32(LAST_STEP) == STEP_DONE then
      local previous, record = previous_quicksave(), read_record(SAVE_RECORD)
      if previous and previous ~= record then
        local buf = G.buffer(ctx, 1)
        for i = 1, RECORD_SIZE do write_u8(buf + i - 1, string.byte(previous, i)) end
        log("juiced: deleted the previous quick save -> " .. G.call(ctx, CONTENT_DELETE, { read_u8(USER), buf, 0 }))
      end
      local f = io.open(qs.file, "wb")
      if f then f:write(record); f:close() end
      G.hud("Game saved")
    else
      G.hud("Quick save failed")
      log("juiced: quick save failed at step " .. read_u32(LAST_STEP))
    end
    return
  end
  if not qs.pressed then return end
  qs.pressed = false
  if not on("quick_save") then return end
  local ok, why = can_save(G.player())
  if not ok then G.hud("Can't quick save: " .. why) return end
  G.call(ctx, SAVE_START, { G.buffer(ctx, 0), 0 })
  qs.saving = read_u8(WRITING) ~= 0
  G.hud(qs.saving and "Saving..." or "Quick save failed")
  log("juiced: quick save started -> " .. tostring(qs.saving))
end

-- ================================================================ start-up
-- Logos: 0x822826B0 starts the THQ movie and the region check the legal
-- screen waits for (so it must still run); the boot loop plays logos until
-- u32 0x8370DD7C reaches 3, the path a button press takes. Legal screen:
-- it is also the start-up's loading screen, so only its fades are cut; its
-- tick 0x821FF480 ends it once u8 0x8370DA95 is set, and u8 0x8370DA94
-- says the start-up is done. (While it's up the game update runs on the
-- boot thread, so nothing is called into the game then.)
local LOGO_START, LOGO_STEP, LOGOS_DONE = 0x822826B0, 0x8370DD7C, 3
local LEGAL_TICK, STARTUP_DONE, LEGAL_DONE = 0x821FF480, 0x8370DA94, 0x8370DA95
-- Main menu (0x822861F0, runs only while shown). No Continue; LOAD GAME
-- writes these four values (front-end screen 44 = save/load screen). The
-- load list (newest first): count, 312-byte entries, +308 / +309 corrupt
-- flags; its input handler 0x822BCDD8 does, on A: the row, a "loading"
-- flag, the load 0x822BF470(1) (nonzero = done), then 0x82284600 leaves.
local MAIN_MENU_UPDATE, MAIN_MENU_SCREEN = 0x822861F0, 0x82FFB6C0
local MENU_DIALOGS = { 0x839E0FB0, 0x82FFE434, 0x82FFE43C }
local SAVE_CONTEXT, LOAD_STEP, LOAD_STEP_BEFORE, FRONT_END_SCREEN, LOAD_SCREEN = 0x827AF780, 0x8300FD40, 0x8300FD3C, 0x8370DDB0, 44
local LIST_INPUT, SAVE_COUNT, SAVES, MAX_SAVES = 0x822BCDD8, 0x8370E1DC, 0x8300FFD0, 24
local PICKED, LOADING, LOAD_SAVE, LEAVE_FRONT_END = 0x8300FD38, 0x8370DDA0, 0x822BF470, 0x82284600
local CHOOSE_DEVICE = 0x823493F8   -- (0): the device selector, as the load screen opens it
local MIN_WAIT, DEVICE_WAIT, GIVE_UP, TRIGGER_PRESSED = 0.3, 1.0, 15, 128
-- phase 0 waiting for the main menu, 1 on the load screen, 2 done
local ls = { phase = 0, since = nil, asked_device = false, cancelled = false, pad_before = 0, triggers_before = false }

local function main_menu_idle()
  if game_state() ~= STATE_FRONT_END or read_u32(G.FRONT_END) ~= 0xFFFFFFFF then return false end
  if read_u32(G.MENU_A) ~= MAIN_MENU_SCREEN or read_u8(USER) == 0xFF then return false end
  for _, d in ipairs(MENU_DIALOGS) do
    if read_u32(d) ~= 0 then return false end
  end
  return true
end

local function newest_save()
  local n = math.min(read_u32(SAVE_COUNT), MAX_SAVES)
  for i = 0, n - 1 do
    local e = SAVES + i * RECORD_SIZE
    if read_u8(e + 308) == 0 and read_u8(e + 309) == 0 then return i end
  end
  return nil
end

local function install_startup(skip_intro, load_last)
  if skip_intro then
    wml.hook(LOGO_START, function(ctx)
      ctx:call_original()
      write_u32(LOGO_STEP, LOGOS_DONE)
      fired_once("logos skipped")
    end)
    wml.hook(LEGAL_TICK, function(ctx)
      if read_u8(STARTUP_DONE) ~= 0 then write_u8(LEGAL_DONE, 1); fired_once("legal screen cut short") return end
      ctx:call_original()
    end)
  end
  if not load_last then return end
  local cancel_key = key_setting("load_cancel_key", "SHIFT")

  -- While the main menu waits, any key, mouse button, pad button or
  -- trigger pressed (not one already held) cancels the load.
  on_pad(function(state)
    local buttons = read_u16(state + 4)
    local triggers = read_u8(state + 6) >= TRIGGER_PRESSED or read_u8(state + 7) >= TRIGGER_PRESSED
    local new = (buttons & ~ls.pad_before) ~= 0 or (triggers and not ls.triggers_before)
    ls.pad_before, ls.triggers_before = buttons, triggers
    if ls.phase == 0 and ls.since and new and not ls.cancelled then
      ls.cancelled = string.format("pad buttons %04X, triggers %d / %d", buttons, read_u8(state + 6), read_u8(state + 7))
    end
  end)
  wml.on_frame(function()
    if ls.phase ~= 0 then return end
    if cancel_key ~= "" and wml.key_down(cancel_key) and not ls.cancelled then ls.cancelled = cancel_key .. " held" end
    if not ls.since then return end
    for vk = 1, 254 do
      if wml.key_pressed(vk) then ls.cancelled = ls.cancelled or string.format("key %d (0x%02X)", vk, vk); break end
    end
  end)

  wml.hook(MAIN_MENU_UPDATE, function(ctx)
    if ls.phase == 0 then
      if ls.cancelled then
        ls.phase = 2
        wml.log("juiced: load last save cancelled by " .. tostring(ls.cancelled))
      elseif main_menu_idle() then
        local wait = math.max(MIN_WAIT, F.items.load_wait.v)
        if not ls.since then
          ls.since = now()
          log(string.format("juiced: load last save waiting %.1f s for a key or button", wait))
        end
        if now() - ls.since >= wait then
          write_u32(SAVE_CONTEXT, 0); write_u32(LOAD_STEP_BEFORE, 4)
          write_u32(LOAD_STEP, 4); write_u32(FRONT_END_SCREEN, LOAD_SCREEN)
          ls.phase, ls.since = 1, now()
          log("juiced: load last save opening the load screen")
          ctx:set_r(3, 1)
          return
        end
      else
        ls.since = nil
      end
    end
    ctx:call_original()
  end)

  wml.hook(LIST_INPUT, function(ctx)
    if ls.phase == 1 then
      local pick = newest_save()
      if pick then
        local args = {}
        for i = 3, 10 do args[i] = ctx:r(i) end
        write_u32(SAVE_CONTEXT, 0); write_u32(PICKED, pick); write_u8(LOADING, 1)
        ctx:set_r(3, 1)
        ctx:call(LOAD_SAVE)
        ls.phase = 2
        if (ctx:r(3) & 0xFF) ~= 0 then
          log("juiced: loading save " .. pick)
          ctx:call(LEAVE_FRONT_END)
          return
        end
        log("juiced: the load failed, leaving it to the player")
        write_u8(LOADING, 0)
        for i = 3, 10 do ctx:set_r(i, args[i]) end
      elseif now() - ls.since > GIVE_UP then
        ls.phase = 2
        log("juiced: load last save found no save")
      end
    end
    ctx:call_original()
  end)
end

-- The load screen starts with no storage device until one is chosen.
local function startup_after(ctx)
  if ls.phase ~= 1 or ls.asked_device or read_u32(DEVICE) ~= 0xFFFFFFFF then return end
  if game_state() ~= STATE_FRONT_END or now() - ls.since < DEVICE_WAIT then return end
  ls.asked_device = true
  G.call(ctx, CHOOSE_DEVICE, { 0 })
  log("juiced: asked for a storage device")
end

-- ================================================================ rows
local function fmtx(v) return string.format("x%.2f", v) end
local function fmts(v) return string.format("%.1f s", v) end
local function fmthold(v) return v >= HOLD_ALWAYS and "Always" or string.format("%.1f s", v) end
local function fmtdeg(v) return string.format("%d deg", v) end

-- Rows the game reads every frame: written while on, put back when off.
local function keep(addr, value)
  if math.abs(read_f32(addr) - value) > 1e-4 then write_f32(addr, value) end
end

function J.setup(features)
  F = features
  local reload_key = key_setting("car_reload_key", "R")
  local save_key = key_setting("quick_save_key", "F12")
  J.reload_key, J.save_key = reload_key, save_key

  F.add_rows("Player", nil, {
    { id = "qol_player", label = "Quality of life", kind = "header" },
    { id = "crouch_moving", label = "Crouch while moving", kind = "toggle", needs = "none", v = S("crouch_while_moving", true),
      help = "Crouch while walking or running, on the keyboard too. (Not straight out of a sprint.)",
      update = function() keep(CROUCH_CLICK_SENSITIVITY, CROUCH_ANY_SPEED) end,
      off = function() write_f32(CROUCH_CLICK_SENSITIVITY, CROUCH_GAME) end },
    { id = "no_melee_lock", label = "No melee lock-on", kind = "toggle", needs = "none", v = S("no_melee_lock_on", false),
      help = "Punching no longer turns you to face someone standing close (within about 1.4 m): you hit where you face.",
      update = function() keep(MELEE_LOCK_DIST, 0) end,
      off = function() write_f32(MELEE_LOCK_DIST, MELEE_LOCK_GAME) end },
  })

  F.add_rows("Vehicles", nil, {
    { id = "qol_car_camera", label = "Driving camera", kind = "header" },
    { id = "car_free_cam", label = "Free camera in cars", kind = "toggle", needs = "none", v = S("car_free_camera", true),
      help = "Move the camera and it keeps looking that way: the car turns under it, it doesn't turn with the car or reset.",
      update = function() keep(HOLD_TIME, 0); keep(HOLD_TIME_STOPPED, 0) end,
      off = function()
        -- Back to the reset rows' times, or the game's own with All tweaks off.
        local function back(row) return (F.enabled and row.v ~= row.default) and hold_seconds(row.v) or row.default end
        write_f32(HOLD_TIME, back(F.items.car_cam_hold))
        write_f32(HOLD_TIME_STOPPED, back(F.items.car_cam_hold_stopped))
        free.on = false
      end },
    { id = "car_cam_hold", label = "Camera resets after", kind = "value", needs = "none", default = 3.0, min = 0.5, max = HOLD_ALWAYS,
      step = 0.5, fmt = fmthold, v = S("car_camera_hold", HOLD_ALWAYS),
      help = "After you stop moving it, how long before the camera goes back to following the car. Always: never (game: 3 s).",
      update = function(ctx, p, v, it) if not on("car_free_cam") then keep(HOLD_TIME, hold_seconds(it.v)) end end,
      off = function(ctx, p, v, it) if not on("car_free_cam") then write_f32(HOLD_TIME, it.default) end end },
    { id = "car_cam_hold_stopped", label = "Camera resets after, stopped", kind = "value", needs = "none", default = 0.5, min = 0.5,
      max = HOLD_ALWAYS, step = 0.5, fmt = fmthold, v = S("car_camera_hold_stopped", HOLD_ALWAYS),
      help = "The same while the car stands still (game: 0.5 s).",
      update = function(ctx, p, v, it) if not on("car_free_cam") then keep(HOLD_TIME_STOPPED, hold_seconds(it.v)) end end,
      off = function(ctx, p, v, it) if not on("car_free_cam") then write_f32(HOLD_TIME_STOPPED, it.default) end end },
    { id = "car_cam_follow", label = "Camera swing-back speed", kind = "value", needs = "none", default = 1.0, min = 0.25, max = 4,
      step = 0.25, fmt = fmtx, v = S("car_camera_follow", 1.0),
      help = "How fast the camera swings back behind the car (game: x1).",
      update = function(ctx, p, v, it)
        keep(SWING_FORWARD, SWING_FORWARD_GAME * it.v); keep(SWING_REVERSE, SWING_REVERSE_GAME * it.v)
      end,
      off = function() write_f32(SWING_FORWARD, SWING_FORWARD_GAME); write_f32(SWING_REVERSE, SWING_REVERSE_GAME) end },
    { id = "car_cam_nose", label = "Camera follows the nose", kind = "toggle", needs = "none", v = S("car_camera_follows_nose", true),
      help = "The camera stays behind the car in a handbrake slide instead of swinging towards the slide." },
    { id = "driveby_cam", label = "Free drive-by camera", kind = "toggle", needs = "none", v = S("drive_by_free_camera", true),
      help = "During a drive-by the camera stays where you aim instead of swinging back behind the car." },
    { id = "no_entry_swing", label = "No camera swing getting in", kind = "toggle", needs = "none", v = S("no_car_entry_swing", false),
      help = "The camera doesn't swing round behind you as you get into a car.",
      update = function() if read_u8(ENTER_SWING) ~= 0 then write_u8(ENTER_SWING, 0) end end,
      off = function() write_u8(ENTER_SWING, 1) end },
    { id = "speed_fov", label = "Field of view at top speed", kind = "value", needs = "none", default = 90, min = 60, max = 130, step = 5,
      fmt = fmtdeg, v = S("vehicle_speed_fov", 90),
      help = "How wide the driving camera gets at top speed (game: 90).",
      update = function(ctx, p, v, it) keep(SPEED_FOV, it.v) end,
      off = function(ctx, p, v, it) write_f32(SPEED_FOV, it.default) end },
    { id = "qol_driving", label = "Driving", kind = "header" },
    { id = "brake_lights", label = "Brake lights when stopped", kind = "toggle", needs = "none", v = S("brake_lights_when_stopped", false),
      help = "Brake lights come on when a car waits with its engine running. Every car on the road." },
    { id = "car_reload", label = "Reload in cars (" .. (reload_key ~= "" and reload_key or "no key") .. ")", kind = "toggle", needs = "none",
      v = S("car_reload", false),
      help = "Press " .. (reload_key ~= "" and reload_key or "the car_reload_key in mod.ini") .. " to reload in a car, driving or riding. No controller button." },
  })

  F.add_rows("Visual", nil, {
    { id = "qol_visual", label = "Quality of life", kind = "header" },
    { id = "fov", label = "Field of view", kind = "value", needs = "none", default = 1.0, min = 0.5, max = 2.0, step = 0.05,
      fmt = fmtx, v = S("fov_multiplier", 1.2),
      help = "Widens the normal camera, on foot and driving. Cutscenes and scopes keep the game's own.",
      update = function(ctx, p, v, it) apply_fov(it.v) end,
      off = function() blend, written = 0.0, nil end },
    { id = "no_fog", label = "No fog", kind = "toggle", needs = "none", v = S("no_fog", false),
      help = "Clears the distance haze over the city. It also shows where the world ends.",
      update = function() if read_u8(FOG) ~= 0 then write_u8(FOG, 0) end end,
      off = function() write_u8(FOG, 1) end },
    { id = "map_arrow", label = "Map arrow shows where you face", kind = "toggle", needs = "none", v = S("map_arrow_follows_player", false),
      help = "On the turning minimap and the pause map, the arrow points the way you face, not the camera." },
  })

  local function startup_change(ctx, p, v, it)
    J.save_now(it)
    return it.label .. (it.v and " on" or " off") .. " from the next start"
  end
  F.add_rows("Settings", "status", {
    { id = "save_tweaks", label = "Save tweaks for next time", kind = "action", needs = "none",
      help = "Every tweak starts the way it is now, the next time the game starts.",
      run = function() return J.save_all() end },
    { id = "forget_tweaks", label = "Forget saved tweaks", kind = "action", needs = "none",
      help = "From the next start, every tweak starts the way mod.ini sets it.",
      run = function() return J.forget_saved() end },
    { id = "qol_startup", label = "Start-up and saving", kind = "header" },
    { id = "skip_intro", label = "Skip intro", kind = "toggle", needs = "none", v = S("skip_intro", false), saved_now = true,
      help = "No logo movies, and the legal screen only while the game loads. From the next start.",
      change = startup_change },
    { id = "load_last_save", label = "Load last save", kind = "toggle", needs = "none", v = S("load_last_save", false), saved_now = true,
      help = "The main menu loads your newest save after a few seconds; any key or button stays on the menu. From the next start.",
      change = startup_change },
    { id = "load_wait", label = "Load last save after", kind = "value", needs = "none", default = 3, min = 0.5, max = 10, step = 0.5,
      fmt = fmts, v = S("load_last_save_wait", 3), saved_now = true,
      help = "How long the main menu waits before loading.",
      change = function(ctx, p, v, it) J.save_now(it) end },
    { id = "quick_save", label = "Quick save (" .. (save_key ~= "" and save_key or "no key") .. ")", kind = "toggle", needs = "none",
      v = S("quick_save", false),
      help = "Press " .. (save_key ~= "" and save_key or "the quick_save_key in mod.ini") .. " to save while free-roaming. Keeps only your newest quick save." },
    { id = "cutscene_pause", label = "Pause cutscenes", kind = "toggle", needs = "none", v = S("cutscene_pause", false),
      help = "Back (Tab) pauses a cutscene, sound included; again carries on." },
    { id = "no_tutorials", label = "No tutorial popups", kind = "toggle", needs = "none", v = S("no_tutorials", false),
      help = "No \"Press X to ...\" popups.",
      update = function() if read_u8(TUTORIAL_DISABLE) ~= 1 then write_u8(TUTORIAL_DISABLE, 1) end end,
      off = function() write_u8(TUTORIAL_DISABLE, 0) end },
  })
end

-- ================================================================ saved tweaks
-- "Save tweaks for next time" writes every row that can start from a saved
-- value to saved_tweaks.ini; it's read back while the mod starts. A row
-- can when its value alone does the work: toggles and sliders the update
-- loop applies (update, flag bits, a byte or float) or that hooks and
-- other code read (no `change` of their own), and rows marked saved_now.
-- One-shot rows (notoriety) and rows that act only when changed are left
-- out: setting their value alone wouldn't do what the change did.
local SAVED = wml.mod_folder .. "/saved_tweaks.ini"

local function can_save(it)
  if not it.id or it.nosave or it.oneshot then return false end
  if it.kind ~= "toggle" and it.kind ~= "value" then return false end
  if it.saved_now or it.id == "master" or not it.change then return true end
  return (it.update or it.pbits or it.p212 or it.vbits_a or it.vbits_b or it.byte or it.bits or it.float) ~= nil
end

local function read_saved()
  local saved = {}
  local f = io.open(SAVED, "r")
  if not f then return saved end
  for line in f:lines() do
    local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if k and not line:match("^%s*;") then saved[k] = v end
  end
  f:close()
  return saved
end

local function write_saved(saved)
  local ids = {}
  for k in pairs(saved) do ids[#ids + 1] = k end
  table.sort(ids)
  local f = io.open(SAVED, "w")
  if not f then return false end
  f:write("; SR Tweak Menu - tweaks saved from the menu (Settings > Save tweaks for next time).\n")
  f:write("; Read while the game starts; delete this file (or Forget saved tweaks) to start from mod.ini.\n")
  for _, k in ipairs(ids) do f:write(k, " = ", saved[k], "\n") end
  f:close()
  return true
end

local function value_text(it)
  if it.kind == "toggle" then return tostring(it.v) end
  return string.format("%.4g", it.v)
end

function J.save_all()
  -- Every registered row, pages' rows (Logic, ...) included.
  local saved, n = {}, 0
  for _, it in pairs(F.items) do
    if can_save(it) then saved[it.id] = value_text(it); n = n + 1 end
  end
  if not write_saved(saved) then return "Couldn't write saved_tweaks.ini" end
  log("juiced: saved " .. n .. " tweaks")
  return "Saved: tweaks start this way next time"
end

-- Start-up rows save straight away (they only act while the game starts).
function J.save_now(it)
  local saved = read_saved()
  saved[it.id] = value_text(it)
  write_saved(saved)
end

function J.forget_saved()
  local f = io.open(SAVED, "r")
  if not f then return "No saved tweaks to forget" end
  f:close()
  if not os.remove(SAVED) then return "Couldn't remove saved_tweaks.ini" end
  return "Saved tweaks forgotten: mod.ini from the next start"
end

-- Puts saved values on the rows; called once at start, before J.install.
function J.load_saved()
  local saved, n = read_saved(), 0
  for id, text in pairs(saved) do
    local it = F.items[id]
    if it and can_save(it) then
      if it.kind == "toggle" then it.v = text == "true"
      else
        local v = tonumber(text)
        if v then it.v = math.max(it.min, math.min(it.max, v)) end
      end
      if id == "master" then F.enabled = it.v end
      n = n + 1
    end
  end
  if n > 0 then wml.log("juiced: " .. n .. " saved tweaks applied") end
end

-- ================================================================ hooks
function J.install()
  -- Brake lights: every car's brake input, as the lights ask for it.
  wml.hook(BRAKE_INPUT, function(ctx)
    local handle, from = ctx:r(3), ctx:lr()
    ctx:call_original()
    if not BRAKE_CALLERS[from] or not on("brake_lights") or ctx:f(1) > 0.2 then return end
    local v = vehicle_from_handle(handle)
    if v and waiting(v) then ctx:set_f(1, BRAKE_SHOWN); fired_once("brake lights") end
  end)

  -- Follows the nose: the car's forward row at the car's speed (kept, as
  -- the camera's standing-still tests use it) with the sign of where it's
  -- going (so reversing still swings the game's way).
  wml.hook(FOLLOW_DIRECTION, function(ctx)
    local out, target, from = ctx:r(3), ctx:r(4), ctx:lr()
    ctx:call_original()
    if from ~= FOLLOW_CALL_RETURN or not on("car_cam_nose") or not G.pointer_ok(target) then return end
    if read_u32(target + OBJ_TYPE) ~= TYPE_VEHICLE or read_u8(target + V_ENGINE_OK) ~= 1 then return end
    local vx, vy, vz = read_f32(out), read_f32(out + 4), read_f32(out + 8)
    local fx, fy, fz = read_f32(target + OBJ_FORWARD), read_f32(target + OBJ_FORWARD + 4), read_f32(target + OBJ_FORWARD + 8)
    local speed = math.sqrt(vx * vx + vy * vy + vz * vz)
    local k = (vx * fx + vy * fy + vz * fz) < 0 and -speed or speed
    write_f32(out, fx * k); write_f32(out + 4, fy * k); write_f32(out + 8, fz * k)
    fired_once("camera follows the nose")
  end)

  -- Free camera in cars: the pitch keeps where you tilted it (see above).
  wml.hook(TIMER_RUN_OUT, function(ctx)
    if ctx:lr() == PITCH_TIMER_CALL and on("car_free_cam") and free_camera() then ctx:set_r(3, 0) return end
    ctx:call_original()
  end)

  -- Free drive-by camera and free camera in cars: a negative rate for this
  -- one call, as the game gives passengers; both put back afterwards.
  wml.hook(CAMERA_SWING, function(ctx)
    local why = (on("driveby_cam") and in_drive_by() and "drive-by free camera")
      or (on("car_free_cam") and free_camera() and "free camera in cars")
    if not why then ctx:call_original() return end
    local rate, timed = read_f32(G.CAMERA + CAM_RATE), read_f32(G.CAMERA + CAM_RATE_TIMED)
    write_f32(G.CAMERA + CAM_RATE, -1.0); write_f32(G.CAMERA + CAM_RATE_TIMED, -1.0)
    ctx:call_original()
    write_f32(G.CAMERA + CAM_RATE, rate); write_f32(G.CAMERA + CAM_RATE_TIMED, timed)
    fired_once(why)
  end)

  -- Map arrow: the pause map's heading from the player's rows, and the
  -- Rotational minimap's arrow drawn turned.
  wml.hook(HEADING_OF, function(ctx)
    if ctx:lr() == PAUSE_MAP_CALL and on("map_arrow") then
      local p = G.player()
      if p ~= 0 then ctx:set_r(3, p + P_ROWS); fired_once("pause map arrow") end
    end
    ctx:call_original()
  end)
  wml.hook(ARROW_UPRIGHT, function(ctx)
    local p = ctx:lr() == MINIMAP_CALL and on("map_arrow") and read_u8(MAP_STATIC) == 0 and G.player() or 0
    if p == 0 then ctx:call_original() return end
    local scale_x, scale_y = read_f32(SCALE_X), read_f32(SCALE_Y)
    ctx:set_f(1, s32(MAP_X) * scale_x + s32(OFFSET_X))
    ctx:set_f(2, s32(MAP_Y) * scale_y + s32(OFFSET_Y))
    ctx:set_f(3, math.atan(read_f32(p + P_FORWARD), read_f32(p + P_FORWARD + 8)) + math.pi + read_f32(MAP_HEADING))
    ctx:set_f(4, math.max(scale_x, scale_y))
    ctx:set_r(8, read_u32(ctx:r(1) + CLIP_ARG))
    ctx:call(ARROW_TURNED)   -- r3 is already the arrow's bitmap
    fired_once("minimap arrow")
  end)

  -- Cutscene pause: Back edges, and nothing else reaches the game while
  -- paused so no skip gets queued.
  on_pad(function(state)
    local buttons = read_u16(state + 4)
    if (buttons & BACK) ~= 0 and (cs.previous & BACK) == 0 then cs.toggle = true end
    cs.previous = buttons
    if cs.paused then write_u16(state + 4, buttons & ~HIDDEN_WHILE_PAUSED & 0xFFFF) end
  end)

  -- Keys, held for the next update (presses count per frame; updates come
  -- less often).
  wml.on_frame(function()
    if J.reload_key ~= "" and wml.key_pressed(J.reload_key) then J.reload_pressed = true end
    if J.save_key ~= "" and wml.key_pressed(J.save_key) then qs.pressed = true end
  end)

  install_startup(F.items.skip_intro.v, F.items.load_last_save.v)

  wml.hook(PAD_STATE, function(ctx)
    local user, state = ctx:r(3), ctx:r(4)
    ctx:call_original()
    if user ~= 0 or state == 0 then return end
    for _, fn in ipairs(pad_listeners) do fn(state) end
  end)
end

-- Before the game's update: the cutscene pause holds the frame it's on.
function J.before(ctx)
  cutscene_before(ctx)
end

-- After the game's update (and the menu's own rows).
function J.after(ctx)
  if game_state() == STATE_LEGAL then return end
  startup_after(ctx)
  quicksave_after(ctx)
  if J.reload_pressed then
    J.reload_pressed = false
    local p = G.player()
    if on("car_reload") and p ~= 0 and read_u32(p + G.P.VEHICLE) ~= 0 and read_u32(p + G.P.NOT_DRIVING) == 0
        and read_u32(p + G.P.EQUIPPED) ~= 0 and not G.in_cutscene() and not G.screen_up() then
      G.call(ctx, G.RELOAD, { p })
      log("juiced: car reload")
    end
  end
end

return J
