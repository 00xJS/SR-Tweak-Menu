-- SR Tweak Menu - table part.
--
-- Edits the game's tables inside the player's own packfiles. The same tables
-- live in misc.vpp_xbox2 and misc2.vpp_xbox2, so both are patched.
--
--   vehicles.xtbl          Nitro_Capable (every car can take nitrous, only
--                          with Nitrous in every vehicle on), and the optional
--                          speed, torque and hitpoint settings
--   weapons.xtbl           NPC_Damage, Trigger_Type (optional settings)
--   spawn_info_ranks.xtbl  enemies' Hit_Points (optional setting)
--   gameplay_constants     Ragdoll_Melee_Impulse_Multiplier (optional)
--   GML_CUST.xtbl          adds the empty SRT_Player animation set the
--                          Movement style menu gives the player
--   unlockables.xtbl       adds the srt_* rewards Settings > Unlocks can
--                          give (free shopping, bulletproof ...); nothing
--                          has them until you pick one
--
-- Every number comes from [settings] in mod.ini; at their defaults nothing
-- changes. Everything else is switched live in the menu.

local PACKS = { "misc.vpp_xbox2", "misc2.vpp_xbox2" }

-- The clothing rows (Customize > Clothing mods) are start-up rows: the menu
-- saves them to saved_tweaks.ini straight away, and that wins over mod.ini.
local saved_tweaks = {}
do
  local f = io.open(wml.mod_folder .. "/saved_tweaks.ini", "r")
  if f then
    for line in f:lines() do
      local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
      if k and not line:match("^%s*;") then saved_tweaks[k] = v end
    end
    f:close()
  end
end
local function startup(key, default)
  local v = saved_tweaks[key]
  if v == "true" then return true elseif v == "false" then return false end
  if key == "work_boots" and v then
    return ({ ["Off"] = "off", ["Own shoe"] = "duplicate", ["Replace Hiking Boots"] = "replace" })[v] or default
  end
  return wml.setting(key, default)
end

local S = {
  uniform        = wml.setting("vehicle_uniform", false),
  uniform_speed  = wml.setting("vehicle_uniform_speed", 140),
  torque_per_kg  = wml.setting("vehicle_torque_per_kg", 0.45),
  reference      = wml.setting("vehicle_reference", "car_2dr_exoticsports01"),
  accel_mult     = wml.setting("vehicle_acceleration_multiplier", 1.0),
  nitro_all      = startup("nitro_all", wml.setting("vehicle_nitrous_everywhere", false)),
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
  { "hud_sheet_10", "srt_slate_digits", 384, 448, 128, 64 },
  { "hud_sheet_10", "srt_ammo_0", 192, 224, 24, 32 },
  { "hud_sheet_10", "srt_ammo_1", 192, 256, 24, 32 },
  { "hud_sheet_10", "srt_ammo_2", 132, 360, 24, 32 },
  { "hud_sheet_10", "srt_ammo_3", 156, 360, 24, 32 },
  { "hud_sheet_10", "srt_ammo_4", 180, 360, 24, 32 },
  { "hud_sheet_10", "srt_ammo_5", 204, 360, 24, 32 },
  { "hud_sheet_10", "srt_ammo_6", 228, 360, 24, 32 },
  { "hud_sheet_10", "srt_ammo_7", 96, 364, 24, 32 },
  { "hud_sheet_10", "srt_ammo_8", 224, 392, 24, 32 },
  { "hud_sheet_10", "srt_ammo_9", 224, 424, 24, 32 },
  { "hud_sheet_08", "srt_reserve_0", 452, 0, 24, 32 },
  { "hud_sheet_08", "srt_reserve_1", 452, 32, 24, 32 },
  { "hud_sheet_08", "srt_reserve_2", 452, 64, 24, 32 },
  { "hud_sheet_08", "srt_reserve_3", 476, 84, 24, 32 },
  { "hud_sheet_08", "srt_reserve_4", 452, 96, 24, 32 },
  { "hud_sheet_08", "srt_reserve_5", 476, 116, 24, 32 },
  { "hud_sheet_08", "srt_reserve_6", 452, 128, 24, 32 },
  { "hud_sheet_08", "srt_reserve_7", 476, 148, 24, 32 },
  { "hud_sheet_08", "srt_reserve_8", 452, 160, 24, 32 },
  { "hud_sheet_08", "srt_reserve_9", 476, 180, 24, 32 },
  { "hud_sheet_08", "srt_brush_left", 320, 384, 64, 64 },
  { "hud_sheet_08", "srt_respect_0", 456, 216, 32, 32 },
  { "hud_sheet_08", "srt_respect_1", 456, 256, 32, 32 },
  { "hud_sheet_08", "srt_respect_2", 456, 296, 32, 32 },
  { "hud_sheet_08", "srt_respect_3", 456, 336, 32, 32 },
  { "hud_sheet_10", "srt_brush_right", 448, 384, 64, 64 },
}
local function patch_hud_sheets(peg, filename)
  local file = io.open(wml.mod_folder .. "/" .. filename, "rb")
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
    local new, n = patch_hud_sheets(peg, "hud_images.bin")
    local polished, more = patch_hud_sheets(new, "hud_polish.bin")
    new, n = polished, n + more
    if n > 0 then
      wml.packfile_write("pegfiles.vpp_xbox2", "interface-backend.peg_xbox2", new)
      wml.log("pegfiles.vpp_xbox2: interface-backend.peg_xbox2 - " .. n .. " blocks of new HUD pictures")
    end
  end
