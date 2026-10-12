-- SR Tweak Menu - table part.
--
-- Edits the game's tables inside the player's own packfiles. The same tables
-- live in misc.vpp_xbox2 and misc2.vpp_xbox2, so both are patched.
--
--   vehicles.xtbl        Maximum_Speed, Maximum_Speed_With_Nitrous, Torque,
--                        Extra_Gravity, Max_Speed_Steering, Max_Hitpoints
--   weapons.xtbl         Refire_Delay, Trigger_Type, npc_refire_delay,
--                        Player_Spread_Min/Max, Magazine_Size, NPC_Damage,
--                        Ragdoll_Force_Shoot
--   camera_free.xtbl     crouch_damping, crouch_max_accel
--   metered_sprint.xtbl  UseTime, RechargeTime
--
-- Every number comes from [settings] in mod.ini.

local PACKS = { "misc.vpp_xbox2", "misc2.vpp_xbox2" }

local S = {
  uniform        = wml.setting("vehicle_uniform", false),
  uniform_speed  = wml.setting("vehicle_uniform_speed", 140),
  torque_per_kg  = wml.setting("vehicle_torque_per_kg", 0.45),
  reference      = wml.setting("vehicle_reference", "car_2dr_exoticsports01"),
  accel_mult     = wml.setting("vehicle_acceleration_multiplier", 1.0),
  nitro_all      = wml.setting("vehicle_nitrous_everywhere", true),
  shotgun_mult   = wml.setting("shotgun_fire_rate_multiplier", 2.0),
  npc_health     = wml.setting("npc_health_multiplier", 1),
  player_health  = wml.setting("player_health_multiplier", 3),
  knockdown      = wml.setting("player_knockdown_multiplier", 100),
  melee_impulse  = wml.setting("melee_impulse_multiplier", 1),
  fall_velocity  = wml.setting("panic_fall_velocity", 100),
  speed_mult     = wml.setting("vehicle_speed_multiplier", 1.0),
  speed_min      = wml.setting("vehicle_speed_min", 0),
  speed_max      = wml.setting("vehicle_speed_max", 0),
  torque_mult    = wml.setting("vehicle_torque_multiplier", 1.0),
  extra_gravity  = wml.setting("vehicle_extra_gravity", 5),
  scale_steering = wml.setting("vehicle_scale_steering", true),
  fire_mult      = wml.setting("fire_rate_multiplier", 2.0),
  fire_min       = wml.setting("fire_delay_min", 40),
  full_auto      = wml.setting("full_auto", false),
  npc_fire       = wml.setting("npc_fire_rate", false),
  spread_mult    = wml.setting("spread_multiplier", 0.05),
  min_magazine   = wml.setting("min_magazine", 8),
  damage_mult    = wml.setting("damage_multiplier", 1),
  force_mult     = wml.setting("ragdoll_force_multiplier", 3),
  hitpoints_mult = wml.setting("vehicle_hitpoints_multiplier", 1),
  crouch_mult    = wml.setting("crouch_speed_multiplier", 3.0),
  sprint_length  = wml.setting("sprint_length_multiplier", 2.0),
  sprint_recharge= wml.setting("sprint_recharge_multiplier", 0.5),
  debug          = wml.setting("debug", false),
}

local function fmt(x)
  if x == math.floor(x) then return string.format("%d", x) end
  return (string.format("%.3f", x):gsub("0+$", ""):gsub("%.$", ""))
end

local function debug(...) if S.debug then wml.log(...) end end

-- Replaces the number inside every <tag>...</tag> in `xml` with f(value).
-- Returns the new text and how many values changed.
local function map_tag(xml, tag, f)
  local n = 0
  xml = xml:gsub("(<" .. tag .. ">)%s*(%-?[%d%.]+)%s*(</" .. tag .. ">)", function(open, value, close)
    local v = tonumber(value)
    if not v then return nil end
    local new = f(v)
    if new == nil or new == v then return nil end
    n = n + 1
    return open .. fmt(new) .. close
  end)
  return xml, n
end

