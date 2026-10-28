-- SR Tweak Menu - rows after Saints Row (2006) mods on saintsrowmods.com
-- (Stilwater+, Hardcore Edition, Stamina Mod, Saints of Rage, Gangs drive
-- civilian cars, Bouncy Cars, Simply Less Damping, More Unlockable Unlock
-- Rewards, Fully explored map + 24/7 Stores, Tervel's "MP actions in SP"
-- patch ...). Those mods edit the game's tables or patch the Title Update 1
-- executable; nothing of theirs is used here. Every row works live on the
-- disc build's own data, found in the recompiled code.
--
-- E.setup(F) adds the rows to their tabs (layout.lua places them),
-- E.install() puts in the hooks, E.after(ctx) runs after the game's update.
-- Rows follow the menu's usual rules: a toggle's `update` runs every update
-- while it's on and `off` puts the game's own back.

local G = require("game")
local read_u8, read_u16, read_u32, read_f32 = wml.read_u8, wml.read_u16, wml.read_u32, wml.read_f32
local write_u8, write_u16, write_u32, write_f32 = wml.write_u8, wml.write_u16, wml.write_u32, wml.write_f32
local S = wml.setting

local E = {}
local F         -- the features table, from setup
local MENU      -- the menu, from install
local MASK = 0xFFFFFFFF

