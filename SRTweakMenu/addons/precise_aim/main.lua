-- Precise Aim 1.0 by Eazzy (Eazeepz), https://github.com/Eazeepz/Precise-Aim
-- Bundled with SR Tweak Menu with the author's permission. The original code is
-- unchanged; the block at the end, marked SR Tweak Menu, is added.

-- Precise Aim 1.0 for Saints Reborn

-- Game addresses
local A = {
  PLAYER        = 0x8309ABEC,
  OBJECTS       = 0x830866C8,
  CAMERA        = 0x827D9778,
  CAMERA_MODE   = 0x827DA15C,
  CLOCK         = 0x827AA6E0,   -- game clock, ms
  MENU_WORDS    = { 0x839E0DF8, 0x839E0FB0, 0x82FFE434, 0x82FFE43C },
  WEAPON_TABLE  = 0x832ABCA8,
  WEAPON_COUNT  = 0x832ABCAC,
  FP_FLAG       = 0x8370D01E,   -- camera_first_mode: the game's aim mode (walk, strafe, face the aim)
  FP_CONSOLE    = 0x8370CFEF,
  CROUCH_OFFSET = 0x827D937C,   -- camera_free.xtbl crouch_y_offset
  INVERT        = 0x829B83F2,   -- bit 0x40 invert X, 0x20 invert Y
  HUD_BITMAPS   = 0x827AF1C8,   -- HUD bitmap table, 8 bytes per entry (name, handle)
  BIND_TABLE    = 0x829CC818,   -- the controller scheme's buttons, 16 bytes per action
  BIND_SCHEME   = 0x829CC814,
  AXIS_TABLE    = 0x829CCD28,   -- the stick bindings, 16 bytes per action
  PAD_STATE     = 0x832BAAE8,   -- right stick deadzone at +520
  -- camera_free.xtbl pan multipliers, the look timer
  SLOW_PAN_H    = 0x827D9348,
  SLOW_PAN_V    = 0x827D934C,
  FAST_PAN      = 0x827D9350,
  CAM_LOOK_TIMER = 0x827DA224,  -- clock ms when the camera may swing behind him again (-1 = now)
  -- animation pool
  POOL_GROUPS   = 0x82BC5BD8,   -- one slot per animation group, 0xA30 bytes
  POOL_SETS     = 0x82BBDBD8,
  POOL_VALUES   = 0x82BC1BD8,

  -- functions
  FRAME_FN      = 0x82167690,   -- per-frame player update
  PAD_READ      = 0x82788EC4,   -- XamInputGetState (state r5); the port merges keyboard and mouse in here
  CAMERA_UPDATE = 0x82109608,
  CAMERA_TURN   = 0x8210D518,   -- third-person camera step (f1 = frame time)
  ASSIST_FN     = 0x824878D0,   -- the game's target tracking
  RAISE_FN      = 0x82449708,   -- weapon raise (character, on, hold ms)
  CROUCH_FN     = 0x82461F58,   -- the game's own "crouch now"
  MOVE_FN       = 0x8245FC08,   -- movement (character r3)
  POSE_FN       = 0x82443DD8,   -- carry pose (character r3)
  LOCO_FN       = 0x82468398,   -- locomotion (character r3)
  SPREAD_FN     = 0x824703A8,   -- weapon cone (out min r3, out max r4, character r7)
  DRAW_BITMAP   = 0x8227E720,   -- HUD bitmap draw (handle r3, scale f4)
  ANIM_PICK     = 0x8246DFE8,   -- animation picker (character r3, flags r5: 0x10 gun up, 0x10000 aim)
  ANIM_CHOOSE   = 0x8244E018,   -- movement state chooser (character r5, returns state r3)
  ANIM_BLEND    = 0x8243FA50,   -- blend seconds between states (character r3, states r6 r7 r8 r10; f1 out)
  PLAY_ACTION   = 0x82444F88,   -- upper-body action (character r3, blend f3)
  PLAY_TURN     = 0x824451D8,   -- turn on the spot (character r3)
  PLAY_TRANS    = 0x82445300,   -- start / stop / turn-round transitions (character r3)
}
A.CAM_POS    = A.CAMERA + 44
A.CAM_RIGHT  = A.CAMERA + 80
A.CAM_UP     = A.CAMERA + 92
A.CAM_FWD    = A.CAMERA + 104
A.CAM_FOV    = A.CAMERA + 188
A.TURN_YAW   = A.CAMERA + 320
A.TURN_YAW2  = A.CAMERA + 324
A.TURN_PITCH = A.CAMERA + 336
A.TRACK_YAW  = A.CAMERA + 344   -- extra turn speeds (radians per second), added to the
A.TRACK_PITCH = A.CAMERA + 340  -- look input by the camera step and cleared after it
A.BODY_YAW   = A.CAMERA + 356   -- his heading at the camera's last step
A.LOOK_SPEED_X, A.LOOK_SPEED_Y = A.CAMERA + 312, A.CAMERA + 316  -- OPTIONS > CONTROLS look sensitivity

local P_POS, P_RIGHT, P_UP, P_FWD = 20, 32, 44, 56
local P_FLAGS, P_MOVE, P_STATE, P_SEAT, P_EXPIRY, P_EQUIP = 0xD8, 0x200, 508, 2496, 0x7C8, 3548
local CROUCH_BIT = 0x20000000
local VEH_RAISE_BITS = 0x88024120

local VEHICLE  = { [7] = true, [21] = true }
local GAMEPLAY = { [6] = true, [7] = true, [15] = true, [16] = true, [17] = true, [18] = true, [21] = true }
local RMB, LMB = 2, 1
local RETICLE_FIRST, RETICLE_LAST = 9, 19
local SLOT_STRIDE, SLOT_GROUP, SLOT_ID, SLOT_MIN, SLOT_MAX = 520, 0x10, 0x20, 0xA8, 0xAC

local NO_AIM = {
  sniper_rifle = true, grenade = true, bombsml = true, molotov = true, pipe_bomb = true,
  knife = true, knifel = true, baseball_bat = true, nightstick = true, tire_iron = true,
  kabob = true, ["40oz"] = true,
}

local SHOULDER_GROUP = { [1] = true, [7] = true, [8] = true, [9] = true, [10] = true, [11] = true }
local G_AK, G_SHOTGUN, G_SNIPER = 1, 7, 11

local ST = {
  STAND_SHLDR = 0x7D, WALK_SHLDR = 0x7E,
  WALK_L = 0x48, WALK_R = 0x49, WALK_B = 0x4A,
}

-- Settings
local function on(v) return v == 1 or v == true or v == "1" end
local function setting(name, default)
  local v = wml.setting(name, default)
  if v == nil then return default end
  return v
end
local function num(name, default, lo, hi)
  local v = tonumber(setting(name, default)) or default
  if lo and v < lo then v = lo end
  if hi and v > hi then v = hi end
  return v
end

local S = {
  aim_key        = setting("aim_key", 2),
  aim_toggle     = on(setting("aim_toggle", 1)),
  aim_speed      = num("aim_speed", 8.0, 0.5, 40),
  raise_hold_ms  = 500,
  remap_melee    = on(setting("remap_melee", 1)),
  melee_key      = setting("melee_key", "X"),
  aim_body_max   = num("aim_body_max", 20, 0, 180),
  face_speed     = 12,
  face_aim       = on(setting("face_aim", 1)),
  start_preset   = tostring(setting("preset", "SR1")),
  vehicle_fov    = num("vehicle_fov", 0.85, 0.5, 1.0),

  grenade_aim    = on(setting("grenade_aim", 1)),
  grenade_weapons = "grenade bombsml molotov pipe_bomb",
  grenade_toss_key = setting("grenade_toss_key", ""),
  grenade_raise  = on(setting("grenade_raise", 1)),

  melee_aim      = on(setting("melee_aim", 1)),
  melee_weapons  = "knife knifel baseball_bat nightstick tire_iron kabob 40oz",
  melee_raise    = on(setting("melee_raise", 0)),

  settle_delay   = num("aim_settle_delay", 0.5, 0, 5),
  settle_blend   = 0.6,
  lower_blend    = 0.4,
  full_push      = num("precise_exit_push", 0.95, 0.3, 1.0),
  gentle_push    = num("precise_walk_push", 0.7, 0, 1.0),
  gentle_ms      = 250,
  dir_margin     = 20,
  side_blend     = num("strafe_blend", 0.25, 0.05, 1.0),
  dir_hold_ms    = num("strafe_hold_ms", 150, 0, 1000),
  stop_ms        = num("strafe_stop_ms", 120, 0, 1000),
  via_ms         = 100,

  walk_key       = setting("walk_toggle_key", 20),
  walk_on        = on(setting("walk_start", 0)),
  slow_stick     = num("slow_walk_stick", 0.45, 0, 1),
  key_fwd        = setting("move_forward_key", "W"),
  key_back       = setting("move_back_key", "S"),
  key_left       = setting("move_left_key", "A"),
  key_right      = setting("move_right_key", "D"),

  crouch_moving  = on(setting("crouch_while_moving", 1)),
  crouch_key     = setting("crouch_key", "C"),
  crouch_scale   = num("crouch_scale", 1.25, 0, 3),

  cone_model     = on(setting("cone_model", 1)),
  moving_speed   = num("moving_speed", 0.6, 0, 10),
  cone = {},
  reticle_cone   = on(setting("reticle_follows_cone", 1)),
  reticle_grow   = num("reticle_grow", 0.4, 0, 2),
  reticle_shrink = num("reticle_shrink", 0.5, 0, 1),
  reticle_aim    = num("aim_reticle_scale", 0.8, 0.1, 2),
  reticle_vehicle = num("vehicle_reticle_scale", 0.7, 0.1, 2),

  tune_keys      = on(setting("tune_keys", 1)),
  tune_step      = num("tune_step", 0.25, 0.01, 1),

  pad            = on(setting("controller", 1)),
  pad_aim        = setting("pad_aim", "LT"),
  pad_melee      = setting("pad_melee", "RS"),
  pad_walk       = setting("pad_walk_toggle", "LB"),
  pad_veh_aim    = setting("pad_vehicle_aim", "LB"),
  pad_veh_split  = num("pad_vehicle_split", 0.8, 0.3, 0.98),
  pad_direct_aim = on(setting("pad_aim_direct", 1)),
  pad_direct_hip = on(setting("pad_hip_direct", 1)),
  pad_direct_veh = on(setting("pad_vehicle_direct", 1)),
  pad_hip_x      = num("pad_hip_speed_x", 3.6, 0.1, 20),
  pad_hip_y      = num("pad_hip_speed_y", 2.2, 0.1, 20),
  pad_curve      = num("pad_aim_curve", 1.8, 1, 4),
  pad_boost      = num("pad_turn_boost", 0.5, 0, 2),
  pad_boost_time = num("pad_turn_boost_time", 0.35, 0.05, 2),
  pad_zoom_scale = on(setting("pad_zoom_scale", 1)),
  pad_game_sens  = on(setting("pad_use_game_sensitivity", 1)),
  mouse_game_sens = on(setting("mouse_use_game_sensitivity", 1)),
  aim_sens       = num("aim_sensitivity", 1.0, 0.1, 3.0),
  zoom_match     = on(setting("aim_zoom_match", 1)),
  pad_dz         = num("pad_deadzone", 0.08, 0, 0.5),
  pad_outer_dz   = num("pad_outer_deadzone", 0.03, 0, 0.3),
  pad_game_dz    = 0.24,
}
-- Aiming turns as fast as not aiming unless these are set; aim_sensitivity scales both.
S.pad_aim_x     = num("pad_aim_speed_x", S.pad_hip_x, 0.1, 20)
S.pad_aim_y     = num("pad_aim_speed_y", S.pad_hip_y, 0.1, 20)
S.pad_boost_aim = num("pad_turn_boost_aim", S.pad_boost, 0, 2)
for _, k in ipairs({
    { "stand_hip", 1.00 }, { "stand_ads", 0.40 }, { "crouch_hip", 0.80 }, { "crouch_ads", 0.30 },
    { "move_hip", 1.60 }, { "move_ads", 0.70 }, { "crouch_move_hip", 1.30 }, { "crouch_move_ads", 0.55 },
    { "slowwalk_hip", 1.25 }, { "slowwalk_ads", 0.55 }, { "crouch_slowwalk_hip", 1.05 },
    { "crouch_slowwalk_ads", 0.45 }, { "sprint", 2.00 }, { "vehicle_hip", 2.00 }, { "vehicle_ads", 1.00 } }) do
  S.cone[k[1]] = num("cone_" .. k[1], k[2], 0.01, 10)