-- Applies f to each <block>...</block> element in the <Table> section only,
-- leaving the <TableDescription> (which reuses the same tag names) alone.
local function map_blocks(xml, block, f)
  local table_end = xml:find("</Table>", 1, true) or #xml
  local head, tail = xml:sub(1, table_end - 1), xml:sub(table_end)
  head = head:gsub("<" .. block .. ">.-</" .. block .. ">", f)
  return head .. tail
end

-- ---------------------------------------------------------------- vehicles

local function speed(v)
  v = v * S.speed_mult
  if S.speed_min > 0 then v = math.max(v, S.speed_min) end
  if S.speed_max > 0 then v = math.min(v, S.speed_max) end
  return math.floor(v + 0.5)
end

-- The reference car's engine and transmission blocks, copied into every
-- vehicle in uniform mode so they all pull away alike. The top-level
-- <Engine> block is the one that starts with <Torque> or <Nitro_Capable>;
-- the <Engine> inside <Foley> is a sound name and is left alone.
local ENGINE_PATTERN = "<Engine>(%s*<[NT][a-z_A-Z]*>.-)</Engine>"
local function reference_blocks(xml)
  local ref
  for block in xml:gmatch("<Vehicle>.-</Vehicle>") do
    if block:find("<Name>" .. S.reference .. "</Name>", 1, true) then ref = block break end
  end
  if not ref then return nil end
  local engine = ref:match(ENGINE_PATTERN)
  local transmission = ref:match("<Transmission>(.-)</Transmission>")
  local mass = tonumber(ref:match("<Mass>%s*([%d%.]+)%s*</Mass>"))
  local torque = engine and tonumber(engine:match("<Torque>%s*([%d%.]+)%s*</Torque>"))
  if not (engine and transmission and mass and torque) then return nil end
  return { engine = engine, transmission = transmission, mass = mass, torque = torque }
end

local function patch_vehicles(xml)
  local changed = 0
  local ref = S.uniform and reference_blocks(xml) or nil
  if S.uniform and not ref then wml.log("vehicle_reference '" .. S.reference .. "' not found; using torque per kg instead") end
  xml = map_blocks(xml, "Vehicle", function(block)
    local n
    if S.uniform then
      -- Every vehicle gets the same top speed, and the reference car's
      -- engine and gearbox, with torque scaled by mass so a heavy car pulls
      -- away like the light one.
      local target = S.uniform_speed
      block, n = map_tag(block, "Maximum_Speed", function() return target end); changed = changed + n
      block, n = map_tag(block, "Maximum_Speed_With_Nitrous", function() return math.floor(target * 1.15 + 0.5) end); changed = changed + n
      local mass = tonumber(block:match("<Mass>%s*([%d%.]+)%s*</Mass>"))
      local special = block:match("<Special_Vehicle_Type>%s*(%a+)%s*</Special_Vehicle_Type>")
      local ordinary = (special == nil or special == "None") and not block:find("<Name>sp_eltrain", 1, true)
      if ref and mass and ordinary and block:find(ENGINE_PATTERN) and block:find("<Transmission>", 1, true) then
        local torque = math.floor(ref.torque * (mass / ref.mass) * S.accel_mult + 0.5)
        local engine = ref.engine:gsub("<Torque>%s*[%d%.]+%s*</Torque>", "<Torque>" .. torque .. "</Torque>")
        if S.nitro_all then engine = engine:gsub("<Nitro_Capable>%s*%a+%s*</Nitro_Capable>", "<Nitro_Capable>true</Nitro_Capable>") end
        block = block:gsub(ENGINE_PATTERN, function() return "<Engine>" .. engine .. "</Engine>" end, 1)
        block = block:gsub("<Transmission>.-</Transmission>", function() return "<Transmission>" .. ref.transmission .. "</Transmission>" end, 1)
        changed = changed + 2
      elseif mass and S.torque_per_kg > 0 then
        block, n = map_tag(block, "Torque", function() return math.floor(mass * S.torque_per_kg * S.accel_mult + 0.5) end); changed = changed + n
      end
      if S.scale_steering then
        block, n = map_tag(block, "Max_Speed_Steering", function() return math.floor(target * 0.5 + 0.5) end); changed = changed + n
      end
    else
      block, n = map_tag(block, "Maximum_Speed", speed); changed = changed + n
      block, n = map_tag(block, "Maximum_Speed_With_Nitrous", speed); changed = changed + n
      if S.torque_mult ~= 1 then
        block, n = map_tag(block, "Torque", function(v) return v * S.torque_mult end); changed = changed + n
      end
      if S.scale_steering and S.speed_mult ~= 1 then
        block, n = map_tag(block, "Max_Speed_Steering", function(v) return v * S.speed_mult end); changed = changed + n
      end
      if S.nitro_all and not block:find("<Name>sp_eltrain", 1, true) then
        -- Nitrous (Shift) in every car, so a random car off the street has it too.
        local c
        block, c = block:gsub("<Nitro_Capable>%s*false%s*</Nitro_Capable>", "<Nitro_Capable>true</Nitro_Capable>")
        changed = changed + c
      end
    end
    if S.extra_gravity ~= 0 then
      -- Negative values pull the car down (the game uses -20 on most cars).
      block, n = map_tag(block, "Extra_Gravity", function(v) return v - S.extra_gravity end); changed = changed + n
    end
    if S.hitpoints_mult ~= 1 then
      if not block:find("<Max_Hitpoints>", 1, true) then
        block = block:gsub("(<Name>[^<]*</Name>)", "%1\n\t\t<Max_Hitpoints>5000</Max_Hitpoints>", 1)
      end
      block, n = map_tag(block, "Max_Hitpoints", function(v) return v * S.hitpoints_mult end); changed = changed + n
    end
    return block
  end)
  return xml, changed