local function on(id) return F.enabled and F.items[id] and F.items[id].v end
local function log(...) if G.debug then wml.log(...) end end
local function s32(v) return v >= 0x80000000 and v - 0x100000000 or v end
local function mp() return read_u8(G.MULTIPLAYER) ~= 0 end
-- A float written only when it differs (the write wakes the GPU watch and the
-- game's own readers for nothing otherwise).
local function keep(addr, v) if math.abs(read_f32(addr) - v) > 1e-4 then write_f32(addr, v) end end

-- A hook the loader refuses switches off only its own row, logged.
E.broken = {}
local function hook(addr, name, fn)
  local ok, err = pcall(wml.hook, addr, fn)
  if not ok then
    E.broken[name] = true
    wml.log(string.format("extras: couldn't hook %s at %08X (%s) - that row is off, the rest of the menu works",
      name, addr, tostring(err)))
  end
  return ok
end

local function cstring(a, max)
  if not G.pointer_ok(a) then return nil end
  local t = {}
  for i = 0, (max or 64) - 1 do
    local c = read_u8(a + i)
    if c == 0 then break end
    t[#t + 1] = string.char(c)
  end
  return table.concat(t)
end

-- The game's name hash (0x82637C18(name, 0)): unlockables, store and
-- vehicle variant records are keyed by it.
local NAME_HASH = 0x82637C18
local hashes = {}
local function name_hash(ctx, name)
  local h = hashes[name]
  if not h then
    h = G.call(ctx, NAME_HASH, { G.cstr(ctx, name, 0), 0 })
    hashes[name] = h
  end
  return h
end

-- Names for value rows that pick from a list.
local function named(list) return function(v) return list[math.floor(v + 0.5)] or "?" end end

-- ================================================================ no health regen
--
-- gameplay_constants.xtbl <player_health> is parsed (0x821BD688) into the
-- constants block at 0x838F8360: restore_per_sec_sp f32 at +204, the MP one
-- (co-op) at +212. The human update (0x82442DE8) reads them every frame, so
-- 0 there stops health coming back on its own; food, drinks and the
-- ambulance still heal.
local REGEN_SP, REGEN_MP = 0x838F842C, 0x838F8434
local regen_own = nil
local function regen_stop()
  if not regen_own then
    local sp, mp_rate = read_f32(REGEN_SP), read_f32(REGEN_MP)
    if not (sp > 0 and sp < 100000) then return end   -- the table isn't read yet
    regen_own = { sp, (mp_rate > 0 and mp_rate < 100000) and mp_rate or 25 }
  end
  keep(REGEN_SP, 0); keep(REGEN_MP, 0)
end
local function regen_back()
  if regen_own then write_f32(REGEN_SP, regen_own[1]); write_f32(REGEN_MP, regen_own[2]) end
  regen_own = nil
end

-- ================================================================ sprint presets
--
-- metered_sprint.xtbl rows are copied by 0x82485B70(row) into floats the
-- sprint code reads every frame (0x82484F68, 0x82485290, 0x8247D3B0): use,
-- recharge and delay in ms, use / recharge, recharge * pant, jump penalty.
-- The bonus multiplier at 0x8309ABE0 and the unlimited byte 0x8307B1C7 are
-- the spray-tag rewards, saved with the game: never written here. While
-- Infinite sprint (the cheat bit) is on the sprint never runs out anyway.
local SPRINT = { JUMP = 0x8309ABCC, PANT = 0x8309ABD0, RATIO = 0x8309ABD4, DELAY = 0x8309ABD8,
  RECHARGE = 0x8309ABDC, USE = 0x8309ABE4 }
-- { name, use s, recharge s, delay s, pant, jump penalty } (the first three
-- are the table's own rows; Short is the forum mod's "1 second" one).
local SPRINT_PRESETS = {
  { "Game's own", 10, 9, 2, 0.25, 0.0 },
  { "Multiplayer", 3, 6, 2, 0.25, 0.2 },
  { "Pimp", 2, 7, 2, 0.25, 0.2 },
  { "Short", 1, 12, 2, 0.25, 0.5 },
}
local SPRINT_NAMES = {}
for i, p in ipairs(SPRINT_PRESETS) do SPRINT_NAMES[i] = p[1] end
local function sprint_write(preset)
  local use, recharge = preset[2] * 1000, preset[3] * 1000
  keep(SPRINT.USE, use); keep(SPRINT.RECHARGE, recharge); keep(SPRINT.DELAY, preset[4] * 1000)
  keep(SPRINT.RATIO, use / recharge); keep(SPRINT.PANT, recharge * preset[5]); keep(SPRINT.JUMP, preset[6])
end

-- ================================================================ your gang
--
-- Saints are enemies (features.lua) puts you on another team (human+232);
-- this picks which. The team names are teams.xtbl's.
local GANGS = { "Your model's gang", "Vice Kings", "Los Carnales", "Rollerz", "Police", "Neutral" }
local GANG_TEAMS = { nil, "Vice Lords", "Los Carnales", "Rollerz", "Police", "Neutral Gang" }

-- ================================================================ D-pad heal
--
-- The on-foot controls (0x82167690, r3 = player) give the player what the
-- buttons may do this frame at player+4472. Only the multiplayer path adds
-- 0x8000, healing (the multiplayer "drugs" on D-pad down). The heal itself
-- isn't multiplayer only: with the bit set, D-pad down starts it
-- (0x82484AA0: 8 s, a quarter of your health a second in the last 4, no
-- item) and letting go stops it. The same tests as the multiplayer path:
-- not zoomed in (+3593 bit 0x40), not burning.
local ON_FOOT_CAPS, CAPS = 0x82167690, 4472
local CAN_HEAL, CAN_ACT = 0x8000, 0x2400

-- ================================================================ D-pad taunts
--
-- Multiplayer's three taunts (anim actions 598, 599, 600 on D-pad up, left
-- and right) are behind an inline multiplayer test in the controls update,
-- so they're played here on a D-pad press, with the game's own call and
-- the same tests (+508 state 23 = no, +1956 must be -1). Left and right do
-- nothing on foot in single player; up is recruit, so it's an option.
-- The pad read 0x827166D0(user, XINPUT_STATE*): buttons u16 at +4; the
-- keyboard's arrow keys reach the game through it too.
local PAD_STATE = 0x827166D0
local PAD_UP, PAD_LEFT, PAD_RIGHT = 0x1, 0x4, 0x8
local TAUNT_ACTION = 597   -- + 1, 2, 3
local TAUNT_MODES = { "Off", "Left and right", "Up, left and right" }
local taunt = { previous = 0, want = nil }

-- ================================================================ stores 24/7
--
-- shop_set_open_at_night(name, bool) (0x824DBBC8) sets bit 0x80 of the
-- shop record's +156; the mechanics already have it. The names are
-- shops_sr_city.xtbl's.
local SHOPS = {
  "Condos Plastic Surgeon", "Condos Liquor", "Airport Jewelry", "Projects Liquor", "Trainyard Hair",
  "Suburbs Gun", "Barrio Music", "Docks Gun", "Docks Liquor", "Apartments Liquor", "High End Retail Clothing",
  "Red Light Low Clothing", "Red Light Liquor", "Museum Liquor", "Saint's Row Liquor", "Saint's Row Low Clothing",
  "Saint's Row Gun", "Downtown Tattoo", "Downtown Clothing", "Downtown Music", "Downtown Gun", "Arena Clothing",
  "Apartments Hair", "Apartments Gun", "Barrio Clothing", "Red Light Tattoo", "High End Retail Jewelry",
  "High End Retail Hair", "Suburbs Clothing", "Chinatown Jewelry", "Barrio Plastic Surgeon", "Docks Tattoo",
  "Downtown Plastic Surgeon", "Projects Clothing", "Apartments Music", "Chinatown Tattoo", "Suburbs Jewelry",
  "Saint's Row Plastic Surgeon", "Truckyard Clothing", "Truckyard Liquor", "Suburbs Music",
}
-- Script lines of up to ~900 characters (the script buffer takes 1008).
local function shop_lines(open)
  local lines, names = {}, {}
  local function flush()
    if #names == 0 then return end
    lines[#lines + 1] = "for _, n in ipairs({ " .. table.concat(names, ", ") ..
      string.format(" }) do shop_set_open_at_night(n, %s) end", open and "true" or "false")
    names = {}
  end
  local size = 0
  for _, name in ipairs(SHOPS) do
    if size + #name > 800 then flush(); size = 0 end
    names[#names + 1] = '"' .. name .. '"'
    size = size + #name + 4
  end
  flush()
  return lines
end
local stores = { player = 0, next_at = 0 }

-- ================================================================ districts
--
-- hood_set_owner(hood, team) (0x824CE1E0) is the full takeover the game
-- uses (0x8211F9B0), rewards included. The hoods, districts and starting
-- owners are neighborhoods.xtbl's.
local HOODS = {
  { "lc_airport01", "Airport", "Los Carnales" }, { "lc_barrio01", "Barrio", "Los Carnales" },
  { "lc_barrio02", "Barrio", "Los Carnales" }, { "lc_barrio03", "Barrio", "Los Carnales" },
  { "lc_barrio04", "Barrio", "Los Carnales" }, { "lc_docks01", "Docks And Warehouses", "Los Carnales" },
  { "lc_docks02", "Docks And Warehouses", "Los Carnales" }, { "lc_docks03", "Docks And Warehouses", "Los Carnales" },
  { "lc_factory01", "Factories", "Los Carnales" }, { "lc_factory02", "Factories", "Los Carnales" },
  { "lc_factory03", "Factories", "Los Carnales" }, { "lc_factory04", "Factories", "Los Carnales" },
  { "ts_saintsrow01", "Saints Row", "Vice Lords" }, { "ts_saintsrow02", "Saints Row", "Rollerz" },
  { "ts_saintsrow03", "Saints Row", "Los Carnales" }, { "vk_downtown01", "Downtown", "Vice Lords" },
  { "vk_downtown02", "Downtown", "Vice Lords" }, { "vk_downtown03", "Downtown", "Vice Lords" },
  { "vk_downtown04", "Downtown", "Vice Lords" }, { "vk_highend01", "High End Retail", "Vice Lords" },
  { "vk_highend02", "High End Retail", "Vice Lords" }, { "vk_museum01", "Museum", "Vice Lords" },
  { "vk_museum02", "Museum", "Vice Lords" }, { "vk_projects01", "Projects", "Vice Lords" },
  { "vk_projects02", "Projects", "Vice Lords" }, { "vk_redlight01", "Red Light", "Vice Lords" },
  { "vk_redlight02", "Red Light", "Vice Lords" }, { "vk_redlight03", "Red Light", "Vice Lords" },
  { "wr_apartments01", "Apartments", "Rollerz" }, { "wr_arena01", "Race Track", "Rollerz" },
  { "wr_arena02", "Race Track", "Rollerz" }, { "wr_chinatown01", "Chinatown", "Rollerz" },
  { "wr_suburb01", "Suburbs", "Rollerz" }, { "wr_suburb02", "Suburbs", "Rollerz" },
  { "wr_suburb03", "Suburbs", "Vice Lords" }, { "wr_truckyard01", "Truck Yard", "Rollerz" },
}
local DISTRICTS = { "Whole city", "Airport", "Apartments", "Barrio", "Chinatown", "Docks And Warehouses", "Downtown",
  "Factories", "High End Retail", "Museum", "Projects", "Race Track", "Red Light", "Saints Row", "Suburbs", "Truck Yard" }
local OWNERS = { "Saints", "Vice Kings", "Los Carnales", "Rollerz", "Starting owners" }
local OWNER_TEAMS = { "Playas", "Vice Lords", "Los Carnales", "Rollerz" }

-- ================================================================ gangs drive ordinary cars
--
-- Gang cars are civilian models with a gang paint variant. Street gangs:
-- spawn_info_groups groups (*0x8370D028, count *0x8370D024, 1596 bytes
-- each) list their cars' variant records at +1084 + 4i (count at +56; the
-- record's +4 is the variant's name hash; 0 = any paint). Notoriety cars:
-- the paint name is fixed per team at team+472. Taken away, new gang cars
-- spawn with the ordinary paint roll; restored when switched off.
local GROUPS, GROUP_COUNT, GROUP_SIZE, GROUP_CARS, GROUP_VARIANTS = 0x8370D028, 0x8370D024, 1596, 56, 1084
local TEAM_PAINT = { { 0x82831C18 + 472, 0x82047BA0 }, { 0x82831EAC + 472, 0x82047B98 }, { 0x82832140 + 472, 0x82072E2C } }
local GANG_PAINTS = { "Gang_LC", "Gang_VK", "Gang_WR" }   -- not the Saints' Gang_3SS
local civ = { base = nil, saved = {}, paint = {} }
local function civ_apply(ctx)
  local paints = {}
  for _, n in ipairs(GANG_PAINTS) do paints[name_hash(ctx, n)] = true end
  local base, count = read_u32(GROUPS), read_u32(GROUP_COUNT)
  if base ~= civ.base then civ.base, civ.saved = base, {} end   -- a new table: nothing of ours in it
  local changed = 0
  if G.pointer_ok(base) and count > 0 and count < 1024 then
    for g = 0, count - 1 do
      local group = base + g * GROUP_SIZE
      local cars = read_u32(group + GROUP_CARS)
      if cars > 128 then cars = 0 end
      for i = 0, cars - 1 do
        local a = group + GROUP_VARIANTS + 4 * i
        local rec = read_u32(a)
        if rec ~= 0 and G.pointer_ok(rec) and paints[read_u32(rec + 4)] then
          civ.saved[a] = rec
          write_u32(a, 0)
          changed = changed + 1
        end
      end
    end
  end
  for _, t in ipairs(TEAM_PAINT) do
    if read_u32(t[1]) == t[2] then write_u32(t[1], 0); civ.paint[t[1]] = t[2]; changed = changed + 1 end
  end
  if changed > 0 then log("gang cars: " .. changed .. " gang paints taken away") end
end
local function civ_restore()
  if read_u32(GROUPS) == civ.base then
    for a, rec in pairs(civ.saved) do if read_u32(a) == 0 then write_u32(a, rec) end end
  end
  for a, v in pairs(civ.paint) do if read_u32(a) == 0 then write_u32(a, v) end end
  civ.saved, civ.paint = {}, {}
end

-- ================================================================ no guns
--
-- spawn_info_ranks: every person gets a loadout from their rank (0x82477550)
-- when made. Rank table 0x829A0028 (1448 bytes each, count *0x8370D038,
-- name hash at +0); per team (7) a block at +20 + team * 204, and in it per
-- category (melee, firearm, thrown) 68 bytes whose byte +0 is the chance
-- that category is handed out at all, +1 how many weapons it lists.
-- Notoriety crews (police, SWAT, FBI, gang response) also get a weapon from
-- notoriety_spawn through 0x823FC7E0(team, human, slot), skipped while on.
-- Missions hand out their own (scripts and .cts), left alone.
local RANKS, RANK_COUNT, RANK_SIZE, RANK_TEAMS = 0x829A0028, 0x8370D038, 1448, 7
local ARMED_RANKS = { "Thug", "Killa", "Gangsta", "Kingpin", "Patrolman", "Sergeant", "SWAT", "FBI" }
local CREW_WEAPON = 0x823FC7E0
local guns = { saved = nil, ranks = nil }
local function guns_ranks(ctx)
  if guns.ranks then return guns.ranks end
  local want = {}
  for _, n in ipairs(ARMED_RANKS) do
    want[name_hash(ctx, n)] = n
    want[G.call(ctx, G.NAME_HASH, { G.cstr(ctx, n, 0) })] = n   -- the other name hash the game uses
  end
  local found, count = {}, read_u32(RANK_COUNT)
  if count == 0 or count > 256 then return nil end
  for r = 0, count - 1 do
    local rank = RANKS + r * RANK_SIZE
    if want[read_u32(rank)] then found[#found + 1] = rank end
  end
  if #found == 0 then wml.log("no guns: the gang and police ranks weren't found; left alone") return nil end
  log("no guns: " .. #found .. " ranks")
  guns.ranks = found
  return found
end
local function guns_apply(ctx)
  local ranks = guns_ranks(ctx)
  if not ranks then return end
  guns.saved = guns.saved or {}
  for _, rank in ipairs(ranks) do
    for t = 0, RANK_TEAMS - 1 do
      local block = rank + 20 + t * 204
      local melee, fire, thrown = block, block + 68, block + 136
      for _, a in ipairs({ melee, fire, thrown }) do
        if guns.saved[a] == nil then guns.saved[a] = read_u8(a) end
      end
      if read_u8(fire) ~= 0 then write_u8(fire, 0) end
      if read_u8(thrown) ~= 0 then write_u8(thrown, 0) end
      if read_u8(melee + 1) > 0 and read_u8(melee) ~= 100 then write_u8(melee, 100) end
    end
  end
end
local function guns_restore()
  for a, v in pairs(guns.saved or {}) do write_u8(a, v) end
  guns.saved = nil
end

-- ================================================================ car handling
--
-- Every car: the vehicle list (head *0x83289904, next at +50308, a ring),
-- its info record at +50324 (vehicles.xtbl) and its physics at the engine
-- object (+224, while +50300 is 1).
--   Bouncy cars: Extra_Gravity (info +652, -20 on most cars) is copied into
--   a physics action at engine+216, f32 +28, and pushes the car along the
--   ground's normal while all four wheels touch: negative holds it down,
--   positive throws it off the road, it lands, and again.
--   Less stiff: Angular_Damping (info +904 normal, +908 in collisions) is
--   copied into the Havok damper at engine+72 (+8, +12), read every physics
--   step; a rebuilt car gets the table's again, so it's checked often.
local VEHICLES, VEHICLE_NEXT, VEHICLE_INFO = 0x83289904, 50308, 50324
local INFO_GRAVITY, INFO_SPIN, INFO_SPIN_HIT, INFO_NAME = 652, 904, 908, 96
local DAMPER = 72
-- Trailers and the police helicopter keep their own damping (as the forum
-- mod left them).
local STIFF = { sp_trailer_tank1 = true, sp_trailer_carri01 = true, sp_bagtrailer01 = true, sp_trailer_box01 = true,
  heli_4dr_police01 = true }
local function each_vehicle(fn)
  local head = read_u32(VEHICLES)
  if not G.pointer_ok(head) then return end
  local v = head
  for _ = 1, 512 do
    local e = G.engine_object(v)
    local info = read_u32(v + VEHICLE_INFO)
    if e and G.pointer_ok(info) then fn(v, e, info) end
    v = read_u32(v + VEHICLE_NEXT)
    if v == head or not G.pointer_ok(v) then break end
  end
end
local info_names = {}
local function vehicle_name(info)
  local n = info_names[info]
  if n == nil then
    local p = read_u32(info + INFO_NAME)
    n = (G.pointer_ok(p) and cstring(p, 48)) or cstring(info + INFO_NAME, 48) or ""
    info_names[info] = n:lower()
  end
  return info_names[info]
end
local function downforce(e)
  local action = read_u32(e + G.ENGINE_ACTION)
  return G.pointer_ok(action) and action + G.ACTION_DOWNFORCE or nil
end
local function damper(e)
  local d = read_u32(e + DAMPER)
  if not G.pointer_ok(d) then return nil end
  local n = read_f32(d + 8)
  if not (n >= 0 and n < 100) then return nil end
  return d
end

-- ================================================================ money rain
--
-- Bills of cash made a few metres up, mostly ahead of where you're going,
-- the way the menu's cash drops are made (G.CASH_AT). The game keeps at
-- most 50 cash pickups lying around and deletes the oldest, so
-- the rain never piles up.
local rain = { due = 0, last = nil }

-- ================================================================ rewards
--
-- unlockables.xtbl rows patch.lua adds (srt_*). Unlocking one (0x82226738,
-- what the console's unlockable_unlock calls) queues it, at most 7 at a
-- time at 0x82B8C294 (count just before it); the game then applies it,
-- shows its popup and keeps it in the save. The table's rows: count at
-- +60, 64 bytes each from +68, name hash at +0.
local UNLOCK, UNLOCKS = 0x82226738, 0x82B8C294
local REWARDS = {
  { id = "reward_free_shopping", label = "Free shopping", what = "Everything in Impressions, Foreign Power, Friendly Fire, On Thin Ice, On the Rag, Rim Jobs, Sloppy Seconds and Branded costs nothing.",
    names = { "srt_free_impressions", "srt_free_foreign_power", "srt_free_friendly_fire", "srt_free_on_thin_ice",
      "srt_free_on_the_rag", "srt_free_rim_jobs", "srt_free_sloppy_seconds", "srt_free_branded" } },
  { id = "reward_bulletproof", label = "Bulletproof", what = "Bullets don't hurt you.", names = { "srt_bulletproof" } },
  { id = "reward_blastproof", label = "Explosion-proof", what = "Explosions don't hurt you.", names = { "srt_blastproof" } },
  { id = "reward_crashproof", label = "Crash-proof", what = "Car crashes don't hurt you.", names = { "srt_crashproof" } },
  { id = "reward_police_forget", label = "Police forget fast", what = "Police notoriety fades almost at once.", names = { "srt_police_forget" } },
  { id = "reward_gangs_forget", label = "Gangs forget fast", what = "Every gang's notoriety fades almost at once.",
    names = { "srt_carnales_forget", "srt_vice_kings_forget", "srt_rollerz_forget" } },
}
local reward_queue = {}
local function reward_known(ctx, name)
  local h = name_hash(ctx, name)
  local count = read_u32(UNLOCKS + 60)
  if count > 1024 then return false end
  for i = 0, count - 1 do
    if read_u32(UNLOCKS + 68 + i * 64) == h then return true end
  end
  return false
end

-- ================================================================ first person view
--
-- First Person (Saints Reborn's built-in mod, V) puts the camera at the
-- eyes in its hook on the camera update (0x82109608) and writes its own
-- field of view to the camera (+188) after the game's. Mods load after the
-- built-in ones, so this hook runs round First Person's: after it, while
-- first person is showing, the menu's field of view goes on top. First
-- person is showing when the camera is the follow camera (type 0 at +0),
-- First Person has the near-camera fade switched off (0x827D93C0 = 0, it
-- puts it back when it stops) and the camera sits at the player's head.
local CAMERA_UPDATE, CAMERA_FADE_RADIUS = 0x82109608, 0x827D93C0
local CAM_POS, CAM_FOV = 44, 188
-- First Person's own field of view (its mod.ini, next to this mod's folder).
local fp_fov = 75
do
  local f = io.open(wml.mod_folder .. "/../../core/FirstPerson/mod.ini", "r")
  if f then
    for line in f:lines() do
      local v = line:match("^%s*fov%s*=%s*([%d%.]+)")
      if v then fp_fov = tonumber(v) or fp_fov end
    end
    f:close()
  end
  if fp_fov <= 0 then fp_fov = 60 end   -- 0 there keeps the game's own, about 60
end
-- Switching it: First Person 1.4 reads a small block at 0x00F01000 in the
-- low guest memory Saints Reborn keeps for mods (Windows): +0 'FPSW' once it
-- reads it, +4 1 while first person is on, +8 a request (1 on, 2 off),
-- cleared by First Person once done. Older First Person: V only.
local FP_SHARED = package.config:sub(1, 1) == "\\" and 0x00F01000 or nil
local FP_MAGIC = 0x46505357
local fp_request_at = nil   -- the tick a request was made, until First Person takes it
local function fp_switchable() return FP_SHARED and read_u32(FP_SHARED) == FP_MAGIC end
local function first_person_showing()
  local p = G.player()
  if p == 0 or read_u32(G.CAMERA) ~= 0 or read_f32(CAMERA_FADE_RADIUS) ~= 0 then return false end
  local cx, cy, cz = G.vec(G.CAMERA + CAM_POS)
  local px, py, pz = G.vec(p + G.P.POS)
  local dy = cy - py
  return (cx - px) ^ 2 + (cz - pz) ^ 2 < 0.8 * 0.8 and dy > 0.4 and dy < 2.2
end

-- ================================================================ shoulder camera
--
-- On foot the follow camera looks at the player from straight behind (its
-- presets at 0x827D9ED8 have a look-at height, pitch limits and the field of
-- view, nothing sideways). Over the shoulder, as in GTA: after each camera
-- update the camera's position (+44) is moved along its own right row (+80)
-- and towards where it looks (+104), so the player stands off to one side
-- and the aim stays in the middle. Before the next update that move is
-- taken back off, so the game's camera keeps easing from its own place.
-- Only the normal on-foot presets (6, 15 to 18; not 12, aiming, which the
-- aim add-ons handle, nor 13, swimming), the follow camera (type 0), not in
-- first person or the menu's free and fitting-room cameras. The move isn't
-- tested against walls: standing with a wall close on that side the camera
-- can look through it.
local CAMERA_PRESET = 0x827DA15C
local SHOULDER_PRESETS = { [6] = true, [15] = true, [16] = true, [17] = true, [18] = true }
local CAM_RIGHT, CAM_FORWARD = 80, 104
local shoulder_last = nil   -- the move applied after the last update { dx, dy, dz }
local shoulder_blend = 0    -- 0..1, eased in and out so aiming, cars and cutscenes don't snap
local FREECAM = require("freecam")
local function shoulder_wanted()
  if not F.enabled or not F.items.shoulder_cam.v then return false end
  local p = G.player()
  if p == 0 or G.vehicle_object(p) or G.in_cutscene() then return false end
  if read_u32(G.CAMERA) ~= 0 or not SHOULDER_PRESETS[read_u32(CAMERA_PRESET)] then return false end
  if FREECAM.on or FREECAM.orbiting or read_f32(CAMERA_FADE_RADIUS) == 0 then return false end
  return true
end

-- ================================================================ give items
--
-- The weed, booze, drinks and food from the stores (drugs.xtbl) load into
-- the same item table as the inventory items (0x823F6298 -> count at
-- 0x830828DC), so the script function inv_item_add hands them out like the
-- stores do. { name, the game's own name, kind }.
local ITEMS = {
  { "spliff", "Spliff", "weed" }, { "blunt", "Blunt", "weed" }, { "pipe", "Pipe", "weed" }, { "bong", "Bong", "weed" },
  { "40oz", "40 oz.", "booze" }, { "gin_n_juice", "Gin N' Juice", "booze" }, { "hennessy", "Cognac", "booze" },
  { "krystal", "Bubbly", "booze" }, { "large_softdrink", "Big Swallow", "drink" }, { "chicken_bazooms", "Chicken Bazooms", "food" },
  { "burgera", "The Twins", "food" }, { "the_fist", "The Fist", "food" },
}
local ITEM_LIST = {}
for _, it in ipairs(ITEMS) do ITEM_LIST[#ITEM_LIST + 1] = { it[1], string.format("%s (%s)", it[2], it[3]) } end

-- ================================================================ rows
local function fmtx(v) return string.format("x%.2f", v) end
local function fmtint(v) return string.format("%d", v) end

function E.setup(features)
  F = features

  F.add_rows("Player", nil, {
    { id = "no_regen", label = "No health regen", kind = "toggle", needs = "none", v = S("no_health_regen", false),
      help = "Your health no longer comes back on its own: eat, drink, use the D-pad heal or call 911. (Hardcore Edition)",
      update = function() regen_stop() end,
      off = function() regen_back() end },
    { id = "dpad_heal", label = "Heal on D-pad down", kind = "toggle", needs = "none", v = S("dpad_heal", false),
      help = "Multiplayer's heal in single player: hold D-pad down (arrow down) on foot to heal over 8 seconds. Also cancels an activity, as D-pad down does." },
    { id = "sprint_preset", label = "Sprint", kind = "value", needs = "none", default = 1, min = 1, max = #SPRINT_PRESETS, step = 1,
      v = S("sprint_preset", 1), fmt = named(SPRINT_NAMES),
      help = "How long you can sprint: the game's own (10 s), Multiplayer (3 s), Pimp (2 s) or Short (1 s, jumping costs half). Infinite sprint overrides it.",
      update = function() if not mp() then sprint_write(SPRINT_PRESETS[F.items.sprint_preset.v] or SPRINT_PRESETS[1]) end end,
      off = function() if not mp() then sprint_write(SPRINT_PRESETS[1]) end end },
    { id = "join_gang", label = "Gang you side with", kind = "value", needs = "none", default = 1, min = 1, max = #GANGS, step = 1,
      v = S("join_gang", 1), fmt = named(GANGS),
      help = "While Saints are enemies is on: the gang (or the police) you belong to. Their members are your friends, the Saints and everyone else your enemies.",
      change = function(ctx, p, v, it)
        if it.v > 1 and not F.items.saints_enemies.v then
          F.items.saints_enemies.v = true
          return "Saints are enemies on: you side with " .. GANGS[it.v]
        end
      end,
      update = function() end },
    { id = "dpad_taunts", label = "D-pad taunts", kind = "value", needs = "none", default = 1, min = 1, max = #TAUNT_MODES, step = 1,
      v = S("dpad_taunts", 1), fmt = named(TAUNT_MODES),
      help = "Multiplayer's three taunts on foot: D-pad left and right (arrow keys), and up too if you like (up still recruits). Left and right are off while Weapon switch uses the D-pad.",
      update = function() end },
  })

  F.add_rows("Vehicles", nil, {
    { id = "bouncy_cars", label = "Bouncy cars", kind = "toggle", needs = "none", v = S("bouncy_cars", false),
      help = "Every car on the road bounces along like it's on springs. (Bouncy Cars by Ricsow) Overrides Extra car grip.",
      update = function() if F.tick % 5 == 0 then E.bounce(true) end end,
      off = function() E.bounce(false) end },
    { id = "bounce_strength", label = "Bounce strength", kind = "value", needs = "none", default = 25, min = 5, max = 60, step = 5,
      v = S("bounce_strength", 25), fmt = fmtint, oneshot = true,
      hidden = function() return not F.items.bouncy_cars.v end,
      help = "How hard the road throws cars up (the game holds them down with 20)." },
    { id = "soft_spin", label = "Less stiff cars", kind = "toggle", needs = "none", v = S("less_stiff_cars", false),
      help = "Cars turn, slide and spin more freely: their spin damping is cut. Trailers and the helicopter keep theirs. (Simply Less Damping by B Dawg)",
      update = function() if F.tick % 10 == 0 then E.spin(true) end end,
      off = function() E.spin(false) end },
    { id = "spin_damping", label = "Spin damping", kind = "value", needs = "none", default = 0.5, min = 0.1, max = 0.9, step = 0.1,
      v = S("spin_damping", 0.5), fmt = fmtx, oneshot = true,
      hidden = function() return not F.items.soft_spin.v end,
      help = "How much of the game's spin damping cars keep (0.5 = half)." },
  })

  F.add_rows("Weapons", "give_weapon", {
    { id = "give_item", label = "Give item", kind = "list", items = ITEM_LIST,
      help = "Weed, booze, drinks and food, as the stores sell them: Left / Right picks, Enter puts them in your inventory.",
      run = function(ctx, p, _, it)
        local item = ITEM_LIST[it.v]
        local n = F.items.give_item_count.v
        G.script(ctx, string.format('inv_item_add("%s", %d, "#PLAYER#")', item[1], n))
        return string.format("Given: %d x %s", n, item[2])
      end },
    { id = "give_item_count", label = "How many", kind = "value", needs = "none", default = 1, min = 1, max = 10, step = 1,
      v = 1, oneshot = true, nosave = true, fmt = fmtint, help = "How many of the item Give item hands you." },
  })

  local fp_default = math.floor(fp_fov + 0.5)
  F.add_rows("Visual", nil, {
    { id = "first_person", label = "First person", kind = "toggle", needs = "none", nosave = true,
      help = "Look through your character's eyes (Saints Reborn's First Person, the same as V). Shops and cutscenes switch back by themselves.",
      change = function(ctx, p, v, it)
        if not fp_switchable() then
          it.v = false
          return "Press V for first person (the menu can switch it with First Person 1.4)"
        end
        write_u32(FP_SHARED + 8, it.v and 1 or 2)
        fp_request_at = F.tick
        return it.v and "First person on" or "First person off"
      end },
    { id = "fp_fov", label = "First person field of view", kind = "value", needs = "none", default = fp_default,
      min = 50, max = 120, step = 5, v = S("first_person_fov", fp_default),
      fmt = function(v) return string.format("%d deg", math.floor(v + 0.5)) end,
      help = "How wide you see in first person (V): wider shows more of your arms, your gun as it fires and what's around you. First Person's own is " .. fp_default .. ".",
      update = function() end },
    { id = "shoulder_cam", label = "Over-the-shoulder camera", kind = "toggle", needs = "none", v = S("shoulder_camera", false),
      help = "Walking around, the camera sits over your shoulder like GTA: you to one side, the aim in the middle. Aiming keeps the aim style's own camera." },
    { id = "shoulder_side", label = "Shoulder offset", kind = "value", needs = "none", default = 0.6, min = -1.5, max = 1.5, step = 0.1,
      v = S("shoulder_offset", 0.6), oneshot = true,
      fmt = function(v)
        if math.abs(v) < 0.05 then return "centred" end
        return string.format("%.1f m %s", math.abs(v), v > 0 and "right" or "left")
      end,
      hidden = function() return not F.items.shoulder_cam.v end,
      help = "How far to the side the camera sits: right puts you on the left of the screen, left on the right." },
    { id = "shoulder_closer", label = "Shoulder camera closer", kind = "value", needs = "none", default = 0.8, min = -1.0, max = 2.0, step = 0.1,
      v = S("shoulder_closer", 0.8), oneshot = true,
      fmt = function(v) return string.format("%+.1f m", v) end,
      hidden = function() return not F.items.shoulder_cam.v end,
      help = "How much closer to you the camera comes (negative: further back)." },
  })

  local district_rows = {
    { id = "district", label = "District", kind = "choice", needs = "none", options = DISTRICTS,
      help = "Which part of Stilwater to hand over." },
    { id = "district_owner", label = "Give it to", kind = "choice", needs = "none", options = OWNERS,
      help = "Who gets it. Starting owners puts it back the way a new game starts." },
    { id = "district_apply", label = "Hand it over", kind = "action",
      help = "Changes who owns those neighbourhoods. Saved with your game: owning hoods unlocks homie slots and rewards, and missions can change owners again.",
      run = function(ctx, p) return E.hand_over() end },
    { id = "explore_map", label = "Reveal the whole map", kind = "action",
      help = "Every neighbourhood shows on the map as explored. Saved with your game.",
      run = function(ctx) G.console(ctx, "hood_explore_all"); return "The whole map is explored" end },
  }
  F.add_rows("World", nil, district_rows)
  F.add_rows("World", nil, {
    { id = "stores_24_7", label = "Stores open 24/7", kind = "toggle", needs = "player", v = S("stores_24_7", false),
      help = "Every store stays open at night.",
      update = function(ctx, p)
        if p ~= stores.player or F.tick >= stores.next_at then
          for _, line in ipairs(shop_lines(true)) do F.queue[#F.queue + 1] = line end
          stores.player, stores.next_at = p, F.tick + 50 * 120
        end
      end,
      off = function()
        for _, line in ipairs(shop_lines(false)) do F.queue[#F.queue + 1] = line end
        stores.player = 0
      end },
    { id = "gang_civ_cars", label = "Gangs drive ordinary cars", kind = "toggle", needs = "none", v = S("gangs_drive_ordinary_cars", false),
      help = "Gang members drive ordinary paint jobs, not their gang colours. Cars already on the road keep theirs. (Gangs drive civilian cars)",
      update = function(ctx) if F.tick % 100 == 1 then civ_apply(ctx) end end,
      off = function() civ_restore() end },
    { id = "no_guns", label = "Gangs and police without guns", kind = "toggle", needs = "none", v = S("no_guns", false),
      help = "Gang members and police (SWAT and FBI too) come at you with bats, knives and nightsticks. Missions keep theirs; people already out keep what they have. (Saints of Rage)",
      update = function(ctx) if F.tick % 100 == 1 then guns_apply(ctx) end end,
      off = function() guns_restore() end },
    { id = "money_rain", label = "Money rain", kind = "toggle", v = S("money_rain", false),
      help = "Cash falls around you as you walk: pick it up as you go. On foot only.",
      off = function() rain.due, rain.last = 0, nil end },
    { id = "money_rain_rate", label = "Money rain: bills a second", kind = "value", needs = "none", default = 3, min = 1, max = 10, step = 1,
      v = S("money_rain_rate", 3), fmt = fmtint, oneshot = true,
      hidden = function() return not F.items.money_rain.v end,
      help = "How many bills fall each second." },
    { id = "money_rain_bill", label = "Money rain: bill", kind = "value", needs = "none", default = 0, min = 0, max = 1000, step = 50,
      v = S("money_rain_bill", 0), oneshot = true,
      fmt = function(v) return v == 0 and "Random" or string.format("$%d", v) end,
      hidden = function() return not F.items.money_rain.v end,
      help = "How much each bill is worth (Random: $10 to $500)." },
  })

  local unlock_rows = {
    { id = "unlock_mp_clothing", label = "Unlock multiplayer clothing", kind = "action",
      help = "The clothes and jewelry multiplayer keeps for itself (MP chains, Cross pennant, cards medallion, MP pimp hat, wool socks ...) in your wardrobe.",
      run = function(ctx, p) return F.unlock_items(ctx, p, F.MP_CLOTHING) end },
    { id = "unlock_reward_clothing", label = "Unlock reward clothing", kind = "action",
      help = "The clothes activities give as rewards (pimp, zoot, racing, the chains and medallions), now.",
      run = function(ctx, p) return F.unlock_items(ctx, p, F.REWARD_CLOTHING) end },
  }
  local reward_pages = { { id = "rewards_header", label = "Rewards (kept in your save)", kind = "header" } }
  for _, r in ipairs(REWARDS) do
    reward_pages[#reward_pages + 1] = { id = r.id, label = r.label .. " (permanent)", kind = "page",
      help = r.what .. " Kept in your save for good: it can't be taken back.",
      open = function()
        local pg
        pg = { title = r.label .. ": keep it for good?", rows = {
          { label = "Yes", kind = "action", run = function(c) pg.close_after = 1; return E.reward(c, r) end },
          { label = "No", kind = "action", run = function() pg.close_after = 1 end } } }
        return pg
      end }
  end
  for _, row in ipairs(reward_pages) do unlock_rows[#unlock_rows + 1] = row end
  F.add_rows("Settings", nil, unlock_rows)
  E.reward_ids = {}
  for _, r in ipairs(REWARDS) do E.reward_ids[#E.reward_ids + 1] = r.id end

  -- Picked by Saints are enemies (features.lua): the team to be on, or nil
  -- for the gang of the character you look like.
  function F.join_gang_team()
    local it = F.items.join_gang
    return it and F.enabled and GANG_TEAMS[it.v] or nil
  end
end

-- ================================================================ actions
function E.hand_over()
  local where = DISTRICTS[F.items.district.v] or "Whole city"
  local who = F.items.district_owner.v
  local n = 0
  for _, h in ipairs(HOODS) do
    if where == "Whole city" or h[2] == where then
      local team = OWNER_TEAMS[who] or h[3]
      F.queue[#F.queue + 1] = string.format('hood_set_owner("%s", "%s")', h[1], team)
      n = n + 1
    end
  end
  return string.format("%s: %d neighbourhood%s to %s", where, n, n == 1 and "" or "s", OWNERS[who] or "?")
end

function E.reward(ctx, r)
  for _, name in ipairs(r.names) do
    if not reward_known(ctx, name) then
      return "Restart the game once first: the reward isn't in the game's table yet"
    end
  end
  for _, name in ipairs(r.names) do reward_queue[#reward_queue + 1] = name end
  return r.label .. ": unlocking"
end

function E.bounce(want)
  local strength = F.items.bounce_strength.v
  each_vehicle(function(v, e, info)
    local addr = downforce(e)
    if not addr then return end
    if want then keep(addr, strength) else
      local own = read_f32(info + INFO_GRAVITY)
      if own > -1000 and own < 1000 then keep(addr, own) end
    end
  end)
end

function E.spin(want)
  local k = F.items.spin_damping.v
  each_vehicle(function(v, e, info)
    if STIFF[vehicle_name(info)] then return end
    local d = damper(e)
    if not d then return end
    local normal, hit = read_f32(info + INFO_SPIN), read_f32(info + INFO_SPIN_HIT)
    if not (normal >= 0 and normal < 100 and hit >= 0 and hit < 100) then return end
    if want then keep(d + 8, normal * k); keep(d + 12, hit * k)
    else keep(d + 8, normal); keep(d + 12, hit) end
  end)
end

-- ================================================================ hooks
function E.install(menu)
  MENU = menu

  hook(ON_FOOT_CAPS, "D-pad heal", function(ctx)
    local p = ctx:r(3) & MASK
    ctx:call_original()
    if not on("dpad_heal") or p == 0 or p ~= read_u32(G.PLAYER) or mp() then return end
    local caps = read_u32(p + CAPS)
    if (caps & CAN_ACT) ~= CAN_ACT then return end
    if (read_u8(p + 3593) & 0x40) ~= 0 or (read_u32(p + G.P.FLAGS) & G.BURNING) ~= 0 then return end
    write_u32(p + CAPS, caps | CAN_HEAL)
  end)

  hook(PAD_STATE, "D-pad taunts", function(ctx)
    local user, state = ctx:r(3) & MASK, ctx:r(4) & MASK
    ctx:call_original()
    if user ~= 0 or state == 0 then return end
    local buttons = read_u16(state + 4)
    local pressed = buttons & ~taunt.previous
    taunt.previous = buttons
    if pressed == 0 or not F.enabled then return end
    local mode = F.items.dpad_taunts.v
    if mode < 2 then return end
    if (pressed & PAD_LEFT) ~= 0 then taunt.want = 2
    elseif (pressed & PAD_RIGHT) ~= 0 then taunt.want = 3
    elseif (pressed & PAD_UP) ~= 0 and mode >= 3 then taunt.want = 1 end
  end)

  hook(CAMERA_UPDATE, "first person field of view and shoulder camera", function(ctx)
    -- (the shoulder camera's last move off again, so the game eases from its own place)
    if shoulder_last and read_u32(G.CAMERA) == 0 and not FREECAM.on and not FREECAM.orbiting then
      local x, y, z = G.vec(G.CAMERA + CAM_POS)
      write_f32(G.CAMERA + CAM_POS, x - shoulder_last[1])
      write_f32(G.CAMERA + CAM_POS + 4, y - shoulder_last[2])
      write_f32(G.CAMERA + CAM_POS + 8, z - shoulder_last[3])
    end
    shoulder_last = nil
    ctx:call_original()
    local it = F.items.fp_fov
    if F.enabled and it.v ~= it.default and first_person_showing() then write_f32(G.CAMERA + CAM_FOV, it.v) end
    local want = shoulder_wanted()
    shoulder_blend = shoulder_blend + ((want and 1 or 0) - shoulder_blend) * 0.12
    if shoulder_blend < 0.01 then shoulder_blend = 0 end
    if read_f32(CAMERA_FADE_RADIUS) == 0 then shoulder_blend = 0 end   -- (first person: its camera, no move)
    if shoulder_blend > 0 and read_u32(G.CAMERA) == 0 and not FREECAM.on and not FREECAM.orbiting then
      local side, closer = F.items.shoulder_side.v * shoulder_blend, F.items.shoulder_closer.v * shoulder_blend
      local rx, ry, rz = G.vec(G.CAMERA + CAM_RIGHT)
      local fx, fy, fz = G.vec(G.CAMERA + CAM_FORWARD)
      local dx, dy, dz = rx * side + fx * closer, ry * side + fy * closer, rz * side + fz * closer
      if dx == dx and dy == dy and dz == dz and dx * dx + dy * dy + dz * dz < 25 then
        local x, y, z = G.vec(G.CAMERA + CAM_POS)
        write_f32(G.CAMERA + CAM_POS, x + dx)
        write_f32(G.CAMERA + CAM_POS + 4, y + dy)
        write_f32(G.CAMERA + CAM_POS + 8, z + dz)
        shoulder_last = { dx, dy, dz }
      end
    end
  end)

  hook(CREW_WEAPON, "notoriety crews without guns", function(ctx)
    if on("no_guns") then return end
    ctx:call_original()
  end)
end

-- ================================================================ after the update
local function taunt_now(ctx, p)
  local which = taunt.want
  taunt.want = nil
  if not which or F.items.dpad_taunts.v < 2 or p == 0 or not G.playing(p) then return end
  if MENU and MENU.is_open() then return end
  -- Weapon switch keeps D-pad left and right for weapons.
  if which ~= 1 and F.on("weapon_switch") and F.items.weapon_dpad.v == 1 then return end
  if read_u32(p + G.P.STATE) == 23 or s32(read_u32(p + 1956)) ~= -1 then return end
  local ok = G.call(ctx, G.ACTION_PLAY, { p, TAUNT_ACTION + which, 0, 1, 0, 0, 0, MASK }, { 0.0, 1.0, -1.0 })
  log(string.format("taunt %d -> %s", which, (ok & 0xFF) ~= 0 and "played" or "refused"))
end

local function rain_now(ctx, p)
  if not on("money_rain") or p == 0 or not G.playing(p) or mp() then rain.last = nil return end
  local x, y, z = G.vec(p + G.P.POS)
  local vx, vz = 0, 0
  if rain.last then vx, vz = (x - rain.last[1]) * 50, (z - rain.last[3]) * 50 end
  rain.last = { x, y, z }
  if vx * vx + vz * vz > 400 then vx, vz = 0, 0 end   -- a teleport, not a walk
  rain.due = rain.due + F.items.money_rain_rate.v / 50
  local made = 0
  while rain.due >= 1 and made < 2 do
    rain.due = rain.due - 1
    made = made + 1
    local a, r = math.random() * 2 * math.pi, 1.5 + math.random() * 4
    local bx, bz = x + vx * 1.2 + math.cos(a) * r, z + vz * 1.2 + math.sin(a) * r
    local by = y + 4 + math.random() * 2
    local bill = F.items.money_rain_bill.v
    if bill <= 0 then bill = math.random(1, 50) * 10 end
    G.call(ctx, G.CASH_AT, { G.floats(ctx, { bx, by, bz }, 0), G.ROWS_ID, 0, 0, 255 }, bill)
  end
  if rain.due > 3 then rain.due = 3 end
end

local function rewards_now(ctx)
  if #reward_queue == 0 or F.tick % 10 ~= 0 or G.player() == 0 then return end
  if read_u32(UNLOCKS - 4) >= 7 then return end   -- the game's queue is full; it empties as it shows them
  local name = table.remove(reward_queue, 1)
  G.call(ctx, UNLOCK, { name_hash(ctx, name) })
  log("reward: " .. name .. " unlocked")
end

-- The First person row shows what First Person is doing (V switches it too),
-- once a request of ours has been taken (or given up on after 2 s).
local function first_person_row()
  local it = F.items.first_person
  if not fp_switchable() then it.v = false return end
  if fp_request_at then
    if read_u32(FP_SHARED + 8) ~= 0 and F.tick - fp_request_at < 100 then return end
    fp_request_at = nil
  end
  it.v = read_u32(FP_SHARED + 4) == 1
end

function E.after(ctx)
  first_person_row()
  local p = G.player()
  if p == 0 then stores.player = 0 end   -- a load in between: 24/7 stores go on again after it
  taunt_now(ctx, p)
  rain_now(ctx, p)
  rewards_now(ctx)
end

return E