end

-- Helpers
local function clamp(v, lo, hi) return v < lo and lo or (v > hi and hi or v) end
local function ok_num(v) return type(v) == "number" and v == v and v > -1e9 and v < 1e9 end
local function s16(v) return v >= 0x8000 and v - 0x10000 or v end
local function read_vec(a) return wml.read_f32(a), wml.read_f32(a + 4), wml.read_f32(a + 8) end
local function write_vec(a, x, y, z) wml.write_f32(a, x) wml.write_f32(a + 4, y) wml.write_f32(a + 8, z) end
local function clock_now() return wml.read_u32(A.CLOCK) or 0 end
local function key_ok(k)
  if type(k) == "number" then return k > 0 and k < 256 end
  return k ~= nil and k ~= "" and pcall(wml.key_down, k)
end
local function down(k) return k ~= nil and wml.key_down(k) == true end
local function wrap_pi(a) return (a + math.pi) % (2 * math.pi) - math.pi end

local FOLDER = wml.mod_folder
local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local t = f:read("a")
  f:close()
  return t
end
local function write_file(path, text)
  local f = io.open(path, "w")
  if not f then wml.log("Precise Aim: could not write " .. path) return false end
  f:write(text)
  f:close()
  return true
end

local function set_facing(p, yaw)
  local r0x, r0y, r0z = read_vec(p + P_RIGHT)
  local r1x, r1y, r1z = read_vec(p + P_UP)
  local r2x, r2y, r2z = read_vec(p + P_FWD)
  local nfx, nfz = math.sin(yaw), math.cos(yaw)
  local cx, cy, cz = r1y * r2z - r1z * r2y, r1z * r2x - r1x * r2z, r1x * r2y - r1y * r2x
  local sign = (cx * r0x + cy * r0y + cz * r0z) >= 0 and 1 or -1
  write_vec(p + P_RIGHT, sign * nfz, 0, -sign * nfx)
  write_vec(p + P_UP, 0, 1, 0)
  write_vec(p + P_FWD, nfx, 0, nfz)
end
local function facing_of(p)
  local _, uy = wml.read_f32(p + P_UP), wml.read_f32(p + P_UP + 4)
  if not (ok_num(uy) and uy >= 0.9) then return nil end
  return math.atan(wml.read_f32(p + P_FWD), wml.read_f32(p + P_FWD + 8))
end
local function camera_yaw()
  local fx, _, fz = read_vec(A.CAM_FWD)
  if not (ok_num(fx) and ok_num(fz)) or fx * fx + fz * fz < 1e-6 then return nil end
  return math.atan(fx, fz)
end

-- Controller: buttons, the game's scheme, the look stick
local PAD_BITS = {
  DPAD_UP = 0x0001, DPAD_DOWN = 0x0002, DPAD_LEFT = 0x0004, DPAD_RIGHT = 0x0008,
  START = 0x0010, BACK = 0x0020, LS = 0x0040, RS = 0x0080, LB = 0x0100, RB = 0x0200,
  A = 0x1000, B = 0x2000, X = 0x4000, Y = 0x8000,
}
local TRIGGER_ON = 30
local BIND_BITS = { [0] = 0x1000, 0x2000, 0x4000, 0x8000, 0x0100, 0x0200, 0, 0,
                    0x0008, 0x0001, 0x0004, 0x0002, 0x0010, 0x0020, 0x0040, 0x0080 }
local ACT = { weapon_menu = 0, sprint = 9, crouch = 14 }
local GAME = { ready = false, scheme = -1, sprint = PAD_BITS.RB, wheel = PAD_BITS.B, crouch = PAD_BITS.LS,
               look_x = { code = 0, neg = false }, look_y = { code = 1, neg = false } }

local FOOT_KEYS = {
  LT = { 2 }, RT = { 1 }, A = { "R", "ENTER" }, X = { "SPACE" }, B = { "Q", "BACKSPACE" },
  Y = { "E" }, LB = { "F" }, RB = { "SHIFT" }, LS = { "C" }, RS = { "V", 4 },
  BACK = { "TAB" }, START = { "ESC", "M" },
  DPAD_UP = { "UP" }, DPAD_DOWN = { "DOWN" }, DPAD_LEFT = { "LEFT" }, DPAD_RIGHT = { "RIGHT" },
}
local VEH_KEYS = {
  LT = { "SPACE" }, RT = { 1 }, A = { "W", "ENTER" }, X = { "S" }, B = { "Q", "BACKSPACE" },
  Y = { "E" }, LB = { "Z", "X" }, RB = { "C", "X" }, LS = { "CTRL" }, RS = { "SHIFT", "V", 4 },
  BACK = { "TAB" }, START = { "ESC", "M" },
  DPAD_UP = { "UP" }, DPAD_DOWN = { "DOWN" }, DPAD_LEFT = { "LEFT" }, DPAD_RIGHT = { "RIGHT" },
}
local function any_key(list)
  for _, k in ipairs(list or {}) do if down(k) then return true end end
  return false
end

local function pad_input(name, what)
  if name == nil or name == 0 or name == "" or name == "0" then return nil end
  local n = tostring(name):upper():gsub("%s", "")
  if n == "LT" or n == "RT" then return { trigger = n, name = n } end
  if PAD_BITS[n] then return { bit = PAD_BITS[n], name = n } end
  wml.log("Precise Aim: " .. what .. " = " .. tostring(name) .. " is not a controller button")
  return nil
end

local function bind_bit(slot)
  local code = wml.read_u32(A.BIND_TABLE + slot * 16)
  if type(code) ~= "number" or code > 15 then return 0 end
  return BIND_BITS[code] or 0
end
local function axis_bind(action)
  local e = A.AXIS_TABLE + action * 16
  local code, neg = wml.read_u32(e), wml.read_u8(e + 4)
  if type(code) ~= "number" or code > 3 then code, neg = wml.read_u32(e + 8), wml.read_u8(e + 12) end
  if type(code) ~= "number" or code > 3 then return nil end
  return { code = code, neg = (neg or 0) ~= 0 }
end
local function read_bindings()
  if (wml.read_u32(A.BIND_TABLE + 12) or 0) == 0 then return end
  local scheme = wml.read_u32(A.BIND_SCHEME) or -1
  local sprint, wheel, crouch = bind_bit(ACT.sprint), bind_bit(ACT.weapon_menu), bind_bit(ACT.crouch)
  GAME.ready, GAME.scheme, GAME.sprint, GAME.wheel, GAME.crouch = true, scheme, sprint, wheel, crouch
  local x, y = axis_bind(0), axis_bind(1)
  if x and y then GAME.look_x, GAME.look_y = x, y end
end

if not key_ok(S.aim_key) then wml.log("Precise Aim: aim_key is not a usable key; mouse aiming is off") S.aim_key = nil end
if S.remap_melee and not key_ok(S.melee_key) then
  wml.log("Precise Aim: melee_key is not a usable key; melee stays on right mouse") S.remap_melee = false
end
if S.walk_key == 0 or S.walk_key == "" or not key_ok(S.walk_key) then S.walk_key = nil end
if S.melee_aim and not key_ok(S.melee_key) then
  wml.log("Precise Aim: melee_key is not a usable key; melee weapon aiming is off") S.melee_aim = false
end
if S.grenade_toss_key == nil or S.grenade_toss_key == "" or S.grenade_toss_key == 0 then S.grenade_toss_key = S.melee_key end
if not key_ok(S.grenade_toss_key) then
  wml.log("Precise Aim: grenade_toss_key is not a usable key; no key tosses a grenade") S.grenade_toss_key = nil
end
if S.crouch_moving and not key_ok(S.crouch_key) then S.crouch_key = nil end
if S.pad then
  S.pad_aim     = pad_input(S.pad_aim, "pad_aim")
  S.pad_melee   = pad_input(S.pad_melee, "pad_melee")
  S.pad_walk    = pad_input(S.pad_walk, "pad_walk_toggle")
  S.pad_veh_aim = pad_input(S.pad_veh_aim, "pad_vehicle_aim")
  if S.pad_melee and S.pad_melee.trigger then S.pad_melee = nil end
  if S.pad_walk and not S.pad_walk.bit then S.pad_walk = nil end
else
  S.pad_aim, S.pad_melee, S.pad_walk, S.pad_veh_aim = nil, nil, nil, nil
end
S.pad_aim_lt = S.pad_aim ~= nil and S.pad_aim.trigger == "LT"
S.veh_split = math.floor(S.pad_veh_split * 255)
local ANY_AIM = S.aim_key ~= nil or S.pad_aim ~= nil or S.pad_veh_aim ~= nil

-- Weapons
local W = { built = false, retry_at = 0, by_id = {}, by_name = {}, rec = nil, name = nil, misses = 0, miss_key = nil }