end

-- ----------------------------------------------------------------- weapons

local function patch_weapons(xml)
  local changed = 0
  xml = map_blocks(xml, "Weapon", function(block)
    local n
    if S.damage_mult ~= 1 then
      -- Damage the player's weapons do to others (guns and melee alike).
      -- <Player_Damage> is what the same weapon does to the player; untouched.
      block, n = map_tag(block, "NPC_Damage", function(v) return v * S.damage_mult end); changed = changed + n
    end
    if S.force_mult ~= 1 then
      block, n = map_tag(block, "Ragdoll_Force_Shoot", function(v) return v * S.force_mult end); changed = changed + n
    end
    local delay = tonumber(block:match("<Refire_Delay>%s*([%d%.]+)%s*</Refire_Delay>"))
    if not delay or delay <= 0 then return block end  -- melee, thrown, props
    local mult = S.fire_mult
    if block:find("<Weapon_Class>shotgun</Weapon_Class>", 1, true) then mult = mult * S.shotgun_mult end
    block, n = map_tag(block, "Refire_Delay", function(v)
      return math.max(S.fire_min, math.floor(v / mult + 0.5))
    end); changed = changed + n
    if S.min_magazine > 0 then
      -- One-shot and small-magazine guns (RPG, shotguns, revolvers) reload
      -- after every shot or two, which defeats a faster fire rate.
      block, n = map_tag(block, "Magazine_Size", function(v) return math.max(v, S.min_magazine) end); changed = changed + n
    end
    if S.npc_fire then
      block, n = map_tag(block, "npc_refire_delay", function(v)
        return math.max(S.fire_min, math.floor(v / S.fire_mult + 0.5))
      end); changed = changed + n
    end
    if S.spread_mult ~= 1 then
      -- Only the player's spread; the <NPCWeaponSpread> block keeps its values.
      block = block:gsub("<PlayerWeaponSpread>.-</PlayerWeaponSpread>", function(section)
        local n
        section, n = map_tag(section, "Player_Spread_Max", function(v) return v * S.spread_mult end); changed = changed + n
        section, n = map_tag(section, "Player_Spread_Min", function(v) return v * S.spread_mult end); changed = changed + n
        return section
      end)
    end
    if S.full_auto then
      local c
      block, c = block:gsub("<Trigger_Type>single</Trigger_Type>", "<Trigger_Type>burst</Trigger_Type>")
      changed = changed + c
    end
    return block
  end)
  return xml, changed