end

-- ------------------------------------------------------------- rewards
--
-- New rewards for Settings > Unlocks (extras.lua), each a copy of one of
-- the game's own rows of the same kind with its name and amount changed:
-- { new name, row copied, amount, store for a discount }. A discount of 1
-- is everything free; a damage reward of 100 is all of that damage gone;
-- a notoriety reward is how much faster it fades (the game's own give 5).
local REWARDS = {
  { "srt_free_impressions", "all_hitman1", "1.0", "Impressions" },
  { "srt_free_foreign_power", "all_hitman1", "1.0", "Foreign Power" },
  { "srt_free_friendly_fire", "all_hitman1", "1.0", "Friendly Fire" },
  { "srt_free_on_thin_ice", "all_hitman1", "1.0", "On Thin Ice" },
  { "srt_free_on_the_rag", "all_hitman1", "1.0", "On the Rag" },
  { "srt_free_rim_jobs", "all_hitman1", "1.0", "Rim Jobs" },
  { "srt_free_sloppy_seconds", "all_hitman1", "1.0", "Sloppy Seconds" },
  { "srt_free_branded", "all_hitman1", "1.0", "Branded" },
  { "srt_bulletproof", "vk_fraud", "100" },
  { "srt_blastproof", "wr_fraud", "100" },
  { "srt_crashproof", "lc_fraud", "100" },
  { "srt_police_forget", "all_drug", "100" },
  { "srt_carnales_forget", "lc_drug", "100" },
  { "srt_vice_kings_forget", "vk_drug", "100" },
  { "srt_rollerz_forget", "wr_drug1", "100" },
}
local function plain(s) return (s:gsub("[%%%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")) end
local function patch_unlockables(xml)
  if xml:find("<Name>srt_", 1, true) then return xml, 0 end
  local nl = xml:find("\r\n", 1, true) and "\r\n" or "\n"
  local rows = {}
  for _, r in ipairs(REWARDS) do
    local at = xml:find("<Name>" .. r[2] .. "</Name>", 1, true)
    local first, last = nil, nil
    if at then
      local s = 1
      while true do
        local f = xml:find("<Unlockable>", s, true)
        if not f or f > at then break end
        first, s = f, f + 1
      end
      local _, e = xml:find("</Unlockable>", at, true)
      last = e
    end
    if first and last then
      local row = xml:sub(first, last)
      row = row:gsub("<Name>" .. plain(r[2]) .. "</Name>", "<Name>" .. r[1] .. "</Name>", 1)
      row = row:gsub("<Amount>[^<]*</Amount>", "<Amount>" .. r[3] .. "</Amount>", 1)
      if r[4] then row = row:gsub("(<Discount>%s*<Name>)[^<]*(</Name>)", "%1" .. r[4]:gsub("%%", "%%%%") .. "%2", 1) end
      rows[#rows + 1] = "\t" .. row .. nl
    else
      wml.log("unlockables.xtbl: no row " .. r[2] .. " to copy for " .. r[1])
    end
  end
  local close = xml:find("\t</Table>", 1, true)
  if not close or #rows == 0 then return xml, 0 end
  return xml:sub(1, close - 1) .. table.concat(rows) .. xml:sub(close), #rows
end

-- -------------------------------------------------------------------- main

local FILES = {
  { "vehicles.xtbl",       patch_vehicles },
  { "weapons.xtbl",        patch_weapons },
  { "spawn_info_ranks.xtbl", patch_ranks },
  { "gameplay_constants.xtbl", patch_constants },
  { "unlockables.xtbl",    patch_unlockables },
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

-- Juiced bank startup replacement withdrawn in 1.9.26: save-load recovery.

-- Medium Parted 02 (Saints Row 2) in place of Flat Top, Lightning. WML only
-- replaces files a pack already has, and the game wears a piece only if
-- player_cust.xtbl lists its mesh and variant - so the SR2 hair goes into
-- Flat Top B's own files (its mesh, texture and both morphs, in the mesh and
-- morph streams) and keeps that item's ids. sr2_hair in mod.ini.
do
  local folder=wml.mod_folder.."/hair_port/"
  local function file(name)
    local f=io.open(folder..name,"rb");local d=f and f:read("a");if f then f:close() end;return d
  end
  local files={
    {"cmesh_stream.vpp_xbox2","htop_flattopb.cmesh_xbox2","htop_sr2partedm02.cmesh_xbox2"},
    {"cmesh_stream.vpp_xbox2","htop_flattopb.peg_xbox2","htop_sr2partedm02.peg_xbox2"},
    {"cmesh_stream.vpp_xbox2","htop_flattopb_pc.morph_xbox2","htop_sr2partedm02_pc.morph_xbox2"},
    {"morph_stream.vpp_xbox2","htop_flattopb_pc.morph_xbox2","htop_sr2partedm02_pc.morph_xbox2"},
    {"morph_stream.vpp_xbox2","htop_flattopb_car_pc.morph_xbox2","htop_sr2partedm02_car_pc.morph_xbox2"},
  }
  local ready=true
  for _,f in ipairs(files) do f[4]=file(f[3]);ready=ready and f[4]~=nil end
  if startup("sr2_hair",false) and ready then
    local ok,err=pcall(function() for _,f in ipairs(files) do wml.packfile_write(f[1],f[2],f[4]) end end)
    wml.log(ok and "Medium Parted 02: in place of Flat Top, Lightning" or ("Medium Parted 02: "..tostring(err)))
  end
end

-- Names shown in the game (US_Strings.txt: UTF-16, KEY=Text per line, then
-- the number of entries). Only existing keys get new text, so the count
-- stays right - a line added after it broke every string in the game.
do
  local names={}
  if startup("sr2_hair",false) then names.CUST_ITEM_FLAT_TOP_DESIGN_A="Medium Parted" end
  if startup("playa_choice",false) then names.CUST_ITEM_SHIRT_AZZURE="Cropped Football Jersey" end
  local function utf16(s) return (s:gsub(".","%0\0")) end
  for _,pack in ipairs({"misc.vpp_xbox2","misc2.vpp_xbox2"}) do
    local text=wml.packfile_read(pack,"US_Strings.txt")
    if text then
      local changed=0
      for key,value in pairs(names) do
        local s=text:find(utf16("\r\n"..key.."="),1,true)
        local e=s and text:find(utf16("\r\n"),s+4,true)
        if e then text=text:sub(1,s-1)..utf16("\r\n"..key.."="..value)..text:sub(e);changed=changed+1 end
      end
      if changed>0 then wml.packfile_write(pack,"US_Strings.txt",text);wml.log(pack..": "..changed.." names changed") end
    end
  end
end

-- Playa Choice by CommyGT (saintsrowmods.com, "SR1 - Playa Choice"), its
-- clothing only: the necklace fixes (Sleeveless Henley, Hensley, Roundneck
-- Pullover), cropping and untucked undershirts, the Parted Afro at Do It Up,
-- the Light Silver Braided Belt, the Cross Pendant and MP chains, and every
-- unlockable in the stores. Prices and respect stay the game's own (its
-- respect and economy changes are left out). playa_choice in mod.ini.
do
  local folder=wml.mod_folder.."/playa_choice/"
  local function file(name)
    local f=io.open(folder..name,"rb");local d=f and f:read("a");if f then f:close() end;return d
  end

  local items,stores=file("items.xml"),file("customization_stores.xtbl")
  if startup("playa_choice",false) and items and stores then
    for _,name in ipairs({"misc.vpp_xbox2","misc2.vpp_xbox2"}) do
      local xml=wml.packfile_read(name,"customization_items.xtbl")
      if xml and not xml:find("<!-- playa choice -->",1,true) then
        local n=0
        for block in items:gmatch("<Customization_Item>.-</Customization_Item>") do
          local item=block:match("<Name>([^<]*)</Name>")
          local s=xml:find("<Customization_Item>%s*<Name>"..item:gsub("%p","%%%0").."</Name>")
          local e=s and xml:find("</Customization_Item>",s,true)
          if e then xml=xml:sub(1,s-1)..block..xml:sub(e+#"</Customization_Item>");n=n+1 end
        end
        -- The Parted Afro (cut, never sold) takes Frohawk, Striped's place: its
        -- meshes and name on that item. The pair the game wears by must be one
        -- player_cust.xtbl lists - (variant 36, mesh 119) for the afro and
        -- (36, 132) for its hat version - and the Frohawk's variant is 36.
        local fs=xml:find("<Customization_Item>%s*<Name>curley mohawk, striped sides</Name>")
        local fe=fs and xml:find("</Customization_Item>",fs,true)
        if fe then
          local row=xml:sub(fs,fe-1)
          row=row:gsub("CUST_ITEM_CURLY_MOHAWK_STRIPED_SIDES","CUST_ITEM_PARTED_AFRO",1)
          row=row:gsub("hTop_fuzzyMowhawkC%.cmeshx","htop_partedafro.cmeshx",1):gsub("<MeshID>123</MeshID>","<MeshID>119</MeshID>",1)
          row=row:gsub("hTop_flatmoC%.cmeshx","hTop_flatAfro.cmeshx",1):gsub("<MeshID>142</MeshID>","<MeshID>132</MeshID>",1)
          xml=xml:sub(1,fs-1)..row..xml:sub(fe)
          n=n+1
        end
        wml.packfile_write(name,"customization_items.xtbl",(xml:gsub("</Table>","<!-- playa choice -->\n</Table>",1)))
        wml.packfile_write(name,"customization_stores.xtbl",stores)
        wml.log(name..": Playa Choice clothing - "..n.." items updated (Frohawk, Striped is the Parted Afro), stores")
      end
    end
  end
end

-- Ultor Unlimited Work Boots: the Timberland boots (saintsrowmods.com,
-- "Timberland Boots" for Saints Row 1) as a shoe of their own beside the
-- Hiking Boots. work_boots in mod.ini:
--   duplicate  a new item, Ultor Unlimited Work Boots. WML only replaces
--              files a pack already has, so the boots go into the game's
--              own unused Timberland boots (cshoe_timberland, which no item
--              wears), plus a store entry and its name
--   replace    the Hiking Boots look like them (the stock files replaced)
--   off        nothing
do
  local mode=tostring(startup("work_boots","off")):lower()
  local folder=wml.mod_folder.."/work_boots/"
  local STREAM="cmesh_stream.vpp_xbox2"
  local function read(name)
    local f=io.open(folder.."cshoe_timberland"..name,"rb")
    local d=f and f:read("a");if f then f:close() end
    return d
  end
  local parts={{".cmesh_xbox2"},{".peg_xbox2"},{"_pc.morph_xbox2"}}
  for _,p in ipairs(parts) do p[2]=read(p[1]) end
  local ready=parts[1][2] and parts[2][2] and parts[3][2]
  if mode=="off" or not ready then
    if not ready and mode~="off" then wml.log("Work boots: files missing in work_boots/") end
  elseif mode=="replace" then
    for _,p in ipairs(parts) do wml.packfile_write(STREAM,"cshoe_hikingboots"..p[1],p[2]) end
    wml.log("Work boots: Hiking Boots replaced by the Timberland boots")
  else
    local ok,err=pcall(function()
      for _,p in ipairs(parts) do wml.packfile_write(STREAM,"cshoe_timberland"..p[1],p[2]) end
    end)
    if not ok then
      wml.log("Work boots: the Timberland slot couldn't be written ("..tostring(err).."); set work_boots = replace")
    else
      local function utf16(s) return (s:gsub(".","%0\0")) end
      for _,name in ipairs({"misc.vpp_xbox2","misc2.vpp_xbox2"}) do
        local xml=wml.packfile_read(name,"customization_items.xtbl")
        if xml and not xml:find("<Name>ultor work boots</Name>",1,true) then
          local s=xml:find("<Customization_Item>%s*<Name>hiking boots</Name>")
          local e=s and xml:find("</Customization_Item>",s,true)
          local ending=xml:find("</Table>",1,true)
          if e and ending then
            -- (ids the game's items leave unused, inside their range)
            local function free(tag)
              local used,top={},0
              for v in xml:gmatch("<"..tag..">%s*(%d+)%s*</"..tag..">") do local n=tonumber(v);used[n]=true;top=math.max(top,n) end
              for v=top-1,1,-1 do if not used[v] then return tostring(v) end end
            end
            local item,mesh,variant=free("ID"),free("MeshID"),free("VariantID")
            if item and mesh and variant then
              local row=xml:sub(s,e+#"</Customization_Item>"-1)
              row=row:gsub("<Name>hiking boots</Name>","<Name>ultor work boots</Name>",1)
                :gsub("CUST_ITEM_HIKING_BOOTS","CUST_ITEM_ULTOR_WORK_BOOTS",1)
                :gsub("cShoe_hikingBoots%.cmeshx","cShoe_timberland.cmeshx")
                :gsub("<MeshID>%d+</MeshID>","<MeshID>"..mesh.."</MeshID>",1)
                :gsub("<ID>%d+</ID>","<ID>"..item.."</ID>")
              -- one variant: the boots' own texture
              local vs,ve=row:find("<Variants>.-</Variants>")
              row=row:sub(1,vs-1).."<Variants>\n\t\t\t<Variant>\n\t\t\t\t<Name>CUST_VARIANT_DEFAULT</Name>\n\t\t\t\t<Variant_Name>default</Variant_Name>\n\t\t\t\t<VariantID>"..variant.."</VariantID>\n\t\t\t\t<Price>250</Price>\n\t\t\t\t<Respect_Bonus>30</Respect_Bonus>\n\t\t\t\t<MPPrice>0</MPPrice>\n\t\t\t\t</Variant>\n\t\t\t</Variants>"..row:sub(ve+1)
              wml.packfile_write(name,"customization_items.xtbl",xml:sub(1,ending-1).."\t"..row.."\n"..xml:sub(ending))
              wml.log(name..": Ultor Unlimited Work Boots added (item "..item..", mesh "..mesh..", variant "..variant..")")
            end
          end
        end
      end
    end
  end
end