local function read_name(addr)
  if type(addr) ~= "number" or addr < 0x80000000 or addr >= 0xC0000000 then return nil end
  local out = {}
  for w = 0, 12 do
    local v = wml.read_u32(addr + w * 4)
    if type(v) ~= "number" then return nil end
    for b = 3, 0, -1 do
      local c = (v >> (b * 8)) & 0xFF
      if c == 0 then return table.concat(out) end
      if c < 32 or c > 126 then return nil end
      out[#out + 1] = string.char(c)
    end
  end
  return nil
end

local function table_changed()
  return wml.read_u32(A.WEAPON_TABLE) ~= W.base or wml.read_u32(A.WEAPON_COUNT) ~= W.count
end

local function build_weapons(frame)
  if W.built and not table_changed() then return true end
  W.built = false
  if frame < W.retry_at then return false end
  W.retry_at = frame + 60
  local base, cnt = wml.read_u32(A.WEAPON_TABLE), wml.read_u32(A.WEAPON_COUNT)
  if type(base) ~= "number" or base == 0 or type(cnt) ~= "number" or cnt <= 0 or cnt > 4096 then return false end
  W.by_name, W.by_id = {}, {}
  for i = 0, cnt - 1 do
    local slot = base + i * SLOT_STRIDE
    local nm = read_name(wml.read_u32(slot))
    if nm and nm ~= "" then
      local mn, mx = wml.read_f32(slot + SLOT_MIN), wml.read_f32(slot + SLOT_MAX)
      local e = { name = nm, min = mn, max = mx, group = wml.read_u32(slot + SLOT_GROUP),
                  cone = ok_num(mx) and ok_num(mn) and mx > 0 and mx <= 1.0 and mn >= 0 and mn <= mx }
      W.by_name[nm] = e
      local id = wml.read_u32(slot + SLOT_ID)
      if id and id ~= 0 then W.by_id[id] = e end
    end
  end
  W.built = next(W.by_id) ~= nil
  W.base, W.count = base, cnt
  return W.built
end

local function equipped_weapon(p, frame)
  if p == 0 then return nil end
  local w = wml.read_u32(p + P_EQUIP)
  if type(w) ~= "number" or w == 0 then W.rec, W.name = nil, nil return nil end
  local direct, alt = wml.read_u32(w + 8), wml.read_u32(w + 16)
  if type(alt) == "number" and alt ~= 0 then alt = wml.read_u32(alt + 8) end
  if W.built and w == W.rec and direct == W.direct and alt == W.alt then
    if W.name or frame < W.retry_at then return W.name end
    W.built = false
  end
  if not build_weapons(frame) then return nil end
  local e = W.by_id[alt] or W.by_id[direct]
  W.rec, W.direct, W.alt, W.name = w, direct, alt, e and e.name or nil
  local key = w .. ":" .. tostring(direct) .. ":" .. tostring(alt)
  if key ~= W.miss_key then W.miss_key, W.misses = key, 0 end
  if e then
    W.misses = 0
  else
    W.misses = W.misses + 1
    W.built, W.retry_at = false, frame + (W.misses < 5 and 60 or 180)
  end
  return W.name
end

local function aims_with(name) return type(name) == "string" and name ~= "" and not NO_AIM[name] end
local THROWABLE = {}
for n in S.grenade_weapons:gmatch("[%w_%-]+") do THROWABLE[n] = true end
local function throws_with(name) return S.grenade_aim and type(name) == "string" and THROWABLE[name] == true end
local MELEE = {}
for n in S.melee_weapons:gmatch("[%w_%-]+") do MELEE[n] = true end
local function melees_with(name) return S.melee_aim and type(name) == "string" and MELEE[name] == true end
local function holds_with(name) return throws_with(name) or melees_with(name) end
local function shoulders(name)
  if not aims_with(name) then return false end
  local e = W.by_name[name]
  return e ~= nil and SHOULDER_GROUP[e.group] == true
end

-- Camera presets, camera.cfg, tuning keys
local LIM = { zoom = { -3.5, 0.0 }, fov = { 0.5, 1.0 }, height = { 0.8, 2.6 }, shoulder = { -1.5, 1.5 } }
local FILES = { presets = FOLDER .. "/presets.ini", mine = FOLDER .. "/my_presets.ini",
                state = FOLDER .. "/camera.cfg" }
local PR = { list = {}, order = {}, mine = {}, name = nil, style = "zoom",
             zoom = 0, fov = 1, height = 1.7, shoulder = 0.6, note = "" }

local function add_preset(name, p, mine)
  if not (p.zoom and p.fov and p.height and p.shoulder) then
    wml.log("Precise Aim: preset [" .. name .. "] is missing a value and was skipped")
    return
  end
  p.name, p.style = name, p.style or "zoom"
  for k, l in pairs(LIM) do p[k] = clamp(p[k], l[1], l[2]) end
  if not PR.list[name] then PR.order[#PR.order + 1] = name end
  PR.list[name] = p
  if mine then PR.mine[name] = true end
end

local function parse_presets(text, mine)
  if not text then return end
  local name, cur = nil, nil
  local function flush() if name and cur then add_preset(name, cur, mine) end end
  for raw in text:gmatch("[^\r\n]+") do
    local line = (raw:gsub("%s*[;#].*$", ""))
    local hdr = line:match("^%s*%[(.-)%]%s*$")
    if hdr then
      flush()
      name = hdr:match("^%s*(.-)%s*$")
      cur = (name ~= "") and {} or nil
    elseif cur then
      local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
      if k == "style" then cur.style = (v:lower() == "orbit") and "orbit" or "zoom"
      elseif LIM[k] then cur[k] = tonumber(v) end
    end
  end
  flush()
end

local function apply_preset(name)
  local p = PR.list[name]
  if not p and type(name) == "string" then   -- names are matched ignoring case
    for n, q in pairs(PR.list) do
      if n:lower() == name:lower() then name, p = n, q break end
    end
  end
  if not p then return false end
  PR.name, PR.style = name, p.style
  PR.zoom, PR.fov, PR.height, PR.shoulder = p.zoom, p.fov, p.height, p.shoulder
  return true
end

local function remove_preset(name)
  PR.list[name], PR.mine[name] = nil, nil
  for i, n in ipairs(PR.order) do if n == name then table.remove(PR.order, i) break end end
end

local function save_mine()
  local t = { "; Presets saved in game. Share one by copying its [block] into someone's presets.ini.\n\n" }
  for _, n in ipairs(PR.order) do
    local p = PR.list[n]
    if PR.mine[n] then
      t[#t + 1] = string.format("[%s]\nstyle = %s\nzoom = %.2f\nfov = %.2f\nheight = %.2f\nshoulder = %.2f\n\n",
                                p.name, p.style, p.zoom, p.fov, p.height, p.shoulder)
    end
  end
  write_file(FILES.mine, table.concat(t))
end

parse_presets(read_file(FILES.presets), false)
parse_presets(read_file(FILES.mine), true)
if #PR.order == 0 then
  add_preset("SR1", { style = "orbit", zoom = 0.0, fov = 0.60, height = 1.69, shoulder = 0.35 }, false)
end
if not apply_preset(S.start_preset) then apply_preset(PR.order[1]) end

local CFG = { last = nil, poll_at = 0, dirty = false }
local function cfg_text()
  local t = { string.format("preset = %s\nzoom = %.2f\nfov = %.2f\nheight = %.2f\nshoulder = %.2f\n",
                            PR.name, PR.zoom, PR.fov, PR.height, PR.shoulder) }
  for _, n in ipairs(PR.order) do
    local p = PR.list[n]
    if PR.mine[n] and n:match("^custom%d+$") then
      t[#t + 1] = string.format("%s = %.2f %.2f %.2f %.2f\n", n, p.zoom, p.fov, p.height, p.shoulder)
    end
  end
  return table.concat(t)
end
local function apply_cfg(text)
  local vals, chosen, mine_changed = {}, nil, false
  for line in text:gmatch("[^\r\n]+") do
    local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if k == "preset" then chosen = v
    elseif k and k:match("^custom%d+$") then
      local z, f, h, s = v:match("^(-?[%d.]+)%s+([%d.]+)%s+([%d.]+)%s+(-?[%d.]+)$")
      local old = PR.list[k]
      if z and (not old or PR.mine[k]) then
        add_preset(k, { style = old and old.style, zoom = tonumber(z), fov = tonumber(f),
                        height = tonumber(h), shoulder = tonumber(s) }, true)
        mine_changed = true
      end
    elseif k then
      vals[k] = tonumber(v)
    end
  end
  if mine_changed then save_mine() end
  if chosen and chosen ~= "" then apply_preset(chosen) end
  for k, l in pairs(LIM) do if vals[k] then PR[k] = clamp(vals[k], l[1], l[2]) end end
  CFG.last = text
end
local function save_cfg()
  local text = cfg_text()
  if write_file(FILES.state, text) then CFG.last = text end
  CFG.dirty = false
end
do
  local text = read_file(FILES.state)
  if text and text ~= "" then apply_cfg(text) end
end

local MODS = { CTRL = "CTRL", CONTROL = "CTRL", ALT = "ALT", SHIFT = "SHIFT" }
local TUNE = { repeat_at = 0, hold = 0, fired = false, map = {}, combo = nil, mask = 0 }
if S.pad and S.tune_keys then
  local c = pad_input(setting("pad_tune_button", "LB"), "pad_tune_button")
  if c and c.bit then TUNE.combo = c end
end

local function bind(name, default, pad_default)
  local out, raw = {}, setting(name, default)
  if raw ~= nil and raw ~= "" then
    local mod, key = nil, raw
    if type(raw) == "string" then
      local m, rest = raw:match("^%s*(%a+)%s*%+%s*(.-)%s*$")
      if m and MODS[m:upper()] then mod, key = MODS[m:upper()], rest end
      key = tonumber(key) or key
    end
    if key_ok(key) then
      pcall(wml.take_key, key)
      out.key, out.mod = key, mod
    else
      wml.log("Precise Aim: " .. name .. " is not a usable key")
    end
  end
  if TUNE.combo and pad_default then
    local pname = name:gsub("^key_", "pad_")
    local pb = pad_input(setting(pname, pad_default), pname)
    if pb and pb.bit and pb.bit ~= TUNE.combo.bit then
      out.pad = pb
      TUNE.mask = TUNE.mask | pb.bit
    end
  end
  if out.key == nil and out.pad == nil then return nil end
  return out
end

local function step_preset(d)
  local i = 1
  for k, n in ipairs(PR.order) do if n == PR.name then i = k break end end
  apply_preset(PR.order[((i - 1 + d) % #PR.order) + 1])
end
local function save_custom()
  local slot = tonumber((PR.name or ""):match("^custom(%d+)$"))
  if not (slot and PR.mine[PR.name]) then
    slot = nil
    for i = 1, 8 do if not PR.list["custom" .. i] then slot = i break end end
  end
  if not slot then PR.note = "all 8 custom slots are full" return end
  local name = "custom" .. slot
  remove_preset(name)
  add_preset(name, { style = PR.style, zoom = PR.zoom, fov = PR.fov, height = PR.height, shoulder = PR.shoulder }, true)
  PR.name = name
  save_mine()
  PR.note = "saved as " .. name
end
local function clear_custom()
  local target = PR.mine[PR.name] and PR.name or nil
  if not target then PR.note = "only your saved presets can be deleted" return end
  remove_preset(target)
  save_mine()
  apply_preset(PR.order[1])
  PR.note = "cleared " .. target
end

if S.tune_keys then
  local function adj(field, d)
    return function()
      PR[field] = clamp(PR[field] + d, LIM[field][1], LIM[field][2])
      CFG.dirty = true
    end
  end
  local step = S.tune_step
  for _, b in ipairs({
      { "key_zoom_in", "MINUS", adj("zoom", -step), "Y" },
      { "key_zoom_out", "PLUS", adj("zoom", step), "A" },
      { "key_fov_wide", "PAGEUP", adj("fov", step), "B" },
      { "key_fov_narrow", "PAGEDOWN", adj("fov", -step), "X" },
      { "key_height_down", "HOME", adj("height", -0.1), "DPAD_DOWN" },
      { "key_height_up", "END", adj("height", 0.1), "DPAD_UP" },
      { "key_shoulder_left", "CTRL+I", adj("shoulder", -0.1), "DPAD_LEFT" },
      { "key_shoulder_right", "CTRL+O", adj("shoulder", 0.1), "DPAD_RIGHT" } }) do
    local k = bind(b[1], b[2], b[4])
    if k then TUNE.map[#TUNE.map + 1] = { k, b[3] } end
  end
  TUNE.reset = bind("key_preset_reset", "CTRL+J", "RS")
  TUNE.prev  = bind("key_preset_prev", "CTRL+K", "")
  TUNE.next  = bind("key_preset_next", "CTRL+Y", "RB")
  TUNE.save  = bind("key_preset_save", "CTRL+U", "START")
  TUNE.clear = bind("key_preset_clear", "CTRL+G", "BACK")
end

local function tune_status()
  return string.format("Precise Aim [%s]  zoom %.2f  fov %.2f  height %.2f  shoulder %.2f%s",
                       tostring(PR.name), PR.zoom, PR.fov, PR.height, PR.shoulder,
                       PR.note ~= "" and ("  " .. PR.note) or "")
end
local function show(text)
  if text == TUNE.shown or type(wml.overlay_text) ~= "function" then return end
  TUNE.shown = text
  pcall(wml.overlay_text, text)
end

-- Runtime state
local st = {
  player = 0, last_player = 0, frames = 0, clock = 0, last_clock = nil,
  paused = false, frozen = 0, in_veh = false, seated = false,
  equipped = nil, last_gun = nil,
  pad_buttons = 0, pad_lt = 0, pad_rt = 0, pad_lx = 0, pad_ly = 0, pad_rx = 0, pad_ry = 0,
  pad_edit = false, pad_veh_edit = false, pad_remap = false, pad_hold = false,
  combo = false, combo_prev = false, combo_used = false, combo_tap = 0, combo_at = nil,
  aim_input = false, aim_held_prev = false, aim_tog = false, aim_latch = false,
  shift = false, prev_shift = false, prev_latch = false, sprint_held = false, sprint_wins = false,
  shift_taken = false, kb_melee = false, rmb_hold = false,
  mv_x = 0, mv_y = 0, push = 0, still = true,
  walk_on = S.walk_on, walk_prev = false, pad_walk_prev = false, walk_block = false,
  wheel = false, wheel_until = 0, switching = false,
  aiming = false, throw_aim = false, melee_aim = false, precise = false, still_since = nil,
  raise = false, armed = false, hold_raise = false, sprint_wait = 0,
  blend = 0.0,
  blend_next = nil, blend_next_until = 0,
  fp_ours = false,
  face_yaw = nil, face_on = false, face_clock = nil, look_until = 0,
  gentle_since = nil, pdir = nil, pdir_t = 0, plast = nil, plast_t = 0, pvia_to = nil, pvia_until = 0,
  anim_still = true, still_t = 0,
  crouched = false, crouch_now = 0.0, crouch_prev = false, crouch_key_prev = false,
  crouch_at = 0, crouch_until = 0, move_state = 0, speed = 0.0, sx = nil, sz = nil, sclock = nil,
  veh_kb = false, veh_zone = 0, veh_pad = false, veh_aim = false, veh_tog = false, veh_held_prev = false, vblend = 0.0, veh_held = false,
  cam_saved = false, saved_pos = { 0, 0, 0 }, written_pos = { 0, 0, 0 },
  fov_base = 60.0, fov_written = false, fov_last = nil,
  turn_x = 0.0, turn_y = 0.0, direct_was = false, turn_frame = -100, edge_time = 0,
  ret_now = 1.0, ret_handles = {}, ret_set = {},
}

-- Start clean, also after a reload
pcall(wml.take_key, "SHIFT", false)
pcall(wml.take_key, RMB, false)
pcall(wml.force_key, RMB, false)
if (wml.read_u8(A.FP_CONSOLE) or 0) == 0 then wml.write_u8(A.FP_FLAG, 0) end

local function riding() return st.in_veh or st.seated end
local function allowed()
  return wml.read_u32(A.CAMERA) == 0 and GAMEPLAY[wml.read_u32(A.CAMERA_MODE)] == true
end
local function menu_up()
  for _, a in ipairs(A.MENU_WORDS) do if (wml.read_u32(a) or 0) ~= 0 then return true end end
  return false
end
local function seat_is_vehicle(p)
  if p == 0 then return false end
  local s = wml.read_u32(p + P_STATE) or 0
  if s == 9 or s == 12 then return false end
  local idx = (wml.read_u32(p + P_SEAT) or 0) & 0xFFFF
  if idx == 0 or idx >= 4096 then return false end
  local ob = wml.read_u32(A.OBJECTS + 12 + idx * 16) or 0
  return ob ~= 0 and (wml.read_u32(ob + 72) or 0) == 5
end
local function pad_down(b)
  if b == nil then return false end
  if b.trigger == "LT" then return st.pad_lt > TRIGGER_ON end
  if b.trigger == "RT" then return st.pad_rt > TRIGGER_ON end
  return (st.pad_buttons & b.bit) ~= 0
end
local function pad_bits(mask)
  return (st.pad_buttons & mask & ~(st.combo and (TUNE.mask | (TUNE.combo and TUNE.combo.bit or 0)) or 0)) ~= 0
end

local SLOWWALK = { move_ads = "slowwalk_ads", crouch_move_ads = "crouch_slowwalk_ads",
                   move_hip = "slowwalk_hip", crouch_move_hip = "crouch_slowwalk_hip" }
local function cone_mult(ads)
  if st.seated then return ads and S.cone.vehicle_ads or S.cone.vehicle_hip end
  local s
  if st.move_state == 3 and not ads then s = "sprint"
  elseif st.speed > S.moving_speed then s = st.crouched and "crouch_move" or "move"
  else s = st.crouched and "crouch" or "stand" end
  if s ~= "sprint" then s = s .. (ads and "_ads" or "_hip") end
  if st.walk_on then s = SLOWWALK[s] or s end
  return S.cone[s] or 1.0
end

-- Per frame: read the inputs, decide the state
-- Slow walk on the camera tuning button (LB): a quick tap toggles slow walk, holding it
-- with another button tunes the camera.
local WALK_TAP_MS = 400
local function walk_on_combo()
  return S.pad_walk ~= nil and TUNE.combo ~= nil and S.pad_walk.bit == TUNE.combo.bit
end

local function update_inputs(p, clock)
  if TUNE.combo then
    local raw = (st.pad_buttons & TUNE.combo.bit) ~= 0
    if st.combo_tap > 0 then st.combo_tap = st.combo_tap - 1 end
    st.combo = raw and not any_key(FOOT_KEYS[TUNE.combo.name]) and p ~= 0
               and not st.paused and not st.in_veh and not st.seated
    if st.combo then
      if not st.combo_prev then st.combo_at = clock end
      if (st.pad_buttons & TUNE.mask) ~= 0 then st.combo_used = true end
    elseif st.combo_prev then
      if not st.combo_used and not st.paused then
        if not walk_on_combo() then
          st.combo_tap = 3
        elseif clock - (st.combo_at or clock) <= WALK_TAP_MS then
          st.walk_on = not st.walk_on
        end
      end
      st.combo_used = false
    end
    st.combo_prev = st.combo
  end

  st.shift = down("SHIFT") or pad_bits(GAME.sprint)
  st.sprint_held = st.shift and not st.seated and not st.in_veh

  local mouse = down(S.aim_key)
  local held = mouse or (pad_down(S.pad_aim) and not (S.pad_aim_lt and st.kb_melee))
  if S.aim_toggle then
    local live = p ~= 0 and not st.paused and allowed()
    if live and held and not st.aim_held_prev then st.aim_tog = not st.aim_tog end
    if p == 0 or (st.shift and not st.prev_shift) or st.seated or st.in_veh
       or not (aims_with(st.equipped) or holds_with(st.equipped)) then
      st.aim_tog = false
    end
    st.aim_input = st.aim_tog
  else
    st.aim_input = held
  end
  st.aim_held_prev = held

  local va = S.pad_veh_aim
  st.veh_kb = va ~= nil and any_key(VEH_KEYS[va.name])
  if (st.seated or st.in_veh) and va and not st.paused then
    if va.trigger then
      local v = va.trigger == "LT" and st.pad_lt or st.pad_rt
      if v <= TRIGGER_ON or st.veh_kb then st.veh_zone, st.veh_pad = 0, false
      elseif v < S.veh_split then
        st.veh_zone = st.veh_zone + 1
        if st.veh_zone >= 3 then st.veh_pad = true end
      end
    else
      st.veh_pad = pad_down(va) and not st.veh_kb
    end
  else
    st.veh_zone, st.veh_pad = 0, false
  end
  local riding = st.seated or st.in_veh
  local veh_held = mouse or (va ~= nil and va.bit ~= nil and st.veh_pad)
  if not riding then
    st.veh_tog = false
  elseif S.aim_toggle and not st.paused and veh_held and not st.veh_held_prev then
    st.veh_tog = not st.veh_tog
  end
  st.veh_held_prev = veh_held
  local veh_in = veh_held
  if S.aim_toggle then veh_in = st.veh_tog end
  if riding then
    st.aim_latch = veh_in or (va ~= nil and va.trigger ~= nil and st.veh_pad)
  else
    st.aim_latch = st.aim_input
  end

  if st.seated or st.in_veh or not st.shift then
    st.sprint_wins = false
  else
    if not st.prev_shift and st.aim_latch then st.sprint_wins = true end
    if st.aim_latch and not st.prev_latch then st.sprint_wins = false end
  end
  st.prev_shift, st.prev_latch = st.shift, st.aim_latch

  st.wheel = GAME.wheel ~= 0 and (st.pad_buttons & GAME.wheel) ~= 0
  if st.wheel then st.wheel_until = clock + 500 end
  st.switching = st.wheel or clock < st.wheel_until

  if S.walk_key then
    local d = down(S.walk_key)
    if d and not st.walk_prev and not st.paused then st.walk_on = not st.walk_on end
    st.walk_prev = d
  end
  if S.pad_walk and not walk_on_combo() then
    local raw = pad_down(S.pad_walk)
    if (st.wheel or st.combo) and raw then st.walk_block = true elseif not raw then st.walk_block = false end
    local d = st.pad_edit and raw and not st.walk_block and not any_key(FOOT_KEYS[S.pad_walk.name])
    if d and not st.pad_walk_prev then st.walk_on = not st.walk_on end
    st.pad_walk_prev = d
  end

  local mx, my = st.pad_lx, st.pad_ly
  if mx * mx + my * my < 4000 * 4000 then
    local kx = (down(S.key_right) and 1 or 0) - (down(S.key_left) and 1 or 0)
    local ky = (down(S.key_fwd) and 1 or 0) - (down(S.key_back) and 1 or 0)
    if kx ~= 0 or ky ~= 0 then
      local n = 32767 / math.sqrt(kx * kx + ky * ky)
      mx, my = kx * n, ky * n
    end
  end
  st.mv_x, st.mv_y = mx, my
  st.push = math.min(1, math.sqrt(mx * mx + my * my) / 32767)
  st.still = st.push < S.pad_dz + 0.12
  return mouse
end

local function update_body(p, clock, dt)
  local flags = p ~= 0 and (wml.read_u32(p + P_FLAGS) or 0) or 0
  st.crouched = (flags & CROUCH_BIT) ~= 0
  st.move_state = p ~= 0 and (wml.read_u32(p + P_MOVE) or 0) or 0

  if S.crouch_moving then
    local cd = down(S.crouch_key) or (S.pad and pad_bits(GAME.crouch))
    if cd and not st.crouch_key_prev and not st.crouched and not st.crouch_prev
       and not st.seated and not st.in_veh and not st.paused then
      st.crouch_at, st.crouch_until = st.frames + 1, st.frames + 4
    end
    if st.crouched then st.crouch_until = 0 end
    st.crouch_key_prev = cd
  end
  st.crouch_prev = st.crouched
  local target = st.crouched and (wml.read_f32(A.CROUCH_OFFSET) or 0.45) * S.crouch_scale or 0
  local k = 1 - math.exp(-dt * (target < st.crouch_now and 6 or 8))
  st.crouch_now = clamp(st.crouch_now + (target - st.crouch_now) * k, 0, 1.5)

  if p ~= 0 then
    local x, z = wml.read_f32(p + P_POS), wml.read_f32(p + P_POS + 8)
    if st.sx and clock > st.sclock then
      local v = math.sqrt((x - st.sx) ^ 2 + (z - st.sz) ^ 2) / ((clock - st.sclock) / 1000)
      st.speed = st.speed + (v - st.speed) * (1 - math.exp(-(clock - st.sclock) / 47))
      if st.speed ~= st.speed or st.speed > 50 then st.speed = 0 end
    end
    if clock ~= st.sclock then st.sx, st.sz, st.sclock = x, z, clock end
  end
end

local function update_melee()
  st.kb_melee = false
  local throw = holds_with(st.equipped)
  if not (S.remap_melee or throw) then return end
  if st.paused then
    wml.take_key(RMB, false) wml.force_key(RMB, false)
  elseif st.in_veh then
    wml.take_key(RMB, false) wml.force_key(RMB, false)
  elseif (S.remap_melee and aims_with(st.equipped)) or throw then
    wml.take_key(RMB, true)
    st.kb_melee = down(throws_with(st.equipped) and S.grenade_toss_key or S.melee_key)
    wml.force_key(RMB, st.kb_melee)
    st.rmb_hold = down(RMB)
  elseif st.rmb_hold and down(RMB) then
    wml.take_key(RMB, true) wml.force_key(RMB, false)
  else
    st.rmb_hold = false
    wml.take_key(RMB, false) wml.force_key(RMB, false)
  end
end

local function update_aim_state(p, clock)
  local gun = aims_with(st.equipped)
  local throw, melee = throws_with(st.equipped), melees_with(st.equipped)
  local on_foot = p ~= 0 and not st.paused and not st.in_veh and not st.seated and allowed()

  st.aiming = ANY_AIM and st.aim_input and (gun or throw or melee) and on_foot and not st.sprint_wins
  st.throw_aim = st.aiming and throw
  st.melee_aim = st.aiming and melee

  if st.aiming and st.move_state == 3 and st.sprint_wait < 20 then
    st.sprint_wait, st.hold_raise = st.sprint_wait + 1, true
  else
    st.hold_raise = false
    if not st.aiming then st.sprint_wait = 0 end
  end

  local free = on_foot and not st.sprint_held and not st.switching

  local base = st.aiming and free and shoulders(st.equipped)
  if base and st.still then st.still_since = st.still_since or clock else st.still_since = nil end
  -- A gentle push of the stick counts as slow walking (keys always push fully).
  if base and not st.still and st.push <= S.gentle_push then
    st.gentle_since = st.gentle_since or clock
  else
    st.gentle_since = nil
  end
  local shooting = down(LMB) or (S.pad and st.pad_rt > TRIGGER_ON)
  local precise
  if not base then
    precise = false
  elseif st.walk_on then
    precise = true
  elseif st.precise then
    precise = st.push < S.full_push
  else
    precise = (st.still_since ~= nil and clock - st.still_since >= S.settle_delay * 1000)
              or (st.still and shooting)
              or (st.gentle_since ~= nil and clock - st.gentle_since >= S.gentle_ms)
  end
  if precise ~= st.precise then
    st.blend_next = precise and S.settle_blend or S.lower_blend
    st.blend_next_until = clock + math.floor(st.blend_next * 1000) + 150
  end
  st.precise = precise
  -- The animations only stop once the stick or keys have rested a moment: changing keys
  -- (A to D) often has a frame with none down, which snapped him to standing and back.
  -- Still moving while he is still sliding along, so a slow stop does not flicker.
  if not st.still or st.speed > 0.5 then st.still_t = clock end
  st.anim_still = st.still and clock - st.still_t >= S.stop_ms
  if st.anim_still or not precise then st.pdir = nil end

  st.raise = st.aiming and not st.hold_raise and not st.switching
             and (gun or (throw and S.grenade_raise) or (melee and S.melee_raise))

  if precise then
    wml.write_u8(A.FP_FLAG, 1)
    st.fp_ours = true
  elseif st.fp_ours then
    if (wml.read_u8(A.FP_CONSOLE) or 0) == 0 then wml.write_u8(A.FP_FLAG, 0) end
    st.fp_ours = false
  end

  if st.aiming ~= st.shift_taken then
    wml.take_key("SHIFT", st.aiming)
    st.shift_taken = st.aiming
  end

  st.veh_aim = st.seated and st.aim_latch and not st.paused and (st.equipped == nil or gun)
  if st.equipped and gun then st.last_gun = st.equipped end
end

local function update_blends(dt)
  local kr = 1 - math.exp(-S.aim_speed * dt)
  if riding() or not allowed() then st.blend = 0 end
  st.blend = st.blend + ((st.aiming and 1 or 0) - st.blend) * kr
  if st.blend < 0.002 then st.blend = 0 end
  if st.blend > 0.998 and st.aiming then st.blend = 1 end
  st.vblend = st.vblend + ((st.veh_aim and 1 or 0) - st.vblend) * kr
  if st.vblend < 0.002 then st.vblend = 0 end
end

local function update_reticle(dt)
  if st.frames % 30 == 1 then
    local changed = false
    for i = RETICLE_FIRST, RETICLE_LAST do
      local h = wml.read_u32(A.HUD_BITMAPS + i * 8 + 4) or 0xFFFFFFFF
      if st.ret_handles[i] ~= h then st.ret_handles[i], changed = h, true end
    end
    if changed then
      st.ret_set = {}
      for i = RETICLE_FIRST, RETICLE_LAST do
        local h = st.ret_handles[i]
        if h ~= 0xFFFFFFFF and h ~= 0 then st.ret_set[h] = true end
      end
    end
  end
  local size = 1.0
  local eq = st.equipped or (st.seated and st.last_gun) or nil
  local e = eq and W.by_name[eq]
  if e and e.cone and (aims_with(eq) or eq == "sniper_rifle") then
    if S.cone_model and S.reticle_cone then
      local m = cone_mult(st.aiming or st.veh_aim)
      size = m > 1 and 1 + (m - 1) * S.reticle_grow or 1 - (1 - m) * S.reticle_shrink
    else
      size = 1 - math.max(st.blend, st.vblend) * (1 - S.reticle_aim)
    end
  end
  if st.seated then size = size * S.reticle_vehicle end
  st.ret_now = st.ret_now + (size - st.ret_now) * (1 - math.exp(-dt / 0.075))
  if math.abs(st.ret_now - size) < 0.002 then st.ret_now = size end
end

local function vehicle_raise(p)
  if p == 0 then return end
  if st.veh_aim then
    wml.write_u32(p + P_EXPIRY, (clock_now() + 30000) & 0xFFFFFFFF)
    wml.write_u32(p + P_FLAGS, (wml.read_u32(p + P_FLAGS) or 0) | VEH_RAISE_BITS)
    st.veh_held = true
  elseif st.veh_held then
    wml.write_u32(p + P_EXPIRY, 0)
    st.veh_held = false
  end
end

local function update_tuning()
  if st.frames >= CFG.poll_at then
    CFG.poll_at = st.frames + 60
    local text = read_file(FILES.state)
    if text and text ~= "" and text ~= CFG.last then apply_cfg(text) TUNE.hold = 180 end
  end
  if S.tune_keys then
    local function held(b)
      if b == nil then return false end
      if b.key ~= nil and (b.mod == nil or down(b.mod)) and down(b.key) then return true end
      return b.pad ~= nil and st.combo and (st.pad_buttons & b.pad.bit) ~= 0
    end
    local any = false
    for _, e in ipairs(TUNE.map) do if held(e[1]) then any = true break end end
    local once = (held(TUNE.next) and 1) or (held(TUNE.prev) and -1) or (held(TUNE.reset) and 0)
                 or (held(TUNE.save) and "save") or (held(TUNE.clear) and "clear")
    if not any and not once then
      TUNE.repeat_at, TUNE.fired = 0, false
    elseif once then
      if not TUNE.fired then
        TUNE.fired = true
        if once == "save" then save_custom()
        elseif once == "clear" then clear_custom()
        elseif once == 0 then apply_preset(PR.name)
        else step_preset(once) end
        CFG.dirty, TUNE.hold = true, 180
      end
    elseif st.frames >= TUNE.repeat_at then
      TUNE.repeat_at = st.frames + 12
      for _, e in ipairs(TUNE.map) do if held(e[1]) then e[2]() end end
      TUNE.hold = 180
    end
  end
  if TUNE.hold > 0 then
    TUNE.hold = TUNE.hold - 1
    if TUNE.hold == 0 then PR.note = "" end
  end
  if CFG.dirty and TUNE.hold == 0 then save_cfg() end
  if st.frames % 6 == 0 then show((TUNE.hold > 0 or CFG.dirty) and tune_status() or "") end
end

local set_swap

local FOV = { ref = nil, now = nil }
wml.on_frame(function()
  st.frames = st.frames + 1
  if st.frames % 30 == 1 then read_bindings() end
  local p = wml.read_u32(A.PLAYER) or 0
  st.player = p
  if p ~= 0 and p ~= st.last_player then
    W.built, W.retry_at, W.rec, W.name, W.misses, W.miss_key = false, 0, nil, nil, 0, nil
    FOV.ref, FOV.now = nil, nil
  end
  st.last_player = p
  local clock = clock_now()
  local dt = st.last_clock and clamp((clock - st.last_clock) / 1000, 0, 0.1) or 0
  st.last_clock, st.clock = clock, clock

  if dt > 0 then st.frozen = 0 else st.frozen = st.frozen + 1 end
  st.paused = st.frozen >= 3 or menu_up()
  st.in_veh = VEHICLE[wml.read_u32(A.CAMERA_MODE)] == true
  st.seated = seat_is_vehicle(p)
  st.pad_edit = p ~= 0 and not st.paused and not st.in_veh and not st.seated
  st.pad_veh_edit = S.pad and p ~= 0 and not st.paused and riding() and S.pad_veh_aim ~= nil

  update_inputs(p, clock)
  update_body(p, clock, dt)
  update_melee()

  local pad_aim_held = pad_down(S.pad_aim)
  if not (S.pad and st.pad_edit and S.pad_aim) then
    st.pad_remap, st.pad_hold = false, false
  elseif (aims_with(st.equipped) and (S.remap_melee or not S.pad_aim_lt)) or holds_with(st.equipped) then
    st.pad_remap, st.pad_hold = true, pad_aim_held
  else
    st.pad_remap, st.pad_hold = false, st.pad_hold and pad_aim_held
  end

  update_aim_state(p, clock)
  update_blends(dt)
  update_reticle(dt)
  vehicle_raise(p)
  pcall(set_swap, st.precise)
  update_tuning()
end)

-- Hooks: raise the gun, crouch on the move
local function call_with(ctx, fn, regs, fregs)
  local saved, fsaved = {}, {}
  for r, v in pairs(regs) do saved[r] = ctx:r(r) ctx:set_r(r, v) end
  for r, v in pairs(fregs or {}) do fsaved[r] = ctx:f(r) ctx:set_f(r, v) end
  local ok, err = pcall(function() ctx:call(fn) end)
  for r, v in pairs(saved) do ctx:set_r(r, v) end
  for r, v in pairs(fsaved) do ctx:set_f(r, v) end
  return ok, err
end

local function hook(addr, fn)
  if not pcall(wml.hook, addr, fn) then
    wml.log(string.format("Precise Aim: could not hook %08X", addr))
  end
end

hook(A.FRAME_FN, function(ctx)
  st.equipped = equipped_weapon(st.player, st.frames)
  ctx:call_original()
  local p = st.player
  if p == 0 then st.armed = false return end
  if st.crouch_until > 0 and st.frames >= st.crouch_at then
    if st.frames <= st.crouch_until and not st.seated
       and ((wml.read_u32(p + P_FLAGS) or 0) & CROUCH_BIT) == 0 then
      call_with(ctx, A.CROUCH_FN, { [3] = p })
    end
    st.crouch_until = 0
  end
  if st.seated then return end
  if st.raise then
    call_with(ctx, A.RAISE_FN, { [3] = p, [4] = 1, [5] = S.raise_hold_ms })
    st.armed = true
  elseif st.armed then
    call_with(ctx, A.RAISE_FN, { [3] = p, [4] = 0, [5] = 0 })
    st.armed = false
  end
end)

-- Hook: the controller state the game reads (keyboard and mouse merged in)
local function game_deadzone()
  local v = wml.read_f32(A.PAD_STATE + 520)
  if ok_num(v) and v >= 0 and v <= 0.6 then return v end
  return S.pad_game_dz
end

local function shape_stick(addr, scale)
  local rx, ry = s16(wml.read_u16(addr + 12) or 0), s16(wml.read_u16(addr + 14) or 0)
  if rx == 0 and ry == 0 then return false end
  local gdz = S.pad_game_dz > 0 and game_deadzone() or 0
  if gdz <= 0 and scale >= 1 then return false end
  local m = math.sqrt(rx * rx + ry * ry) / 32767
  local nx, ny = 0, 0
  if m > S.pad_dz then
    local t = math.min(1, (m - S.pad_dz) / (1 - S.pad_dz)) * scale
    local dx, dy = rx / 32767 / m, ry / 32767 / m
    local out = (gdz + t * (1 - gdz)) / math.max(math.abs(dx), math.abs(dy))
    nx = clamp(math.floor(dx * out * 32767 + 0.5), -32767, 32767)
    ny = clamp(math.floor(dy * out * 32767 + 0.5), -32767, 32767)
  end
  if nx == rx and ny == ry then return false end
  wml.write_u16(addr + 12, nx & 0xFFFF)
  wml.write_u16(addr + 14, ny & 0xFFFF)
  return true
end

local function direct_now()
  if not S.pad or st.paused or st.player == 0 then return false end
  if riding() then return S.pad_direct_veh end
  if not st.pad_edit or st.combo then return false end
  if st.aiming then return S.pad_direct_aim end
  return S.pad_direct_hip
end

hook(A.PAD_READ, function(ctx)
  local user, addr = ctx:r(3) & 0xFF, ctx:r(5)
  ctx:call_original()
  if addr == 0 or ctx:r(3) ~= 0 or (user ~= 0 and user ~= 0xFF) then return end
  local b, lt, rt = wml.read_u16(addr + 4) or 0, wml.read_u8(addr + 6) or 0, wml.read_u8(addr + 7) or 0
  st.pad_buttons, st.pad_lt, st.pad_rt = b, lt, rt
  st.pad_lx, st.pad_ly = s16(wml.read_u16(addr + 8) or 0), s16(wml.read_u16(addr + 10) or 0)
  st.pad_rx, st.pad_ry = s16(wml.read_u16(addr + 12) or 0), s16(wml.read_u16(addr + 14) or 0)
  local nb, nlt, nrt, changed = b, lt, rt, false

  if st.pad_veh_edit then
    local va = S.pad_veh_aim
    if not st.veh_kb then
      if va.bit then nb = b & ~va.bit
      elseif va.trigger == "LT" and lt < S.veh_split then nlt = 0
      elseif va.trigger == "RT" and rt < S.veh_split then nrt = 0 end
    end
    if not (direct_now() and st.frames - st.turn_frame < 10)
       and shape_stick(addr, 1) then
      changed = true
    end
  elseif st.pad_edit then
    if S.pad and (st.pad_remap or st.pad_hold) then
      local aim = S.pad_aim
      if aim.bit then nb = nb & ~aim.bit end
      if aim.trigger == "RT" then nrt = 0 end
      if S.pad_aim_lt then
        local melee = st.pad_remap and ((not st.combo and S.pad_melee and (b & S.pad_melee.bit) ~= 0) or st.kb_melee)
        nlt = melee and 255 or 0
        if st.pad_remap and S.pad_melee then nb = nb & ~S.pad_melee.bit end
      end
    end
    if S.pad_walk and not st.walk_block and (b & GAME.wheel) == 0 and not any_key(FOOT_KEYS[S.pad_walk.name]) then
      nb = nb & ~S.pad_walk.bit
    end
    if TUNE.combo then
      if st.combo then nb = nb & ~(TUNE.mask | TUNE.combo.bit) end
      if st.combo_tap > 0 then nb = nb | TUNE.combo.bit end
    end
    if st.aiming then nb = nb & ~GAME.sprint end

    if S.slow_stick > 0 and st.walk_on and not st.sprint_held and (b & GAME.wheel) == 0 then
      local m = math.sqrt(st.pad_lx * st.pad_lx + st.pad_ly * st.pad_ly) / 32767
      if m > S.slow_stick then
        local f = S.slow_stick / m
        wml.write_u16(addr + 8, clamp(math.floor(st.pad_lx * f + 0.5), -32767, 32767) & 0xFFFF)
        wml.write_u16(addr + 10, clamp(math.floor(st.pad_ly * f + 0.5), -32767, 32767) & 0xFFFF)
        changed = true
      end
    end
    if S.pad and not (direct_now() and st.frames - st.turn_frame < 10)
       and shape_stick(addr, 1) then
      changed = true
    end
  else
    return
  end

  if nb ~= b then wml.write_u16(addr + 4, nb) changed = true end
  if nlt ~= lt then wml.write_u8(addr + 6, nlt) changed = true end
  if nrt ~= rt then wml.write_u8(addr + 7, nrt) changed = true end
  if changed then wml.write_u32(addr, ((wml.read_u32(addr) or 0) + 1) & 0xFFFFFFFF) end
end)

-- Hook: turning the camera with the controller
local function note_game_fov(f)
  FOV.now = f
  if not FOV.ref or f > FOV.ref then FOV.ref = f
  else FOV.ref = FOV.ref + (f - FOV.ref) * 0.0002 end
end
-- How much narrower a field of view is than another, on screen (degrees or radians).
local function fov_ratio(now, ref)
  local deg = ref > 3.2
  local function t(v) return math.tan(math.min(deg and math.rad(v) or v, 3.0) / 2) end
  return t(now) / t(ref)
end
local function zoom_scale()
  if not S.pad_zoom_scale or not (FOV.ref and FOV.now) or FOV.ref <= 0 then return 1.0 end
  local r = fov_ratio(FOV.now, FOV.ref)
  if not ok_num(r) or r >= 0.85 then return 1.0 end
  if r > 0.7 then return r + (1 - r) * (r - 0.7) / 0.15 end
  return clamp(r, 0.1, 1.0)
end
-- The game's look sensitivity (OPTIONS > CONTROLS, 1.0 = default)
local function game_sens(addr, use)
  if not use then return 1.0 end
  local v = wml.read_f32(addr)
  if not ok_num(v) or v < 0.05 or v > 10 then return 1.0 end
  return v
end
-- While the aim camera zooms in, the same turn moves the picture further. Turning slower
-- by the zoom keeps a mouse or stick movement moving the view as far as when not aiming.
local function aim_zoom()
  if not (S.zoom_match and st.fov_written and st.fov_last) or st.fov_base <= 0 then return 1.0 end
  local r = fov_ratio(st.fov_last, st.fov_base)
  if not ok_num(r) then return 1.0 end
  return clamp(r, 0.1, 1.0)
end
-- Turn speed while aiming, on foot or from a vehicle, compared with not aiming.
local function aim_scale()
  local b = riding() and st.vblend or st.blend
  return (1 + (S.aim_sens - 1) * clamp(b, 0, 1)) * aim_zoom()
end
local function raw_axis(code)
  if code == 0 then return st.pad_rx elseif code == 1 then return st.pad_ry elseif code == 2 then return st.pad_lx end
  return st.pad_ly
end

local function stick_turn(dt)
  local bx, by = GAME.look_x, GAME.look_y
  local x, y = raw_axis(bx.code) / 32767, raw_axis(by.code) / 32767
  if bx.neg then x = -x end
  if by.neg then y = -y end
  local m = math.sqrt(x * x + y * y)
  local t = 0.0
  st.turn_x, st.turn_y = 0.0, 0.0
  if m > S.pad_dz then
    t = math.min(1, (m - S.pad_dz) / math.max(0.05, 1 - S.pad_dz - S.pad_outer_dz))
    local mag = t ^ S.pad_curve
    st.turn_x, st.turn_y = x / m * mag, y / m * mag
  end
  local b = clamp(st.blend, 0, 1)
  local a = aim_scale()
  local sx = (S.pad_hip_x + (S.pad_aim_x - S.pad_hip_x) * b) * game_sens(A.LOOK_SPEED_X, S.pad_game_sens) * a
  local sy = (S.pad_hip_y + (S.pad_aim_y - S.pad_hip_y) * b) * game_sens(A.LOOK_SPEED_Y, S.pad_game_sens) * a
  local boost = S.pad_boost + (S.pad_boost_aim - S.pad_boost) * b
  if boost > 0 and t > 0.95 and math.abs(st.turn_x) > 0.7 then st.edge_time = st.edge_time + dt else st.edge_time = 0 end
  local ramp = clamp((st.edge_time - 0.15) / S.pad_boost_time, 0, 1)
  sx = sx * (1 + boost * ramp * ramp * (3 - 2 * ramp))
  if st.blend <= 0 and not riding() then
    local z = zoom_scale()
    sx, sy = sx * z, sy * z
  end
  local inv = wml.read_u8(A.INVERT) or 0
  if (inv & 0x40) ~= 0 then sx = -sx end
  if (inv & 0x20) ~= 0 then sy = -sy end
  return st.turn_x * sx, st.turn_y * sy
end

-- While he faces the aim, the look timer stops the camera swinging round behind the way
-- he walks (strafing would otherwise turn it, and him with it).
local LOOK_HOLD_MS = 300
local function hold_look_timer()
  if st.face_on and not st.in_veh and not st.seated and not st.paused
     and (wml.read_u32(A.CAMERA_MODE) or 0) ~= 0xC then
    local t = clock_now() + LOOK_HOLD_MS
    if t >= 1800000000 then t = t - 1800000000 end
    wml.write_u32(A.CAM_LOOK_TIMER, t)
    st.look_until = t
  end
end

-- While the look timer runs (the mouse and stick start it too), the camera step adds every
-- turn of his body since its last step to the camera. While aiming his body turns after the
-- camera, so the camera chased his body and his body the camera: a spin that sped up every
-- frame. Telling the step he has not turned keeps the camera on the mouse and stick alone.
local function pin_body_heading()
  local p = st.player
  if p == 0 or st.paused or riding() then return end
  if not (st.aiming or st.blend > 0 or st.face_on or clock_now() < st.look_until) then return end
  local yaw = facing_of(p)
  if yaw then wml.write_f32(A.BODY_YAW, yaw) end
end

-- Mouse sensitivity, on foot and in vehicles: the game's look sensitivity and aim_sensitivity.
-- The port turns the camera by the mouse inside the camera step. Left / right: the extra
-- turn goes in through wml.turn_camera, which the port adds to the mouse turn of this very
-- step, so it takes exactly the mouse's path. Up / down: as an extra turn speed in the
-- step's pitch tracking input, which the step adds to the look input.
local STICK_LOOK = 0.24 * 32767   -- where the port counts the right stick into mouse_look
local function mouse_extra(dt)
  if type(wml.mouse_look) ~= "function" or type(wml.turn_camera) ~= "function" then return 0, 0, false end
  local my, mp = wml.mouse_look()   -- read every step, so it holds just this step's mouse
  if not (ok_num(my) and ok_num(mp)) or (my == 0 and mp == 0) then return 0, 0, false end
  if st.player == 0 or st.paused or not (dt > 0.0001 and dt < 0.5)
     or math.abs(st.pad_rx) > STICK_LOOK or math.abs(st.pad_ry) > STICK_LOOK then
    return 0, 0, true
  end
  local a = aim_scale()
  local sx = game_sens(A.LOOK_SPEED_X, S.mouse_game_sens) * a
  local sy = game_sens(A.LOOK_SPEED_Y, S.mouse_game_sens) * a
  -- The port caps the turn speed in vehicles at 6 radians per second (also the extra yaw).
  local rp = mp / dt
  if riding() then rp = clamp(rp, -6, 6) end
  return my * (sx - 1), rp * (sy - 1), true
end
local function add_f32(addr, v)
  local old = wml.read_f32(addr)
  wml.write_f32(addr, (ok_num(old) and old or 0) + v)
end

local DIRECT = S.pad and (S.pad_direct_aim or S.pad_direct_hip or S.pad_direct_veh)
hook(A.CAMERA_TURN, function(ctx)
  hold_look_timer()
  pin_body_heading()
  st.turn_frame = st.frames
  local dt = ctx:f(1)
  local ex, ey, mouse = mouse_extra(dt)
  if not DIRECT or not direct_now() or not (dt > 0.0001 and dt < 0.5) then
    st.turn_x, st.turn_y = 0.0, 0.0
    if st.direct_was then
      -- in vehicles the game keeps the turn inputs between steps: drop the mod's last one
      st.direct_was = false
      for _, addr in ipairs({ A.TURN_YAW, A.TURN_YAW2, A.TURN_PITCH }) do wml.write_f32(addr, 0.0) end
    end
    if ex ~= 0 or ey ~= 0 then
      if ex ~= 0 then wml.turn_camera(ex) end
      add_f32(A.TRACK_PITCH, ey)
    elseif not mouse and not st.paused and aim_scale() ~= 1 then
      -- the game's own stick turn
      local a = aim_scale()
      for _, addr in ipairs({ A.TURN_YAW, A.TURN_YAW2, A.TURN_PITCH }) do
        local v = wml.read_f32(addr)
        if ok_num(v) then wml.write_f32(addr, v * a) end
      end
    end
    ctx:call_original()
    return
  end

  -- The mod turns the camera from the right stick: slow pan at 1:1, no fast-pan acceleration.
  st.direct_was = true
  local yaw, pitch = stick_turn(dt)
  if st.wheel then yaw, pitch, st.turn_x, st.turn_y = 0.0, 0.0, 0.0, 0.0 end
  local sh, sv, th = wml.read_f32(A.SLOW_PAN_H), wml.read_f32(A.SLOW_PAN_V), wml.read_f32(A.FAST_PAN)
  wml.write_f32(A.SLOW_PAN_H, 1.0)
  wml.write_f32(A.SLOW_PAN_V, 1.0)
  wml.write_f32(A.FAST_PAN, 1.0e6)
  wml.write_f32(A.TURN_YAW, yaw)
  wml.write_f32(A.TURN_YAW2, 0.0)
  wml.write_f32(A.TURN_PITCH, pitch)
  -- on foot the game's target tracking is off; in vehicles it keeps the camera behind the car
  if not riding() then wml.write_f32(A.TRACK_YAW, 0.0) end
  if ex ~= 0 then wml.turn_camera(ex) end
  if ey ~= 0 then add_f32(A.TRACK_PITCH, ey) end
  ctx:call_original()
  wml.write_f32(A.SLOW_PAN_H, sh)
  wml.write_f32(A.SLOW_PAN_V, sv)
  wml.write_f32(A.FAST_PAN, th)
end)
if DIRECT then
  hook(A.ASSIST_FN, function(ctx)
    if direct_now() and not riding() then wml.write_f32(A.TRACK_YAW, 0.0) return end
    ctx:call_original()
  end)
end

-- Hooks: the aim mode flag, his facing, the cone, the crosshair
local function shield(ctx, reg)
  if st.fp_ours and ctx:r(reg) ~= st.player then
    wml.write_u8(A.FP_FLAG, 0)
    ctx:call_original()
    wml.write_u8(A.FP_FLAG, 1)
  else
    ctx:call_original()
  end
end

local function hold_face()
  local p = st.player
  if p == 0 or not st.face_on or st.face_yaw == nil or facing_of(p) == nil then return end
  set_facing(p, st.face_yaw)
end

hook(A.MOVE_FN, function(ctx)
  local mine = ctx:r(3) == st.player
  if mine then hold_look_timer() end
  shield(ctx, 3)
  if mine then hold_face() end
end)
hook(A.LOCO_FN, function(ctx)
  local mine = ctx:r(3) == st.player
  if mine then hold_look_timer() end
  shield(ctx, 3)
  if mine then hold_face() end
end)
hook(A.POSE_FN, function(ctx) shield(ctx, 3) end)

hook(A.SPREAD_FN, function(ctx)
  local mine, a, b = ctx:r(7) == st.player, ctx:r(3), ctx:r(4)
  shield(ctx, 7)
  local eq = st.equipped or (st.seated and st.last_gun) or nil
  if mine and S.cone_model and a ~= 0 and b ~= 0 and eq then
    local e = W.by_name[eq]
    if e and e.cone then
      local m = cone_mult(st.aiming or st.veh_aim)
      wml.write_f32(a, e.min * m)
      wml.write_f32(b, e.max * m)
    end
  end
end)

hook(A.DRAW_BITMAP, function(ctx)
  if st.ret_now ~= 1 and st.ret_set[ctx:r(3)] then ctx:set_f(4, ctx:f(4) * st.ret_now) end
  ctx:call_original()
end)

-- Hooks: precise aim animations
local POOL = { SIZE = 0xA30, COUNT = 4, START = 0x368, NO = 0xFFFF }
local function group_slot(g) return A.POOL_GROUPS + g * POOL.SIZE end
local SWAP = { list = nil, on = false, retry_at = 0 }

local function scan_swap()
  if wml.read_u32(group_slot(2)) ~= A.POOL_GROUPS then return nil, "animation tables not loaded yet" end
  local list, sn = {}, group_slot(G_SNIPER)
  for _, g in ipairs({ G_AK, G_SHOTGUN }) do
    local gs = group_slot(g)
    for _, id in ipairs({ ST.WALK_L, ST.WALK_R, ST.WALK_B }) do
      local gc, sc = wml.read_u8(gs + POOL.COUNT + id) or 0, wml.read_u8(sn + POOL.COUNT + id) or 0
      local gst, sst = wml.read_u16(gs + POOL.START + id * 2), wml.read_u16(sn + POOL.START + id * 2)
      if gc > 0 and sc > 0 and gst ~= POOL.NO and sst ~= POOL.NO then
        for i = 0, gc - 1 do
          local set = wml.read_u32(A.POOL_SETS + (gst + i) * 4)
          for j = 0, sc - 1 do
            if wml.read_u32(A.POOL_SETS + (sst + j) * 4) == set then
              local idx = gst + i
              list[#list + 1] = { idx = idx, vanilla = wml.read_u32(A.POOL_VALUES + idx * 4),
                                  sniper = wml.read_u32(A.POOL_VALUES + (sst + j) * 4) }
              break
            end
          end
        end
      end
    end
  end
  if #list == 0 then return nil, "no matching animation entries" end
  local backup, by = FOLDER .. "/pool_backup.txt", {}
  for idx, v in (read_file(backup) or ""):gmatch("(%d+)=(%d+)") do by[tonumber(idx)] = tonumber(v) end
  local t = {}
  for _, e in ipairs(list) do
    if e.vanilla == e.sniper and by[e.idx] then e.vanilla = by[e.idx] end
    t[#t + 1] = e.idx .. "=" .. e.vanilla
  end
  write_file(backup, table.concat(t, "\n") .. "\n")
  return list
end

set_swap = function(want)
  if want == SWAP.on and SWAP.list then return end
  if not SWAP.list then
    if st.frames < SWAP.retry_at then return end
    local list = scan_swap()
    if not list then
      SWAP.retry_at = st.frames + 120
        return
    end
    SWAP.list = list
  end
  for _, e in ipairs(SWAP.list) do wml.write_u32(A.POOL_VALUES + e.idx * 4, want and e.sniper or e.vanilla) end
  SWAP.on = want
end

hook(A.ANIM_PICK, function(ctx)
  if st.precise and st.player ~= 0 and ctx:r(3) == st.player then ctx:set_r(5, ctx:r(5) | 0x10010) end
  ctx:call_original()
end)

local PRECISE_STILL = {}
for id = 0x00, 0x03 do PRECISE_STILL[id] = ST.STAND_SHLDR end
for id = 0x3E, 0x40 do PRECISE_STILL[id] = ST.STAND_SHLDR end
for id = 0x1A, 0x2B do PRECISE_STILL[id] = ST.WALK_SHLDR end
for id = 0x2D, 0x32 do PRECISE_STILL[id] = ST.WALK_SHLDR end
PRECISE_STILL[0x47], PRECISE_STILL[0x4E] = ST.WALK_SHLDR, ST.WALK_SHLDR
for _, id in ipairs({ 0x44, 0x48, 0x4B, 0x4F, 0x52, 0x55, 0x58, 0x5B }) do PRECISE_STILL[id] = ST.WALK_L end
for _, id in ipairs({ 0x45, 0x49, 0x4C, 0x50, 0x53, 0x56, 0x59, 0x5C }) do PRECISE_STILL[id] = ST.WALK_R end
for _, id in ipairs({ 0x46, 0x4A, 0x4D, 0x51, 0x54, 0x57, 0x5A, 0x5D }) do PRECISE_STILL[id] = ST.WALK_B end
local DIR_STATE = { f = ST.WALK_SHLDR, r = ST.WALK_R, l = ST.WALK_L, b = ST.WALK_B }
local DIR_ANGLE = { f = 0, r = 90, b = 180, l = -90 }

local function precise_direction(clock)
  local a = math.deg(math.atan(st.mv_x, st.mv_y))
  local function off(d) return math.abs((a - DIR_ANGLE[d] + 540) % 360 - 180) end
  local cur, best = st.pdir, "f"
  if st.still then return cur or "f" end   -- between keys: keep walking the way he was
  for _, d in ipairs({ "r", "b", "l" }) do if off(d) < off(best) then best = d end end
  if cur and cur ~= best and (off(cur) < 45 + S.dir_margin or clock - st.pdir_t < S.dir_hold_ms) then
    best = cur
  end
  if best ~= cur then st.pdir_t = clock end
  local prev = cur or ((clock - st.plast_t < 500) and st.plast or nil)
  if best ~= "f" and prev and prev ~= "f" and prev ~= best and st.pvia_to ~= best then
    st.pvia_to, st.pvia_until = best, clock + S.via_ms
  end
  st.pdir = best
  if best ~= "f" then st.plast, st.plast_t = best, clock end
  if st.pvia_to == best and clock < st.pvia_until then return "f" end
  st.pvia_to = nil
  return best
end

hook(A.ANIM_CHOOSE, function(ctx)
  local mine = st.player ~= 0 and ctx:r(5) == st.player
  ctx:call_original()
  if not (mine and st.precise) or st.crouched then return end
  local id = ctx:r(3) & 0xFFFFFFFF
  if st.anim_still then
    local to = PRECISE_STILL[id]
    if to then ctx:set_r(3, to) end
  elseif id ~= 0x04 and id ~= 0x05 and not (id >= 0x33 and id <= 0x38) and not (id >= 0x5E and id <= 0x65) then
    ctx:set_r(3, DIR_STATE[precise_direction(st.clock)])
  end
end)

local function strafe_id(v) v = v & 0xFFFFFFFF return v >= ST.WALK_L and v <= ST.WALK_B end
hook(A.ANIM_BLEND, function(ctx)
  local mine = st.player ~= 0 and ctx:r(3) == st.player
  local strafe = false
  if mine and st.precise then
    for _, r in ipairs({ 6, 7, 8, 10 }) do
      if strafe_id(ctx:r(r)) then strafe = true end
    end
  end
  ctx:call_original()
  if strafe then
    -- at least strafe_blend; a longer blend the game picked stays
    local f = ctx:f(1)
    if not (type(f) == "number" and f >= S.side_blend and f < 2) then ctx:set_f(1, S.side_blend) end
  elseif mine and st.blend_next then
    if st.clock <= st.blend_next_until then
      local f = ctx:f(1)
      if not (type(f) == "number" and f >= st.blend_next) then ctx:set_f(1, st.blend_next) end
    else
      st.blend_next = nil
    end
  end
end)

hook(A.PLAY_ACTION, function(ctx)
  if st.blend_next and st.player ~= 0 and ctx:r(3) == st.player and st.clock <= st.blend_next_until then
    local f3 = ctx:f(3)
    if not (type(f3) == "number" and f3 >= st.blend_next) then ctx:set_f(3, st.blend_next) end
  end
  ctx:call_original()
end)

local function skip_turns(ctx)
  if st.precise and st.player ~= 0 and ctx:r(3) == st.player then ctx:set_r(3, 0) return end
  ctx:call_original()
end
hook(A.PLAY_TURN, skip_turns)
hook(A.PLAY_TRANS, skip_turns)

-- Hook: the camera (placement, field of view) and his facing
local ORBIT_DIST, ORBIT_UP, PITCH_MAX, HALF_PI = 1.85, 0.15, 0.9414778, math.pi / 2
local PIVOT_H, AIM_LIFT, HEIGHT_RATE = 1.4, 0.1, 0.8

local function orbit_target(px, py, pz, ux, uy, uz)
  local rx, ry, rz = read_vec(A.CAM_RIGHT)
  local vx, vy, vz = read_vec(A.CAM_UP)
  local fx, fy, fz = read_vec(A.CAM_FWD)
  local pitch = clamp(math.asin(clamp(-fy, -1, 1)), -PITCH_MAX, PITCH_MAX)
  local back, up = ORBIT_DIST, ORBIT_UP
  if pitch < 0 then
    local t = (pitch + HALF_PI) / HALF_PI - 1
    back = back + 0.4 * t * t * t
  elseif pitch > 0 then
    local t = (HALF_PI - pitch) / HALF_PI - 1
    up = up + 0.18 * t * t
  end
  back = back * 2 ^ (PR.zoom / 2)
  local eye = PR.height - ORBIT_UP - st.crouch_now
  local ex, ey, ez = px + ux * eye, py + uy * eye, pz + uz * eye
  local sh = PR.shoulder
  return ex + rx * sh + vx * up - fx * back, ey + ry * sh + vy * up - fy * back, ez + rz * sh + vz * up - fz * back
end

local function place_camera(p, blend)
  local px, py, pz = read_vec(p + P_POS)
  local ux, uy, uz = read_vec(p + P_UP)
  if not (uy > 0.5 and uy < 1.5) then ux, uy, uz = 0, 1, 0 end
  local ox, oy, oz = px + ux * PIVOT_H, py + uy * PIVOT_H, pz + uz * PIVOT_H
  local cx, cy, cz = read_vec(A.CAM_POS)
  local dx, dy, dz = cx - ox, cy - oy, cz - oz
  if dx * dx + dy * dy + dz * dz >= 1600 then return end
  local nx, ny, nz
  if PR.style == "orbit" then
    local tx, ty, tz = orbit_target(px, py, pz, ux, uy, uz)
    nx, ny, nz = cx + (tx - cx) * blend, cy + (ty - cy) * blend, cz + (tz - cz) * blend
  else
    local f, sx = 2 ^ (PR.zoom * blend / 2), PR.shoulder * blend
    local rx, _, rz = read_vec(A.CAM_RIGHT)
    nx, nz = ox + dx * f + rx * sx, oz + dz * f + rz * sx
    local want_y = py + uy * (PR.height - st.crouch_now) + AIM_LIFT
    ny = cy + (want_y - cy) * math.min(1.0, blend * HEIGHT_RATE)
  end
  write_vec(A.CAM_POS, nx, ny, nz)
  local sp, w = st.saved_pos, st.written_pos
  sp[1], sp[2], sp[3], w[1], w[2], w[3] = cx, cy, cz, nx, ny, nz
  st.cam_saved = true
end

-- His body follows the aim. The camera step ignores these turns (pin_body_heading), so the
-- camera itself only moves with the mouse or stick.
local function update_facing(p, dt)
  local want = camera_yaw()
  local have = p ~= 0 and facing_of(p) or nil
  local lock = S.face_aim and (st.precise or (st.still and (st.throw_aim or st.melee_aim)))
  if lock and want and have then
    if st.face_yaw == nil then st.face_yaw = have end
    local diff = wrap_pi(want - st.face_yaw)
    local step = S.face_speed * dt
    local turn = clamp(diff * math.min(1, 25 * dt), -step, step)
    if math.abs(diff) < 0.01 then turn = diff end
    st.face_yaw = wrap_pi(st.face_yaw + turn)
    set_facing(p, st.face_yaw)
    st.face_on = true
    return
  end
  st.face_yaw, st.face_on = nil, false
  if S.face_aim and st.aiming and st.blend > 0 and want and have and S.aim_body_max < 180 then
    local lim = math.rad(S.aim_body_max)
    local d = wrap_pi(have - want)
    if math.abs(d) > lim then set_facing(p, want + (d > 0 and lim or -lim)) end
  end
end

hook(A.CAMERA_UPDATE, function(ctx)
  hold_look_timer()
  if st.cam_saved then
    local x, y, z = read_vec(A.CAM_POS)
    local w, sp = st.written_pos, st.saved_pos
    if math.abs(x - w[1]) + math.abs(y - w[2]) + math.abs(z - w[3]) < 0.5 then write_vec(A.CAM_POS, sp[1], sp[2], sp[3]) end
    st.cam_saved = false
  end
  if st.fov_written and st.fov_last then
    local f = wml.read_f32(A.CAM_FOV)
    if ok_num(f) and math.abs(f - st.fov_last) < 1e-4 then wml.write_f32(A.CAM_FOV, st.fov_base) end
  end

  ctx:call_original()

  local fov = wml.read_f32(A.CAM_FOV)
  if ok_num(fov) and fov > 0 then
    st.fov_base = fov
    if not riding() then note_game_fov(fov) end
  end

  local p = st.player
  local active = st.blend > 0 and not st.paused and not st.in_veh and not st.seated
  if active and p ~= 0 then place_camera(p, st.blend) end

  local fclock = clock_now()
  local fdt = st.face_clock and clamp((fclock - st.face_clock) / 1000, 0, 0.1) or 0
  st.face_clock = fclock
  update_facing(p, fdt)

  local vb = (not st.paused) and st.vblend or 0
  if active or vb > 0 then
    local f = active and (1 - st.blend * (1 - PR.fov)) or (1 - vb * (1 - S.vehicle_fov))
    st.fov_last = st.fov_base * f
    wml.write_f32(A.CAM_FOV, st.fov_last)
    st.fov_written = true
  elseif st.fov_written then
    wml.write_f32(A.CAM_FOV, st.fov_base)
    st.fov_written = false
  end
end)

-- Edits to mod.ini apply while the game runs
if type(wml.on_settings_changed) == "function" and type(wml.reload_lua_mod) == "function" then
  wml.on_settings_changed(function() wml.reload_lua_mod(wml.mod_name) end)
end

wml.log("Precise Aim 1.0 ready")

-- ---------------------------------------------------------------- SR Tweak Menu
-- Added for SR Tweak Menu (not part of Precise Aim). The menu switches the mod on
-- and off: while off, every hook here runs only the game's code (addons.lua), and
-- release() first puts back what the mod changes in the game. The menu's aim rows
-- tunes the camera through the functions below instead of the tuning keys.
if type(wml.srtm) == "table" then
  local M = wml.srtm
  function M.release()
    st.aiming, st.throw_aim, st.melee_aim, st.precise, st.raise = false, false, false, false, false
    st.aim_tog, st.aim_input, st.aim_latch, st.veh_tog, st.veh_aim = false, false, false, false, false
    st.blend, st.vblend, st.face_on, st.face_yaw, st.blend_next = 0, 0, false, nil, nil
    if st.fov_written then wml.write_f32(A.CAM_FOV, st.fov_base) st.fov_written = false end
    if st.cam_saved then
      local x, y, z = read_vec(A.CAM_POS)
      local w, sp = st.written_pos, st.saved_pos
      if math.abs(x - w[1]) + math.abs(y - w[2]) + math.abs(z - w[3]) < 0.5 then write_vec(A.CAM_POS, sp[1], sp[2], sp[3]) end
      st.cam_saved = false
    end
    pcall(set_swap, false)
    if st.fp_ours then
      if (wml.read_u8(A.FP_CONSOLE) or 0) == 0 then wml.write_u8(A.FP_FLAG, 0) end
      st.fp_ours = false
    end
    if st.shift_taken then wml.take_key("SHIFT", false) st.shift_taken = false end
    wml.take_key(RMB, false) wml.force_key(RMB, false)
    if st.veh_held and st.player ~= 0 then wml.write_u32(st.player + P_EXPIRY, 0) st.veh_held = false end
    st.ret_now, st.last_clock, st.face_clock = 1.0, nil, nil
    if CFG.dirty then save_cfg() end
  end
  -- The gun is lowered through the frame hook, so it keeps running until it is.
  function M.must(addr) return addr == A.FRAME_FN and st.armed end
  function M.presets() return PR.order end
  function M.preset() return PR.name end
  function M.limits() return LIM end
  function M.get(field) return PR[field] end
  function M.apply(name)
    if not apply_preset(name) then return false end
    save_cfg()
    return true
  end
  function M.set(field, value)
    local l = LIM[field]
    if not l then return end
    PR[field] = clamp(value, l[1], l[2])
    save_cfg()
  end
  function M.save_custom()
    save_custom()
    save_cfg()
    return PR.name, PR.note
  end
  -- The menu's Aim button row: true = toggle, false = hold, nil = this file's setting.
  local own_toggle = S.aim_toggle
  function M.set_toggle(on)
    if on == nil then on = own_toggle end
    S.aim_toggle = on
    st.aim_tog, st.veh_tog = false, false
  end
  function M.toggle() return S.aim_toggle end
  -- The menu's turning rows: the game's own turning, or this mod's (its own
  -- right-stick curve, and the game's look sensitivity on the mouse too); and
  -- the turn speed while aiming (aim_sensitivity).
  local own_turning = { S.pad_direct_hip, S.pad_direct_aim, S.pad_direct_veh, S.mouse_game_sens }
  function M.set_turning(game_own)
    if game_own then
      S.pad_direct_hip, S.pad_direct_aim, S.pad_direct_veh, S.mouse_game_sens = false, false, false, false
    else
      S.pad_direct_hip, S.pad_direct_aim, S.pad_direct_veh, S.mouse_game_sens = own_turning[1], own_turning[2], own_turning[3], own_turning[4]
    end
  end
  function M.aim_sens() return S.aim_sens end
  function M.set_aim_sens(v) S.aim_sens = clamp(v, 0.1, 3.0) end
end