end

-- -------------------------------------------------------------- NPC health

-- spawn_info_ranks.xtbl: hit points per rank. The Player is a rank here
-- too (1000 hit points), and so are the homies; only enemies and civilians
-- get the NPC multiplier, the player gets their own.
local function patch_ranks(xml)
  local changed = 0
  xml = map_blocks(xml, "Rank", function(block)
    local name = block:match("<Name>%s*([^<]-)%s*</Name>") or ""
    local mult
    if name == "Player" then mult = S.player_health
    elseif name:find("^Homie") then mult = 1
    else mult = S.npc_health end
    if mult == 1 then return block end
    local n
    block, n = map_tag(block, "Hit_Points", function(v) return math.max(1, math.floor(v * mult + 0.5)) end); changed = changed + n
    if name == "Player" then
      -- Damage needed to knock the player down: effectively never.
      block, n = map_tag(block, "Knockdown_Points", function(v) return math.floor(v * S.knockdown + 0.5) end); changed = changed + n
      -- The player's own melee strength.
      block, n = map_tag(block, "Melee_Damage_Modifier", function(v) return v * S.damage_mult end); changed = changed + n
    end
    return block
  end)
  return xml, changed
end

-- gameplay_constants.xtbl: how hard melee hits fling people.
local function patch_constants(xml)
  local changed, n = 0
  if S.melee_impulse ~= 1 then
    -- Global: applies to hits on the player as well, so keep it at 1 unless asked.
    xml, n = map_tag(xml, "Ragdoll_Melee_Impulse_Multiplier", function(v) return v * S.melee_impulse end); changed = changed + n
  end
  if S.fall_velocity > 0 then
    -- Falling faster than this (m/s) makes the player flail and ragdoll.
    xml, n = map_tag(xml, "panic_fall_velocity", function() return S.fall_velocity end); changed = changed + n
  end
  return xml, changed
end

-- ------------------------------------------------------------------ crouch

local function patch_camera(xml)
  if S.crouch_mult == 1 then return xml, 0 end
  local changed, n = 0
  xml, n = map_tag(xml, "crouch_damping", function(v) return math.min(1, v * S.crouch_mult) end); changed = changed + n
  xml, n = map_tag(xml, "crouch_max_accel", function(v) return v * S.crouch_mult end); changed = changed + n
  return xml, changed
end

-- ------------------------------------------------------------------ sprint

local function patch_sprint(xml)
  local changed = 0
  xml = map_blocks(xml, "SprintEntry", function(block)
    if not block:find("<Name>Single Player</Name>", 1, true) then return block end
    local n
    block, n = map_tag(block, "UseTime", function(v)
      if S.sprint_length <= 0 then return 100000 end
      return v * S.sprint_length
    end); changed = changed + n
    block, n = map_tag(block, "RechargeTime", function(v) return v * S.sprint_recharge end); changed = changed + n
    return block
  end)
  return xml, changed
end

-- -------------------------------------------------------------------- main

local FILES = {
  { "vehicles.xtbl",       patch_vehicles },
  { "weapons.xtbl",        patch_weapons },
  { "spawn_info_ranks.xtbl", patch_ranks },
  { "gameplay_constants.xtbl", patch_constants },
  { "camera_free.xtbl",    patch_camera },
  { "metered_sprint.xtbl", patch_sprint },
}

for _, pack in ipairs(PACKS) do
  for _, entry in ipairs(FILES) do
    local name, patch = entry[1], entry[2]
    local xml = wml.packfile_read(pack, name)
    if xml then
      local new, changed = patch(xml)
      if changed > 0 then
        wml.packfile_write(pack, name, new)
        wml.log(pack .. ": " .. name .. " - " .. changed .. " values changed")
      else
        debug(pack .. ": " .. name .. " - nothing to change")
      end
    else
      debug(pack .. ": " .. name .. " not found")
    end
  end
end
