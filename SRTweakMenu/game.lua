-- SR Tweak Menu - game access layer.
--
-- Everything that touches the game lives here: addresses, the calling
-- convention for game functions from inside the update hook, the two big
-- levers (the game's own Lua 5.0 state and its debug console), and the usual
-- player / vehicle lookups. Features and the menu build on this and never
-- hold an address of their own.
--
-- All addresses are Xbox 360 guest addresses found in the recompiled game
-- code on the author's machine. Confidence is noted where it is not certain.

local G = {}

-- ------------------------------------------------------------ addresses
G.PLAYER      = 0x8309ABEC  -- pointer to the player object (0 = no game loaded)
G.OBJECTS     = 0x830866C8  -- handle table, 16 bytes per entry
G.UPDATE      = 0x82209E30  -- game update, ~50 Hz, main thread (every mod hooks it)
G.MULTIPLAYER = 0x8370E9F6  -- byte: a multiplayer session is active
G.CUTSCENE_A, G.CUTSCENE_B = 0x8370D991, 0x8370D990
G.MENU_A, G.MENU_B = 0x839E0DF8, 0x839E0FB0  -- a screen (pause menu, map ...) is up
G.FRONT_END   = 0x827B04D4  -- 0 in play, -1 in the front end, 1 in the character creator
G.CAMERA      = 0x827D9778  -- +80 right row, +104 forward row (3 floats each)

G.HUD_MESSAGE   = 0x82367568  -- (UTF-16 text*, f1 = seconds): the script function message()
G.LUA_STATE     = 0x8370F8C4  -- the game's own lua_State* (Lua 5.0)
G.LUA_DOSTRING  = 0x824F1C70  -- (L, const char*) -> 0 on success
G.CONSOLE       = 0x82626AD8  -- (const char* line) -> 0 ok / -1 error: the debug console
G.INPUT_GET_STATE = 0x82788EC4  -- XamInputGetState(user, flags, XINPUT_STATE*)
G.TAKE_DAMAGE   = 0x824470D0  -- (victim, attacker, ..., f1 = damage); every damage path ends here

-- Player object fields.
G.P = {
  POS = 20, TYPE = 72, DIRTY = 212, FLAGS = 216, NAV_NODE = 392, FALL_START = 404,
  CONTROLLER = 476, STATE = 508, HEALTH_MAX = 1908, HEALTH = 1912, CASH = 2320,
  VEHICLE = 2496, VEHICLE_BYTE = 2569, NOT_DRIVING = 3456, EQUIPPED = 3548,
  RESPECT = 3848, RESPECT_BAR = 3860, NOTORIETY = 3868,
}
-- Bits in the flags word at +216.
G.FLAG = { INVULNERABLE = 0x00100000, PERFECT_AIM = 0x00200000, NO_RAGDOLL = 0x00800000, NO_FLINCH = 0x40 }
-- Bits in the word at +212 (bit 1 is the game's dirty flag).
G.FLAG212 = { NO_EXPLOSION_FLING = 2, NO_KNEECAP = 4 }

-- Notoriety: 24 bytes per gang at player+3868: +0 level, +4 min, +8 max, +12 points.
G.GANG = { carnales = 0, vice_kings = 1, rollerz = 2, players = 3, police = 4 }
G.NOTORIETY_SET = 0x821D2F50  -- (player+3868, gang, f1 = level)
G.NOTORIETY_MAX = 0x821D3070  -- (player+3868, gang, max)

-- Vehicle object fields.
G.V = {
  ENGINE = 224, ENGINE_OK = 50300, HP_MAX = 53508, HP = 53512, EXPLOSION_MOD = 53540,
  FLAGS_A = 53976, FLAGS_B = 53980,
}
G.VFLAG_A = { NO_EXPLOSION_FLING = 0x00010000, INVULNERABLE = 0x00020000 }
G.VFLAG_B = { INFINITE_MASS = 0x00080000, NEVER_FLAT = 0x00100000, BULLETPROOF_GLASS = 0x02000000 }
-- Engine object fields (engine = *(vehicle+224)). The game's engine update
-- (0x825839B8) multiplies the nitrous force at +384 by +396 while nitrous is
-- on (+380 == 1), and its speed cap (0x8253DE30) adds +400 (m/s) to the
-- model's top speed only while bit 0x40 of the byte at +440 is set.
G.ENGINE = { NITRO_STRENGTH = 396, EXTRA_TOP_SPEED = 400, FLAGS = 440 }
G.ENGINE_FLAG_EXTRA_SPEED = 0x40
G.MPH_TO_MS = 0.44704
G.VEHICLE_REPAIR = 0x82536F30  -- (vehicle, f1 = fraction)
G.VEHICLE_NITRO  = 0x8253FE38  -- (vehicle, bool)
G.VEHICLE_INDEX  = 0x8256A638  -- (name) -> vehicle info index, or -1
G.GARAGE_DROP_STATE, G.GARAGE_DROP_INDEX = 0x827E5E44, 0x827E5E48  -- the vehicle cheat's delivery queue
G.LETTERBOX      = 0x8229AB20  -- (bool)

-- Teleporting (the Teleport to Waypoint mod's sequence).
G.STREAM_AT       = 0x82510520  -- (pos*, 0, 0): load the world around a spot first
G.PLAYER_TELEPORT = 0x82481000  -- (player, pos*, rows*): the script teleport; car and homies come along

-- People (the co-op mod creates its players' copies this way).
G.MODEL_LOOKUP   = 0x82114928  -- (name, 0) -> character definition, 0 if unknown
G.NUDGE_SPOT     = 0x824C2CF8  -- (pos*): moves a spawn point off anyone standing there
G.HUMAN_CREATE   = 0x82479AB0  -- (kind, 2, def, pos*, rows*, 255, 0, 0) + stack {+84 u32 0, +94 u16 8, +103 u8 0} -> object
G.STREAM_REF     = 0x8250C750  -- (0x83E876B0 + (id>>24)*204, id, 5, 0, 1): keep a model loaded
G.STREAM_TABLE   = 0x83E876B0
G.HUMAN_DEF      = 228         -- object+228 = definition; definition+608 = model id

-- Vehicles made in the world (the co-op mod creates cars this way).
G.VEHICLE_CREATE = 0x82569700  -- (3, 2, info index, pos*, rows*, 0, 0, 0, f1 = 0) + stack {+84 u32 0, +95 u8 0, +100 u32 0} -> handle
G.VEHICLE_FROM_HANDLE = 0x82569630  -- (handle) -> vehicle object
G.VEHICLE_PLACE  = 0x82535C68  -- (vehicle, pos*, rows*, 0)
G.VEHICLE_INFO_TABLE, G.VEHICLE_INFO_SIZE = 0x83E8ABD8, 1196  -- first word of an entry = model id
G.OBJECT_DESTROY = 0x823ACF50  -- (handle): removes a car or person the mod made
G.RELOAD         = 0x82474AB0  -- (human): starts a reload of the equipped gun
G.POLICE_TEAM    = 0x828316F0  -- team object; byte +645 = no notoriety spawns

-- Spawn density (how many cars / people the game wants around the player).
G.TRAFFIC_WANTED = 0x824194A8  -- () -> number of traffic cars wanted
G.PEDS_WANTED    = 0x82419208  -- () -> number of ambient people wanted
G.PEDS_COUNT     = 0x8240DB70  -- () -> number of ambient people now
G.TRAFFIC_MAX    = 0x8208978C  -- float: cars wanted at density 1.0
G.PEDS_MAX       = 0x82089998  -- float: people wanted at density 1.0
G.AMBIENT_PED_LIMIT = 26       -- compiled into the game
G.TRAFFIC_TRIM     = 0x82411E30  -- () removes the furthest traffic car when over 12; r3 = removed
G.SAME_MODEL_COUNT = 0x82413AD8  -- () -> cars of one model on the road (the spawner allows 3)
G.TRAFFIC_COUNT    = 0x8309A1C0  -- int: traffic cars now

-- Globals the game reads every frame (debug console variables).
G.VAR = {
  UNLIMITED_AMMO = 0x8370F86A,  -- byte
  ALLOW_COPS = 0x827AD06C,      -- byte
  ALLOW_GANGS = 0x827AD06D,     -- byte
  ALLOW_BUST = 0x827D95C5,      -- byte
  TRAFFIC_DENSITY = 0x827AD060, -- float 0..1
  PED_DENSITY = 0x827AD064,     -- float 0..1
  JUMP_HEIGHT = 0x827D099C,     -- float, 0.85
  SWIM_SPEED = 0x827ACF34,      -- float, 4.5
  FALL_DAMAGE = 0x827ACE58,     -- float, 0.2
  CHAR_GRAVITY = 0x827D0988,    -- float, 1.5
  SATURATION = 0x827D6C0C,      -- float, 1.0
  CLOCK_RATE = 0x82B2EF40,      -- float, 40 (0 freezes the day/night clock)
  CLOCK_HOUR = 0x82B2EF34,      -- byte
  CLOCK_MINUTE = 0x82B2EF35,    -- byte
  CHEAT_FLAGS = 0x82B2E0A8,     -- word; 0x02000000 = infinite sprint (cheat #), 0x04000000 = infinite ammo
}

-- ------------------------------------------------------------ helpers
local read_u8, read_u16, read_u32, read_f32 = wml.read_u8, wml.read_u16, wml.read_u32, wml.read_f32
local write_u8, write_u16, write_u32, write_f32 = wml.write_u8, wml.write_u16, wml.write_u32, wml.write_f32

function G.pointer_ok(v) return v >= 0x10000 and v < 0xC0000000 end
function G.vec(a) return read_f32(a), read_f32(a + 4), read_f32(a + 8) end

function G.set_bits(addr, mask, on)
  local v = read_u32(addr)
  if on then v = v | mask else v = v & ~mask & 0xFFFFFFFF end
  write_u32(addr, v)
end
function G.has_bits(addr, mask) return (read_u32(addr) & mask) ~= 0 end

-- Player flags carry the game's dirty bit so the change is noticed.
function G.player_flag(p, mask, on)
  G.set_bits(p + G.P.FLAGS, mask, on)
  write_u32(p + G.P.DIRTY, read_u32(p + G.P.DIRTY) | 1)
end

-- The player object, or 0 when no single-player game is loaded.
function G.player()
  local p = read_u32(G.PLAYER)
  if p == 0 or not G.pointer_ok(p) or read_u32(p + G.P.TYPE) ~= 1 then return 0 end
  if read_u8(G.MULTIPLAYER) ~= 0 then return 0 end
  return p
end

function G.in_cutscene()
  return read_u8(G.CUTSCENE_A) ~= 0 or read_u8(G.CUTSCENE_B) ~= 0
end
function G.screen_up()
  return read_u32(G.MENU_A) ~= 0 or read_u32(G.MENU_B) ~= 0
end
function G.in_front_end() return read_u32(G.FRONT_END) ~= 0 end

-- The vehicle the player sits in (object, handle), or nil. The same test
-- the keyboard controls use.
function G.vehicle_object(p)
  if read_u32(p + G.P.NOT_DRIVING) ~= 0 then return nil end
  local handle = read_u32(p + G.P.VEHICLE)
  if handle == 0 or (read_u8(p + G.P.VEHICLE_BYTE) & 0x10) ~= 0 then return nil end
  local state = read_u32(p + G.P.STATE)
  if state == 9 or state == 12 then return nil end
  local index = handle & 0xFFFF
  if index >= 4096 then return nil end
  local object = read_u32(G.OBJECTS + 12 + index * 16)
  if object ~= 0 and read_u32(object + 68) == handle and read_u32(object + 72) == 5 then return object, handle end
  return nil
end

-- True while the handle still names that vehicle object.
function G.vehicle_alive(object, handle)
  local still = read_u32(G.OBJECTS + 12 + (handle & 0xFFFF) * 16)
  return still == object and read_u32(still + 68) == handle
end

-- The engine object of a vehicle (torque multiplier, max speed), or nil.
function G.engine_object(vehicle)
  if read_u8(vehicle + G.V.ENGINE_OK) ~= 1 then return nil end
  local e = read_u32(vehicle + G.V.ENGINE)
  if not G.pointer_ok(e) then return nil end
  return e
end

-- On foot and in control: not in a car, menu, cutscene or the front end.
function G.playing(p)
  if p == 0 then return false end
  if G.in_cutscene() or G.screen_up() or G.in_front_end() then return false end
  return G.vehicle_object(p) == nil
end

-- --------------------------------------------------- calling the game
--
-- Game functions are called from inside the update hook with the hook's
-- own CPU context, the way every mod does it: r1 is lowered to leave the
-- callee stack room, our own buffers live in the gap just below the hook's
-- r1, arguments go in r3.. and f1, the result comes back in r3 / f1.
G.SCRATCH = 0x6000          -- stack room for the callee (the collision probe alone takes 11 KB)
local BUF_BASE = 0x1000     -- our buffers: 4 slots of 1 KB at r1 - 0x1000 .. r1

-- Writes a NUL-terminated string into buffer slot 0..3 and returns its address.
function G.cstr(ctx, s, slot)
  local buf = ctx:r(1) - BUF_BASE + (slot or 0) * 0x400
  local n = math.min(#s, 0x3F0)
  local i = 1
  -- Four bytes per write cuts the Lua/C round trips by four.
  while i + 3 <= n do
    write_u32(buf + i - 1, (string.byte(s, i) << 24) | (string.byte(s, i + 1) << 16) | (string.byte(s, i + 2) << 8) | string.byte(s, i + 3))
    i = i + 4
  end
  while i <= n do write_u8(buf + i - 1, string.byte(s, i)); i = i + 1 end
  write_u8(buf + n, 0)
  return buf
end

-- A float vector written into slot 3 (addresses stay valid during one call).
-- `at` offsets several vectors within the slot: 0, 16, 32 ...
function G.floats(ctx, values, at)
  local buf = ctx:r(1) - BUF_BASE + 3 * 0x400 + (at or 0)
  for i, v in ipairs(values) do write_f32(buf + (i - 1) * 4, v) end
  return buf
end

-- Writes a UTF-16 string (ASCII only) into slot 2..3 and returns its address.
function G.wstr(ctx, s)
  local buf = ctx:r(1) - BUF_BASE + 2 * 0x400
  local n = math.min(#s, 0x1F0)
  for i = 1, n do write_u16(buf + (i - 1) * 2, string.byte(s, i)) end
  write_u16(buf + n * 2, 0)
  return buf
end

-- Calls fn with r3.. = args and f1 = f (optional). `stack` is an optional
-- list of { offset, width, value } written relative to the callee's r1, for
-- the few game functions that take arguments past r10. Returns r3 and f1.
function G.call(ctx, fn, args, f, stack)
  local r1 = ctx:r(1)
  local saved = {}
  for i = 3, 10 do saved[i] = ctx:r(i) end
  local saved_f1 = ctx:f(1)
  for i, v in ipairs(args or {}) do ctx:set_r(2 + i, v & 0xFFFFFFFF) end
  if f ~= nil then ctx:set_f(1, f) end
  local callee_r1 = r1 - G.SCRATCH
  if stack then
    for _, a in ipairs(stack) do
      if a[2] == 1 then write_u8(callee_r1 + a[1], a[3])
      elseif a[2] == 2 then write_u16(callee_r1 + a[1], a[3])
      else write_u32(callee_r1 + a[1], a[3]) end
    end
  end
  ctx:set_r(1, callee_r1)
  ctx:call(fn)
  local r3, f1 = ctx:r(3) & 0xFFFFFFFF, ctx:f(1)
  ctx:set_r(1, r1)
  for i = 3, 10 do ctx:set_r(i, saved[i]) end
  ctx:set_f(1, saved_f1)
  return r3, f1
end

-- Runs a line of the game's debug console ("super_ragdoll", "R_wireframe on").
-- Returns true on success. Names are case-sensitive.
function G.console(ctx, line)
  local rc = G.call(ctx, G.CONSOLE, { G.cstr(ctx, line, 0) })
  local ok = rc == 0
  if G.debug then wml.log(string.format("console: %s -> %s", line, ok and "ok" or "error")) end
  return ok
end

-- Runs Lua code in the game's own script state, where all 643 mission
-- script functions (set_weather, notoriety_set, inv_item_add, teleport ...)
-- are globals. Errors are caught by the game's pcall and shown on the HUD.
--
-- The script globals table raises an error on reading an undefined global
-- and the error reporter looks up _ALERT, which the game never defines, so
-- the first thing run is a definition of _ALERT: without it a bad string
-- could take the interpreter down. Code that yields (delay, teleport with
-- a chunk name) must be wrapped in a global and started with thread_new.
local alert_defined = false
function G.script(ctx, code)
  local L = read_u32(G.LUA_STATE)
  if L == 0 then return false end
  if not alert_defined then
    alert_defined = true
    G.call(ctx, G.LUA_DOSTRING, { L, G.cstr(ctx, 'rawset(_UGGlobals, "_ALERT", function(m) message("Script error: " .. tostring(m), 5) end)', 1) })
  end
  local rc = G.call(ctx, G.LUA_DOSTRING, { L, G.cstr(ctx, code, 1) })
  local ok = rc == 0
  if G.debug or not ok then wml.log(string.format("script: %s -> %s", code, ok and "ok" or ("error " .. rc))) end
  return ok
end

-- ---------------------------------------------------------- HUD messages
--
-- Queued here, shown from the update hook where a CPU context is available.
local hud_queue = {}
G.hud_seconds = 3
function G.hud(text) hud_queue[#hud_queue + 1] = text end
function G.flush_hud(ctx)
  if #hud_queue == 0 then return end
  local text = table.remove(hud_queue, 1)
  G.call(ctx, G.HUD_MESSAGE, { G.wstr(ctx, text:sub(1, 200)) }, G.hud_seconds)
  if G.debug then wml.log("hud: " .. text) end
end

return G
