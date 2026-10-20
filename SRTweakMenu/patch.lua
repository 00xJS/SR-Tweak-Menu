-- SR Tweak Menu - table part.
--
-- Edits the game's tables inside the player's own packfiles. The same tables
-- live in misc.vpp_xbox2 and misc2.vpp_xbox2, so both are patched.
--
--   vehicles.xtbl          Nitro_Capable (every car can take nitrous; the
--                          menu decides who may use it), and the optional
--                          speed, torque and hitpoint settings
--   weapons.xtbl           NPC_Damage, Trigger_Type (optional settings)
--   spawn_info_ranks.xtbl  enemies' Hit_Points (optional setting)
--   gameplay_constants     Ragdoll_Melee_Impulse_Multiplier (optional)
--   GML_CUST.xtbl          adds the empty SRT_Player animation set the
--                          Movement style menu gives the player
--
-- Every number comes from [settings] in mod.ini; at their defaults only
-- Nitro_Capable changes. Everything else is switched live in the menu.

local PACKS = { "misc.vpp_xbox2", "misc2.vpp_xbox2" }

local S = {
  uniform        = wml.setting("vehicle_uniform", false),
  uniform_speed  = wml.setting("vehicle_uniform_speed", 140),
  torque_per_kg  = wml.setting("vehicle_torque_per_kg", 0.45),
  reference      = wml.setting("vehicle_reference", "car_2dr_exoticsports01"),
  accel_mult     = wml.setting("vehicle_acceleration_multiplier", 1.0),
  nitro_all      = true,
  npc_health     = wml.setting("npc_health_multiplier", 1),
  melee_impulse  = wml.setting("melee_impulse_multiplier", 1),
  speed_mult     = wml.setting("vehicle_speed_multiplier", 1.0),
  speed_min      = wml.setting("vehicle_speed_min", 0),
  speed_max      = wml.setting("vehicle_speed_max", 0),
  torque_mult    = wml.setting("vehicle_torque_multiplier", 1.0),
  scale_steering = wml.setting("vehicle_scale_steering", true),
  full_auto      = wml.setting("full_auto", false),
  damage_mult    = wml.setting("damage_multiplier", 1),
  hitpoints_mult = wml.setting("vehicle_hitpoints_multiplier", 1),
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
    local n
    if name == "Player" then
      if S.damage_mult == 1 then return block end
      -- The player's own melee strength.
      block, n = map_tag(block, "Melee_Damage_Modifier", function(v) return v * S.damage_mult end); changed = changed + n
      return block
    end
    if name:find("^Homie") or S.npc_health == 1 then return block end
    block, n = map_tag(block, "Hit_Points", function(v) return math.max(1, math.floor(v * S.npc_health + 0.5)) end); changed = changed + n
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
  return xml, changed
end

-- GML_CUST.xtbl (one of the animation set files): one more, empty set,
-- SRT_Player, which only the player is given while a Movement style is
-- chosen. It has no animations of its own, so the menu can tell the
-- player's lookups from everyone else's and answer them from the chosen
-- style (features.lua). Its parent is the player's normal set, GML1, so
-- with the menu off it animates exactly like the game's own player.
local PLAYER_SET = [[
	<Skeleton_Set>
		<Parent_Skeleton>GML1</Parent_Skeleton>
		<Name>SRT_Player</Name>
		<Groups>
			<Group>
				<group>Default</group>
				<States></States>
				<Actions></Actions>
				</Group>
			</Groups>
		<_Editor>
			<Category>Entries</Category>
			</_Editor>
		</Skeleton_Set>
]]
local function patch_anim_sets(xml)
  if xml:find("<Name>SRT_Player</Name>", 1, true) then return xml, 0 end
  local at = xml:find("</Table>", 1, true)
  if not at then return xml, 0 end
  -- Back to the start of the line holding </Table>.
  local line = at
  while line > 1 and xml:sub(line - 1, line - 1) ~= "\n" do line = line - 1 end
  return xml:sub(1, line - 1) .. PLAYER_SET .. xml:sub(line), 1
end

-- ---------------------------------------------------------- HUD images
--
-- New pictures in cells of the HUD sheets the game leaves empty, so every
-- existing picture keeps its place. hud_sheet_11 (the homie heads): No
-- Render heads (her / him) for homies without a head picture and a yellow
-- minimap dot for Vice Kings on your side. hud_sheet_10: heads for gang
-- members you recruit (Vice Kings, Los Carnales, Rollerz; his and hers) and
-- the co-op player's logo. hud_images.bin holds the compressed 4x4 blocks
-- (built by build_heads_patch.py from the sheets themselves).
local HUD_IMAGES = {
  { "hud_sheet_11", "recruit_norender_f", 128, 448, 64, 64 },
  { "hud_sheet_11", "recruit_norender_m", 192, 448, 64, 64 },
  { "hud_sheet_11", "map_other_blip_yellow", 192, 0, 48, 48 },
  { "hud_sheet_10", "recruit_vicekingz_m", 256, 320, 64, 64 },
  { "hud_sheet_10", "recruit_vicekingz_f", 320, 320, 64, 64 },
  { "hud_sheet_10", "recruit_carnales_m", 384, 320, 64, 64 },
  { "hud_sheet_10", "recruit_carnales_f", 448, 320, 64, 64 },
  { "hud_sheet_10", "recruit_wrollerz_m", 256, 384, 64, 64 },
  { "hud_sheet_10", "recruit_wrollerz_f", 320, 384, 64, 64 },
  { "hud_sheet_10", "recruit_coop_player", 384, 384, 64, 64 },
}
local function patch_hud_sheets(peg)
  local file = io.open(wml.mod_folder .. "/hud_images.bin", "rb")
  if not file then return peg, 0 end
  local bin = file:read("*a"); file:close()
  if bin:sub(1, 4) ~= "SRT2" then return peg, 0 end
  -- Where each sheet's data starts in the peg, and its size and format.
  local sheets = {}
  local n = string.unpack(">I2", peg, 0x10 + 1)
  for j = 0, n - 1 do
    local e = 0x18 + j * 0x48
    local off, w, h, fmt = string.unpack(">I4I2I2I2", peg, e + 1)
    local name = peg:sub(e + 0x16 + 1, e + 0x46):match("^[\1-\31]*([^%z]*)")
    if name then sheets[name:lower():gsub("%.tga$", "")] = { off, w, h, fmt } end
  end
  local recs, total = {}, 0
  local at = 9
  for _ = 1, string.unpack(">I4", bin, 5) do
    local sheet = bin:sub(at, at + 15):match("^[^%z]*")
    local w, h, count = string.unpack(">I2I2I4", bin, at + 16)
    at = at + 24
    local s = sheets[sheet]
    if s and s[2] == w and s[3] == h and s[4] == 0x191 then
      for i = 0, count - 1 do
        local base = at + i * 20
        recs[#recs + 1] = { s[1] + string.unpack(">I4", bin, base), bin:sub(base + 4, base + 19) }
      end
      total = total + count
    else
      wml.log("HUD images: " .. sheet .. " isn't the expected " .. w .. "x" .. h .. " DXT3; left alone")
    end
    at = at + count * 20
  end
  if total == 0 then return peg, 0 end
  table.sort(recs, function(a, b) return a[1] < b[1] end)
  local parts, from = {}, 1
  for _, r in ipairs(recs) do
    parts[#parts + 1] = peg:sub(from, r[1])
    parts[#parts + 1] = r[2]
    from = r[1] + 17
  end
  parts[#parts + 1] = peg:sub(from)
  return table.concat(parts), total
end

local function patch_bitmap_sheets(xml)
  local added = 0
  for _, im in ipairs(HUD_IMAGES) do
    local s = xml:find("<Name>" .. im[1] .. "</Name>", 1, true)
    local e = s and xml:find("</Images>", s, true)
    if e and not xml:sub(s, e):find("<Name>" .. im[2] .. "</Name>", 1, true) then
      local add = string.format("\t\t\t<Properties>32<Name>%s</Name>\n\t\t\t\t<StartX>%d</StartX>\n\t\t\t\t<StartY>%d</StartY>\n" ..
        "\t\t\t\t<ImageWidth>%d</ImageWidth>\n\t\t\t\t<ImageHeight>%d</ImageHeight>\n\t\t\t\t</Properties>\n", im[2], im[3], im[4], im[5], im[6])
      local line = e
      while line > 1 and xml:sub(line - 1, line - 1) ~= "\n" do line = line - 1 end
      xml = xml:sub(1, line - 1) .. add .. xml:sub(line)
      added = added + 1
    end
  end
  return xml, added
end
do
  local peg = wml.packfile_read("pegfiles.vpp_xbox2", "interface-backend.peg_xbox2")
  if peg then
    local new, n = patch_hud_sheets(peg)
    if n > 0 then
      wml.packfile_write("pegfiles.vpp_xbox2", "interface-backend.peg_xbox2", new)
      wml.log("pegfiles.vpp_xbox2: interface-backend.peg_xbox2 - " .. n .. " blocks of new HUD pictures")
    end
  end
end

-- -------------------------------------------------------------------- main

local FILES = {
  { "vehicles.xtbl",       patch_vehicles },
  { "weapons.xtbl",        patch_weapons },
  { "spawn_info_ranks.xtbl", patch_ranks },
  { "gameplay_constants.xtbl", patch_constants },
  { "GML_CUST.xtbl",       patch_anim_sets },
  { "bitmap_sheets.xtbl",  patch_bitmap_sheets },
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
