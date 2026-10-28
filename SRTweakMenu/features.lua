-- SR Tweak Menu - the features, as the menu sees them.
--
-- Every row of the menu is an item here. An item is one of:
--   toggle   on/off; `update` runs every game update while on, `off` once
--            when switched off. `pbits`/`p212`/`vbits` are shorthand for
--            "set these flag bits on the player / the player's car".
--   value    a number; `update` runs while it differs from `default`, `off`
--            when it returns to it, `change` once per adjustment.
--   choice   one of `options`; `change` runs when it changes, `run` on Enter.
--   list     a long list (vehicles, weapons); Left/Right browse, Enter picks.
--   action   `run` on Enter.
-- `needs` says what must be loaded: "player" (default), "vehicle", or "none".
-- Items marked experimental in their help text rest on disassembly only.

local G = require("game")
local VEHICLES = require("vehicles")
local CHARACTERS = require("characters")
local VARIANTS = require("variants")
-- Alphabetical by the name shown in the menu.
table.sort(VEHICLES, function(a, b) return a[2]:lower() < b[2]:lower() end)
-- The game's own blinged versions (variant names in each car's table; never
-- seen in traffic), listed after the plain car. The Hollywood's are the
-- Blinged Out Ride mode's top level in its four colours.
-- VEHICLES.spawn is the Spawn vehicle list: { xtbl name, display name, group,
-- special type, variant }.
do
local BLINGED = {
  car_2dr_compact06 = { "Blinged" }, car_2dr_exolux01 = { "Blinged" },
  car_4dr_luxury05 = { "Bling" }, suv_4dr_03 = { "Bling" }, suv_4dr_luxury05 = { "Bling" },
  car_2dr_luxury04 = { "Bling" }, car_2dr_muscle01 = { "Bling" }, car_2dr_muscle02 = { "Bling" },
  car_2dr_sports04 = { "Bling" }, car_2dr_standard02 = { "Bling" }, car_4dr_lowrider01 = { "Bling" },
  car_4dr_luxury03 = { "Bling" }, car_4dr_luxury04 = { "Bling" }, car_4dr_std01 = { "Bling" },
  car_4dr_std06 = { "Bling" }, minivan_4dr_02 = { "Bling" }, sp_hearse01 = { "Bling" },
  suv_4dr_05 = { "Bling" }, suv_4dr_luxury01 = { "Bling" }, wagon_4dr_sprt01 = { "Bling" },
  car_4dr_classic01 = { "BlingedBlue4", "Blue", "BlingedPurple4", "Purple", "BlingedRed4", "Red", "BlingedYellow4", "Yellow" },
}
local SPAWN_VEHICLES = {}
for _, v in ipairs(VEHICLES) do
  SPAWN_VEHICLES[#SPAWN_VEHICLES + 1] = v
  local b = BLINGED[v[1]:lower()]
  if b and #b == 1 then
    SPAWN_VEHICLES[#SPAWN_VEHICLES + 1] = { v[1], v[2] .. " Blinged", v[3], v[4], b[1] }
  elseif b then
    for i = 1, #b, 2 do
      SPAWN_VEHICLES[#SPAWN_VEHICLES + 1] = { v[1], v[2] .. " Blinged " .. b[i + 1], v[3], v[4], b[i] }
    end
  end
end
VEHICLES.spawn = SPAWN_VEHICLES
end
local WAYPOINT = require("waypoint")
local HOMIES = require("homies")
local FREECAM = require("freecam")

-- Filter presets: { key, name, game saturation, game tint {r, g, b},
-- post-process look }. The look is the loader's wml.set_look, in its order:
-- sharpen, bloom, bloom threshold, exposure, contrast, saturation, vibrance,
-- filmic, temperature, tint, vignette, black level, FXAA, anisotropic.
local FILTERS = {
  { "off", "Off" },
  { "noir", "Noir", 0, { 1, 1, 1 }, { 0.3, 0, 0.8, 0, 1.35, 1, 0, 0.5, 0, 0, 0.55, 0.04, 0, 0 } },
  { "sepia", "Sepia", 0, { 1.10, 0.92, 0.68 }, { 0, 0, 0.8, 0.1, 1.1, 1, 0, 0.3, 0, 0, 0.35, 0.02, 0, 0 } },
  { "vivid", "Vivid", 1.5, { 1, 1, 1 }, { 0.4, 0.15, 0.75, 0, 1.15, 1, 0.4, 0.4, 0, 0, 0.1, 0.02, 0, 0 } },
  { "cold", "Cold", 0.85, { 0.85, 0.97, 1.15 }, { 0, 0, 0.8, 0, 1.05, 1, 0, 0, -1, 0, 0.15, 0, 0, 0 } },
  { "warm", "Warm", 1.1, { 1.12, 1.0, 0.82 }, { 0, 0.1, 0.8, 0.05, 1.05, 1, 0.1, 0.2, 1, 0, 0.15, 0, 0, 0 } },
  { "night", "Night vision", 0, { 0.35, 1.6, 0.35 }, { 0.2, 0.35, 0.6, 0.8, 1.2, 1, 0, 0, 0, -1, 0.75, 0, 0, 0 } },
  { "retro", "Retro", 0.65, { 1.08, 0.98, 0.85 }, { 0, 0.1, 0.8, 0, 0.85, 1, 0, 0, 0.5, 0.3, 0.4, 0, 0, 0 } },
}
local S = wml.setting

local state_number_of  -- set below; poses use the animation-state lookup
local burn_queue, patched, burn_queued = {}, {}  -- rocket and fire ammo (below)
local F_menu_open = false
local function MENU_OPEN() return F_menu_open end
local F = { categories = {}, items = {}, enabled = true, debug = false, spawn_queue = {}, guard_queue = {}, guards_joining = {}, scene_queue = {}, scene_actors = {} }
F.FREECAM = FREECAM

-- Paints: { key, name, palette, colour }. Palettes 0-5 hold the same 80
-- colours with different finishes (Opaque, Matte, Gloss, Candy, Metallic,
-- Pearlescent); 11 is Iridescent (the gang colours among them); 7 is Metal,
-- which only a few cars take on the body.
local PAINTS = {
  { "jet_black", "Jet Black", 2, 15 }, { "matte_black", "Matte Black", 1, 15 }, { "ultra_white", "Ultra White", 2, 0 },
  { "pearl_white", "Pearl White", 5, 0 }, { "silver", "Silver", 4, 6 }, { "gunmetal", "Gunmetal", 4, 13 },
  { "matte_gray", "Matte Gray", 1, 8 }, { "insane_red", "Insane Red", 2, 72 }, { "candy_red", "Candy Red", 3, 72 },
  { "wine_red", "Wine Red", 4, 77 }, { "orange", "Furious Orange", 2, 24 }, { "yellow", "Double Yellow", 2, 28 },
  { "green", "Wildlife Green", 2, 34 }, { "brg", "British Racing Green", 4, 44 }, { "teal", "Solid Teal", 5, 47 },
  { "regatta_blue", "Regatta Blue", 2, 52 }, { "midnight_blue", "Midnight Blue", 4, 61 },
  { "candy_blue", "Candy Cosmos Blue", 3, 58 }, { "royal_purple", "Royal Purple", 4, 64 },
  { "candy_purple", "Candy Harlequin Purple", 3, 65 }, { "saints_purple", "Saints Purple", 11, 36 },
  { "hot_pink", "Hot Pink", 2, 68 }, { "princess_pink", "Princess Pink", 5, 69 }, { "tan", "Coffee Tan", 2, 20 },
  { "rust", "Rust Brown", 1, 19 }, { "goldenrod", "Goldenrod", 11, 16 }, { "vk_yellow", "Vice Kings Yellow", 11, 37 },
  { "rollerz_blue", "Rollerz Blue", 11, 38 }, { "lc_red", "Los Carnales Red", 11, 39 },
  { "mirrorshine", "Mirrorshine", 11, 28 }, { "mercury", "Mercury", 11, 34 }, { "oil_slick", "Oil Slick", 11, 7 },
  { "chameleon", "Chameleon", 11, 18 }, { "opal", "Opal", 11, 27 }, { "chrome", "Chrome", 7, 0 },
  { "gold", "Gold", 7, 13 },
}

-- Bodyguards: { model, name, weapon }. Saints gang members, plus a few
-- others who switch to your side.
local BODYGUARDS = {
  { "TS_X_M_Killa-A",    "Saints killa",       "ak47" },
  { "TS_X_M_KillaB",     "Saints killa (2)",   "m16" },
  { "TS_X_M_Thug1-01",   "Saints thug",        "mac10" },
  { "TS_X_M_Thug2-01",   "Saints thug (2)",    "pump_action_shotgun" },
  { "TS_X_F_Thug-01",    "Saints thug (F)",    "tec9" },
  { "TS_A_M_JohnnyGat",  "Johnny Gat",         "desert_eagle_gold" },
  { "TS_W_M_Troy-01",    "Troy",               "glock" },
  { "TS_B_M_Dex-01",     "Dex",                "beretta" },
  { "TS_B_M_Julius",     "Julius",             "magnum" },
  { "lw_w_m_swat01",     "SWAT officer",       "m16" },
  { "LW_X_M_Officer_01", "Police officer",     "glock" },
  { "PD_B_M_Bouncer-01", "Bouncer",            "baseball_bat" },
}
F.BODYGUARDS = BODYGUARDS

-- The same verified character definitions used by Spawn person can also be
-- recruited as homies. Keep the selector short by browsing one faction at a
-- time; the existing bodyguard presets remain available above it.
local HOMIE_GROUPS = { "Saints", "Vice Kings", "Los Carnales", "Westside Rollerz", "Police", "Activity", "Pedestrian" }
local HOMIE_WEAPONS = {
  ["Saints"] = "glock", ["Vice Kings"] = "mac10", ["Los Carnales"] = "ak47",
  ["Westside Rollerz"] = "beretta", ["Police"] = "glock",
  ["Activity"] = "glock", ["Pedestrian"] = "glock",
}
local HOMIE_BY_GROUP = {}
for _, group in ipairs(HOMIE_GROUPS) do HOMIE_BY_GROUP[group] = {} end
for _, character in ipairs(CHARACTERS) do
  local group = character[1] == "AC_A_F_TanyaWinters" and "Vice Kings" or character[3]
  local list = HOMIE_BY_GROUP[group]
  if list then
    -- Women and girls are marked (F).
    local name = character[2]:gsub("^[^:]+: ", ""):gsub(" %(woman%)$", " (F)")
    if character[1] == "VK_B_M_WWilliams" then name = "Warren Williams" end
    if character[1] == "TS_B_M_Dex-01" then name = "Dex" end
    list[#list + 1] = { character[1], name, HOMIE_WEAPONS[group] }
  end
end

-- Movement styles: the game's animation sets, each a whole way of moving
-- (stand, walk, jog, sprint, crouch, and the weapon-holding versions where
-- the set has them). { set, name }. GML1 is the player's own. Left out:
-- the vehicle and prop sets, and GML3/4, GHL3/4 and GFL3/4, whose
-- animations aren't on the disc.
local MOVE_STYLES = {
  { false, "Default" },
  { "GML1", "Gang: Saints (your own)" }, { "GHL1", "Gang: Pimp swagger" }, { "GFL1", "Gang: Female" },
  { "GFL_Zombie", "Gang: Zombie" },
  { "CML1", "Law: Cop" }, { "CML_SWT1", "Law: SWAT" }, { "EMT1", "Law: Paramedic" },
  { "PML1", "Street: Man" }, { "PHL1", "Street: Heavyset man" }, { "POL1", "Street: Elderly" },
  { "JOGGER1", "Street: Jogger" }, { "PFL1", "Street: Woman" }, { "PFL1_High_Class", "Street: High-class woman" },
  { "PFL1_High_Heels", "Street: High heels" }, { "PFL-Heavy", "Street: Heavyset woman (walk)" },
  { "PHL1_Female", "Street: Heavyset woman" }, { "PFL_SKTE1", "Street: Roller skater" },
  { "MASCOT", "Special: Mascot" },
}
-- How you move, in parts (stance, walk, run, sprint, melee/throw run,
-- combat: movement.lua), each Default or one of its choices; kept in
-- movement.txt ("part=n" lines).
F.MOVEMENT = require("movement")
F.move_parts = {}
F.MOVEMENT_FILE = wml.mod_folder .. "/movement.txt"
do
  local file = io.open(F.MOVEMENT_FILE, "rb")
  if file then
    for line in file:lines() do
      local k, v = line:match("^%s*([%w_]+)%s*=%s*(%d+)")
      if k then F.move_parts[k] = tonumber(v) end
    end
    file:close()
  end
end
function F.save_movement()
  local file = io.open(F.MOVEMENT_FILE, "wb")
  if not file then return end
  for k, v in pairs(F.move_parts) do if v and v > 0 then file:write(k, "=", v, "\n") end end
  file:close()
end

-- Walk and run variants: the extra walks and runs people get at random.
-- They replace only the walk (or run); everything else stays the style's.
local WALK_VARIANTS = { { 0, "Style's own" } }
for n = 1, 17 do WALK_VARIANTS[#WALK_VARIANTS + 1] = { n, "Walk variant " .. n } end
local RUN_VARIANTS = { { 0, "Style's own" } }
for n = 1, 4 do RUN_VARIANTS[#RUN_VARIANTS + 1] = { n, "Run variant " .. n } end

-- Voice personas with a homie head picture in follower_heads.xtbl. Anyone
-- else following you gets the Saints fleur-de-lis instead.
local HEAD_PERSONAS = {}
for _, prefix in ipairs({ "AF", "BF", "HF", "WF", "AM", "BM", "HM", "WM" }) do
  for n = 1, 3 do HEAD_PERSONAS[prefix .. "_3SS" .. n] = true end
end
for _, name in ipairs({ "WF_HO1", "WF_HO2", "WF_HO3", "WF_HO4", "BF_HO1", "BF_HO2", "BF_HO3", "AF_HO1", "AF_HO2",
    "HF_HO1", "HF_HO2", "HF_HO3", "SP_KING", "SP_DEX", "SP_GAT", "SP_JULIUS", "SP_TROY", "SP_LAURA", "SP_ZOMBIE",
    "SP_RES", "SP_SAMANTHA", "SP_WILL", "SP_WONG", "SP_TOBIAS", "SP_MARVIN", "SP_AISHA", "SP_AMPLAYER",
    "SP_BMPLAYER", "SP_HMPLAYER", "SP_WMPLAYER" }) do
  HEAD_PERSONAS[name] = true
end
F.HEAD_PERSONAS = HEAD_PERSONAS

local read_u8, read_u16, read_u32, read_f32 = wml.read_u8, wml.read_u16, wml.read_u32, wml.read_f32
local write_u8, write_u16, write_u32, write_f32 = wml.write_u8, wml.write_u16, wml.write_u32, wml.write_f32

-- Registers rows (their defaults and needs) under F.items.
function F.register(items)
  for _, it in ipairs(items) do
    it.needs = it.needs or "player"
    if it.kind == "toggle" then it.v = it.v == true
    elseif it.kind == "value" then it.v = it.v or it.default
    elseif it.kind == "choice" or it.kind == "list" then it.v = it.v or 1 end
    F.items[it.id] = it
  end
end
local function category(name, items)
  F.categories[#F.categories + 1] = { name = name, items = items }
  F.register(items)
end
-- More rows for a tab defined earlier, after the row `after`.
function F.add_rows(name, after, items)
  F.register(items)
  for _, cat in ipairs(F.categories) do
    if cat.name == name then
      local at = #cat.items + 1
      for i, it in ipairs(cat.items) do if it.id == after then at = i + 1 end end
      for k, it in ipairs(items) do table.insert(cat.items, at + k - 1, it) end
      return
    end
  end
end

local function fmt1(v) return string.format("%.1f", v) end
local function fmt2(v) return string.format("%.2f", v) end
local function fmtint(v) return string.format("%d", v) end
local function fmtx(v) return string.format("x%.1f", v) end

-- Weapons, given the way the game's own weapon cheats give them (the
-- routine the trainer uses): these are the weapons those cheats hand out.
-- Alphabetical by the name shown; the names are the game's own (US_Strings).
local WEAPONS = {
  { "rpg_launcher", "RPG" }, { "ak47", "K6 Krukov" }, { "m16", "AR-40 Xtnd" }, { "spas12", "AS12 Riot" },
  { "baseball_bat", "Baseball Bat" }, { "desert eagle", "GDHC .50" }, { "tec9", "T3K Urban" }, { "grenade", "Grenades" },
  { "knife", "Knife" }, { "sniper_rifle", "McManus" }, { "molotov", "Molotovs" }, { "nightstick", "Nightstick" },
  { "beretta", "Vice 9" }, { "pimpcane", "Pimp Cane" }, { "pipe_bomb", "Pipe Bombs" }, { "magnum", ".44 Shepherd" },
  { "mac10", "SKR-7 Spree" }, { "tire_iron", "Crowbar" }, { "twelve_gauge", "12 Gauge" }, { "glock", "NR4" },
  { "pump_action_shotgun", "Tombstone" }, { "pimp_slap", "Pimp Slap" },
}
table.sort(WEAPONS, function(a, b) return a[2]:lower() < b[2]:lower() end)
-- Drop weapons around me: a random mix, then every weapon.
WEAPONS.drop = { { "random", "Random mix" } }
for _, w in ipairs(WEAPONS) do WEAPONS.drop[#WEAPONS.drop + 1] = w end
F_WEAPON_QUEUE = {}

local WEATHER = { "Default", "Clear Skies", "Partly Cloudy", "Light Rain", "Medium Rain", "Heavy Rain", "Overcast", "Thunderstorm" }

-- Single-shot script calls are queued and run one per update, so a burst
-- (give every weapon) never stalls a frame.
F.queue = {}
local function enqueue(code) F.queue[#F.queue + 1] = code end

-- ================================================================ Player
category("Player", {
  { id = "god", label = "God mode", kind = "toggle",
    help = "You can't be hurt.",
    -- The flag has one owner, F.sync_invulnerable (below), shared with the
    -- landing and teleport shields.
    off = function(ctx, p) if p and p ~= 0 then F.sync_invulnerable(p) end end },
  { id = "noclip", label = "No Clip", kind = "toggle", needs = "player",
    help = "Fly through anything. Move: left stick / WASD. Up: RT / Space. Down: LT / Ctrl. Faster: A / Shift." },
  { id = "health_mult", label = "Health multiplier", kind = "value", default = 1, min = 1, max = 10, step = 0.5, fmt = fmtx,
    help = "Multiplies your maximum health.",
    update = function(ctx, p, v, it) F.scale_health(p, it.v) end,
    off = function(ctx, p) F.scale_health(p, 1) end },
  { id = "heal", label = "Refill health", kind = "action", help = "",
    run = function(ctx, p) write_f32(p + G.P.HEALTH, read_u32(p + G.P.HEALTH_MAX)); return "Health refilled" end },
  { id = "kill_self", label = "Kill Yourself", kind = "action", needs = "player",
    help = "You die and respawn. Also clears invulnerability left on by mistake.",
    run = function(ctx, p) return F.kill_self(ctx, p) end },
  { id = "never_wanted", label = "Never wanted", kind = "toggle",
    help = "Police and gangs won't come after you.",
    update = function(ctx, p)
      for _, g in ipairs({ 0, 1, 2, 4 }) do
        local base = p + G.P.NOTORIETY + g * 24
        if read_u32(base) ~= 0 then write_u32(base, 0) end
        write_u32(base + 12, 0)
      end
    end },
  { id = "saints_enemies", label = "Saints are enemies", kind = "toggle",
    help = "The Saints treat you as a rival gang. You side with the gang picked below, or the gang of the character you look like, and can recruit from it.",
    update = function(ctx, p) F.update_saints_enemies(ctx, p, true) end,
    off = function(ctx, p) F.update_saints_enemies(ctx, p, false) end },
  { id = "wanted_police", label = "Police notoriety", kind = "value", default = 0, min = 0, max = 5, step = 1, fmt = fmtint, live = true, oneshot = true,
    help = "",
    read = function(p) return read_u32(p + G.P.NOTORIETY + 4 * 24) end,
    change = function(ctx, p, _, it) F.set_notoriety(ctx, p, 4, it.v) end },
  { id = "wanted_carnales", label = "Los Carnales notoriety", kind = "value", default = 0, min = 0, max = 5, step = 1, fmt = fmtint, live = true, oneshot = true,
    help = "",
    read = function(p) return read_u32(p + G.P.NOTORIETY) end,
    change = function(ctx, p, _, it) F.set_notoriety(ctx, p, 0, it.v) end },
  { id = "wanted_vk", label = "Vice Kings notoriety", kind = "value", default = 0, min = 0, max = 5, step = 1, fmt = fmtint, live = true, oneshot = true,
    help = "",
    read = function(p) return read_u32(p + G.P.NOTORIETY + 24) end,
    change = function(ctx, p, _, it) F.set_notoriety(ctx, p, 1, it.v) end },
  { id = "wanted_rollerz", label = "Westside Rollerz notoriety", kind = "value", default = 0, min = 0, max = 5, step = 1, fmt = fmtint, live = true, oneshot = true,
    help = "",
    read = function(p) return read_u32(p + G.P.NOTORIETY + 2 * 24) end,
    change = function(ctx, p, _, it) F.set_notoriety(ctx, p, 2, it.v) end },
  { id = "wanted_saints", label = "Saints notoriety", kind = "value", default = 0, min = 0, max = 5, step = 1, fmt = fmtint, live = true, oneshot = true,
    help = "Requires Saints are enemies.",
    read = function(p) return math.floor(F.saints_notoriety(p)) end,
    change = function(ctx, p, _, it)
      if not F.on("saints_enemies") then
        it.v = 0
        G.hud("Turn on Saints are enemies first")
        return
      end
      F.set_saints_notoriety(ctx, p, it.v > 0 and it.v + 0.5 or 0)
    end },
  { id = "max_wanted", label = "Max notoriety", kind = "action",
    run = function(ctx, p) return F.set_notoriety_all(ctx, p, 5) end,
    help = "Police and every gang at full notoriety." },
  { id = "homies", label = "Homie limit", kind = "value", needs = "none", default = 0, min = 0, max = 10, step = 1,
    v = S("homie_limit", 0), fmt = function(v) return v == 0 and "Default" or string.format("%d", v) end,
    help = "How many homies can follow you. Requires recruiting to be unlocked." },
  { id = "move_style", label = "Movement style", kind = "list", items = MOVE_STYLES, retired = true,
    help = "How your character stands, walks and runs. Press A / Enter to apply.",
    usable = function(ctx, p, style) return not style[1] or F.style_entry(ctx, style[1]) ~= 0 end,
    run = function(ctx, p, _, it)
      local style = it.items[it.v]
      if style[1] and F.style_entry(ctx, style[1]) == 0 then return "That style isn't in this game" end
      if style[1] and F.player_set(ctx) == 0 then return "Movement styles need the game restarted once (new animation set)" end
      F.move.style = style[1] or nil
      F.apply_movement(ctx, p)
      F.keep_preview_move()
      return "Movement style: " .. style[2]
    end },
  { id = "walk_variant", label = "Walk variant", kind = "list", items = WALK_VARIANTS, retired = true,
    help = "Replaces the movement style's walk. Press A / Enter to apply.",
    usable = function(ctx, p, w) return w[1] == 0 or F.variant_available(ctx, "walk variant " .. w[1]) end,
    run = function(ctx, p, _, it)
      local w = it.items[it.v]
      if w[1] ~= 0 and F.player_set(ctx) == 0 then return "Walk variants need the game restarted once (new animation set)" end
      F.move.walk = w[1]
      F.apply_movement(ctx, p)
      F.keep_preview_move()
      return "Walk: " .. w[2]
    end },
  { id = "run_variant", label = "Run variant", kind = "list", items = RUN_VARIANTS, retired = true,
    help = "Replaces the movement style's jog. Press A / Enter to apply.",
    usable = function(ctx, p, r) return r[1] == 0 or F.variant_available(ctx, "run variant " .. r[1]) end,
    run = function(ctx, p, _, it)
      local r = it.items[it.v]
      if r[1] ~= 0 and F.player_set(ctx) == 0 then return "Run variants need the game restarted once (new animation set)" end
      F.move.run = r[1]
      F.apply_movement(ctx, p)
      F.keep_preview_move()
      return "Run: " .. r[2]
    end },
  -- (Movement style and the variants above stay for the code that uses
  -- them, out of sight: the parts below replace them in the menu.)
  { id = "bodyguard", label = "Spawn bodyguard", kind = "list", items = BODYGUARDS,
    help = "Spawns an armed bodyguard who follows you as a homie.",
    run = function(ctx, p, _, it)
      local g = BODYGUARDS[it.v]
      if read_u32(p + G.PARTY_COUNT) + #F.guard_queue >= 10 then return "Your party is full (10)" end
      F.guard_queue[#F.guard_queue + 1] = g
      return "Bodyguard on the way: " .. g[2]
    end },
  { id = "homie_group", label = "Character homie group", kind = "choice", options = HOMIE_GROUPS, needs = "none",
    help = "Which characters Spawn character homie lists.",
    change = function(ctx, p, v, it)
      local spawn = F.items.character_homie
      spawn.items = HOMIE_BY_GROUP[HOMIE_GROUPS[it.v]]
      spawn.v = 1
    end },
  { id = "character_homie", label = "Spawn character homie", kind = "list", items = HOMIE_BY_GROUP["Saints"],
    help = "Spawns the selected character as an armed homie.",
    run = function(ctx, p, _, it)
      local g = it.items[it.v]
      if read_u32(p + G.PARTY_COUNT) + #F.guard_queue >= 10 then return "Your party is full (10)" end
      F.guard_queue[#F.guard_queue + 1] = g
      return "Character homie on the way: " .. g[2]
    end },
  { id = "bodyguard_squad", label = "Bodyguard squad (4)", kind = "action",
    help = "Spawns four armed Saints.",
    run = function(ctx, p)
      local room = 10 - read_u32(p + G.PARTY_COUNT) - #F.guard_queue
      if room <= 0 then return "Your party is full (10)" end
      for i = 1, math.min(4, room) do F.guard_queue[#F.guard_queue + 1] = BODYGUARDS[i] end
      return string.format("%d bodyguards on the way", math.min(4, room))
    end },
  { id = "dismiss_homies", label = "Dismiss all homies", kind = "action",
    help = "",
    run = function(ctx, p)
      local n = HOMIES.count(p)
      if n == 0 then return "No homies are following you" end
      G.call(ctx, HOMIES.DISMISS_ALL, { p })
      return string.format("Dismissed %d homie%s", n, n == 1 and "" or "s")
    end },
  { id = "no_cops", label = "No cops", kind = "toggle", needs = "none", byte = { G.VAR.ALLOW_COPS, 0, 1 },
    help = "Police no longer patrol the streets." },
  { id = "no_gangs", label = "No gangs", kind = "toggle", needs = "none", byte = { G.VAR.ALLOW_GANGS, 0, 1 },
    help = "Gang members no longer roam the streets." },
  { id = "no_bust", label = "Never busted", kind = "toggle", needs = "none", byte = { G.VAR.ALLOW_BUST, 0, 1 },
    help = "" },
  { id = "no_ragdoll", label = "No ragdoll", kind = "toggle", pbits = G.FLAG.NO_RAGDOLL | G.FLAG.NO_FLINCH, p212 = G.FLAG212.NO_EXPLOSION_FLING | G.FLAG212.NO_KNEECAP,
    help = "You can't be knocked down, staggered or thrown." },
  { id = "perfect_aim", label = "Perfect aim", kind = "toggle", pbits = G.FLAG.PERFECT_AIM,
    help = "Every shot goes exactly where you aim." },
  { id = "run", label = "Run boost", kind = "toggle", v = S("run_boost", false),
    help = "Run and sprint faster. Set the speed below." },
  { id = "run_speed", label = "Run speed", kind = "value", default = 1.0, min = 1, max = 6, step = 0.25, fmt = fmtx, oneshot = true,
    v = S("run_speed_multiplier", 1.5), help = "" },
  { id = "jump", label = "High jump", kind = "toggle", v = S("high_jump", false), help = "Jump higher. Set the height below." },
  { id = "jump_boost", label = "High jump boost", kind = "value", default = 1.0, min = 1, max = 10, step = 0.5, fmt = fmtx, oneshot = true,
    v = S("jump_multiplier", 4.0), help = "" },
  { id = "landing", label = "Soft landing", kind = "toggle", v = S("soft_landing", false), needs = "none",
    help = "Falls never hurt or stagger you.",
    -- No flailing: the panic-fall speed raised for everyone while on.
    update = function() F.hold_float(G.PANIC_FALL, 100) end,
    off = function() F.release_float(G.PANIC_FALL) end },
  { id = "quick_crouch", label = "Quick crouch", kind = "toggle", needs = "none", help = "Crouch instantly.",
    update = function()
      F.hold_float(G.CROUCH_ACCEL, 9); F.hold_float(G.CROUCH_DAMPING, 0.75)
    end,
    off = function() F.release_float(G.CROUCH_ACCEL); F.release_float(G.CROUCH_DAMPING) end },
  { id = "jump_height", label = "Game jump height", kind = "value", needs = "none", default = 0.85, min = 0.2, max = 6, step = 0.1, fmt = fmt2, float = G.VAR.JUMP_HEIGHT,
    help = "The game's own jump height." },
  { id = "swim_speed", label = "Swim speed", kind = "value", needs = "none", default = 4.5, min = 1, max = 40, step = 0.5, fmt = fmt1, float = G.VAR.SWIM_SPEED,
    help = "" },
  { id = "fall_damage", label = "Fall damage", kind = "value", needs = "none", default = 0.2, min = 0, max = 1, step = 0.05, fmt = fmt2, float = G.VAR.FALL_DAMAGE,
    help = "How much health a hard landing costs. 0 = none." },
  { id = "sprint", label = "Infinite sprint", kind = "toggle", needs = "none", bits = { G.VAR.CHEAT_FLAGS, 0x02000000 },
    help = "Sprint without running out of stamina. Experimental." },
  { id = "money", label = "Money +$50,000", kind = "action", help = "",
    run = function(ctx, p)
      local cents = read_u32(p + G.P.CASH)
      if cents >= 0x80000000 then cents = cents - 0x100000000 end
      cents = math.min(2000000000, math.max(0, cents + 5000000))
      write_u32(p + G.P.CASH, cents)
      return "Added $50,000"
    end },
  { id = "respect", label = "Respect +5,000", kind = "action",
    help = "",
    run = function(ctx, p)
      local most = read_u32(p + G.P.RESPECT_BAR) * 99
      local now = read_u32(p + G.P.RESPECT)
      if now >= 0x80000000 then now = 0 end
      write_u32(p + G.P.RESPECT, math.min(most, now + 5000))
      return "Added 5,000 respect"
    end },
})

-- Player model: swapped live, behind a short fade, the way the game takes
-- a body out of the world and puts it back (F.update_model below). The
-- choice is remembered in player_model.txt and put back when you load a
-- game or respawn.
category("Models", {
  { id = "model_group", label = "Model group", kind = "choice", options = HOMIE_GROUPS, needs = "none",
    help = "",
    change = function(ctx, p, v, it)
      local model = F.items.player_model
      model.items = HOMIE_BY_GROUP[HOMIE_GROUPS[it.v]]
      model.v = 1
      model.ok = nil
    end },
  { id = "player_model", label = "Player model", kind = "list", items = HOMIE_BY_GROUP["Saints"],
    help = "The character you play as. Press A / Enter to apply.",
    usable = function(ctx, p, c) return F.model_usable(ctx, c[1]) end,
    run = function(ctx, p, _, it) return F.request_model(p, it.items[it.v]) end },
  { id = "apply_player_model", label = "Switch to Model", kind = "action",
    help = "",
    run = function(ctx, p)
      local it = F.items.player_model
      return F.request_model(p, it.items[it.v])
    end },
  { id = "restore_player_model", label = "Restore Playa Model", kind = "action",
    help = "Return to your own character.",
    run = function(ctx, p) return F.request_model(p, nil) end },
  { id = "reload_character", label = "Reload Character", kind = "action",
    help = "Rebuilds your character as they are, fresh: for animations that are stuck or won't play.",
    run = function(ctx, p) return F.reload_character(ctx, p) end },
  { id = "line_rate", label = "Character dialogue", kind = "choice", needs = "none", v = 3,
    options = { "Off", "Rarely", "Sometimes", "Often" },
    help = "How often the character speaks. Pain and death sounds always play." },
  { id = "missing_moves", label = "Animation Fallback", kind = "choice", needs = "none", v = 1, options = { "On", "Off" },
    help = "Characters with an incomplete animation set borrow the moves they're missing: sprinting, crouching, jumping and weapon handling.",
    change = function(ctx, p) F.apply_movement(ctx, p) end },
  { id = "loose_parts", label = "Cloth physics", kind = "choice", needs = "none", v = 2,
    options = { "Simulated", "Locked", "Default" },
    help = "Locked: hair and clothing hold their shape. Simulated: they move freely. Default: the game's own behavior.",
    change = function(ctx, p) F.bones.dirty = true end },
})

-- ================================================================ Customize
--
-- EXPERIMENTAL: the look of the character you're playing, like the game's
-- own clothing and appearance menus: Left/Right through each kind of part,
-- shown on you half a second later. See "Customize (EXPERIMENTAL)" below.
local function look_row(id, label, help)
  return { id = id, label = label, kind = "list", items = { { false, "none for this model" } }, help = help,
    hidden = function() return not F.model.name end,
    change = function(ctx, p, _, it) F.look_pick(it) end,
    run = function(ctx, p, _, it) F.look_pick(it); return F.look_apply(p) end }
end
-- Rows for you as yourself: the game's own appearance screens, reached
-- through its stores and crib wardrobes (see "Your look" further down).
local function yours(row)
  local own = row.hidden
  row.hidden = function() return F.model.name ~= nil or (own ~= nil and own()) end
  return row
end
local NO_PLACES = { { false, "none" } }
-- What the stores sell, by kind, in the order they show them.
local CLOTHES = { "Hat", "Eyewear", "Coat", "Overshirt", "Undershirt", "Special T-Shirts", "Pants", "Belt", "Underwear", "Socks", "Shoes" }
local JEWELRY = { "Necklace High", "Necklace Medium", "Necklace Low", "Pendant", "Medallion", "Left Wrist", "Right Wrist", "Ring",
  "Piercing Ear", "Piercing Eyebrow", "Piercing Nose", "Piercing Lip" }
category("Customize", {
  look_row("look_race", "Race / variation", "EXPERIMENTAL. Their variations (race, outfit set). Right stick / mouse turns the camera, LT / RT (Z / X) zoom."),
  look_row("look_head", "Head", "EXPERIMENTAL. Their heads and faces."),
  look_row("look_hair", "Hair", "EXPERIMENTAL. Their hairstyles."),
  look_row("look_top", "Top", "EXPERIMENTAL. Shirts, jackets, dresses."),
  look_row("look_bottom", "Bottom", "EXPERIMENTAL. Pants, shorts, skirts, legs."),
  look_row("look_shoes", "Shoes", "EXPERIMENTAL. Their shoes and boots."),
  look_row("look_accessories", "Accessories", "EXPERIMENTAL. Hats, glasses, chains, earrings, watches; each can be none."),
  look_row("look_body", "Body", "EXPERIMENTAL. The rest of their model's parts."),
  look_row("look_colours", "Colours", "EXPERIMENTAL. Skin, colours and patterns of what they wear."),
  { id = "look_mix", label = "MIX VARIATIONS (EXPERIMENTAL)", kind = "choice", options = { "Off", "On" },
    hidden = function() return not F.model.name end,
    help = "Combine parts from every variation of this character. Experimental.",
    change = function(ctx, p, _, it) F.look.mix = it.v == 2; F.look_rows() end },
  { id = "look_random", label = "Random look", kind = "action",
    hidden = function() return not F.model.name end,
    help = "Randomizes every part and color.",
    run = function(ctx, p) F.look.custom = true; return F.look_random(p) end },
  { id = "look_reset", label = "Reset look", kind = "action",
    hidden = function() return not F.model.name end,
    help = "Restores the variation's default look.",
    run = function(ctx, p)
      local L = F.look
      if not L.ok then return "Change into a character with options first" end
      L.mix, L.custom, F.items.look_mix.v = false, false, 1
      return F.request_model(p, { F.model.name, F.model.label or F.model.name }, { variant = L.state.race, quick = true })
    end },
  -- As yourself: every part of your look, free, laid out like the game's
  -- creator, surgeon, salon, stores and tattoo parlour (see Your look).
  yours({ id = "style_presets", label = "Saved Presets", kind = "page", open = function(ctx, p) return F.page_presets(ctx, p, "look") end,
    help = "Save up to 10 looks: face and body, skin, eyes, hair, facial hair and tattoos." }),
  yours({ id = "style_head", label = "Head", kind = "page", open = function(ctx, p) return F.page_head(ctx, p) end,
    help = "" }),
  yours({ id = "style_eyes", label = "Eyes", kind = "page", open = function(ctx, p) return F.page_eyes(ctx, p) end,
    help = "" }),
  yours({ id = "style_hair", label = "Hair", kind = "page", open = function(ctx, p) return F.page_hair(ctx, p) end,
    help = "" }),
  yours({ id = "style_body", label = "Body", kind = "page", open = function(ctx, p) return F.page_sliders(ctx, p, "Body", "Body") end,
    help = "" }),
  yours({ id = "style_skin", label = "Skin", kind = "page", open = function(ctx, p) return F.page_skin(ctx, p) end,
    help = "" }),
  yours({ id = "style_clothes", label = "Clothes", kind = "page", open = function(ctx, p) return F.page_store(ctx, p, "Clothes", CLOTHES) end,
    help = "" }),
  yours({ id = "style_jewelry", label = "Jewelry", kind = "page", open = function(ctx, p) return F.page_store(ctx, p, "Jewelry", JEWELRY) end,
    help = "" }),
  yours({ id = "style_tattoos", label = "Tattoos", kind = "page", open = function(ctx, p) return F.page_tattoos(ctx, p) end,
    help = "" }),
  yours({ id = "style_voice", label = "Voice", kind = "page", open = function(ctx, p) return F.page_voice(ctx, p) end,
    help = "Choose the voice your character speaks with." }),
})
-- The tab is there for you as yourself, and as someone else only when they
-- have something to change.
F.categories[#F.categories].hidden = function() return F.model.name ~= nil and not F.look.ok end
-- ================================================================ Emotes
--
-- Poses are animation states (anim_states.xtbl), set on you the way
-- set_animation_state does it and held until you move. Actions are one-off
-- moves (anim_actions.xtbl), played by the game's own play_action script
-- function in a script thread, as missions do (it waits for the move).
-- An animation is a built-in state name (anim_states, the game's own list
-- of 227) or { file = "name" }: an animation file from the people's
-- animation sets, played the way the game plays custom animations
-- (pfl1/pml1 = female/male sets).
-- Scenes: women spawned doing the game's animations.
local F_MODELS = { "Stripper-Black", "Stripper-Latina", "Stripper-White", "Stripper-Asian", "PD_W_F_HO-01",
  "PD_X_F_SkinnyHo", "PD_X_F_HO-03", "pd_x_f_genericyoung-01", "PD_X_F_GenericYoung-02", "PD_X_F_GenericYoung-03" }
-- A scene: pairs { first, second, "mf"/"ff"/"fm" sexes } and singles { animation, "f"/"m" }.
local SCENES = {
  { "dance_pairs", "Dance pairs", pairs = { { "pair dance a", "pair dance a" }, { "pair dance b", "pair dance b" },
      { "pair dance c", "pair dance c" } } },
  { "strip_club", "Strip club", singles = { { "pole stand" }, { "stage stand" }, { "pole stand" }, { "stage stand" },
      { "react cheer" }, { "react cheer" }, { "Beer Stand" } } },
  { "house_party", "House party", pairs = { { "pair dance a", "pair dance a" }, { "pair dance d", "pair dance d" } },
    singles = { { "dance a" }, { "dance b" }, { "dance c" }, { "dance d" }, { "blunt smoking" },
      { "forty drinking" }, { "react cheer" } } },
}

category("Emotes", {
  { id = "poses", label = "Poses", kind = "page", open = function(ctx, p) return F.page_emotes("poses")(ctx) end,
    help = "Available poses. RB + D-pad Up (Shift + Up) stops a pose." },
  { id = "actions", label = "Actions", kind = "page", open = function(ctx, p) return F.page_emotes("actions")(ctx) end,
    help = "Available gestures and actions. Move or RB + D-pad Up to stop." },
  { id = "stop_pose", label = "Stop posing", kind = "action", needs = "player",
    help = "",
    run = function(ctx, p) return F.stop_pose(ctx, p) end },
  { id = "scene", label = "Stage a scene", kind = "list", items = SCENES,
    help = "Characters appear in front of you and act out a scene.",
    run = function(ctx, p, _, it) return F.stage_scene(p, SCENES[it.v]) end },
  { id = "clear_scene", label = "Clear scene", kind = "action",
    help = "",
    run = function(ctx) return F.clear_scene(ctx) end },
  { id = "repeat_action", label = "Repeat action", kind = "toggle",
    help = "Repeats the last action. RB + D-pad Up (Shift + Up) stops it." },
  { id = "repeat_every", label = "Repeat interval (s)", kind = "value", needs = "none", default = 3, min = 1, max = 15, step = 0.5,
    fmt = fmt1, oneshot = true, help = "" },

})

-- ================================================================ Weapons
category("Weapons", {
  { id = "infinite_ammo", label = "Infinite ammo", kind = "toggle", needs = "none", byte = { G.VAR.UNLIMITED_AMMO, 1, 0 },
    help = "Reserve ammo never runs out." },
  { id = "no_reload", label = "No reload", kind = "toggle",
    help = "Your magazine never empties.",
    update = function(ctx, p)
      local item = read_u32(p + G.P.EQUIPPED)
      if not G.pointer_ok(item) then return end
      local ammo = read_u32(item + 16)
      if not G.pointer_ok(ammo) then return end
      local info = read_u32(ammo + 8)  -- the weapon record the game's own reload code reads
      if not G.pointer_ok(info) then return end
      local mag = read_u16(info + 104)
      if F.debug and F.tick % 50 == 0 then
        wml.log(string.format("no reload: item %08X ammo %08X info %08X type %d mag %d rounds %d reserve %d",
          item, ammo, info, read_u32(info + 100), mag, read_u32(ammo + 16), read_u32(ammo + 20)))
      end
      if read_u32(info + 100) >= 2 or mag < 1 then return end  -- melee, thrown
      if read_u32(ammo + 16) < mag then write_u32(ammo + 16, mag) end
      if read_u32(ammo + 20) < 1 then write_u32(ammo + 20, 1) end
    end },
  { id = "fire", label = "Rapid fire", kind = "toggle", needs = "none", v = S("auto_fire", false),
    help = "Weapons fire faster.",
    update = function() F.faster_guns(true) end,
    off = function() F.faster_guns(false) end },
  { id = "weapon_switch", label = "Weapon switch", kind = "toggle", needs = "none", v = S("weapon_switch", false),
    help = "By Eazeepz: keys 1 to 8 pick a weapon type, the mouse wheel or D-pad left/right steps. Tap Q (B on a pad) for the next weapon; hold it for the wheel and keep moving." },
  { id = "weapon_dpad", label = "Weapon switch D-pad", kind = "choice", needs = "none",
    options = { "Switches weapons", "Left to the game" }, v = (tostring(S("weapon_dpad", "switch")):lower() == "taunts") and 2 or 1,
    help = "With Weapon switch on: D-pad left/right step through your weapons, or are left to the game (the radio in a car, and D-pad taunts on foot)." },
  { id = "weapon_tap", label = "Weapon wheel tap", kind = "choice", needs = "none",
    options = { "Next weapon", "Wheel only" }, v = (tostring(S("weapon_tap", "next")):lower() == "wheel") and 2 or 1,
    help = "With Weapon switch on: a quick tap of the wheel button (B, or RB on layout 3) gives the next weapon, or does nothing." },
  { id = "harder_hits", label = "Heavy knockback", kind = "toggle", needs = "none",
    help = "Enemies you kill are thrown further.",
    update = function() F.harder_hits(true) end,
    off = function() F.harder_hits(false) end },
  { id = "one_hit", label = "One-hit kill", kind = "toggle", help = "Every hit kills. Experimental." },
  { id = "rocket_ammo", label = "Rocket ammo", kind = "toggle",
    help = "Every shot fires a rocket. The blast can hurt you up close.",
    off = function() F.restore_guns() end },
  { id = "fire_ammo", label = "Fire ammo", kind = "toggle",
    help = "Enemies you shoot catch fire." },
  { id = "money_gun", label = "Money gun", kind = "toggle",
    help = "Your shots fire bills that land where the bullet hits; pick them up after. Not with Rocket ammo." },
  { id = "money_gun_cash", label = "Money gun bill ($)", kind = "value", needs = "none", default = 100, min = 100, max = 10000, step = 100,
    fmt = fmtint, oneshot = true, hidden = function() return not F.items.money_gun.v end,
    help = "How many dollars each bill from the money gun is worth. Default 100." },
  { id = "explosive_punch", label = "Explosive punches", kind = "toggle",
    help = "Punches and melee hits blow up whoever or whatever you hit, cars too. You're shielded from your own blast." },
  { id = "punch_blast", label = "Punch blast", kind = "choice", needs = "none",
    options = { "Small", "Grenade", "Rocket", "Huge" }, v = 2, hidden = function() return not F.items.explosive_punch.v end,
    help = "How big the explosive punch blast is." },
  { id = "give_weapon", label = "Give weapon", kind = "list", items = WEAPONS,
    help = "Adds the selected weapon with 500 rounds.",
    run = function(ctx, p, _, it)
      local w = WEAPONS[it.v]
      F.give_weapon(ctx, w[1])
      return "Given: " .. w[2]
    end },
  { id = "all_weapons", label = "Give every weapon", kind = "action", help = "",
    run = function(ctx, p)
      for _, w in ipairs(WEAPONS) do F_WEAPON_QUEUE[#F_WEAPON_QUEUE + 1] = w[1] end
      return "Giving every weapon..."
    end },
  { id = "ammo_all", label = "Refill all ammo", kind = "action", help = "",
    run = function(ctx, p)
      local n = F.refill_all(p)
      return n > 0 and string.format("Ammo refilled (%d gun%s)", n, n == 1 and "" or "s") or "No guns to refill"
    end },
})

-- ================================================================ Vehicles
do  -- the aim rows (scoped: this file is near Lua's 200-locals limit)
-- ================================================================ Aim
--
-- The aiming add-ons (addons.lua): Precise Aim by Eazeepz and Fine Aim by
-- car123609, bundled with their permission. Only one runs at a time. Precise
-- Aim's camera is tuned here instead of with its tuning keys.
local AIM_STYLES = { "Game's own", "Precise Aim", "Fine Aim" }
local AIM_BUTTONS = { "Each add-on's own", "Toggle", "Hold" }
local AIM_BUTTON_START = { own = 1, toggle = 2, hold = 3 }
-- Hold or toggle, handed to both aim add-ons (nil = their own setting).
function F.apply_aim_button()
  local v = F.items.aim_button.v
  local on = nil
  if v == 2 then on = true elseif v == 3 then on = false end
  for _, name in ipairs({ "precise", "fine" }) do
    local M = F.addon[name]
    if M and M.set_toggle then pcall(M.set_toggle, on) end
  end
end
local AIM_START = { off = 1, precise = 2, fine = 3 }
local AIM_NAMES = { SR1 = "Saints Row 1", SR2 = "Saints Row 2", SR3 = "Saints Row: The Third",
  SR4 = "Saints Row IV", SR2022 = "Saints Row (2022)", TPA = "Gentle third person" }
local function aim_label(name)
  local n = tostring(name):match("^custom(%d+)$")
  return AIM_NAMES[name] or (n and ("My camera " .. n)) or tostring(name)
end
-- Precise Aim's presets, from its files (the menu's list; the add-on applies them).
local function aim_presets()
  local list, seen = {}, {}
  for _, file in ipairs({ "presets.ini", "my_presets.ini" }) do
    local h = io.open(wml.mod_folder .. "/addons/precise_aim/" .. file, "r")
    if h then
      for line in h:lines() do
        local name = line:match("^%s*%[(.-)%]%s*$")
        if name and not seen[name] then seen[name] = true; list[#list + 1] = { name, aim_label(name) } end
      end
      h:close()
    end
  end
  if #list == 0 then list[1] = { "SR1", aim_label("SR1") } end
  return list
end
local AIM_PRESETS = aim_presets()
F.AIM_PRESETS = AIM_PRESETS
F.addon = {}
local function precise() return F.addon.precise end
local function cam_value(field)
  return function() local M = precise() return M and M.get(field) or nil end
end
local function cam_set(field)
  return function(ctx, p, v, it) local M = precise() if M then M.set(field, it.v) end end
end
-- The list shows the preset the add-on is using.
function F.sync_aim_camera()
  local M = precise()
  local name = M and M.preset()
  if not name then return end
  for i, e in ipairs(AIM_PRESETS) do if e[1] == name then F.items.aim_camera.v = i return end end
  AIM_PRESETS[#AIM_PRESETS + 1] = { name, aim_label(name) }
  F.items.aim_camera.v = #AIM_PRESETS
end

-- Saves a tuning row's value in an add-on's settings file, so it is there next time.
local function save_addon(name, key, value)
  local M = F.addon[name]
  if M and M.folder and F.ADDONS then F.ADDONS.save_setting(M.folder .. "/settings.ini", key, value) end
end
local function fine_value(key) return function() local M = F.addon.fine return M and M.get and M.get(key) or nil end end
local function fine_set(key, ini)
  return function(ctx, p, v, it)
    local M = F.addon.fine
    if M and M.set then M.set(key, it.v) save_addon("fine", ini, string.format("%.2f", it.v)) end
  end
end

F.add_rows("Weapons", "weapon_tap", {
  { id = "camera_turn", label = "Camera turn speed", kind = "value", needs = "none", default = 1.0, min = 0.5, max = 2.0, step = 0.1,
    fmt = fmtx, live = true, oneshot = true,
    read = function() local v = read_f32(G.LOOK_SPEED_X) return (v > 0.05 and v < 10) and v or nil end,
    help = "The game's look sensitivity (Options > Controls): how fast the stick turns the camera. Saved for next time. With Precise Aim's own turning it sets the mouse too.",
    change = function(ctx, p, v, it) F.set_camera_turn(it.v) end },
  { id = "aim_style", label = "Aim style", kind = "choice", needs = "none", options = AIM_STYLES,
    v = AIM_START[tostring(S("aim_style", "off")):lower()] or 1,
    help = "Precise Aim by Eazeepz: over-the-shoulder camera, accuracy by stance, slow walk. Fine Aim by car123609: aim zoom, slower turning, tighter shots. Both aim on right mouse; LT (Precise) or right stick click (Fine).",
    change = function(ctx, p, v, it)
      if it.v == 2 then return "Precise Aim: right mouse / LT to aim, Caps Lock / LB slow walk" end
      if it.v == 3 then return "Fine Aim: hold right mouse, or click the right stick, to aim" end
      return "Aim style: the game's own"
    end },
  { id = "aim_button", label = "Aim button", kind = "choice", needs = "none", options = AIM_BUTTONS,
    v = AIM_BUTTON_START[tostring(S("aim_button", "own")):lower()] or 1,
    help = "Precise Aim and Fine Aim, mouse and controller: press once to aim and again to stop, or hold to aim. Each add-on's own: Precise toggles, Fine holds the mouse and toggles the pad.",
    change = function() F.apply_aim_button() end },
  { id = "precise_turning", label = "Precise Aim turning", kind = "choice", needs = "none",
    options = { "Game's own", "Precise Aim's" }, v = (tostring(S("precise_turning", "game")):lower() == "precise") and 2 or 1,
    help = "Game's own: turning feels like the normal game, Precise Aim only changes it while you aim. Precise Aim's: its own stick curve and the game's look sensitivity on the mouse too.",
    change = function(ctx, p, v, it)
      F.apply_precise_turning()
      if F.ADDONS then F.ADDONS.save_setting(wml.mod_folder .. "/mod.ini", "precise_turning", it.v == 2 and "precise" or "game") end
    end },
  { id = "precise_aim_turn", label = "Precise Aim aim turn speed", kind = "value", needs = "none", default = 1.0, min = 0.1, max = 3.0, step = 0.1,
    fmt = fmtx, live = true, oneshot = true,
    read = function() local M = F.addon.precise return M and M.aim_sens and M.aim_sens() or nil end,
    help = "How fast you turn while aiming with Precise Aim, compared with not aiming (x0.5 = half as fast).",
    change = function(ctx, p, v, it)
      local M = F.addon.precise
      if M and M.set_aim_sens then M.set_aim_sens(it.v) save_addon("precise", "aim_sensitivity", string.format("%.2f", it.v)) end
    end },
  { id = "fine_aim_turn", label = "Fine Aim aim turn speed", kind = "value", needs = "none", default = 0.4, min = 0.05, max = 1.0, step = 0.05,
    fmt = fmtx, live = true, oneshot = true, read = fine_value("sensitivity"), change = fine_set("sensitivity", "sensitivity_multiplier"),
    help = "How fast you turn while aiming with Fine Aim (x1 = as fast as not aiming)." },
  { id = "fine_aim_zoom", label = "Fine Aim zoom", kind = "value", needs = "none", default = 0.75, min = 0.25, max = 1.0, step = 0.05,
    fmt = fmt2, live = true, oneshot = true, read = fine_value("fov"), change = fine_set("fov", "fov_multiplier"),
    help = "Field of view while aiming with Fine Aim, as a share of the normal one (0.75 = a quarter narrower)." },
  { id = "fine_aim_spread", label = "Fine Aim spread", kind = "value", needs = "none", default = 0.25, min = 0, max = 1.0, step = 0.05,
    fmt = fmt2, live = true, oneshot = true, read = fine_value("spread"), change = fine_set("spread", "spread_multiplier"),
    help = "Bullet spread while aiming with Fine Aim (0 = none, 1 = the game's own)." },
  { id = "aim_camera", label = "Aim camera", kind = "list", needs = "none", items = AIM_PRESETS,
    help = "Precise Aim's camera: Left/Right to pick a style (Saints Row 1 to 2022 and yours), Enter to use it.",
    run = function(ctx, p, v, it)
      local M = precise()
      if not M then return "Precise Aim isn't loaded" end
      local e = AIM_PRESETS[it.v]
      if not M.apply(e[1]) then return "No camera called " .. e[2] end
      return "Aim camera: " .. e[2]
    end },
  { id = "aim_zoom", label = "Aim zoom", kind = "value", needs = "none", default = 0, min = -3.5, max = 0, step = 0.25,
    fmt = fmt2, live = true, oneshot = true, read = cam_value("zoom"), change = cam_set("zoom"),
    help = "How far Precise Aim's camera pulls in: 0 = not at all, every -2 halves the distance." },
  { id = "aim_fov", label = "Aim field of view", kind = "value", needs = "none", default = 0.6, min = 0.5, max = 1, step = 0.05,
    fmt = fmt2, live = true, oneshot = true, read = cam_value("fov"), change = cam_set("fov"),
    help = "Field of view while aiming, as a share of the normal one (0.60 = 40% narrower)." },
  { id = "aim_height", label = "Aim camera height", kind = "value", needs = "none", default = 1.69, min = 0.8, max = 2.6, step = 0.05,
    fmt = fmt2, live = true, oneshot = true, read = cam_value("height"), change = cam_set("height"),
    help = "Height of the aim camera above your feet, in metres." },
  { id = "aim_shoulder", label = "Aim shoulder", kind = "value", needs = "none", default = 0.35, min = -1.5, max = 1.5, step = 0.05,
    fmt = fmt2, live = true, oneshot = true, read = cam_value("shoulder"), change = cam_set("shoulder"),
    help = "Sideways offset of the aim camera, in metres: positive = right shoulder, negative = left." },
  { id = "aim_reset", label = "Reset aim camera", kind = "action", needs = "none",
    help = "Puts zoom, field of view, height and shoulder back to the picked camera's own values.",
    run = function()
      local M = precise()
      if not M then return "Precise Aim isn't loaded" end
      M.apply(M.preset())
      return "Aim camera reset to " .. aim_label(M.preset())
    end },
  { id = "aim_save", label = "Save as my camera", kind = "action", needs = "none",
    help = "Saves this aim camera as one of yours (up to 8); it is listed under Aim camera.",
    run = function()
      local M = precise()
      if not M then return "Precise Aim isn't loaded" end
      local name, note = M.save_custom()
      F.sync_aim_camera()
      if note and note:find("full") then return "All 8 of your cameras are used" end
      return "Saved as " .. aim_label(name)
    end },
})

-- Camera turn speed: the game's own look sensitivity, kept in mod.ini.
function F.set_camera_turn(v)
  if not (type(v) == "number" and v >= 0.5 and v <= 2.0) then return end
  local ok = read_f32(G.LOOK_SPEED_X)
  if not (ok > 0.05 and ok < 10) then return end
  write_f32(G.LOOK_SPEED_X, v); write_f32(G.LOOK_SPEED_Y, v)
  if F.ADDONS then F.ADDONS.save_setting(wml.mod_folder .. "/mod.ini", "camera_turn_speed", string.format("%.1f", v)) end
end
F.camera_turn_start = S("camera_turn_speed", 0)
function F.apply_precise_turning()
  local M = F.addon.precise
  if M and M.set_turning then M.set_turning(F.items.precise_turning.v == 1) end
end

end

category("Vehicles", {
  { id = "veh_god", label = "Vehicle god mode", kind = "toggle", needs = "vehicle", vbits_a = G.VFLAG_A.INVULNERABLE,
    help = "Your vehicle can't be damaged.",
    update = function(ctx, p, v, it)
      -- Health alone doesn't keep doors and panels on: parts are damaged on
      -- their own. Any damage gets the game's own full repair at once (the
      -- Repair now call: parts, dents, smoke). Repairing an undamaged car
      -- resets its lights, so it only happens when there is damage.
      -- Explosions can't break parts at all (main.lua's hook).
      local hp, max = read_u32(v + G.V.HP), read_u32(v + G.V.HP_MAX)
      if hp < max then G.call(ctx, G.VEHICLE_REPAIR, { v }, 1.0) end
      write_u32(v + G.V.HP, max)
    end },
  { id = "veh_repair", label = "Repair vehicle", kind = "action", needs = "vehicle", help = "",
    run = function(ctx, p, v) G.call(ctx, G.VEHICLE_REPAIR, { v }, 1.0); return "Repaired" end },
  { id = "tank", label = "Tank mode", kind = "toggle", needs = "vehicle", vbits_b = G.VFLAG_B.INFINITE_MASS, v = S("vehicle_tank", false),
    help = "Your vehicle can't be pushed around in collisions." },
  { id = "bulletproof", label = "Bulletproof glass", kind = "toggle", needs = "vehicle", vbits_b = G.VFLAG_B.BULLETPROOF_GLASS,
    help = "" },
  { id = "never_flat", label = "Bulletproof tires", kind = "toggle", needs = "vehicle", vbits_b = G.VFLAG_B.NEVER_FLAT,
    help = "" },
  { id = "no_fling", label = "No explosion fling", kind = "toggle", needs = "vehicle", vbits_a = G.VFLAG_A.NO_EXPLOSION_FLING,
    help = "Explosions no longer throw your vehicle." },
  { id = "car_grip", label = "Extra car grip", kind = "toggle", needs = "none",
    help = "Keeps your vehicle planted at high speed.",
    update = function(ctx, p, v) if p ~= 0 then F.car_grip(v) end end,
    off = function() F.car_grip(nil) end },
  { id = "nitro_all", label = "Nitrous in every vehicle", kind = "toggle", needs = "none", v = S("vehicle_nitrous_everywhere", false),
    help = "Every vehicle gets nitrous (Shift).",
    update = function() end,
    off = function() end },
  { id = "max_speed", label = "Extra top speed (mph)", kind = "value", needs = "vehicle", default = 0, min = 0, max = 300, step = 10, fmt = fmtint,
    help = "Raises your vehicle's top speed limit.",
    update = function(ctx, p, v, it)
      local e = G.engine_object(v)
      if not e then return end
      write_f32(e + G.ENGINE.EXTRA_TOP_SPEED, it.v * G.MPH_TO_MS)
      local flags = read_u8(e + G.ENGINE.FLAGS)
      if (flags & G.ENGINE_FLAG_EXTRA_SPEED) == 0 then write_u8(e + G.ENGINE.FLAGS, flags | G.ENGINE_FLAG_EXTRA_SPEED) end
    end,
    off = function(ctx, p, v)
      local e = v ~= 0 and G.engine_object(v)
      if e then
        write_f32(e + G.ENGINE.EXTRA_TOP_SPEED, 0)
        write_u8(e + G.ENGINE.FLAGS, read_u8(e + G.ENGINE.FLAGS) & ~G.ENGINE_FLAG_EXTRA_SPEED & 0xFF)
      end
    end },
  { id = "vehicle_custom", label = "Customize Vehicle", kind = "page", needs = "vehicle",
    open = function(ctx, p) return F.page_vehicle(ctx, p) end,
    help = "Every part and color your vehicle can have, free. Right stick / mouse turns the camera." },
  { id = "paint", label = "Paint vehicle", kind = "list", needs = "vehicle", items = PAINTS,
    help = "Press A / Enter to apply.",
    run = function(ctx, p, v, it)
      local paint = PAINTS[it.v]
      local ok, why = F.paint_car(ctx, v, "body", paint[3], paint[4])
      if not ok then return why end
      if F.second_paint and F.second_paint.vehicle == v then
        F.paint_car(ctx, v, "second", F.second_paint.pal, F.second_paint.col)  -- the body paint covers the second tone
      end
      return "Painted " .. paint[2] .. (why and (" (" .. why .. ")") or "")
    end },
  { id = "paint2", label = "Secondary color", kind = "list", needs = "vehicle", items = PAINTS,
    help = "Press A / Enter to apply.",
    run = function(ctx, p, v, it)
      local paint = PAINTS[it.v]
      local ok, why = F.paint_car(ctx, v, "second", paint[3], paint[4])
      if not ok then return why end
      F.second_paint = { vehicle = v, pal = paint[3], col = paint[4] }
      return "Second colour " .. paint[2] .. (why and (" (" .. why .. ")") or "")
    end },
  { id = "boom", label = "Destroy vehicle", kind = "action", needs = "vehicle", help = "",
    run = function(ctx) G.console(ctx, "boom"); return "Boom" end },
  { id = "spawn_vehicle", label = "Spawn vehicle", kind = "list", items = VEHICLES.spawn, needs = "player",
    help = "",
    run = function(ctx, p, _, it)
      local veh = VEHICLES.spawn[it.v]
      return F.spawn_vehicle(ctx, p, veh[1], veh[5]) and ("Spawned " .. veh[2]) or ("Could not spawn " .. veh[2])
    end },
  { id = "remove_vehicles", label = "Remove spawned vehicles", kind = "action", needs = "player", help = "",
    run = function(ctx) return F.remove_spawned(ctx, F.spawned_vehicles, "vehicle") end },
  { id = "garage", label = "Deliver to garage", kind = "list", items = VEHICLES, needs = "player",
    help = "Adds the selected vehicle to your garage.",
    run = function(ctx, p, _, it)
      local veh = VEHICLES[it.v]
      local index = G.call(ctx, G.VEHICLE_INDEX, { G.cstr(ctx, veh[1], 0) })
      if index == 0xFFFFFFFF then return "Unknown vehicle: " .. veh[1] end
      if read_u32(G.GARAGE_DROP_STATE) == 2 then return "A delivery is already on its way" end
      write_u32(G.GARAGE_DROP_INDEX, index)
      write_u32(G.GARAGE_DROP_STATE, 1)
      return "Delivering " .. veh[2] .. " to your garage"
    end },
})

-- ================================================================ World
category("World", {
  { id = "weather", label = "Weather", kind = "choice", needs = "none", options = WEATHER, help = "Default lets the weather change on its own.",
    change = function(ctx, p, _, it) G.script(ctx, string.format("set_weather(%d, true)", it.v - 2)) end },
  { id = "hour", label = "Time of day", kind = "value", needs = "none", default = 12, min = 0, max = 23, step = 1, fmt = fmtint, live = true, oneshot = true,
    help = "",
    read = function() return read_u8(G.VAR.CLOCK_HOUR) end,
    change = function(ctx, p, _, it) G.script(ctx, string.format("set_time_of_day(%d, 0)", it.v)) end },
  { id = "freeze_clock", label = "Freeze time", kind = "toggle", needs = "none", help = "",
    update = function(ctx, p, v, it)
      local rate = read_f32(G.VAR.CLOCK_RATE)
      if rate ~= 0 then it.saved = rate; write_f32(G.VAR.CLOCK_RATE, 0) end
    end,
    off = function(ctx, p, v, it) write_f32(G.VAR.CLOCK_RATE, it.saved or 40) end },
  { id = "clear", label = "Clear streets", kind = "action", needs = "none",
    help = "Removes all traffic and pedestrians. They return over time.",
    run = function(ctx)
      G.script(ctx, "spawning_remove_all()")
      enqueue("spawning_on()")   -- spawning_remove_all leaves spawning off
      return "Cleared"
    end },
  { id = "restore_traffic", label = "Restore streets", kind = "action", needs = "none",
    help = "Resumes traffic and pedestrians.",
    run = function(ctx) G.script(ctx, "spawning_on()"); return "Traffic and peds back on" end },
  { id = "drop", label = "Ragdoll all NPCs", kind = "action", needs = "player", help = "",
    run = function(ctx) G.console(ctx, "super_ragdoll"); return "Everybody drop!" end },
  { id = "kill_all", label = "Kill Everyone", kind = "action", needs = "player", help = "Kills every NPC nearby. Your homies are spared.",
    run = function(ctx, p) return F.kill_everyone(ctx, p) end },
  { id = "everybody", label = "Everybody...", kind = "list", needs = "player", items = {
      { { "dance a", "dance b", "dance c", "dance d" }, "Dance" },
      { { "breakdancer stand" }, "Breakdance" },
      { { "pole stand", "stage stand" }, "Strip dance" },
      { { "react cheer" }, "Cheer" },
      { { "drunk stand" }, "Drunk" },
      { { "surrender" }, "Hands up" },
      { { "cower stand", "cower stand variant 1", "cower stand variant 2" }, "Cower" },
      { { "zombie eat" }, "Zombie" },
      { { "tour Take Pictures" }, "Take pictures" },
      { false, "Back to normal" },
    },
    usable = function(ctx, p, choice) return not choice[1] or F.someone_can(ctx, p, choice[1]) end,
    help = "Left/Right to pick what people near you can do, Enter to start. Back to normal stops it.",
    run = function(ctx, p, _, it)
      local choice = it.items[it.v]
      F.everybody = choice[1] and choice or nil
      local n = F.apply_everybody(ctx, p, choice[1] or { "stand" })
      return choice[1] and string.format("Everybody: %s (%d people)", choice[2], n) or "Everybody back to normal"
    end },
  { id = "spawn_person", label = "Spawn person", kind = "list", needs = "player", items = CHARACTERS,
    help = "Spawns the selected person in front of you as a civilian.",
    run = function(ctx, p, _, it)
      local c = CHARACTERS[it.v]
      local ok, made_room = F.spawn_character(ctx, p, c[1])
      if not ok then return "Couldn't spawn " .. c[2] end
      return made_room and ("Spawned " .. c[2] .. " (the oldest spawned people made room)") or ("Spawned " .. c[2])
    end },
  { id = "crowd_small", label = "Spawn 10 random people", kind = "action", needs = "player", help = "",
    run = function(ctx) F.queue_crowd(10); return "Here they come" end },
  { id = "crowd_big", label = "Spawn a crowd (40)", kind = "action", needs = "player", help = "",
    run = function(ctx) F.queue_crowd(40); return "A crowd is forming" end },
  { id = "remove_people", label = "Remove spawned people", kind = "action", needs = "player", help = "",
    run = function(ctx) return F.remove_spawned(ctx, F.spawned_people, "person") end },
  { id = "cash_rain", label = "Drop cash around me", kind = "action", needs = "player",
    help = "Scatters 10 bills of $10 to $500 on the ground around you.",
    run = function() F.queue_drops("cash", 10); return "Making it rain" end },
  { id = "weapon_rain", label = "Drop weapons around me", kind = "list", items = WEAPONS.drop, needs = "player",
    help = "Drops 6 of the picked weapon, or a random mix, on the ground around you.",
    run = function(ctx, p, _, it)
      local w = WEAPONS.drop[it.v]
      F.queue_drops(w[1], 6)
      return "Dropped: " .. w[2]
    end },
  { id = "cash_drop_chance", label = "Cash drop chance", kind = "value", default = 25, min = 0, max = 100, step = 5,
    fmt = function(v) return string.format("%d%%", v) end,
    help = "How often people and gang members drop cash when they die. The game's own is 25%.",
    update = function() F.set_drop_chance(F.items.cash_drop_chance.v / 100) end,
    off = function() F.set_drop_chance(nil) end },
})

-- ================================================================ Visual
-- Render modes: the renderer's own switches. The console commands for most
-- of them do nothing in the retail game (their handlers only run when a
-- debug flag at 0x832ADFC0 is set), so the flags they set are written
-- directly. "Ugly mode" (0x8370D725, read all through the renderer, with
-- 0x827D6C14 / 0x827D7838 alongside) draws the world without textures. The
-- sky, world, props and characters each have a render flag (0x827D6B04,
-- 0x827D6B05, 0x827D6B07, 0x827D6BE0). Wireframe, polygon, collision and
-- box views have no code left in the retail renderer, so they aren't here.
do   -- (its own scope: the file is at Lua's limit of local names)
local RENDER = { UGLY = 0x8370D725, UGLY_F = 0x827D6C14, UGLY_W = 0x827D7838,
  SKY = 0x827D6B04, LEVEL = 0x827D6B05, STATIC = 0x827D6B07, CHARS = 0x827D6BE0 }
local render_saved = {}
local function flag(addr, on_value)
  return {
    on = function() render_saved[addr] = render_saved[addr] or read_u8(addr); write_u8(addr, on_value) end,
    off = function() if render_saved[addr] then write_u8(addr, render_saved[addr]); render_saved[addr] = nil end end }
end
local no_textures = {
  on = function()
    render_saved.ugly = render_saved.ugly or { read_u8(RENDER.UGLY), read_u32(RENDER.UGLY_F), read_u32(RENDER.UGLY_W) }
    write_u8(RENDER.UGLY, 1); write_f32(RENDER.UGLY_F, read_f32(0x82046438)); write_u32(RENDER.UGLY_W, 0)
  end,
  off = function()
    local s = render_saved.ugly
    if s then write_u8(RENDER.UGLY, s[1]); write_u32(RENDER.UGLY_F, s[2]); write_u32(RENDER.UGLY_W, s[3]); render_saved.ugly = nil end
  end }
F.RENDER_MODES = {
  { "Default", {} },
  { "No Sky", { flag(RENDER.SKY, 0) } },
  { "No Textures", { no_textures } },
  { "No People", { flag(RENDER.CHARS, 0) } },
  { "People Only", { flag(RENDER.LEVEL, 0), flag(RENDER.STATIC, 0) } },
}
F.RENDER_MODE_NAMES = {}
for i, m in ipairs(F.RENDER_MODES) do F.RENDER_MODE_NAMES[i] = m[1] end
F.render_mode = 1
function F.set_render_mode(ctx, n)
  for _, s in ipairs(F.RENDER_MODES[F.render_mode][2]) do s.off() end
  F.render_mode = n
  for _, s in ipairs(F.RENDER_MODES[n][2]) do s.on() end
  return "Render mode: " .. F.RENDER_MODES[n][1]
end
end
category("Visual", {
  { id = "hide_hud", label = "Hide HUD", kind = "toggle", needs = "player", help = "",
    change = function(ctx, p, v, it) G.script(ctx, it.v and "hud_hide()" or "hud_show()") end,
    off = function(ctx) G.script(ctx, "hud_show()") end },
  { id = "saturation", label = "Saturation", kind = "value", needs = "none", default = 1.0, min = 0, max = 2, step = 0.1, fmt = fmt1, float = G.VAR.SATURATION,
    help = "0 = black and white." },
  { id = "letterbox", label = "Letterbox", kind = "toggle", needs = "player", help = "",
    change = function(ctx, p, v, it) G.call(ctx, G.LETTERBOX, { it.v and 1 or 0 }) end,
    off = function(ctx) G.call(ctx, G.LETTERBOX, { 0 }) end },
  { id = "filter", label = "Filter", kind = "list", needs = "none", items = FILTERS,
    help = "",
    run = function(ctx, p, v, it) return F.set_filter(FILTERS[it.v]) end },
  { id = "free_cam", label = "Free camera", kind = "toggle", needs = "player", momentary = true,
    help = "Move: WASD / left stick. Look: mouse / right stick. Up / down: E / Q or triggers. Zoom: Z / X or LB / RB. Faster: Shift. A / Enter plays from this shot.",
    change = function(ctx, p, v, it)
      if it.v then
        if not FREECAM.enter(ctx) then it.v = false return "Free camera needs normal play (no menu screen open)" end
        FREECAM.set_mode(F.items.cam_mode.v)
        if F.items.cam_mode.v > 1 then return "Camera held here: close the menu to play" end
        return "Free camera on: close the menu to fly"
      else
        FREECAM.exit(ctx)
      end
    end,
    off = function(ctx) FREECAM.exit(ctx) end },
  { id = "cam_mode", label = "Free camera mode", kind = "choice", needs = "none", options = FREECAM.MODES,
    help = "Fly: move the camera freely. Fixed shot: the camera holds still while you play. Tracking shot: it holds still and follows you.",
    change = function(ctx, p, v, it)
      FREECAM.set_mode(it.v)
      if FREECAM.on then return it.v == 1 and "Flying the camera" or "Playing from the shot" end
      return "Used when Free camera is on"
    end },
  { id = "freeze_world", label = "Freeze world", kind = "toggle", needs = "player",
    help = "Pauses the world while the menu or the free camera is in use.",
    update = function()
      local frozen = MENU_OPEN() or FREECAM.flying()
      wml.write_f32(G.TIME_DIV, frozen and 100000 or 1.0)
    end,
    off = function() wml.write_f32(G.TIME_DIV, 1.0) end },
  { id = "render_mode", label = "Render mode", kind = "choice", needs = "player", options = F.RENDER_MODE_NAMES,
    help = "The renderer's own views: no sky, no textures, no people, or people only.",
    change = function(ctx, p, v, it) return F.set_render_mode(ctx, it.v) end,
    off = function(ctx) F.set_render_mode(ctx, 1) end },
})

-- ================================================================ Teleport
--
-- The cribs, from the game's own level files (the save point inside each
-- crib), so the height is right. (The garage spots put you inside a closed
-- garage, so they are not offered.)
-- { key, name, area, x, y, z }.
local PLACES = {
  { "church",      "Saints Row church",        "Saints HQ",   -732.0,  -2.1,    81.7 },
  { "sr_crib",     "Saints Row crib",          "Crib",        -656.4,  -3.6,  -159.2 },
  { "bar_crib",    "Barrio crib",              "Crib",         509.8,   8.4,   973.5 },
  { "penthouse",   "Downtown penthouse",       "Crib",        -890.1, 160.1, -1252.4 },
  { "pent_street", "Downtown penthouse door",  "Street",      -869.5,  22.1, -1249.4 },
  { "sub_crib",    "Suburbs crib",             "Crib",         351.0,  38.7, -2114.2 },
}
F.PLACES = PLACES

-- Moves the player (and their car and homies) to a spot with the game's own
-- script teleport, after telling the world to load there. `facing` (the
-- nine floats of a saved player's rows) turns you that way; without it you
-- keep the way you face.
function F.teleport_to(ctx, p, x, y, z, facing)
  F.last_teleport = { "menu teleport", F.tick }
  local pos = G.floats(ctx, { x, y + 0.5, z, 0 }, 0)
  local rows = G.floats(ctx, {}, 16)
  if facing then
    for i = 1, 9 do write_f32(rows + (i - 1) * 4, facing[i]) end
  else
    for i = 0, 32, 4 do write_u32(rows + i, read_u32(p + 32 + i)) end  -- keep the facing
  end
  G.call(ctx, G.STREAM_AT, { pos, 0, 0 })
  G.call(ctx, G.PLAYER_TELEPORT, { p, pos, rows })
  write_f32(p + G.P.FALL_START, x); write_f32(p + G.P.FALL_START + 4, y + 0.5); write_f32(p + G.P.FALL_START + 8, z)
end

-- Stores and activities, by the game's own navpoint names (places.lua):
-- the script teleport takes you to the navpoint outside a store's door, or
-- to where an activity starts.
local NAV_PLACES = require("places")
function F.teleport_nav(ctx, p, nav, name)
  if (G.vehicle_object(p) or 0) ~= 0 then return "Get out of the vehicle first" end
  F.last_teleport = { "menu teleport", F.tick }
  G.script(ctx, string.format('teleport("#PLAYER#", "%s")', nav))
  return "Teleported to " .. name
end
local function nav_groups(title, groups)
  return function()
    local rows = {}
    for _, g in ipairs(groups) do
      local list = {}
      for _, pl in ipairs(NAV_PLACES) do if pl[1] == g then list[#list + 1] = pl end end
      if #list > 0 then
        rows[#rows + 1] = { label = g, kind = "page", open = function()
          local r = {}
          for _, pl in ipairs(list) do
            r[#r + 1] = { label = pl[2], kind = "action", run = function(ctx, p) return F.teleport_nav(ctx, p, pl[3], pl[2]) end }
          end
          return { title = g, rows = r }
        end }
      end
    end
    return { title = title, rows = rows }
  end
end
local STORE_GROUPS = { "Clothing Stores", "Jewelry Stores", "Hair Salons", "Plastic Surgeons", "Tattoo Parlors", "Gun Stores", "Liquor Stores", "Music Stores", "Mechanics" }
local ACTIVITY_GROUPS = {}
do
  local seen = {}
  for _, pl in ipairs(NAV_PLACES) do
    local store = false
    for _, g in ipairs(STORE_GROUPS) do if g == pl[1] then store = true end end
    if not store and not seen[pl[1]] then seen[pl[1]] = true; ACTIVITY_GROUPS[#ACTIVITY_GROUPS + 1] = pl[1] end
  end
end

category("Teleport", {
  { id = "places", label = "Cribs", kind = "list", items = PLACES,
    help = "",
    run = function(ctx, p, _, it)
      local pl = PLACES[it.v]
      F.teleport_to(ctx, p, pl[4], pl[5], pl[6])
      return "Teleported to " .. pl[2]
    end },
  { id = "tp_stores", label = "Stores", kind = "page", open = nav_groups("Stores", STORE_GROUPS) },
  { id = "tp_activities", label = "Activities", kind = "page", open = nav_groups("Activities", ACTIVITY_GROUPS) },
  { id = "waypoint_auto", label = "Auto-teleport to waypoint", kind = "toggle", needs = "none", v = S("waypoint_teleport", false),
    help = "Setting a waypoint on the map takes you there.",
    change = function(ctx, p, v, it)
      if it.v and WAYPOINT.standalone then
        it.v = false
        return "Teleport to Waypoint mod is ticked in the loader; it already does this"
      end
    end },
  { id = "waypoint_go", label = "Teleport to waypoint", kind = "action",
    help = "",
    run = function() return WAYPOINT.go_now() end },
})

-- Movement style and the walk and run variants: in Customize (below Voice)
-- as your Playa, in Models when you play as someone else.
do
  local function find(name) for _, c in ipairs(F.categories) do if c.name == name then return c end end end
  local moved, player = {}, find("Player")
  for i = #player.items, 1, -1 do
    local it = player.items[i]
    if it.retired then table.remove(player.items, i); it.hidden = function() return true end end
  end
  -- One row per part of how you move (movement.lua): Default, then the
  -- animation sets that have that move, then the game's variants of it.
  for _, part in ipairs(F.MOVEMENT) do
    local items = { { 0, "Default" } }
    for k, opt in ipairs(part[5]) do items[#items + 1] = { k, opt[1] } end
    local row = { id = "move_part_" .. part[1], label = part[2], kind = "list", items = items, part = part[1],
      v = (F.move_parts[part[1]] or 0) + 1, needs = "player",
      run = function(ctx, p, _, it)
        F.move_parts[part[1]] = it.items[it.v][1]
        F.save_movement()
        F.apply_movement(ctx, p)
        F.keep_preview_move()
        return part[2] .. ": " .. it.items[it.v][2]
      end }
    moved[#moved + 1] = row
    F.items[row.id] = row
  end
  -- (in Models they show when you're someone else; in Customize they're on
  -- the Movement page, which is there for your Playa)
  for _, it in ipairs(moved) do
    it.hidden = function()
      if F.rows_tab == "Models" then return F.model.name == nil end
      return false
    end
  end
  local function insert_after(cat, id)
    local c = find(cat)
    if not c then return end
    local at = #c.items + 1
    for i, it in ipairs(c.items) do if it.id == id then at = i + 1 end end
    for k, it in ipairs(moved) do table.insert(c.items, at + k - 1, it) end
  end
  insert_after("Models", "missing_moves")
  -- Voice (Models): for a model that can take one (Lin), above the movement rows.
  do
    local models = find("Models")
    local at = #models.items + 1
    for i, it in ipairs(models.items) do if it == moved[1] then at = i break end end
    local row = { id = "model_voice", label = "Voice", kind = "page", needs = "player",
      help = "A gang voice for this character.",
      hidden = function() return not (F.model.name and F.MODEL_VOICES[F.model.name]) end,
      open = function(ctx, p) return F.page_model_voice(ctx, p) end }
    table.insert(models.items, at, row)
    F.items.model_voice = row
  end
  local custom = find("Customize")
  local at = #custom.items + 1
  for i, it in ipairs(custom.items) do if it.id == "style_voice" then at = i + 1 end end
  local page = { id = "style_movement", label = "Movement", kind = "page", needs = "player",
    help = "How your Playa stands, walks, runs, sprints and fights. The one under the cursor plays on the spot.",
    hidden = function() return F.model.name ~= nil end,
    open = function() return { title = "Movement", rows = moved } end }
  table.insert(custom.items, at, page)
  F.items.style_movement = page
  -- Customize as your Playa: Face & Body (Saved Presets to Skin) and Style
  -- (Saved Outfits, Clothes, Jewelry, Tattoos), then Personalization:
  -- Voice and Movement. The model rows (as someone else) stay as they are.
  local function take(id)
    for i, it in ipairs(custom.items) do if it.id == id then return table.remove(custom.items, i) end end
  end
  local face = {}
  for _, id in ipairs({ "style_presets", "style_head", "style_eyes", "style_hair", "style_body", "style_skin" }) do face[#face + 1] = take(id) end
  local style = { { label = "Saved Outfits", kind = "page", help = "Save up to 10 outfits and switch between them.",
    open = function(c, pp) return F.page_presets(c, pp, "outfit") end },
    { id = "style_remove_clothing", label = "Remove Clothing", kind = "page", help = "Takes off every piece of clothing for a clean slate.",
      open = function()
        local pg
        pg = { title = "Remove all clothing?", rows = {
          { label = "Yes", kind = "action", run = function(c, pp) pg.close_after = 1; return F.remove_clothing(c, pp) end },
          { label = "No", kind = "action", run = function() pg.close_after = 1 end } } }
        return pg
      end } }
  for _, id in ipairs({ "style_clothes", "style_jewelry", "style_tattoos" }) do style[#style + 1] = take(id) end
  local voice, movement = take("style_voice"), take("style_movement")
  local mine = function() return F.model.name ~= nil end
  local function section(id, label, rows, help)
    local row = { id = id, label = label, kind = "page", needs = "player", hidden = mine, help = help,
      open = function() return { title = label, rows = rows } end }
    F.items[id] = row
    return row
  end
  local tail = {
    section("style_face_body", "Face & Body", face, "Saved presets, head, eyes, hair, body and skin."),
    section("style_style", "Style", style, "Saved outfits, clothes, jewelry and tattoos."),
    { id = "style_personal", label = "Personalization", kind = "header", hidden = mine },
    voice, movement,
  }
  for _, row in ipairs(tail) do custom.items[#custom.items + 1] = row end
  custom.title = "Character"

end

-- ================================================================ Settings
category("Settings", {
  { id = "master", label = "All tweaks", kind = "toggle", needs = "none", v = true, help = "Turns every tweak on or off." },
  { id = "status", label = "Show active tweaks", kind = "action", needs = "none", help = "",
    run = function() return F.status_line() end },
  { id = "outfit_back", label = "Restore outfit", kind = "action", needs = "player",
    help = "Restores the outfit you wore before changing character.",
    run = function(ctx, p) return F.outfit_back(ctx, p) end },
  { id = "unlock_music", label = "Unlock all music", kind = "action", needs = "player",
    help = "Every song in the music store, ready for your playlists.",
    run = function(ctx) return F.unlock_music(ctx) end },
  { id = "unlock_collectibles", label = "Unlock all collectibles", kind = "action", needs = "player",
    help = "All 60 hidden CDs found, with every bonus song they unlock.",
    run = function(ctx, p) return F.unlock_collectibles(ctx, p) end },
  { id = "unlock_clothing", label = "Unlock all clothing", kind = "action",
    help = "Adds every clothing and jewelry item to your wardrobe.",
    run = function(ctx, p) return F.unlock_clothing(ctx, p) end },
  { id = "low_health_fx", label = "Low health visuals", kind = "toggle", needs = "none",
    help = "A pulsing dark red edge to the screen when your health is low." },
  { id = "low_sprint_fx", label = "Low sprint visuals", kind = "toggle", needs = "none",
    help = "The screen edges darken as your sprint runs out." },
  { id = "low_health_echo", label = "Low health sound echo", kind = "toggle", needs = "none",
    help = "The low health warning echoes softly as it ends, as in Saints Row 2 and 3." },
  { id = "look_pose", label = "Customization pose", kind = "choice", options = { "On", "Off" }, needs = "none",
    help = "Your character holds a T-pose while customizing." },
})

-- Animation Fallback and Cloth physics: in Settings.
do
  local models, settings
  for _, c in ipairs(F.categories) do
    if c.name == "Models" then models = c elseif c.name == "Settings" then settings = c end
  end
  for _, id in ipairs({ "missing_moves", "loose_parts" }) do
    for i, it in ipairs(models.items) do
      if it.id == id then settings.items[#settings.items + 1] = table.remove(models.items, i) break end
    end
  end
end

-- Voice Lines (Player): every situation the game has voice lines for, by
-- kind; a line plays in your character's voice (a gang's, your own, or the
-- model's you play as). A voice keeps a sound set per situation in its
-- record (human+3552: +(situation + 9) * 4, as the line player reads it);
-- with none, the error sound instead.
-- Facial Expressions (Customize > Personalization): the game's emotions
-- (emotions.xtbl), held on your face with human_set_override_emotion;
-- kept in expression.txt and put back after a respawn.
(function()
local SITS = require("voicelines")
local KIND = { combat = "Combat", cower = "Cowering", drug = "Drugs", escort = "Escort", flee = "Fleeing", group = "Group",
  hitman = "Hitman", hostage = "Hostage", loan = "Loan", misc = "Misc", observe = "Observing", pimping = "Pimping",
  special = "Special", taunt = "Taunts", threat = "Threats", voice = "Voice (pain, screams...)" }
-- (a voice has lines for only some situations: the value most of its
-- entries share is its "none", whatever it is)
local empty_of = {}
local function has_line(p, n)
  local per = read_u32(p + G.PERSONA_NOW)
  if not G.pointer_ok(per) then return false end
  local empty = empty_of[per]
  if empty == nil then
    local count, best, most = {}, 0, 0
    for k = 0, #SITS - 1 do
      local v = read_u32(per + (k + 9) * 4)
      count[v] = (count[v] or 0) + 1
      if count[v] > most then best, most = v, count[v] end
    end
    empty = most * 3 >= #SITS and best or false
    empty_of[per] = empty
  end
  local v = read_u32(per + (n + 9) * 4)
  return v ~= 0 and v ~= 0xFFFFFFFF and v ~= empty
end
F.has_voice_line = has_line
-- Only what this voice has: situations without a line are left out, and so
-- are kinds with none.
function F.page_voice_lines(ctx, p)
  local by, order = {}, {}
  for i, s in ipairs(SITS) do
    if has_line(p, i - 1) then
      local kind, what = s:match("^(%w+) %- (.+)$")
      kind = kind or "misc"
      if not by[kind] then by[kind] = {}; order[#order + 1] = kind end
      by[kind][#by[kind] + 1] = { i - 1, s, what or s }
    end
  end
  if #order == 0 then return "No voice lines for this character" end
  local rows = {}
  for _, kind in ipairs(order) do
    rows[#rows + 1] = { label = KIND[kind] or kind, kind = "page", open = function()
      local r = {}
      for _, e in ipairs(by[kind]) do
        r[#r + 1] = { label = e[3]:sub(1, 1):upper() .. e[3]:sub(2), kind = "action", run = function(c, pp)
          if not has_line(pp, e[1]) then return "No line for that in this voice" end
          F.menu_line = true
          G.script(c, string.format('audio_play_persona_line("#PLAYER#", "%s")', e[2]))
          F.menu_line = nil
          return e[3]
        end }
      end
      return { title = KIND[kind] or kind, rows = r }
    end }
  end
  return { title = "Voice Lines", rows = rows }
end

local EMOTIONS = { "None", "Angry", "Disgust", "Fear", "Joy", "Sad", "Surprise" }
local EXPRESSION_FILE = wml.mod_folder .. "/expression.txt"
F.expression = nil
do
  local file = io.open(EXPRESSION_FILE, "rb")
  if file then
    local e = (file:read("*a") or ""):match("^%s*(%a+)")
    file:close()
    if e and e ~= "None" then F.expression = e end
  end
end
local function show(ctx, e)
  if e and e ~= "None" then G.script(ctx, string.format('human_set_override_emotion("#PLAYER#", "%s")', e))
  else G.script(ctx, 'human_clear_override_emotion("#PLAYER#")') end
end
function F.page_expressions(ctx, p)
  local rows, cursor = {}, 1
  for i, e in ipairs(EMOTIONS) do
    rows[#rows + 1] = { label = e, kind = "action",
      note = function() return (F.expression or "None") == e and "CURRENT" or "" end,
      hover = function() F.wear_pending = { at = F.tick + 6, fn = function(c) show(c, e) end } end,
      run = function(c)
        F.wear_pending = nil
        F.expression = e ~= "None" and e or nil
        show(c, e)
        local file = io.open(EXPRESSION_FILE, "wb")
        if file then file:write(e, "\n"); file:close() end
        return "Expression: " .. e
      end }
    if (F.expression or "None") == e then cursor = i end
  end
  return { title = "Facial Expressions", rows = rows, cursor = cursor,
    back = function(c) F.wear_pending = nil; show(c, F.expression) end }
end
-- Held: put back every few seconds (a respawn or a cutscene clears it).
function F.update_expression(ctx, p)
  if p ~= 0 and F.expression and F.tick % 150 == 40 and not F.model.name then show(ctx, F.expression) end
end
end)()

-- Low health sound echo: the game's low health warning (SYS_HEALTH_WARNING)
-- heard once more, softer, as it ends - as in Saints Row 2 and 3. Every
-- sound the game plays is a request handed to 0x821FE3E8 (the sound's index
-- at +4, its volume at +20); the warning's is copied and handed in again.
-- The warning lasts 1.32 s (wave 440 of Other InMemory: 31744 samples at
-- 24 kHz); its echo starts as it ends, each time, so it keeps to the beat
-- however fast the warnings come (0.5 to 1 s apart, gameplay_constants).
do
  local SUBMIT, WARNING_ID = 0x821FE3E8, 0x827ACCF4
  local LENGTH, SHARE = 1.32, 0.3
  local echoes, step, last_update = {}, 0, nil
  G.hook(SUBMIT, function(ctx)
    local req = ctx:r(4) & 0xFFFFFFFF
    local item = F.items.low_health_echo
    if not F.echoing and item and item.v == true and G.pointer_ok(req) then
      local id = read_u32(WARNING_ID)
      if id ~= 0xFFFFFFFF and read_u32(req + 4) == id then
        local words = {}
        for k = 0, 15 do words[k] = read_u32(req + k * 4) end
        echoes = { { at = os.clock() + LENGTH, words = words, share = SHARE } }   -- (one at a time: never layered)
      end
    end
    ctx:call_original()
  end)  function F.update_echo(ctx)
    -- (each echo goes on the update nearest its time, not the first after it)
    local now = os.clock()
    if last_update then step = step + ((now - last_update) - step) * 0.2 end
    last_update = now
    if #echoes == 0 then return end
    local i = 1
    while i <= #echoes do
      local e = echoes[i]
      if now + math.min(step, 0.05) / 2 >= e.at then
        table.remove(echoes, i)
        local req, out = G.buffer(ctx, 0), G.buffer(ctx, 1)
        for k = 0, 15 do write_u32(req + k * 4, e.words[k]) end
        local v = read_f32(req + 20)
        if not (v > 0 and v <= 4) then v = 1 end
        write_f32(req + 20, v * e.share)
        F.echoing = true
        G.call(ctx, SUBMIT, { out, req })
        F.echoing = nil
      else
        i = i + 1
      end
    end
  end
end
-- Submenus: Player (Logic, Notoriety, Bodyguards, Extras, Voice Lines) and
-- Settings (Unlocks, Tweak Settings); Customize > Personalization gets
-- Facial Expressions. Rows keep their ids; only where they're shown moves.
do
  local function find(name) for _, c in ipairs(F.categories) do if c.name == name then return c end end end
  local function group(catname, groups, keep_first)
    local cat = find(catname)
    local by_id = {}
    for _, it in ipairs(cat.items) do by_id[it.id] = it end
    local taken, pages = {}, {}
    for _, g in ipairs(groups) do
      local rows = {}
      for _, id in ipairs(g[3]) do if by_id[id] then rows[#rows + 1] = by_id[id]; taken[id] = true end end
      local page = { id = g[1], label = g[2], kind = "page", needs = "none", help = g[4], page_rows = not g.open and rows or nil,
        open = g.open or function() return { title = g[2], rows = rows } end }
      F.items[g[1]] = page
      pages[#pages + 1] = page
    end
    local rest = {}
    for _, it in ipairs(cat.items) do if not taken[it.id] then rest[#rest + 1] = it end end
    local items = {}
    for k = 1, keep_first or 0 do if rest[k] then items[#items + 1] = rest[k] end end
    for _, pg in ipairs(pages) do items[#items + 1] = pg end
    for k = (keep_first or 0) + 1, #rest do items[#items + 1] = rest[k] end
    cat.items = items
  end
  group("Player", {
    { "player_logic", "Logic", { "god", "noclip", "no_ragdoll", "perfect_aim", "sprint", "run", "jump", "landing", "quick_crouch",
      "heal", "kill_self", "health_mult", "run_speed", "jump_boost", "jump_height", "swim_speed", "fall_damage" },
      "God mode, health, moving, jumping and aiming." },
    { "player_notoriety", "Notoriety", { "never_wanted", "saints_enemies", "no_cops", "no_gangs", "no_bust", "max_wanted",
      "wanted_police", "wanted_carnales", "wanted_vk", "wanted_rollerz", "wanted_saints" }, "Police and gangs." },
    { "player_bodyguards", "Bodyguards", { "bodyguard", "homie_group", "character_homie", "bodyguard_squad", "dismiss_homies", "homies" },
      "Homies and bodyguards." },
    { "player_voice_lines", "Voice Lines", {}, "Every line your character's voice has.", open = function(ctx, p) return F.page_voice_lines(ctx, p) end },
  })
  group("Settings", {
    { "settings_ui_plus", "UI+", { "low_health_fx", "low_sprint_fx", "low_health_echo" }, "Low health and low sprint screen effects, and the low health sound echo." },
    { "settings_unlocks", "Unlocks", { "unlock_music", "unlock_collectibles", "unlock_clothing" }, "Music, collectibles and clothing." },
    { "settings_tweaks", "Tweak Settings", { "outfit_back", "look_pose", "missing_moves", "loose_parts" },
      "Restore outfit, customization pose, animation fallback, cloth physics." },
  }, 1)
  -- Facial Expressions, below Voice.
  local custom = find("Customize")
  for i, it in ipairs(custom.items) do
    if it.id == "style_voice" then
      local row = { id = "style_expressions", label = "Facial Expressions", kind = "page", needs = "player",
        hidden = function() return F.model.name ~= nil end, help = "Joy, anger, fear and more, held on your face.",
        open = function(ctx, p) return F.page_expressions(ctx, p) end }
      table.insert(custom.items, i + 1, row)
      F.items.style_expressions = row
      break
    end
  end
end

-- ---------------------------------------------------------------- engine
--
-- Flag bits are applied every update to whatever the player / their car is
-- now, and cleared from the old car when they change or when switched off.
-- Floats and bytes are written every update while active and put back once.

local last_vehicle, last_handle = 0, 0

local function vehicle_bits_wanted()
  local a, b = 0, 0
  if F.enabled then
    for _, it in pairs(F.items) do
      if it.kind == "toggle" and it.v then
        if it.vbits_a then a = a | it.vbits_a end
        if it.vbits_b then b = b | it.vbits_b end
      end
    end
  end
  return a, b
end

local all_a, all_b = 0, 0
for _, it in pairs(F.items) do
  all_a = all_a | (it.vbits_a or 0)
  all_b = all_b | (it.vbits_b or 0)
end

local function apply_vehicle_bits(v)
  local a, b = vehicle_bits_wanted()
  if v == 0 then return end
  local fa, fb = read_u32(v + G.V.FLAGS_A), read_u32(v + G.V.FLAGS_B)
  local na = (fa & ~all_a & 0xFFFFFFFF) | a
  local nb = (fb & ~all_b & 0xFFFFFFFF) | b
  if na ~= fa then write_u32(v + G.V.FLAGS_A, na) end
  if nb ~= fb then write_u32(v + G.V.FLAGS_B, nb) end
end

local function clear_vehicle_bits(v)
  write_u32(v + G.V.FLAGS_A, read_u32(v + G.V.FLAGS_A) & ~all_a & 0xFFFFFFFF)
  write_u32(v + G.V.FLAGS_B, read_u32(v + G.V.FLAGS_B) & ~all_b & 0xFFFFFFFF)
end

-- Items whose state is active right now.
local function active(it)
  if not F.enabled then return false end
  if it.kind == "toggle" then return it.v end
  if it.kind == "value" and not it.oneshot then return it.v ~= it.default end
  return false
end

-- Items that were active last update and need their `off` run.
local was_active = {}

function F.on(id) return F.enabled and F.items[id].v end

-- Called every game update from the hook, after the game's own work.
F.tick = 0
local update_errors = {}
local function safe(it, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok and not update_errors[it.id] then
    update_errors[it.id] = true
    wml.log("feature " .. it.id .. " failed: " .. tostring(err))
  end
end

function F.set_menu_open(open) F_menu_open = open end

function F.update(ctx)
  F.tick = F.tick + 1
  local p = G.player()
  local v, h = 0, 0
  if p ~= 0 then
    local o, hh = G.vehicle_object(p)
    v, h = o or 0, hh or 0
  end
  if v ~= last_vehicle then
    if last_vehicle ~= 0 and G.vehicle_alive(last_vehicle, last_handle) then clear_vehicle_bits(last_vehicle) end
    last_vehicle, last_handle = v, h
  end
  if v ~= 0 then apply_vehicle_bits(v) end

  local pbits, p212 = 0, 0
  for _, it in pairs(F.items) do
    local on = active(it)
    local ok = it.needs == "none" or (it.needs == "player" and p ~= 0) or (it.needs == "vehicle" and v ~= 0)
    if on and ok then
      if it.pbits then pbits = pbits | it.pbits end
      if it.p212 then p212 = p212 | it.p212 end
      if it.byte then write_u8(it.byte[1], it.byte[2]) end
      if it.bits then G.set_bits(it.bits[1], it.bits[2], true) end
      if it.float then write_f32(it.float, it.v) end
      if it.update then safe(it, it.update, ctx, p, v, it) end
      was_active[it.id] = { p = p, v = v }
    elseif was_active[it.id] and not on then
      -- Switched off (or back to default): put things back once.
      local w = was_active[it.id]
      was_active[it.id] = nil
      if it.byte then write_u8(it.byte[1], it.byte[3]) end
      if it.bits then G.set_bits(it.bits[1], it.bits[2], false) end
      if it.float then write_f32(it.float, it.default) end
      if it.off then safe(it, it.off, ctx, p, v, it) end
    end
  end
  if F.debug and F.tick % 250 == 0 and p ~= 0 then
    local n = p + G.P.NOTORIETY + 4 * 24
    wml.log(string.format("police notoriety: level %d min %d max %d points %.1f decay %d; cops allowed %d, team no-spawn %d; traffic %d cars, spawning %d%d%d%d%d / %d%d%d%d%d, time div %.2f",
      read_u32(n), read_u32(n + 4), read_u32(n + 8), read_f32(n + 12), read_u32(n + 16) & 0xFFFFFFFF,
      read_u8(G.VAR.ALLOW_COPS), read_u8(G.POLICE_TEAM + 645), read_u32(0x8309A1C0),
      read_u8(0x8309A35C), read_u8(0x8309A35D), read_u8(0x8309A35E), read_u8(0x8309A35F), read_u8(0x8309A360),
      read_u8(0x8309A364), read_u8(0x8309A365), read_u8(0x8309A366), read_u8(0x8309A367), read_u8(0x8309A368),
      read_f32(G.TIME_DIV)))
  end
  if p ~= 0 then
    -- Player bits: set the wanted ones, clear the ones we manage but no
    -- longer want. The soft-landing shield in main.lua manages the
    -- invulnerability bit on its own while falling.
    local managed = G.FLAG.PERFECT_AIM | G.FLAG.NO_RAGDOLL | G.FLAG.NO_FLINCH
    local flags = read_u32(p + G.P.FLAGS)
    local nf = (flags & ~managed & 0xFFFFFFFF) | pbits
    if nf ~= flags then write_u32(p + G.P.FLAGS, nf); write_u32(p + G.P.DIRTY, read_u32(p + G.P.DIRTY) | 1) end
    local m212 = G.FLAG212.NO_EXPLOSION_FLING | G.FLAG212.NO_KNEECAP
    local w212 = read_u32(p + G.P.DIRTY)
    local n212 = (w212 & ~m212 & 0xFFFFFFFF) | p212
    if n212 ~= w212 then write_u32(p + G.P.DIRTY, n212) end
  end
  -- One queued script call and one queued person per update.
  if #F.queue > 0 and p ~= 0 then G.script(ctx, table.remove(F.queue, 1)) end
  if #F_WEAPON_QUEUE > 0 and p ~= 0 and G.playing(p) then F.give_weapon(ctx, table.remove(F_WEAPON_QUEUE, 1)) end
  if #F.spawn_queue > 0 and p ~= 0 and G.playing(p) then F.spawn_person(ctx, p, table.remove(F.spawn_queue, 1)) end
  F.apply_filter()
  if #F.watch_people > 0 then F.check_spawned() end
  if F.tick % 100 == 0 then F.sweep_people(ctx) end
  if p ~= 0 then F.limit_nitro(p) end
  if F.stop_requested then
    F.stop_requested = false
    if p ~= 0 and (F.posing or F.repeating or F.release_at or F.looping) then
      F.release_player(ctx, p)
      G.hud("Stopped")
    end
  end
  if F.release_at and F.tick >= F.release_at and not F.posing and not F.repeating then F.release_player(ctx, p) end
  if F.repeating then F.repeat_action(ctx, p) end
  if F.looping then F.loop_action(ctx, p) end
  if p ~= 0 and #burn_queue > 0 then burn_queued(ctx, p) end
  if p ~= 0 then F.drops_update(ctx, p) end
  if p ~= 0 then F.punch_update(ctx, p) end
  if next(patched) and not F.on("rocket_ammo") then F.restore_guns() end
  if F.posing then
    if p == 0 or read_f32(p + G.P.HEALTH) <= 0 or G.screen_up() or G.in_cutscene() then F.release_player(ctx, p) else F.hold_pose(ctx, p) end
  end
  F.sync_invulnerable(p)
  F.update_movement(ctx, p)
  F.update_model(ctx, p, v)
  F.update_bones(p)
  F.forgive_own_gang(ctx, p)
  if F.look.pending and F.tick >= F.look.pending and not F.model_job and p ~= 0 then F.look_apply(p) end
  F.update_wear(ctx, p)
  F.update_voice(ctx, p, F_menu_open)
  F.update_model_voice(ctx, p, F_menu_open)
  F.update_expression(ctx, p)
  F.update_echo(ctx)
  F.update_music(ctx)
  if F.tick % 25 == 0 and p ~= 0 then F.fix_guard_heads(ctx) end
  if p ~= 0 and not G.screen_up() and not G.in_cutscene() then
    if #F.scene_queue > 0 then F.spawn_scene_actor(ctx, p, table.remove(F.scene_queue, 1)) end
    if F.tick % 25 == 0 and #F.scene_actors > 0 then F.hold_scene(ctx) end
  end
  if F.everybody and p ~= 0 and F.tick % 100 == 0 and not G.screen_up() and not G.in_cutscene() then
    F.apply_everybody(ctx, p, F.everybody[1])
  end
  if p ~= 0 and G.playing(p) then
    if #F.guard_queue > 0 then F.spawn_guard(ctx, p, table.remove(F.guard_queue, 1)) end
    F.join_guards(ctx, p)
  end
end

-- ------------------------------------------------------------- no reload
--
-- The game starts a reload through one function (from an empty magazine,
-- the reload button or an idle top-up). While No reload is on, the player's
-- magazine is filled instead and the reload never starts.
-- ------------------------------------------------------------ their lines
--
-- While you're someone else, their own voice lines in a fight (the game's
-- persona situations, played on you as audio_play_persona_line does it):
-- a line after a kill and when reloading. Each situation keeps the game's
-- own chance and delays; a character with no line for it stays quiet.
local line_ready = {}
function F.character_line(situation, gap)
  local M = F.model
  if not (M and M.name and M.def) or F.tick < (line_ready[situation] or 0) then return end
  local p = G.player()
  if p == 0 or read_u32(p + G.HUMAN_DEF) ~= M.def then return end
  line_ready[situation] = F.tick + (gap or 200)
  enqueue(string.format('audio_play_persona_line_do("#PLAYER#", "%s", -1)', situation))
end

-- How often the character you're playing as talks. Every line a person says
-- goes through 0x82219298(human, situation, ...): the game's own (hitting
-- someone with a car, being shot at ...) and the ones above. For you, while
-- you're someone else, chatter is held to a chance and a gap between lines;
-- pain, death and fire screams (situations 69-77) always play.
local LINE_RATES = {           -- { chance, seconds between lines }
  [1] = false,                 -- Off
  [2] = { 0.20, 40 },          -- Rarely
  [3] = { 0.40, 20 },          -- Sometimes
  [4] = { 0.75, 8 },           -- Often
}
local last_line_tick = -100000
-- What others say about you while you're someone else: nobody remarks on
-- clothes (situations 36-39, "clothes not changed" and the style
-- compliments, and the insults 46-49 from anyone outside a gang), and the
-- gang of the character you play praises you instead of taunting you
-- (insults and flipping you off become compliments; no insults when you die).
local CLOTHES_LINES = { [36] = true, [37] = true, [38] = true, [39] = true }
local INSULTS = { [46] = true, [47] = true, [48] = true, [49] = true }
local PRAISE = { [45] = 37, [46] = 37, [47] = 38, [48] = 39, [49] = 37 }
function F.line_about_you(ctx, speaker, situation)
  local M = F.model
  if not (M and M.name and M.def) or situation < 36 or situation > 49 then return situation end
  local p = read_u32(G.PLAYER)
  if p == 0 or speaker == p or read_u32(p + G.HUMAN_DEF) ~= M.def then return situation end
  local mine = F.gang_of and F.gang_of(ctx, M.def)
  local theirs = G.pointer_ok(speaker) and F.gang_of and F.gang_of(ctx, read_u32(speaker + G.HUMAN_DEF))
  if mine and theirs == mine then
    if situation == 40 then return nil end
    return PRAISE[situation] or situation
  end
  if CLOTHES_LINES[situation] or (INSULTS[situation] and not theirs) then return nil end
  return situation
end
-- Out of breath (situation 73) in your own voice while you have a gang's.
-- Lip sync: a person saying a line gets the talking face animation
-- (SAY_LINE plays it on human+568 -> +3592 and stops it when the line ends),
-- except the player (+224 = 1): your character's mouth never moved. For your
-- own lines that mark is down while the game starts the line, so your mouth
-- moves with your voice (a gang's, your own or a model's) like everyone's.
local function say_original(ctx)
  local human, p = ctx:r(3) & 0xFFFFFFFF, read_u32(G.PLAYER)
  if human == 0 or human ~= p or read_u32(p + G.P.PLAYER_MARK) ~= 1 then
    ctx:call_original()
    return
  end
  write_u32(p + G.P.PLAYER_MARK, 0)
  local ok, err = pcall(ctx.call_original, ctx)
  write_u32(p + G.P.PLAYER_MARK, 1)
  if not ok then error(err) end
end
F.say_original = say_original
local function own_breath_call(ctx, saying)
  local human, situation = ctx:r(3) & 0xFFFFFFFF, ctx:r(4) & 0xFFFFFFFF
  if situation ~= 73 then return false end
  local p = read_u32(G.PLAYER)
  if human == 0 or human ~= p then return false end
  local was = F.own_breath(p, situation)
  if not was then return false end
  if saying then say_original(ctx) else ctx:call_original() end
  write_u32(p + G.PERSONA_NOW, was)
  return true
end
G.hook(G.SAY_LINE, function(ctx)
  if (ctx:r(4) & 0xFFFFFFFF) == 70 and (ctx:r(3) & 0xFFFFFFFF) == read_u32(G.PLAYER) then F.voice.screamed_at = F.tick end
  if own_breath_call(ctx, true) then return end
  local M = F.model
  local human, situation = ctx:r(3) & 0xFFFFFFFF, ctx:r(4) & 0xFFFFFFFF
  if M and M.name and situation >= 36 and situation <= 49 and not F.line_about_you(ctx, human, situation) then
    ctx:set_r(3, 0)
    return
  end
  -- (the model's own lines, held to the Character dialogue rate; not a gang
  -- voice you gave it, nor a line asked for in the menu)
  if M and M.name and human ~= 0 and human == read_u32(G.PLAYER) and read_u32(human + G.HUMAN_DEF) == M.def
      and not (situation >= 69 and situation <= 77) and not F.model_voice[M.name] and not F.menu_line then
    local rate = LINE_RATES[F.items.line_rate and F.items.line_rate.v or 3]
    if not rate or F.tick - last_line_tick < rate[2] * 50 or math.random() > rate[1] then
      ctx:set_r(3, 0)
      return
    end
    last_line_tick = F.tick
  end
  say_original(ctx)
end)

-- The line is picked for its situation at 0x8221AC00(human, situation, ...),
-- so the praise swap happens there.
G.hook(G.PLAY_LINE, function(ctx)
  if own_breath_call(ctx) then return end
  local situation = ctx:r(4) & 0xFFFFFFFF
  if F.model.name and situation >= 36 and situation <= 49 then
    local say = F.line_about_you(ctx, ctx:r(3) & 0xFFFFFFFF, situation)
    if not say then ctx:set_r(3, 0) return end
    if say ~= situation then ctx:set_r(4, say) end
  end
  ctx:call_original()
end)

G.hook(G.RELOAD, function(ctx)
  local human = ctx:r(3) & 0xFFFFFFFF
  if human ~= 0 and human == read_u32(G.PLAYER) then F.character_line("combat - reload required", 500) end
  if F.on("no_reload") and human ~= 0 and human == read_u32(G.PLAYER) then
    local item = read_u32(human + G.P.EQUIPPED)
    local ammo = G.pointer_ok(item) and read_u32(item + 16) or 0
    local info = G.pointer_ok(ammo) and read_u32(ammo + 8) or 0
    if G.pointer_ok(info) and read_u32(info + 100) < 2 then
      local mag = read_u16(info + 104)
      if mag >= 1 then
        write_u32(ammo + 16, mag)
        if read_u32(ammo + 20) < 1 then write_u32(ammo + 20, 1) end
        ctx:set_r(3, 0)
        return
      end
    end
  end
  ctx:call_original()
end)

-- ------------------------------------------------------------- crowds
--
-- People are made the way the co-op mod makes its players' copies: look the
-- model up by name, move the spot off anyone standing there, create an
-- ambient person (kind 3, so the game tidies them away itself), then take a
-- streaming reference on the model or nothing is drawn.
local CIVILIANS = {
  "PD_X_M_BusinessMan-01", "PD_X_F_BusinessWoman-01", "PD_X_F_BusinessWoman-02", "PD_X_M_GenericYoung-01",
  "PD_X_M_GenericYoung-02", "pd_x_f_genericyoung-01", "PD_X_F_GenericYoung-02", "PD_X_F_GenericYoung-03",
  "PD_X_M_MiddleAge-01", "PD_X_M_MiddleAge-02", "PD_X_M_MiddleAge-03", "PD_X_F_MiddleAge-01", "PD_X_F_MiddleAge-02",
  "PD_X_M_Jogger-01", "PD_X_F_Jogger-01", "PD_X_F_Rollerskater-01", "PD_X_M_OldMan-01", "PD_X_F_OldWoman-01",
  "PD_X_M_Construction-01", "PD_X_M_Dockworker", "PD_X_M_Garbageman", "PD_X_M_Mailman-01", "PD_X_M_UPS-01",
  "PD_X_M_Trucker-01", "PD_X_M_Utilityworker", "PD_X_M_HighIncome", "PD_X_M_Hustler-01", "PD_X_M_Pimp-02",
  "PD_W_M_Cowboy-01", "PD_W_M_Hippie-01", "PD_W_F_Hippie-01", "PD_W_M_Fatman", "PD_W_M_Bum", "PD_X_F_Baglady-01",
  "PD_X_M_sportsFan-01", "PD_W_M_Mascot-01", "PD_X_M_FoodMascot-01", "PD_B_M_Bouncer-01", "PD_X_M_Poor-01", "PD_X_F_Poor-01",
}
F.spawned_people, F.spawned_vehicles = {}, {}
local MAX_SPAWNED_PEOPLE, MAX_SPAWNED_VEHICLES = 30, 8

-- True while the handle still names that object.
local function handle_alive(handle)
  local index = handle & 0xFFFF
  if handle == 0 or index >= 4096 then return false end
  local object = read_u32(G.OBJECTS + 12 + index * 16)
  return object ~= 0 and read_u32(object + 68) == handle
end

-- People. The game holds at most 12 person models at once; asking for one
-- more pushes a loaded model out, and the game then deletes everyone using
-- it who has no mission script and isn't in your party. So every person the
-- menu makes holds one reference on their model, given back when they go;
-- main.lua tells the game they may never be deleted (while their model is
-- out they are only hidden, back when it loads); and Spawn person keeps to
-- MAX_PERSON_MODELS kinds of person at once.
F.our_people = {}   -- handle -> model id (false if unknown)
local MAX_PERSON_MODELS = 8

local function keep_person(ctx, obj)
  local handle = read_u32(obj + 68)
  local desc = read_u32(obj + G.HUMAN_DEF)
  local id = G.pointer_ok(desc) and read_u32(desc + 608) or false
  if id then G.call(ctx, G.STREAM_REF, { G.STREAM_TABLE + (id >> 24) * 204, id, 5, 0, 1 }) end
  F.our_people[handle] = id
  return handle
end

local function release_person(ctx, handle)
  local id = F.our_people[handle]
  if id == nil then return end
  F.our_people[handle] = nil
  if id then G.call(ctx, G.STREAM_RELEASE, { G.STREAM_TABLE + (id >> 24) * 204, id, 5, 0, 0 }) end
end

-- Models given back for people who are gone (killed, sent home, cleared).
function F.sweep_people(ctx)
  for handle in pairs(F.our_people) do
    if not handle_alive(handle) then release_person(ctx, handle) end
  end
end

local function person_models()
  local seen, n = {}, 0
  for _, id in pairs(F.our_people) do
    if id and not seen[id] then seen[id] = true; n = n + 1 end
  end
  return n, seen
end

local function destroy(ctx, handle)
  if handle_alive(handle) then G.call(ctx, G.OBJECT_DESTROY, { handle }) end
  release_person(ctx, handle)
end

-- Keeps the list of things we made within `limit`, removing the oldest.
local function make_room(ctx, list, limit)
  while #list >= limit do destroy(ctx, table.remove(list, 1)) end
end

function F.remove_spawned(ctx, list, what)
  local n = #list
  for i = #list, 1, -1 do destroy(ctx, table.remove(list, i)) end
  return string.format("Removed %d %s%s", n, what, n == 1 and "" or "s")
end

function F.queue_crowd(n)
  for _ = 1, n do F.spawn_queue[#F.spawn_queue + 1] = CIVILIANS[math.random(#CIVILIANS)] end
end

-- A spot `dist` metres in front of the camera, at the player's height + lift.
-- Spawn person spots: an arc in front of you, nearest first, so people
-- don't stand inside each other. It starts over once you move away.
local PERSON_SPOTS = { { 0, 3 }, { -40, 3 }, { 40, 3 }, { -80, 3 }, { 80, 3 }, { -20, 4.5 }, { 20, 4.5 },
  { -60, 4.5 }, { 60, 4.5 }, { 0, 6 }, { -40, 6 }, { 40, 6 } }
F.person_spot = { n = 0 }
local function person_spot(p)
  local x, y, z = G.vec(p + G.P.POS)
  local ps = F.person_spot
  if not ps.x or (x - ps.x) ^ 2 + (z - ps.z) ^ 2 > 16 then ps.n, ps.x, ps.z = 0, x, z end
  ps.n = ps.n % #PERSON_SPOTS + 1
  local spot = PERSON_SPOTS[ps.n]
  local fx, fz = read_f32(G.CAMERA + 104), read_f32(G.CAMERA + 112)
  local len = math.sqrt(fx * fx + fz * fz)
  if len < 0.01 then fx, fz, len = 0, 1, 1 end
  fx, fz = fx / len, fz / len
  local a = math.rad(spot[1])
  local dx, dz = fx * math.cos(a) + fz * math.sin(a), fz * math.cos(a) - fx * math.sin(a)
  return x + dx * spot[2], y + 0.1, z + dz * spot[2]
end

local function spot_ahead(p, dist, lift)
  local x, y, z = G.vec(p + G.P.POS)
  local fx, fz = read_f32(G.CAMERA + 104), read_f32(G.CAMERA + 112)
  local len = math.sqrt(fx * fx + fz * fz)
  if len < 0.01 then fx, fz, len = 0, 1, 1 end
  return x + fx / len * dist, y + lift, z + fz / len * dist
end

-- Drops a vehicle in front of the player: create, model request, place.
-- variant: one of the car's named versions (nil = the game's random pick).
function F.spawn_vehicle(ctx, p, name, variant)
  local index = G.call(ctx, G.VEHICLE_INDEX, { G.cstr(ctx, name, 0) })
  if index == 0xFFFFFFFF then return false end
  make_room(ctx, F.spawned_vehicles, MAX_SPAWNED_VEHICLES)
  local x, y, z = spot_ahead(p, 7, 1.0)
  local pos = G.floats(ctx, { x, y, z, 0 }, 0)
  local rows = G.floats(ctx, { 1, 0, 0, 0, 1, 0, 0, 0, 1 }, 16)
  -- Creation type 7 is how the game's own vehicle cheat and mission scripts
  -- make cars (3 is the co-op mod's remote copy, which came without nitrous).
  -- The last argument is the variant's name, as missions pass it.
  local vname = variant and G.cstr(ctx, variant, 1) or 0
  local handle = G.call(ctx, G.VEHICLE_CREATE, { 7, 2, index, pos, rows, 0, 0, vname }, 0.0,
    { { 84, 4, 0 }, { 95, 1, 0 }, { 100, 4, 0 } })
  if handle == 0 then if F.debug then wml.log("spawn vehicle: the game's pool of vehicles is full") end return false end
  local vehicle = G.call(ctx, G.VEHICLE_FROM_HANDLE, { handle })
  if not G.pointer_ok(vehicle) then return false end
  -- The game's own model request for a car: it is recorded on the car, so
  -- the reference is given back when the car goes. (A raw reference here
  -- was never given back: spawned cars, trailers especially, kept their
  -- models in memory until traffic and cop cars had no room left.)
  G.call(ctx, G.VEHICLE_MODEL_REF, { vehicle, 5 })
  G.call(ctx, G.VEHICLE_PLACE, { vehicle, pos, rows, 0 })
  F.spawned_vehicles[#F.spawned_vehicles + 1] = handle
  if F.debug then
    wml.log(string.format("spawn vehicle: %s index %d handle %08X at %.1f %.1f %.1f", name, index, handle, x, y, z))
    -- vehicle+216 is the chosen variant (-1 = the name didn't match, random look).
    if variant then wml.log(string.format("spawn vehicle: variant %s -> %d", variant, (read_u32(vehicle + 216) + 0x80000000) % 0x100000000 - 0x80000000)) end
  end
  return true
end
function F.spawn_person(ctx, p, name)
  local def = G.call(ctx, G.MODEL_LOOKUP, { G.cstr(ctx, name, 0), 0 })
  if not G.pointer_ok(def) then if F.debug then wml.log("spawn: unknown model " .. name) end return end
  make_room(ctx, F.spawned_people, MAX_SPAWNED_PEOPLE)
  local x, y, z = G.vec(p + G.P.POS)
  local angle, dist = math.random() * 2 * math.pi, 3 + math.random() * 6
  local pos = G.floats(ctx, { x + math.cos(angle) * dist, y + 0.5, z + math.sin(angle) * dist, 0 }, 0)
  local rows = G.floats(ctx, { 1, 0, 0, 0, 1, 0, 0, 0, 1 }, 16)
  G.call(ctx, G.NUDGE_SPOT, { pos })
  local obj = G.call(ctx, G.HUMAN_CREATE, { 3, 2, def, pos, rows, 255, 0, 0 }, nil,
    { { 84, 4, 0 }, { 94, 2, 8 }, { 103, 1, 0 } })
  if not G.pointer_ok(obj) or obj == p then if F.debug then wml.log("spawn: the game's pool of people is full") end return end
  if not handle_alive(read_u32(obj + 68)) then return end
  F.spawned_people[#F.spawned_people + 1] = keep_person(ctx, obj)
  if F.debug then wml.log(string.format("spawn: %s at %.1f %.1f %.1f (%d kept)", name, x, y, z, #F.spawned_people)) end
end

-- ------------------------------------------------------------- rocket ammo
--
-- The gun in your hands borrows the RPG's rocket fields (explosion +144,
-- underwater explosion +148, the rocket block +312..+351) while Rocket ammo
-- is on; the originals are kept. Only around your own shots is the gun's
-- Ammo_Type set to projectile (and the RPG's rocket-flight bits added to
-- +12, and Shots_Per_Round +164 set to 1 so shotguns fire one rocket), so
-- the muzzle flash, sound, fire rate and magazine stay the gun's own and
-- NPCs with the same gun keep firing bullets. A gun is only put back when
-- no rocket fired from it is still in the air: a flying rocket reads those
-- fields.
local ROCKET_FIELDS = { 144, 148, 312, 316, 320, 324, 328, 332, 336, 340, 344, 348 }
local rpg_info = nil
-- Fast guns would launch 20+ rockets a second, which swamps the game's
-- rocket pool and physics and crashed it. Rockets are limited to one every
-- ROCKET_GAP seconds and ROCKET_MAX in the air; shots in between fire as the
-- gun's own bullets.
local ROCKET_GAP, ROCKET_MAX = 0.1, 16
local last_rocket = -1
-- Rockets of ours in the air: projectiles whose weapon (+208) is a gun we
-- patched. (Counting every projectile included grenades, molotovs and other
-- people's rockets, which held rocket ammo back.)
local function rockets_in_air()
  local head = read_u32(G.PROJECTILES)
  if not G.pointer_ok(head) then return 0 end
  local n, count = head, 0
  for _ = 1, 256 do
    if patched[read_u32(n + 208)] then count = count + 1 end
    n = read_u32(n + 204)
    if n == head or not G.pointer_ok(n) then break end
  end
  return count
end

local function weapon_info(name)
  local base, n = read_u32(G.WEAPON_INFOS), read_u32(G.WEAPON_COUNT)
  if not G.pointer_ok(base) or n > 200 then return nil end
  for i = 0, n - 1 do
    local info = base + i * 520
    local np = read_u32(info)
    if G.pointer_ok(np) then
      local chars = {}
      for k = 0, 31 do local c = read_u8(np + k) if c == 0 then break end chars[#chars + 1] = string.char(c) end
      if table.concat(chars) == name then return info end
    end
  end
end

-- ------------------------------------------------------------- pickups
--
-- Cash and weapons dropped on the ground with the game's own pickup
-- creates (see game.lua), a few per update. The money gun notes where each
-- of your bullets stops and throws a bill from you to there on an arc, so
-- it flies out of the gun and lands at the hit; in a car (or point blank)
-- the bill just appears there.
do
  local drops, bills = {}, {}
  local last_bill, saved_chance = 0, nil
  local BILL_SPEED, BILL_REACH = 22, 40   -- m/s, and how far a miss flies
  local function cash_at(ctx, x, y, z, dollars, pop)
    local item = G.call(ctx, G.CASH_AT, { G.floats(ctx, { x, y, z }, 0), G.ROWS_ID, 0, pop and 1 or 0, 255 }, dollars)
    if G.pointer_ok(item) then return item end
  end
  local function weapon_at(ctx, name, x, y, z)
    local wi = weapon_info(name)
    local item_info = wi and read_u32(wi + 28) or 0
    if not G.pointer_ok(item_info) then if F.debug then wml.log("drop: no pickup for " .. name) end return end
    local rec = G.buffer(ctx, 2)
    for i = 0, 92, 4 do write_u32(rec + i, 0) end
    write_u8(rec, 0x90)
    write_u32(rec + 4, item_info)
    write_f32(rec + 8, x); write_f32(rec + 12, y); write_f32(rec + 16, z)
    for i = 0, 8 do write_f32(rec + 20 + i * 4, (i % 4 == 0) and 1 or 0) end
    write_u32(rec + 56, 255)
    write_u32(rec + 60, read_u32(G.PHYS_GROUP))
    write_f32(rec + 64, -1.0)
    write_u32(rec + 68, 0xFFFFFFFF)
    local item = G.call(ctx, G.ITEM_CREATE, { rec })
    if not G.pointer_ok(item) then return end
    -- A full magazine, as the weapon cheat gives.
    local ammo = read_u32(item + 220)
    local info = G.pointer_ok(ammo) and read_u32(ammo + 8) or 0
    if G.pointer_ok(info) then
      local clip = read_u16(info + 104)
      if clip > 0 and clip < 1000 then write_u32(ammo + 16, clip) end
    end
    G.call(ctx, G.ITEM_POP, { item })
    return item
  end

  function F.queue_drops(what, n)
    for _ = 1, n do if #drops < 40 then drops[#drops + 1] = what end end
  end

  -- Both cash chances at f (0..1), or the game's own back (nil).
  function F.set_drop_chance(f)
    if f then
      saved_chance = saved_chance or { read_f32(G.CASH_CHANCE), read_f32(G.CASH_CHANCE + 4) }
      write_f32(G.CASH_CHANCE, f); write_f32(G.CASH_CHANCE + 4, f)
    elseif saved_chance then
      write_f32(G.CASH_CHANCE, saved_chance[1]); write_f32(G.CASH_CHANCE + 4, saved_chance[2])
      saved_chance = nil
    end
  end

  G.hook(G.BULLET_RAY, function(ctx)
    local out, shooter = ctx:r(3) & 0xFFFFFFFF, ctx:r(5) & 0xFFFFFFFF
    ctx:call_original()
    if not F.on("money_gun") or #bills >= 8 then return end
    local p = read_u32(G.PLAYER)
    if p == 0 or shooter ~= p or not G.pointer_ok(out) then return end
    -- One bill per shot, not per pellet, and no more than about 12 a second.
    local now = os.clock()
    if now - last_bill < 0.08 then return end
    last_bill = now
    bills[#bills + 1] = { read_f32(out), read_f32(out + 4), read_f32(out + 8) }
  end)

  function F.drops_update(ctx, p)
    if #drops == 0 and #bills == 0 then return end
    if read_u8(G.MULTIPLAYER) ~= 0 then drops, bills = {}, {} return end
    local px, py, pz = G.vec(p + G.P.POS)
    for _ = 1, 2 do
      local what = table.remove(drops, 1)
      if not what then break end
      local a, r = math.random() * 2 * math.pi, 2 + math.random() * 5
      local x, y, z = px + math.cos(a) * r, py + 1.5, pz + math.sin(a) * r
      if what == "cash" then
        cash_at(ctx, x, y, z, math.random(1, 50) * 10, true)
      else
        weapon_at(ctx, what == "random" and WEAPONS[math.random(#WEAPONS)][1] or what, x, y, z)
      end
    end
    if not F.on("money_gun") then bills = {} return end
    local dollars = F.items.money_gun_cash.v
    for _ = 1, 3 do
      local hit = table.remove(bills, 1)
      if not hit then break end
      local sy = py + 1.3
      local dx, dy, dz = hit[1] - px, hit[2] - sy, hit[3] - pz
      local d = math.sqrt(dx * dx + dy * dy + dz * dz)
      if d > BILL_REACH then local k = BILL_REACH / d; dx, dy, dz, d = dx * k, dy * k, dz * k, BILL_REACH end
      if d < 1.5 or G.vehicle_object(p) then
        cash_at(ctx, px + dx, sy + dy + 0.3, pz + dz, dollars, true)
      else
        local ux, uy, uz = dx / d, dy / d, dz / d
        local item = cash_at(ctx, px + ux * 0.8, sy + uy * 0.8, pz + uz * 0.8, dollars, false)
        local body = item and read_u32(item + 116)
        if body and body ~= 0xFFFFFFFF then
          -- Straight at the hit, plus the lift gravity takes off on the way.
          local t = d / BILL_SPEED
          G.call(ctx, G.SET_VELOCITY, { body, G.floats(ctx, { dx / t, dy / t + 4.9 * t, dz / t }, 32) })
        end
      end
    end
  end
end

-- ------------------------------------------------------------- explosive punches
--
-- Your melee hits (the game's melee hit, so never the blast's own damage,
-- fire or falls) on a person or a car are noted and blown up on the next
-- update; a short shield keeps you out of it. "Small Bang" is the big test
-- effect, so Small is the propane tank's blast.
do
  local queue, last = {}, -1
  local BLASTS = { "Propane Tank", "Grenade", "RPG", "Big Bang" }
  local GAP = 0.5   -- seconds between blasts
  G.hook(G.MELEE_HIT, function(ctx)
    local target, attacker = ctx:r(3) & 0xFFFFFFFF, ctx:r(4) & 0xFFFFFFFF
    ctx:call_original()
    if not F.on("explosive_punch") or #queue >= 2 then return end
    local p = read_u32(G.PLAYER)
    if p == 0 or attacker ~= p or target == p or not G.pointer_ok(target) then return end
    local kind = read_u32(target + 72)
    if kind ~= 1 and kind ~= 5 then return end   -- people and cars
    local now = os.clock()
    if now - last < GAP then return end
    last = now
    queue[#queue + 1] = read_u32(target + 68)
  end)
  function F.punch_update(ctx, p)
    if #queue == 0 then return end
    if read_u8(G.MULTIPLAYER) ~= 0 then queue = {} return end
    local h = table.remove(queue, 1)
    local index = h & 0xFFFF
    local v = index < 4096 and read_u32(G.OBJECTS + 12 + index * 16) or 0
    if not (G.pointer_ok(v) and read_u32(v + 68) == h) then return end
    local def = G.call(ctx, G.EXPLOSION_DEF, { G.cstr(ctx, BLASTS[F.items.punch_blast.v] or "Grenade", 0) })
    if not G.pointer_ok(def) then if F.debug then wml.log("explosive punch: no explosion def") end return end
    F.shields.punch = F.tick + 40   -- 0.8 s, on before the blast lands
    F.sync_invulnerable(p)
    G.call(ctx, G.EXPLOSION, { def, p, 0, v + 32, v + G.P.POS, 0, 0, 0 }, nil,
      { { 84, 4, 0 }, { 92, 4, 0 }, { 103, 1, 0 }, { 111, 1, 0 } })
    if F.debug then wml.log("explosive punch: " .. BLASTS[F.items.punch_blast.v] .. (read_u32(v + 72) == 5 and " on a car" or "")) end
  end
end

-- Rapid fire: every weapon record's Refire_Delay (+122, ms; the player's
-- own, enemies use +124/+126) cut while on, the game's values put back off.
local fast_saved = nil
function F.faster_guns(on)
  if on and not fast_saved then
    local base, n = read_u32(G.WEAPON_INFOS), read_u32(G.WEAPON_COUNT)
    if not G.pointer_ok(base) or n == 0 or n > 200 then return end
    fast_saved = {}
    for i = 0, n - 1 do
      local info = base + i * 520
      local delay = read_u16(info + G.W.REFIRE)
      if delay > 0 then
        fast_saved[info] = delay
        local mult = read_u32(info + G.W.CLASS) == G.W.SHOTGUN and 4 or 2
        write_u16(info + G.W.REFIRE, math.min(delay, math.max(40, math.floor(delay / mult + 0.5))))
      end
    end
  elseif not on and fast_saved then
    for info, delay in pairs(fast_saved) do write_u16(info + G.W.REFIRE, delay) end
    fast_saved = nil
  end
end

-- Harder hits: every weapon's Ragdoll_Force_Shoot (+304) times three while
-- on, put back off. The game uses it for the shot that kills.
local force_saved = nil
function F.harder_hits(on)
  if on and not force_saved then
    local base, n = read_u32(G.WEAPON_INFOS), read_u32(G.WEAPON_COUNT)
    if not G.pointer_ok(base) or n == 0 or n > 200 then return end
    force_saved = {}
    for i = 0, n - 1 do
      local info = base + i * 520
      local force = read_f32(info + G.W.FORCE)
      if force > 0 and force < 100000 then
        force_saved[info] = force
        write_f32(info + G.W.FORCE, force * 3)
      end
    end
  elseif not on and force_saved then
    for info, force in pairs(force_saved) do write_f32(info + G.W.FORCE, force) end
    force_saved = nil
  end
end

-- A global float set while a toggle is on, the game's value put back off.
local held = {}
function F.hold_float(addr, value)
  if held[addr] == nil then held[addr] = read_f32(addr) end
  if read_f32(addr) ~= value then write_f32(addr, value) end
end
function F.release_float(addr)
  if held[addr] ~= nil then write_f32(addr, held[addr]); held[addr] = nil end
end

-- Extra car grip: the car you drive gets 5 m/s^2 more downforce (the game
-- uses 20 on most cars); the car you leave gets its own back.
local grip = nil
local function downforce_addr(v)
  local e = G.engine_object(v)
  local action = e and read_u32(e + G.ENGINE_ACTION)
  if not action or not G.pointer_ok(action) then return nil end
  return action + G.ACTION_DOWNFORCE
end
function F.car_grip(v)
  if grip and (grip.v ~= v or not G.vehicle_alive(grip.v, grip.handle)) then
    if G.vehicle_alive(grip.v, grip.handle) then
      local addr = downforce_addr(grip.v)
      if addr and addr == grip.addr then write_f32(addr, grip.own) end
    end
    grip = nil
  end
  if not v or v == 0 then return end
  local addr = downforce_addr(v)
  if not addr then return end
  if not grip or grip.addr ~= addr then
    local own = read_f32(addr)
    if own > 0 or own < -1000 then return end
    grip = { v = v, handle = read_u32(v + 68), addr = addr, own = own }
  end
  if read_f32(addr) ~= grip.own - 5 then write_f32(addr, grip.own - 5) end
end

-- Health multiplier: the player's maximum health (+1908) times the
-- multiplier, the bar keeping its share. The game's own maximum is what it
-- last set (a new player after dying or a health upgrade starts over).
local health = nil
function F.scale_health(p, mult)
  if not p or p == 0 then return end
  local max = read_u32(p + G.P.HEALTH_MAX)
  if max <= 0 or max > 10000000 then return end
  if not health or health.p ~= p or max ~= health.set then health = { p = p, base = max, set = max } end
  local want = math.max(1, math.floor(health.base * mult + 0.5))
  if want == max then return end
  local share = math.max(0, math.min(1, read_f32(p + G.P.HEALTH) / max))
  write_u32(p + G.P.HEALTH_MAX, want)
  write_f32(p + G.P.HEALTH, share * want)
  health.set = want
end

-- The weapon record of the gun in the player's hands (pistol, SMG, rifle or
-- shotgun firing bullets), or nil.
function F.gun_info(p)
  local item = read_u32(p + G.P.EQUIPPED)
  if not G.pointer_ok(item) then return nil end
  local ammo = read_u32(item + 16)
  if not G.pointer_ok(ammo) then return nil end
  local info = read_u32(ammo + 8)
  if not G.pointer_ok(info) then return nil end
  if read_u32(info + 20) > 3 or read_u32(info + 100) ~= 0 then return nil end
  return info
end

local function rocket_in_flight(info)
  local head = read_u32(G.PROJECTILES)
  if not G.pointer_ok(head) then return false end
  local n = head
  for _ = 1, 256 do
    if read_u32(n + 208) == info then return true end
    n = read_u32(n + 204)
    if n == head or not G.pointer_ok(n) then return false end
  end
  return false
end

-- Puts every patched gun back once none of its rockets is flying. Returns
-- true when all are back.
function F.restore_guns()
  local all = true
  for info, words in pairs(patched) do
    if rocket_in_flight(info) then
      all = false
    else
      for off, v in pairs(words) do write_u32(info + off, v) end
      patched[info] = nil
    end
  end
  return all
end

G.hook(G.FIRE, function(ctx)
  local shooter = ctx:r(3) & 0xFFFFFFFF
  local p = read_u32(G.PLAYER)
  local info = (shooter ~= 0 and shooter == p and F.on("rocket_ammo") and not G.vehicle_object(p)) and F.gun_info(p) or nil
  if info and not patched[info] then
    rpg_info = rpg_info or weapon_info("rpg_launcher")
    if rpg_info then
      local words = {}
      for _, off in ipairs(ROCKET_FIELDS) do
        words[off] = read_u32(info + off)
        write_u32(info + off, read_u32(rpg_info + off))
      end
      patched[info] = words
    end
  end
  if not (info and patched[info]) then ctx:call_original() return end
  local now = os.clock()
  if now - last_rocket < ROCKET_GAP or rockets_in_air() >= ROCKET_MAX then ctx:call_original() return end
  last_rocket = now
  local old_type, old_flags, old_shots = read_u32(info + 100), read_u8(info + 12), read_u8(info + 164)
  write_u32(info + 100, 1)
  write_u8(info + 12, old_flags | (read_u8(rpg_info + 12) & 0x60))
  write_u8(info + 164, 1)
  local ok, err = pcall(function() ctx:call_original() end)
  write_u32(info + 100, old_type)
  write_u8(info + 12, old_flags)
  write_u8(info + 164, old_shots)
  if not ok then wml.log("rocket ammo: " .. tostring(err)) end
end)

-- ------------------------------------------------------------- fire ammo
--
-- The damage hook (main.lua) notes who the player's bullets hit; they are
-- set alight on the next update with the game's own ignite, so the hit's
-- own knockdown and reactions don't override the burn.
function F.note_hit(victim, attacker)
  if not F.on("fire_ammo") then return end
  local p = read_u32(G.PLAYER)
  if p == 0 or attacker ~= p or victim == p or not G.pointer_ok(victim) then return end
  if read_u32(victim + 72) ~= 1 or (read_u32(victim + 216) & G.BURNING) ~= 0 then return end
  if not F.gun_info(p) or #burn_queue >= 8 then return end
  burn_queue[#burn_queue + 1] = read_u32(victim + 68)
end

burn_queued = function(ctx, p)
  while #burn_queue > 0 do
    local h = table.remove(burn_queue, 1)
    local index = h & 0xFFFF
    local v = index < 4096 and read_u32(G.OBJECTS + 12 + index * 16) or 0
    if G.pointer_ok(v) and read_u32(v + 68) == h and read_u32(v + 72) == 1 and (read_u32(v + 216) & G.BURNING) == 0 then
      local secs = read_f32(G.BURN_TIME)
      if not (secs > 0 and secs < 60) then secs = 5.0 end
      local lit = G.call(ctx, G.IGNITE, { v, 0, p, 0 }, secs)
      -- What the script function character_ignite does after a success.
      if (lit & 0xFF) ~= 0 and read_u32(v + 508) == 9 then G.call(ctx, 0x8257C400, { v, 19 }) end
    end
  end
end

-- ------------------------------------------------------------- nitrous
--
-- patch.lua gives every car nitrous in the vehicle table at start. With
-- the toggle off, a boost on your car is cancelled straight away (the
-- engine applies nitrous while engine+380 is 1), except on the cars that
-- had nitrous in the game: the vehicle record is at vehicle+50324, its
-- name at +96.
local NITRO_ORIGINAL = { sp_derbycar01 = true, sp_derbycar02 = true, truck_2dr_semi02 = true }
local nitro_cache = {}
function F.limit_nitro(p)
  if F.on("nitro_all") then return end
  local v = G.vehicle_object(p)
  if not v then return end
  local e = G.engine_object(v)
  if not e or read_u8(e + 380) ~= 1 then return end
  local info = read_u32(v + 50324)
  local original = nitro_cache[info]
  if original == nil then
    local chars, np = {}, info + 96
    for k = 0, 23 do local c = read_u8(np + k) if c == 0 then break end chars[#chars + 1] = string.char(c) end
    original = NITRO_ORIGINAL[table.concat(chars):lower()] or false
    nitro_cache[info] = original
  end
  if not original then write_u8(e + 380, 0) end
end

-- ------------------------------------------------------------- repeat action
-- An emote action repeats after its animation track ends, with Repeat
-- action's extra pause when enabled. Locomotion is a separate state.
function F.loop_action(ctx, p)
  local L = F.looping
  if p == 0 or G.vehicle_object(p) or G.in_cutscene() or G.screen_up() or read_f32(p + G.P.HEALTH) <= 0 then F.release_player(ctx, p) return end
  local dx, dz = read_f32(p + G.P.POS) - L.x, read_f32(p + G.P.POS + 8) - L.z
  if dx * dx + dz * dz > 0.25 then F.release_player(ctx, p) return end
  if F.tick - L.started < 10 then return end
  local owner = read_u32(p + G.ANIM_OWNER)
  local ap = G.pointer_ok(owner) and read_u32(owner + G.OWNER_ANIM_PLAYER) or 0
  -- Actions have their own track at +760; +576 is the locomotion state and
  -- need never equal 227 + action. Watching it restarted actions every 10 ticks.
  if ap ~= 0 and G.call(ctx, G.ANIM_TRACK_DONE, { ap, read_u32(p + 760) }) == 0 then L.ended = nil return end
  L.ended = L.ended or F.tick
  local pause = F.on("repeat_action") and math.floor(F.items.repeat_every.v * 50) or 0
  if F.tick - L.ended >= pause then
    F.play_action(ctx, p, L.name)
    L.started, L.ended = F.tick, nil
  end
end

function F.repeat_action(ctx, p)
  local r = F.repeating
  if p == 0 or not F.on("repeat_action") or G.vehicle_object(p) or G.screen_up() or G.in_cutscene() or read_f32(p + G.P.HEALTH) <= 0 then F.release_player(ctx, p) return end
  local dx, dz = read_f32(p + G.P.POS) - r.x, read_f32(p + G.P.POS + 8) - r.z
  if dx * dx + dz * dz > 0.25 then F.release_player(ctx, p) return end
  if F.tick >= r.next then
    F.play_action(ctx, p, r.name)
    r.next = F.tick + math.floor(F.items.repeat_every.v * 50)
  end
end

-- ------------------------------------------------------------- filters
--
-- The game's own saturation and tint are written every update while a
-- filter is on (the render setup would otherwise put its own back), except
-- in cutscenes, where the shots set them. The loader's post-process look is
-- set once per change, and only cleared if this menu set it (Modern Look
-- uses the same channel).
local look_set = false
function F.set_filter(filter)
  if filter[3] == nil then
    F.filter = nil
    write_f32(G.VAR.SATURATION, F.items.saturation.v)
    write_f32(G.TINT, 1); write_f32(G.TINT + 4, 1); write_f32(G.TINT + 8, 1)
    if look_set then pcall(wml.set_look); look_set = false end
    return "Filter off"
  end
  F.filter = filter
  local ok = pcall(wml.set_look, filter[5])
  look_set = ok
  return "Filter: " .. filter[2] .. (ok and "" or " (colour only)")
end

function F.apply_filter()
  local f = F.filter
  if not f or G.in_cutscene() then return end
  write_f32(G.VAR.SATURATION, f[3])
  write_f32(G.TINT, f[4][1]); write_f32(G.TINT + 4, f[4][2]); write_f32(G.TINT + 8, f[4][3])
end

-- ------------------------------------------------------------- weapons
--
-- The weapon cheats' routine takes {name, rounds}: it makes the weapon as a
-- pickup and has the player pick it up, so the inventory, ammo and slot
-- limits are the game's own. Called directly, it doesn't set the "cheats
-- used" flag.
function F.give_weapon(ctx, name)
  local params = G.buffer(ctx, 2)
  write_u32(params, G.cstr(ctx, name, 1))
  write_u32(params + 4, 500)
  G.call(ctx, G.WEAPON_CHEAT, { params })
  if F.debug then wml.log("weapon: " .. name) end
end

-- ------------------------------------------------------------- car paint
--
-- The garage's own path: fit the slot's paint part if the car doesn't have
-- one yet (most traffic cars), then set the colour on it; the game writes
-- the colours onto the car's materials every frame, so it shows at once.
local BODY, TRIM = 46, 47

-- The car's slot of slot type `kind`, and its index in the car's own list.
local function cust_slot(cust, kind)
  local n, slots, types = read_u32(cust), read_u32(cust + 4), read_u32(G.SLOT_TYPES)
  if n == 0 or n > 64 or not G.pointer_ok(slots) or not G.pointer_ok(types) then return nil end
  for i = 0, n - 1 do
    local s = slots + i * 16
    local t = read_u32(s)
    if t ~= 0 and (t - types) // 16 == kind and read_u32(s + 8) > 0 then return s, i end
  end
end

-- The part fitted in slot index i, or nil.
local function fitted_part(state, i)
  local head = read_u32(state)
  local node = head
  for _ = 1, 64 do
    if not G.pointer_ok(node) then return nil end
    local part = read_u32(node)
    if G.pointer_ok(part) and read_u32(part + 44) == i then return part end
    node = read_u32(node + 8)
    if node == head then return nil end
  end
end

local function palette_allowed(colour_slot, pal)
  local base = read_u32(G.PALETTES)
  local n, list = read_u32(colour_slot + 20), read_u32(colour_slot + 24)
  if n > 16 or not G.pointer_ok(list) then return false end
  for k = 0, n - 1 do
    if (read_u32(list + k * 4) - base) // 24 == pal then return true end
  end
  return false
end

-- Paints `which` ("body" or "second") with palette `pal`, colour `col`.
-- Returns true (and a note when the finish had to change), or false and why.
function F.paint_car(ctx, vehicle, which, pal, col)
  local state = read_u32(vehicle + G.CUST_STATE)
  local cust = G.pointer_ok(state) and read_u32(state + 8) or 0
  if not G.pointer_ok(cust) then return false, "This vehicle can't be painted" end
  if read_u32(G.PALETTE_COUNT) ~= 12 then return false, "Paint tables not loaded" end
  local slot, index, colour_index
  if which == "body" then
    slot, index = cust_slot(cust, BODY)
    colour_index = 0
  else
    -- A two-tone car's second tone is the body part's colour slot 2
    -- ("Paint 2"); other cars get the trim.
    local body, bi = cust_slot(cust, BODY)
    if body then
      local part = fitted_part(state, bi) or read_u32(body + 12)
      if G.pointer_ok(part) and read_u32(part + 36) > 2 then slot, index, colour_index = body, bi, 2 end
    end
    if not slot then slot, index = cust_slot(cust, TRIM); colour_index = 0 end
  end
  if not slot then return false, which == "body" and "This vehicle can't be painted" or "This vehicle has no second colour" end
  local on = fitted_part(state, index)
  local part = on
  if not part or read_u32(part + 36) == 0 then part = read_u32(slot + 12) end
  if not G.pointer_ok(part) or colour_index >= read_u32(part + 36) then return false, "This vehicle can't take that" end
  local palette = read_u32(G.PALETTES) + pal * 24
  if col >= read_u32(palette + 16) then return false, "Unknown paint" end
  local colour_slot = read_u32(part + 40) + colour_index * 60
  local note
  if not palette_allowed(colour_slot, pal) then
    -- Same colour, gloss finish, if this car allows gloss.
    if pal <= 5 and palette_allowed(colour_slot, 2) then
      pal, palette, note = 2, read_u32(G.PALETTES) + 2 * 24, "gloss on this car"
    else
      return false, "This car doesn't take that finish"
    end
  end
  local colour = read_u32(palette + 20) + col * 80
  if on ~= part then G.call(ctx, G.FIT_PART, { state, part, 0 }) end
  G.call(ctx, G.SET_COLOUR, { state, part, colour_index, colour })
  if F.debug then wml.log(string.format("paint: %s pal %d col %d on part %08X slot %d", which, pal, col, part, colour_index)) end
  return true, note
end

-- Customize Vehicle: every slot the car has (the garage's names for them:
-- vehicle_cust.lua), each part fitted the way the garage fits it
-- (FIT_PART); moving onto a part shows it on the car, A keeps it, B puts
-- the old one back. Colour slots (rim colour, window tint, interior ...)
-- take any colour of the finishes the part allows. Part names come from the
-- garage's table for the car whose slots match this one's; otherwise
-- "Option n".
(function()
local VC = require("vehicle_cust")
local function slot_info(types, s)
  local st = VC.slot_types[(read_u32(s) - types) // 16 + 1]
  return st and st[1] or "Slot", st and st[2] or ""
end
local function names_for(cust)
  local n, slots = read_u32(cust), read_u32(cust + 4)
  for _, v in ipairs(VC.vehicles) do
    if #v[2] == n then
      local ok = true
      for i = 0, n - 1 do if #v[2][i + 1][2] ~= read_u32(slots + i * 16 + 8) then ok = false break end end
      if ok then return v[2] end
    end
  end
end
local function paint_slot(ctx, state, s, i, pal, col)
  local on = fitted_part(state, i)
  local part = on
  if not part or read_u32(part + 36) == 0 then part = read_u32(s + 12) end
  if not G.pointer_ok(part) or read_u32(part + 36) == 0 then return "This can't be painted" end
  local palette = read_u32(G.PALETTES) + pal * 24
  if col >= read_u32(palette + 16) then return "Unknown color" end
  if not palette_allowed(read_u32(part + 40), pal) then return "This part doesn't take that finish" end
  if on ~= part then G.call(ctx, G.FIT_PART, { state, part, 0 }) end
  G.call(ctx, G.SET_COLOUR, { state, part, 0, read_u32(palette + 20) + col * 80 })
  return nil
end
local function page_parts(state, s, i, label, names)
  local count, parts = read_u32(s + 8), read_u32(s + 12)
  local kept = fitted_part(state, i)
  local rows, cursor = {}, nil
  local function fit(c, part) G.call(c, G.FIT_PART, { state, part, 0 }) end
  for k = 0, count - 1 do
    local part = parts + k * 52
    local name = names and names[k + 1] or ("Option " .. (k + 1))
    rows[#rows + 1] = { label = name, kind = "action",
      note = function() return fitted_part(state, i) == part and "FITTED" or "" end,
      hover = function() F.wear_pending = { at = F.tick + 8, fn = function(c) fit(c, part) end } end,
      run = function(c) F.wear_pending = nil; fit(c, part); kept = part; return "Fitted: " .. name end }
    if part == kept then cursor = #rows end
  end
  return { title = label, rows = rows, cursor = cursor,
    dirty = function() return F.wear_pending ~= nil or fitted_part(state, i) ~= kept end,
    accept = function(c)
      local W = F.wear_pending
      F.wear_pending = nil
      if W then W.fn(c) end
      kept = fitted_part(state, i)
    end,
    back = function(c)
      F.wear_pending = nil
      if kept and fitted_part(state, i) ~= kept then fit(c, kept) end
    end }
end
local function page_colours(state, s, i, label)
  local part = fitted_part(state, i) or read_u32(s + 12)
  local cslot = G.pointer_ok(part) and read_u32(part + 36) > 0 and read_u32(part + 40) or nil
  local rows = {}
  for pal, P in ipairs(VC.palettes) do
    if cslot and palette_allowed(cslot, pal - 1) then
      rows[#rows + 1] = { label = P[1], kind = "page", open = function()
        local r = {}
        for col, name in ipairs(P[2]) do
          r[#r + 1] = { label = name, kind = "action",
            run = function(c) return paint_slot(c, state, s, i, pal - 1, col - 1) or (label .. ": " .. name) end }
        end
        return { title = P[1], rows = r }
      end }
    end
  end
  if #rows == 0 then return "This can't be painted" end
  return { title = label, rows = rows }
end
function F.page_vehicle(ctx, p)
  local v = G.vehicle_object(p)
  if not v or v == 0 then return "Get in a vehicle first" end
  local state = read_u32(v + G.CUST_STATE)
  local cust = G.pointer_ok(state) and read_u32(state + 8) or 0
  local types = read_u32(G.SLOT_TYPES)
  if not G.pointer_ok(cust) or not G.pointer_ok(types) then return "This vehicle can't be customized" end
  local n, slots = read_u32(cust), read_u32(cust + 4)
  if n == 0 or n > 64 or not G.pointer_ok(slots) then return "This vehicle can't be customized" end
  local names = names_for(cust)
  local rows = {}
  for i = 0, n - 1 do
    local s = slots + i * 16
    local count = read_u32(s + 8)
    if count > 0 and count < 64 and read_u32(s) ~= 0 then
      local label, kind = slot_info(types, s)
      local part_names = names and names[i + 1] and names[i + 1][2]
      rows[#rows + 1] = { label = label, kind = "page", open = function()
        if kind == "color" then return page_colours(state, s, i, label) end
        return page_parts(state, s, i, label, part_names)
      end }
    end
  end
  return { title = "Customize Vehicle", rows = rows, vehicle = v }
end
end)()
-- ------------------------------------------------------------- scenes
--
-- Scene people are made like bodyguards (scripted characters the game
-- leaves in place), one per update, at an exact spot and facing, then put
-- into their animation state. The state is put back every half second if
-- the game changes it. At most 24 are kept; the oldest go first.
local MAX_SCENE = 24

-- The way the player faces, as a yaw (0 = +z), from their facing row.
function F.facing_yaw(p)
  local fx, fz = read_f32(p + 32 + 24), read_f32(p + 32 + 32)
  if fx * fx + fz * fz < 0.01 then
    fx, fz = read_f32(G.CAMERA + 104), read_f32(G.CAMERA + 112)
  end
  return math.atan(fx, fz)
end

local function rows_for(yaw)
  local s, c = math.sin(yaw), math.cos(yaw)
  return { c, 0, -s, 0, 1, 0, s, 0, c }   -- right, up, forward
end

local function pick(list) return list[math.random(#list)] end

function F.stage_scene(p, scene)
  local x, y, z = G.vec(p + G.P.POS)
  local yaw = F.facing_yaw(p)
  local fx, fz = math.sin(yaw), math.cos(yaw)
  local rx, rz = fz, -fx
  local cx, cz = x + fx * 5, z + fz * 5                     -- the scene's middle, 5 m ahead
  local d = 0.5                                             -- the game's own spacing for its dance pairs
  local slot = 0
  local function spot()
    -- Slots on a loose grid across the scene, 2.5 m apart.
    local col, row = slot % 3 - 1, slot // 3
    slot = slot + 1
    return cx + rx * col * 2.5 + fx * row * 2.5, cz + rz * col * 2.5 + fz * row * 2.5
  end
  local n = 0
  for _, pair in ipairs(scene.pairs or {}) do
    local sx, sz = spot()
    local a_yaw = yaw + math.pi                              -- the first faces you
    local b_yaw = a_yaw + math.pi                           -- facing each other
    F.scene_queue[#F.scene_queue + 1] = { pick(F_MODELS), pair[1], sx, y, sz, a_yaw }
    F.scene_queue[#F.scene_queue + 1] = { pick(F_MODELS), pair[2],
      sx + math.sin(a_yaw) * d, y, sz + math.cos(a_yaw) * d, b_yaw }
    n = n + 2
  end
  for _, single in ipairs(scene.singles or {}) do
    local sx, sz = spot()
    F.scene_queue[#F.scene_queue + 1] = { pick(F_MODELS), single[1], sx, y, sz,
      math.atan(cx - sx, cz - sz) + (math.random() - 0.5) }  -- roughly toward the middle
    n = n + 1
  end
  return string.format("Staging %s (%d people)", scene[2], n)
end

-- ------------------------------------------------------------- animations
--
-- start_anim plays an animation (a state name or { file = }) on a person
-- and returns a token for holding it, or nil and why. A state is set the
-- way set_animation_state does it; a file is played the way the engine
-- plays custom animations (stop what plays, look the file up, play it,
-- mark the person as in a custom animation). The file has to be loaded:
-- it comes with the people whose animation sets hold it.
-- Asked each time, never kept: a file can leave memory (a borrowed set going
-- away) and its id with it.
local function anim_file_id(ctx, name)
  local id = G.call(ctx, G.ANIM_FILE_ID, { G.cstr(ctx, name .. ".anim", 0) })
  if id == 0xFFFFFFFF then return id end
  -- A registered name is not necessarily paged in. This is the same check
  -- the engine makes before allocating an animation track (826F2C30).
  local info = G.call(ctx, G.ANIM_FILE_INFO, { id })
  if not G.pointer_ok(info) or read_u32(info + 24) == 0 then return 0xFFFFFFFF end
  return id
end

-- `hold`: kept at full strength when it ends (flag 1 of the track): a move
-- made to loop goes on looping, one that isn't stays on its last pose - as
-- people do when nothing interrupts them - instead of starting over.
-- Held tracks (flag 1) are skipped by the animation player's stop, so each
-- held emote stayed in it for good: going back to one already played
-- competed with its own frozen copy and didn't show, and after nine (all of
-- its tracks) nothing new could start. The ones played here are kept, and
-- let go before the next one plays and when you stop (the track's flag 1
-- cleared, then the stop frees it). An animation player: tracks of 84
-- bytes at +7260 (+0 its id, +16 flags: 0x400 in use, 1 held).
F.ANIM_PLAYER_OF = 0x826F0BC0   -- (player handle) -> the animation player
F.held_tracks = {}
function F.free_held_tracks(ctx)
  local held_tracks = F.held_tracks
  for i = #held_tracks, 1, -1 do
    local t = held_tracks[i]
    held_tracks[i] = nil
    local ap = G.call(ctx, F.ANIM_PLAYER_OF, { t.player })
    if G.pointer_ok(ap) then
      local tr = ap + 7260 + t.index * 84
      local flags = read_u32(tr + 16)
      if read_u32(tr) == t.id and (flags & 0x400) ~= 0 then write_u32(tr + 16, flags & ~1) end
    end
  end
end
local function play_file(ctx, h, name, hold)
  local owner = read_u32(h + G.ANIM_OWNER)
  if not G.pointer_ok(owner) then return false end
  local player = read_u32(owner + 3592)
  if player == 0 then return false end
  local id = anim_file_id(ctx, name)
  if id == 0xFFFFFFFF then return false end
  if h == read_u32(G.PLAYER) then F.capture_player(h); F.save_player_state(h) end
  F.free_held_tracks(ctx)
  G.call(ctx, G.ANIM_RESET, { player, 0 })
  G.call(ctx, G.ANIM_STOP, { player })
  local handle = G.call(ctx, G.ANIM_PLAY_FILE, { player, id, hold and 17 or 16, 0, 0, 0, 0, 0xFFFFFFFF }, { 0.0, 1.0, 1.0, -1.0 })
  if handle == 0xFFFFFFFF then
    -- Never release tracks owned by the game or another mod.
    if h == read_u32(G.PLAYER) then F.release_player(ctx, h) end
    return false
  end
  if hold then F.held_tracks[#F.held_tracks + 1] = { player = player, index = handle & 0xFF, id = handle >> 8 } end
  write_u32(h + 760, handle)
  write_u32(h + 576, 0)
  write_u32(h + 756, G.CUSTOM_STATE)
  write_u32(h + 592, G.call(ctx, G.ANIM_SLOT_FOR, { read_u32(owner + 4), read_u32(owner), 0 }))
  if h == read_u32(G.PLAYER) and (read_u32(h + 216) & 0x02000000) == 0 then
    F.lock_player(h)
  end
  return true
end

-- ---------------------------------------------------------- the player's lock
--
-- When the game plays a scripted action or animation on the player it marks
-- them busy (player+4040 = 3, bit 0x10 of the byte at +3593), which locks
-- the controls until the animation ends. A held pose or a repeat never ends,
-- so the fields are saved the first time and put back on release: when you
-- press the stop combo (RB + D-pad Up, Shift + Up on the keyboard), pick
-- Stop posing, walk away from a pose, or a few seconds after a one-off action.
local lock_saved = nil
local state_saved = nil   -- the player's animation state before the first pose
function F.save_player_state(p)
  if not state_saved then state_saved = { h = p, state = read_u32(p + G.ANIM_STATE) } end
end
function F.capture_player(h)
  if not lock_saved then
    lock_saved = { h = h, v4040 = read_u32(h + 4040), b3593 = read_u8(h + 3593),
                   v756 = read_u32(h + 756), v576 = read_u32(h + 576),
                   owner = read_u32(h + G.ANIM_OWNER), handle = read_u32(h + 68) }
  end
end
function F.lock_player(h)
  F.capture_player(h)
  write_u32(h + 4040, 3)
  write_u8(h + 3593, read_u8(h + 3593) | 16)
end

-- Ends any pose, repeat or action on the player and gives the controls back.
function F.release_player(ctx, p)
  F.posing, F.repeating, F.release_at, F.looping = nil, nil, nil, nil
  F.end_emote_set(p)
  if p == 0 or (lock_saved and (lock_saved.h ~= p or lock_saved.handle ~= read_u32(p + 68)
      or lock_saved.owner ~= read_u32(p + G.ANIM_OWNER))) then
    lock_saved, state_saved = nil, nil
    F.free_held_tracks(ctx)
    return
  end
  local owner = read_u32(p + G.ANIM_OWNER)
  local player_anim = G.pointer_ok(owner) and read_u32(owner + 3592) or 0
  F.free_held_tracks(ctx)
  if player_anim ~= 0 then
    G.call(ctx, G.ANIM_STOP, { player_anim })
    G.call(ctx, G.ANIM_RESET, { player_anim, 0 })
  end
  if lock_saved and lock_saved.h == p then
    write_u32(p + 4040, lock_saved.v4040)
    write_u8(p + 3593, (read_u8(p + 3593) & ~16 & 0xFF) | (lock_saved.b3593 & 16))
    write_u32(p + 756, lock_saved.v756)
    write_u32(p + 576, lock_saved.v576)
  end
  lock_saved = nil
  -- Back to exactly the state the player was in before the first pose (the
  -- game's own "stand" is not always their normal state).
  if state_saved and state_saved.h == p then
    write_u32(p + G.ANIM_STATE, state_saved.state)
    G.call(ctx, G.ANIM_APPLY, { p, 0xFFFFFFFF, 0xFFFFFFFF, 0 })
  end
  state_saved = nil
end

-- The stop combo (stop_pad in mod.ini, RB + D-pad Up by default; Shift + Up
-- on the keyboard) asks for a release; main.lua's controller hook sets it.
F.stop_requested = false

-- Whether a person's own animation set has state/action slot `slot`
-- (states 0..226, actions 227 + their number): the same lookup the game's
-- play_action_do makes, which answers -1 for a missing one. Query live:
-- weapon groups, borrowed sets and movement overrides all change at runtime.
local function in_set(ctx, h, slot)
  local owner = read_u32(h + G.ANIM_OWNER)
  if not G.pointer_ok(owner) then return false end
  -- Both the set and weapon group can change, as can SRT_Player's overrides.
  -- A positive cached by group alone could accept another set's missing action.
  return G.call(ctx, G.ANIM_SLOT_FOR, {
    read_u32(owner + G.OWNER_SET), read_u32(owner + G.OWNER_GROUP), slot
  }) ~= 0xFFFFFFFF
end

-- Whether person h can play `anim` (a state name or { file = }).
function F.can_play(ctx, h, anim)
  if type(anim) == "table" then return anim_file_id(ctx, anim.file) ~= 0xFFFFFFFF end
  local n = state_number_of(ctx, anim)
  return n ~= 0xFFFFFFFF and in_set(ctx, h, n)
end

-- Whether person h can do action `name`.
function F.can_act(ctx, h, name)
  local n = F.action_number(ctx, name)
  return n ~= nil and in_set(ctx, h, 227 + n)
end

function F.start_anim(ctx, h, anim)
  if F.debug then wml.log("anim: " .. (type(anim) == "table" and ("file " .. anim.file) or anim) .. string.format(" on %08X", h)) end
  if type(anim) == "table" then
    if not play_file(ctx, h, anim.file, anim.hold) then
      if F.debug then wml.log("anim: file not loaded") end
      return nil, "That animation isn't loaded right now"
    end
    return { file = anim.file, hold = anim.hold }
  end
  local n = state_number_of(ctx, anim)
  if n == 0xFFFFFFFF then return nil, "That animation isn't available" end
  if not in_set(ctx, h, n) then
    if F.debug then wml.log("anim: not in this person's animation set") end
    return nil, h == read_u32(G.PLAYER) and "Your character can't do that one" or "They can't do that one"
  end
  write_u32(h + G.ANIM_STATE, n)
  G.call(ctx, G.ANIM_APPLY, { h, 0xFFFFFFFF, 0xFFFFFFFF, 0 })
  return { number = n }
end

-- ------------------------------------------------------------ movement style
--
-- A whole animation set, not one looping walk: the player's body instance
-- is given the empty SRT_Player set (patch.lua), and every animation the
-- game asks for with it is answered here, by the game's own search
-- (0x82226DA8) run over two chains of sets: in each weapon group, from the
-- one in hand up to Default, the chosen style's sets first, then the
-- player's own. So standing, walking, jogging, sprinting and crouching are
-- the style's, while a gun out keeps the game's aim, fire and reload poses
-- unless the style has its own for that weapon, and nothing the player can
-- normally do is ever missing. Walk/run variants swap the plain walk or run
-- (no weapon) for one of the variants, when the sets have it.
local MASK = 0xFFFFFFFF
F.move = { style = nil, walk = 0, run = 0, chain = {}, remap = {}, srt = 0, parts = F.move_parts, over = {} }

local set_cache = {}
function F.style_entry(ctx, name)
  local e = set_cache[name]
  if e == nil then
    e = G.call(ctx, G.ANIM_SET_FIND, { G.cstr(ctx, name, 0) })
    if not G.pointer_ok(e) then return 0 end   -- not remembered: asked again later
    set_cache[name] = e
  end
  return e
end
function F.player_set(ctx) return F.style_entry(ctx, "SRT_Player") end
function F.forget_sets() for k in pairs(set_cache) do set_cache[k] = nil end end   -- (a new game's sets)

-- The animation for `state` in the group at `g`, from the first set of
-- `chain` (set indices) that has one, or nil.
local function find_in(g, state, chain)
  local n = read_u8(g + 4 + state)
  if n == 0 then return nil end
  local first = read_u16(g + 872 + state * 2)
  for _, idx in ipairs(chain) do
    for k = 0, n - 1 do
      if read_u32(G.ANIM_POOL_SET + (first + k) * 4) == idx then
        return read_u32(G.ANIM_POOL_ANIM + (first + k) * 4)
      end
    end
  end
  return nil
end

-- The held group, then its parents (group +0), as the game walks them;
-- with `armed_only`, the weapon groups only (not Default, group 0).
local function resolve(group, state, chain, armed_only)
  local g = G.ANIM_GROUPS + group * G.ANIM_GROUP_SIZE
  for _ = 1, 8 do
    if armed_only and g == G.ANIM_GROUPS then return nil end
    local anim = find_in(g, state, chain)
    if anim then return anim end
    g = read_u32(g)
    if g == 0 then return nil end
  end
  return nil
end
F.resolve_animation = resolve

-- The melee family of weapon groups (Melee, Melee 1h / 2h and what's under
-- them: knife, nightstick, stun gun, thrown, pimp slap): Melee is the child
-- of Default whose children include one with four or more of its own.
local function melee_groups()
  local parent, kids = {}, {}
  for i = 0, 21 do
    local up = read_u32(G.ANIM_GROUPS + i * G.ANIM_GROUP_SIZE)
    local pi = (up ~= 0) and (up - G.ANIM_GROUPS) // G.ANIM_GROUP_SIZE or nil
    if pi and pi >= 0 and pi < 22 then parent[i] = pi; kids[pi] = (kids[pi] or 0) + 1 end
  end
  local family = {}
  for i = 1, 21 do
    if parent[i] == 0 then
      for c = 0, 21 do
        if parent[c] == i and (kids[c] or 0) >= 4 then family[i] = true end
      end
    end
  end
  for _ = 1, 4 do
    for i = 0, 21 do if parent[i] and family[parent[i]] then family[i] = true end end
  end
  return family
end

G.hook(G.ANIM_LOOKUP, function(ctx)
  local m = F.move
  local set = ctx:r(3) & MASK
  if set ~= m.srt or set == 0 then ctx:call_original() return end
  local group, state = ctx:r(4) & MASK, ctx:r(5) & MASK
  local anim
  if group < 22 and state < 867 then
    -- A part of how you move (stance, walk, run ... combat) set to another
    -- set or variant: that move from there. Each part has its own slot, so
    -- Melee & Throw Run doesn't replace your walk, run or sprint.
    --   empty-handed: the stance / walk / run / sprint choice (or combat);
    --   a melee weapon out: Melee & Throw Run and Melee Combat first - the
    --     kit's own move for that weapon, else the same move it has for
    --     another melee weapon (a nightstick swing with a bat);
    --   any weapon out, nothing more specific chosen: the stance / walk /
    --     run / sprint choice's own move for that weapon (a female pistol
    --     run), else its empty-handed one, so the style carries over.
    local o = m.over[state]
    if o then
      local melee = m.melee and m.melee[group]
      if group == 0 then
        local e = o.default or o.any
        if e then anim = resolve(0, e.alt or state, e.chain or m.chain) end
      else
        local e = melee and o.melee
        if e then
          anim = resolve(group, e.alt or state, e.chain or m.chain)
          if not anim and e.chain then
            for g in pairs(m.melee) do
              anim = find_in(G.ANIM_GROUPS + g * G.ANIM_GROUP_SIZE, e.alt or state, e.chain)
              if anim then break end
            end
          end
        end
        if not anim and o.any then anim = resolve(group, o.any.alt or state, o.any.chain or m.chain) end
        if not anim and o.default then
          local d = o.default
          anim = resolve(group, d.alt or state, d.chain or m.chain, true) or resolve(0, d.alt or state, d.chain or m.chain)
        end
      end
    end
    local alt = not anim and group == 0 and m.remap[state]
    if alt then anim = resolve(group, alt, m.chain) end
    -- A gun out: the gang set's way of holding it before a pedestrian set's
    -- (they hold a pistol up at arm's length, or hang it at their side).
    if not anim and group ~= 0 and m.armed then anim = resolve(group, state, m.armed, true) end
    anim = anim or resolve(group, state, m.chain)
  end
  ctx:set_r(3, anim or MASK)
end)

-- Set indices of a set and its parents (entry +8).
local function chain_into(chain, seen, entry)
  for _ = 1, 8 do
    if not G.pointer_ok(entry) then return end
    local idx = (entry - G.ANIM_SETS) // 12
    if not seen[idx] then seen[idx] = true; chain[#chain + 1] = idx end
    entry = read_u32(entry + 8)
  end
end

-- Whether the chosen style (or the player's own set) has this variant.
function F.variant_available(ctx, name)
  local n = state_number_of(ctx, name)
  if n == MASK then return false end
  local chain, seen = {}, {}
  if F.move.style then chain_into(chain, seen, F.style_entry(ctx, F.move.style)) end
  chain_into(chain, seen, F.style_entry(ctx, "GML1"))
  return resolve(0, n, chain) ~= nil
end

-- Whether a definition's own sets lack the fill set (Dex, on GML1 already,
-- needs nothing). Remembered once both sets are known.
local fill_needed = {}
function F.fill_needed(ctx, def, fill)
  local key = string.format("%08X:%s", def, fill)
  local need = fill_needed[key]
  if need ~= nil then return need end
  local base = G.call(ctx, G.ANIM_SET_FIND, { read_u32(def + G.D.ANIM_SET) })
  local entry = F.style_entry(ctx, fill)
  if not G.pointer_ok(base) or entry == 0 then return false end
  local chain, seen = {}, {}
  chain_into(chain, seen, base)
  need = not seen[(entry - G.ANIM_SETS) // 12]
  fill_needed[key] = need
  return need
end

-- Movement preview (Customize, as your Playa): while the cursor is on one of
-- the movement parts, your Playa does that move on the spot with the choice
-- shown - stands, walks, runs, sprints, or throws punches; A keeps it,
-- moving off puts back what you had.
local PREVIEW_STATE = { stance = "stand", walk = "walk", run = "run", sprint = "sprint", melee_run = "run" }
-- Whether the kit chosen for a fighting move has it for the weapon group in
-- hand (or, a melee kit, for any melee weapon); Default has everything.
function F.kit_has(ctx, name, group)
  local n = F.action_number(ctx, name)
  if not n then return false end
  local o = F.move.over[227 + n]
  local e = o and (o.melee or o.any or o.default)
  if not e or not e.chain then return true end
  if resolve(group, e.alt or 227 + n, e.chain) then return true end
  if o.melee then
    for g in pairs(F.move.melee or melee_groups()) do
      if find_in(G.ANIM_GROUPS + g * G.ANIM_GROUP_SIZE, e.alt or 227 + n, e.chain) then return true end
    end
  end
  return false
end
F.COMBAT_STEPS = { "punch L 1", "punch R 1", "punch move l", "punch move r" }
F.MELEE_STEPS = { "attack a", "attack b", "attack c", "attack d", "move attack a", "move attack b" }
function F.preview_move(ctx, p, it)
  local m = F.move
  local P = F.move_preview
  if P and (P.player ~= p or P.owner ~= read_u32(p + G.ANIM_OWNER) or P.handle ~= read_u32(p + 68)) then
    F.end_preview_move(ctx, p)
    P = nil
  end
  if not P then
    local saved = {}
    for k, v in pairs(m.parts) do saved[k] = v end
    P = { parts = saved, state = read_u32(p + G.ANIM_STATE), pos = { G.vec(p + G.P.POS) },
      player = p, owner = read_u32(p + G.ANIM_OWNER), handle = read_u32(p + 68),
      weapon = read_u32(p + G.P.EQUIPPED) }
    F.move_preview = P
  end
  local e = it.items[it.v]
  local key = tostring(it.part) .. "/" .. tostring(e and e[1])
  if key ~= P.key then
    if P.punched then F.release_player(ctx, p) end
    P.punched, P.next_punch, P.step, P.slot = nil, nil, 0, nil
    if P.bat or P.fists then
      G.call(ctx, G.PLAYER_EQUIP, { p, G.pointer_ok(P.weapon) and P.weapon or 0, 0 })
      P.bat, P.fists = nil, nil
    end
    P.key = key
    for k in pairs(m.parts) do m.parts[k] = nil end
    for k, v in pairs(P.parts) do m.parts[k] = v end
    if it.part then m.parts[it.part] = e and e[1] or 0 end
    F.apply_movement(ctx, p)
  end
  local fighting = it.part == "combat" or it.part == "melee_combat"
  if not fighting and P.punched then
    -- (off a fighting part: the moves' hold on you let go, or you couldn't move)
    F.release_player(ctx, p)
    P.punched, P.next_punch, P.step = nil, nil, nil
  end
  -- A baseball bat in hand for the melee parts, so you see them; put away after.
  local needs_bat = it.part == "melee_run" or it.part == "melee_combat"
  if needs_bat and not P.bat then
    -- Your own melee weapon if you have one out; else one you carry (bat,
    -- nightstick, tire iron, knife, cane), else a baseball bat. Nothing is
    -- taken away after: your weapon goes back in your hand.
    P.bat = { weapon = read_u32(p + G.P.EQUIPPED) }
    local inst = read_u32(p + G.ANIM_OWNER)
    local group = G.pointer_ok(inst) and read_u32(inst + G.OWNER_GROUP) or 0
    local mg = F.move.melee or melee_groups()
    if not mg[group] then
      G.script(ctx, 'local w = nil ' ..
        'for _, n in ipairs({ "baseball_bat", "nightstick", "tire_iron", "knife", "pimpcane" }) do ' ..
        '  local ok, has = pcall(inv_have_item, n, "#PLAYER#") if ok and has then w = n break end end ' ..
        'if not w then inv_item_add("baseball_bat", 1, "#PLAYER#") w = "baseball_bat" end ' ..
        'inv_item_equip(w, "#PLAYER#")')
    end
  elseif not needs_bat and P.bat then
    F.put_bat_away(ctx, p, P)
  end
  -- Combat is fists: a weapon in hand is put away while you look (and given
  -- back when you leave the row).
  if it.part == "combat" and not P.fists then
    P.fists = { weapon = read_u32(p + G.P.EQUIPPED) }
    -- holster() sets a persistent script lock at player+212 bit 0x10.
    -- Equip empty hands directly, without disabling the weapon wheel.
    if G.pointer_ok(P.fists.weapon) then G.call(ctx, G.PLAYER_EQUIP, { p, 0, 0 }) end
  elseif it.part ~= "combat" and P.fists then
    local w = P.fists.weapon
    P.fists = nil
    if G.pointer_ok(w) and not needs_bat then G.call(ctx, G.PLAYER_EQUIP, { p, w, 0 }) end
  end
  if fighting then
    -- The choice's moves one after another (left and right punches, then
    -- the running ones; or every attack in the melee kit), each held into
    -- the next, round and round - never back to standing in between.
    P.punched = true
    local opt
    for _, part in ipairs(F.MOVEMENT) do
      if part[1] == it.part and (m.parts[it.part] or 0) > 0 then opt = part[5][m.parts[it.part]] end   -- (Default: the moves as the game has them)
    end
    local list = opt and opt[4]
    local names = it.part == "combat" and F.COMBAT_STEPS or F.MELEE_STEPS
    if P.list ~= list then P.step, P.next_punch, P.list = 0, nil, list end
    -- Every choice is shown the way Default is: the game's own moves, played
    -- as actions - the menu's override answers them from the kit under the
    -- cursor, so it's what you'll get in play. Steps the kit has no move for
    -- are skipped (a kit is never shown with default moves mixed in); the
    -- kit's animation files are only a fallback. A melee kit waits for the
    -- melee weapon to be in hand. One move every 1.1 seconds.
    -- Standing still to show the moves (the row before may have left you
    -- running on the spot).
    local stand = state_number_of(ctx, "stand")
    if stand ~= 0xFFFFFFFF and read_u32(p + G.ANIM_STATE) ~= stand then
      write_u32(p + G.ANIM_STATE, stand)
      G.call(ctx, G.ANIM_APPLY, { p, 0xFFFFFFFF, 0xFFFFFFFF, 0 })
    end
    local now = os.clock()
    if not P.next_punch or now >= P.next_punch then
      local inst = read_u32(p + G.ANIM_OWNER)
      local group = G.pointer_ok(inst) and read_u32(inst + G.OWNER_GROUP) or 0
      local mg = F.move.melee or melee_groups()
      local ready = (it.part == "combat" and not mg[group]) or (it.part == "melee_combat" and mg[group])
      if ready then
        local count = #names
        for _ = 1, count do
          P.step = (P.step or 0) % count + 1
          local name = names[P.step]
          if F.kit_has(ctx, name, group) then
            F.release_player(ctx, p)
            local played = F.play_action(ctx, p, name)
            if not played and list then
              for _, file in ipairs(list) do
                if F.start_anim(ctx, p, { file = file, hold = true }) then played = true break end
              end
            end
            if played then break end
          end
        end
      end
      P.next_punch = now + (ready and 1.1 or 0.1)
    end
    return
  end
  local n = state_number_of(ctx, PREVIEW_STATE[it.part] or "walk")
  if n ~= 0xFFFFFFFF and read_u32(p + G.ANIM_STATE) ~= n then
    write_u32(p + G.ANIM_STATE, n)
    G.call(ctx, G.ANIM_APPLY, { p, 0xFFFFFFFF, 0xFFFFFFFF, 0 })
  end
end
function F.end_preview_move(ctx, p)
  local P = F.move_preview
  if not P then return end
  F.move_preview = nil
  if p ~= P.player or p == 0 or read_u32(p + G.ANIM_OWNER) ~= P.owner or read_u32(p + 68) ~= P.handle then
    F.release_player(ctx, 0)
    p = 0
  end
  if p ~= 0 and P.punched then F.release_player(ctx, p) end
  if p ~= 0 and P.bat then F.put_bat_away(ctx, p, P) end
  if p ~= 0 and P.fists then
    if G.pointer_ok(P.fists.weapon) then G.call(ctx, G.PLAYER_EQUIP, { p, P.fists.weapon, 0 }) end
    P.fists = nil
  end
  local m = F.move
  for k in pairs(m.parts) do m.parts[k] = nil end
  for k, v in pairs(P.parts) do m.parts[k] = v end
  if p ~= 0 then
    F.apply_movement(ctx, p)
    write_u32(p + G.ANIM_STATE, P.state)
    G.call(ctx, G.ANIM_APPLY, { p, 0xFFFFFFFF, 0xFFFFFFFF, 0 })
  end
end
function F.put_bat_away(ctx, p, P)
  local w = P.bat.weapon
  P.bat = nil
  -- (back to what you had in hand: that weapon, or none - the melee weapon
  -- the preview took out is put away)
  G.call(ctx, G.PLAYER_EQUIP, { p, G.pointer_ok(w) and w or 0, 0 })
end
-- A on the row keeps it: what the preview puts back becomes the new one.
function F.keep_preview_move()
  local P = F.move_preview
  if P then
    P.parts = {}
    for k, v in pairs(F.move.parts) do P.parts[k] = v end
  end
end
function F.apply_movement(ctx, p)
  F.move.dirty = true
  if p and p ~= 0 then F.update_movement(ctx, p) end
end

-- Every update: keeps the player's body on SRT_Player while a style or
-- variant is chosen (a respawn or model change makes a new body), and gives
-- the player's own set back when it's Game's own again.
function F.update_movement(ctx, p)
  if p == 0 then return end
  local inst = read_u32(p + G.ANIM_OWNER)
  if not G.pointer_ok(inst) then return end
  -- (an emote borrowing another set has it until it ends; one left behind
  -- with no emote playing is given back)
  if F.emote_set and not (F.posing or F.looping or F.repeating or F.release_at) then F.end_emote_set(p) end
  if F.emote_set and F.emote_set.inst == inst then return end
  local m = F.move
  local def = read_u32(p + G.HUMAN_DEF)
  -- What the model's own sets and the style's lack (sprint, crouch, gun
  -- holds), from a gang set for the same build, after them in the chain.
  local filling = F.items.missing_moves.v == 1
  local fill = filling and F.fill_set and F.fill_set(def) or nil
  if fill and not F.fill_needed(ctx, def, fill) then fill = nil end
  local style_fill = filling and m.style and F.set_female(m.style) and "GFL1" or nil
  local any_part = false
  for _, v in pairs(m.parts) do if v and v > 0 then any_part = true end end
  local want = F.enabled and (m.style ~= nil or m.walk ~= 0 or m.run ~= 0 or fill ~= nil or any_part)
  local srt = want and F.player_set(ctx) or 0
  if want and srt == 0 then want = false end
  if m.dirty or def ~= m.def or fill ~= m.fill or style_fill ~= m.style_fill then
    m.def, m.fill, m.style_fill, m.dirty, m.refresh = def, fill, style_fill, false, true
    local base = G.pointer_ok(def) and G.call(ctx, G.ANIM_SET_FIND, { read_u32(def + G.D.ANIM_SET) }) or 0
    if not G.pointer_ok(base) or base == F.player_set(ctx) then base = F.style_entry(ctx, "GML1") end
    m.base = base
    local chain, seen = {}, {}
    if m.style then chain_into(chain, seen, F.style_entry(ctx, m.style)) end
    if style_fill then chain_into(chain, seen, F.style_entry(ctx, style_fill)) end
    chain_into(chain, seen, base)
    if fill then chain_into(chain, seen, F.style_entry(ctx, fill)) end
    m.armed = nil
    if fill then
      local armed, aseen = {}, {}
      if m.style then chain_into(armed, aseen, F.style_entry(ctx, m.style)) end
      chain_into(armed, aseen, F.style_entry(ctx, fill))
      m.armed = armed
    end
    m.chain = chain
    m.remap = {}
    local function remap(from, to)
      local a, b = state_number_of(ctx, from), state_number_of(ctx, to)
      if a ~= MASK and b ~= MASK then m.remap[a] = b end
    end
    if m.walk ~= 0 then remap("walk", "walk variant " .. m.walk) end
    if m.run ~= 0 then remap("run", "run variant " .. m.run) end
    -- The parts: each changed move, the set (with its parents) or variant to take it from.
    m.over, m.melee = {}, melee_groups()
    for _, part in ipairs(F.MOVEMENT) do
      local opt = (m.parts[part[1]] or 0) > 0 and part[5][m.parts[part[1]]]
      if opt then
        local chain
        if opt[2] then
          local e = F.style_entry(ctx, opt[2])
          if G.pointer_ok(e) then chain = {}; chain_into(chain, {}, e) end
        end
        local alt = opt[3] and state_number_of(ctx, opt[3]) or MASK
        if chain or alt ~= MASK then
          for _, sname in ipairs(part[3]) do
            local n = MASK
            if part[1] == "combat" or part[1] == "melee_combat" then
              local a = F.action_number(ctx, sname)
              if a then n = 227 + a end
            end
            if n == MASK and part[1] ~= "combat" and part[1] ~= "melee_combat" then n = state_number_of(ctx, sname) end
            if n ~= MASK then
              m.over[n] = m.over[n] or {}
              m.over[n][part[4]] = { chain = chain, alt = alt ~= MASK and alt or nil }
            end
          end
        end
      end
    end
    if srt ~= 0 then m.srt = srt end
    if F.debug or fill then
      wml.log(string.format("movement: style %s, walk %d, run %d, base %08X, filled from %s, %d sets", tostring(m.style), m.walk, m.run,
        base, tostring(style_fill or fill), #chain))
    end
  end
  local cur = read_u32(inst + G.OWNER_SET)
  if not want and (m.srt == 0 or cur ~= m.srt) then return end
  local target = want and srt or m.base
  if not G.pointer_ok(target) then return end
  if cur ~= target or m.refresh then
    m.refresh = false
    write_u32(inst + G.OWNER_SET, target)
    -- The animation cached for the state playing now, looked up again.
    local st = read_u32(p + G.HUMAN_STATE_NOW)
    if st ~= MASK and st < 867 then
      write_u32(p + G.HUMAN_ANIM_NOW, G.call(ctx, G.ANIM_LOOKUP, { target, read_u32(inst + G.OWNER_GROUP), st }))
    end
  end
end

-- --------------------------------------------------------------- player model
--
-- The player's body is taken out of the world and put back with another
-- character's definition, the way the game does it for people whose area
-- streams out and in: behind a fade, the new model is loaded, the body is
-- deactivated (mesh detached), the definition, variant, set and look-at
-- bones are switched, and it's activated again, which attaches the new
-- model and rebuilds the rest from its rig. Health, money, weapons, notoriety
-- and position are the player object's own and stay as they are.
local MODEL_FILE = wml.mod_folder .. "/player_model.txt"
F.model = { want = nil }
do
  local file = io.open(MODEL_FILE, "rb")
  if file then
    local name = (file:read("*a") or ""):match("^%s*([%w_%-]+)")
    file:close()
    if name and name ~= "original" then F.model.want = name end
  end
end
local function save_model(name)
  local file = io.open(MODEL_FILE, "wb")
  if file then file:write((name or "original") .. "\n"); file:close() end
end

local function cstring(a, max)
  if not G.pointer_ok(a) then return nil end
  local chars = {}
  for i = 0, (max or 48) - 1 do
    local c = read_u8(a + i)
    if c == 0 then break end
    if c < 32 or c > 126 then return nil end
    chars[#chars + 1] = string.char(c)
  end
  return table.concat(chars)
end

local function own_definition(def)
  local name = G.pointer_ok(def) and cstring(read_u32(def + G.D.NAME), 40)
  return name and name:lower() == "styletest_pc"
end

-- ------------------------------------------------------- build and kit
--
-- Many activity and pedestrian characters move with a pedestrian set
-- (PML1, PFL1, PHL1 ...) that has no sprint, crouch or rifle and shotgun
-- holds: they glide, freeze in the air or hold a shotgun like a bag. What
-- their sets lack comes from a gang set for their build: women GFL1 (with
-- its own sprint), big men GHL1, other men GML1. Miguel keeps his own.
function F.set_female(set)
  set = (set or ""):upper()
  return set:sub(2, 3) == "FL" or set:find("FEMALE", 1, true) ~= nil
end
local function def_name(def)
  return G.pointer_ok(def) and (cstring(read_u32(def + G.D.NAME), 48) or "") or ""
end
function F.def_female(def)
  if not G.pointer_ok(def) then return false end
  if def_name(def):upper():find("_F_", 1, true) then return true end
  return F.set_female(cstring(read_u32(def + G.D.ANIM_SET), 24))
end
local function keeps_own(def)
  return own_definition(def) or def_name(def):lower():find("miguel", 1, true) ~= nil
end
local fill_sets = {}
function F.fill_set(def)
  if not G.pointer_ok(def) then return nil end
  local fill = fill_sets[def]
  if fill == nil then
    if keeps_own(def) then fill = false
    elseif F.def_female(def) then fill = "GFL1"
    elseif (cstring(read_u32(def + G.D.ANIM_SET), 24) or ""):upper():find("^[GP]HL") then fill = "GHL1"
    else fill = "GML1" end
    fill_sets[def] = fill
  end
  return fill or nil
end

-- ------------------------------------------------------- hair and clothing
--
-- Every rig's last 23 bones are loose ones (hair, sleeves, hood, lapels,
-- coat panels), moved by the character's cloth sims or keyed by their
-- cutscenes. Free roam animations key them for the generic bodies, and on
-- a character made for cutscenes (Madame, Mary, Loreana, Tobias ...) that
-- throws the hair off the head and a top down to the ankles. While you're
-- someone else, those bones are held at the model's own rest pose under
-- their parent, before the pose is built; a cloth sim still moves the ones
-- it runs. "Held still" also stops the sims.
F.bones = { player = 0, list = nil, dirty = true }
local ONE = 0x3F800000
local function anim_player(p)
  local inst = read_u32(p + G.ANIM_OWNER)
  if not G.pointer_ok(inst) then return 0 end
  local h = read_u32(inst + G.OWNER_ANIM_PLAYER)
  if h >= 0x80000000 then return 0 end
  return G.ANIM_PLAYERS + (h % G.ANIM_PLAYER_COUNT) * G.ANIM_PLAYER_SIZE
end
-- { slot offset, rest x, y, z (float bits) } for each loose bone.
function F.loose_bones(player)
  local rig, map = read_u32(player + 7152), read_u32(player + 7156)
  if not G.pointer_ok(rig) or not G.pointer_ok(map) then return nil end
  local count, first, n = read_u32(rig + 36), read_u32(rig + 40), read_u32(rig + 44)
  local bones = read_u32(rig + 56)
  -- Never the body itself (pelvis to fingers are the first 41).
  if count > 85 or n == 0 or first < 30 or first + n > count or not G.pointer_ok(bones) then return nil end
  local stride = (read_u32(rig + 32) & 4) ~= 0 and 36 or 32
  local slots = read_u32(map + 4)
  local list = {}
  for b = first, first + n - 1 do
    local slot = read_u16(map + 140 + 2 * b)
    if slot > 0 and slot < slots and slot < 85 then
      local rec = bones + b * stride
      list[#list + 1] = { slot * 48, read_u32(rec + 16), read_u32(rec + 20), read_u32(rec + 24) }
    end
  end
  return list
end
function F.update_bones(p)
  local B, M = F.bones, F.model
  local mode = F.items.loose_parts.v
  local swapped = p ~= 0 and M.name and M.def and read_u32(p + G.HUMAN_DEF) == M.def and not keeps_own(M.def)
  -- Cutscenes key the loose bones themselves.
  local player = (swapped and mode ~= 3 and F.enabled and not G.in_cutscene()) and anim_player(p) or 0
  if player ~= B.player or B.dirty then
    B.player, B.dirty = player, false
    B.list = player ~= 0 and F.loose_bones(player) or nil
    if not B.list then B.player = 0 end
    if player ~= 0 then wml.log(string.format("player model: %d loose bones held at rest", B.list and #B.list or 0)) end
  end
end
-- The fitting room (the Customize tab open while you're someone else):
-- every bone but the root at the model's rest pose - a T-pose - so the
-- whole outfit can be seen.
F.fitting = { on = false, player = 0, list = nil }
function F.rest_bones(player)
  local rig, map = read_u32(player + 7152), read_u32(player + 7156)
  if not G.pointer_ok(rig) or not G.pointer_ok(map) then return nil end
  local count, bones = read_u32(rig + 36), read_u32(rig + 56)
  if count > 85 or count < 20 or not G.pointer_ok(bones) then return nil end
  local stride = (read_u32(rig + 32) & 4) ~= 0 and 36 or 32
  local slots = math.min(read_u32(map + 4), 85)
  local list = {}
  for slot = 1, slots - 1 do
    local b = read_u16(map + 12 + 2 * slot)
    if b < count then
      local rec = bones + b * stride
      list[#list + 1] = { slot * 48, read_u32(rec + 16), read_u32(rec + 20), read_u32(rec + 24) }
    end
  end
  return list
end
function F.set_fitting(p, on)
  local Fi = F.fitting
  on = on and p ~= 0 and F.items.look_pose.v == 1
  local player = on and anim_player(p) or 0
  if player ~= Fi.player then
    Fi.player, Fi.snap = player, nil
    Fi.list = player ~= 0 and F.rest_bones(player) or nil
    Fi.slots = player ~= 0 and math.min(read_u32(read_u32(player + 7156) + 4), 85) or 0
    if not Fi.list then Fi.player = 0 end
  end
  Fi.on = Fi.player ~= 0
end

G.hook(G.POSE_BUILD, function(ctx)
  local Fi = F.fitting
  if Fi.on and (ctx:r(3) & MASK) == Fi.player then
    local base = ctx:r(4) & MASK
    for _, e in ipairs(Fi.list) do
      local a = base + e[1]
      write_u32(a, ONE); write_u32(a + 4, 0); write_u32(a + 8, 0)
      write_u32(a + 12, 0); write_u32(a + 16, ONE); write_u32(a + 20, 0)
      write_u32(a + 24, 0); write_u32(a + 28, 0); write_u32(a + 32, ONE)
      write_u32(a + 36, e[2]); write_u32(a + 40, e[3]); write_u32(a + 44, e[4])
    end
    ctx:call_original()
    -- Held completely still, as in the tattoo shop: the first pose built
    -- is put back after every build (no breathing, no head turning to the
    -- camera, nothing the game adds on top).
    local pose, words = Fi.player + 3072, Fi.slots * 12
    if not Fi.snap then
      Fi.snap = {}
      for i = 0, words - 1 do Fi.snap[i + 1] = read_u32(pose + i * 4) end
    else
      for i = 0, words - 1 do write_u32(pose + i * 4, Fi.snap[i + 1]) end
    end
    return
  end
  local B = F.bones
  if B.player ~= 0 and (ctx:r(3) & MASK) == B.player then
    local base = ctx:r(4) & MASK
    for _, e in ipairs(B.list) do
      local a = base + e[1]
      write_u32(a, ONE); write_u32(a + 4, 0); write_u32(a + 8, 0)
      write_u32(a + 12, 0); write_u32(a + 16, ONE); write_u32(a + 20, 0)
      write_u32(a + 24, 0); write_u32(a + 28, 0); write_u32(a + 32, ONE)
      write_u32(a + 36, e[2]); write_u32(a + 40, e[3]); write_u32(a + 44, e[4])
    end
  end
  ctx:call_original()
end)

local model_ok = {}
function F.model_usable(ctx, name)
  if model_ok[name] then return true end
  local def = G.call(ctx, G.MODEL_LOOKUP, { G.cstr(ctx, name, 0), 0 })
  local ok = G.pointer_ok(def) and read_u32(def + G.D.STREAM_ID) ~= 0 and G.pointer_ok(read_u32(def + G.D.RIG))
  if ok then model_ok[name] = true end
  return ok
end

-- The body's mesh (its variant and the parts rolled for it): the
-- variant record list at +0 (+4 how many), the rolls at +644 (+640 how many):
-- the variant first, then one per part group, one per material group ...
local function mesh_of(p)
  local inst = read_u32(p + G.ANIM_OWNER)
  if not G.pointer_ok(inst) or read_u8(inst + G.OWNER_MESH_KIND) ~= 1 then return nil end
  local mesh = read_u32(inst + G.OWNER_MESH)
  return G.pointer_ok(mesh) and mesh or nil
end
F.mesh_of = mesh_of
local function rolls(mesh)
  local out = {}
  for i = 0, math.min(read_u32(mesh + 640), 64) - 1 do out[#out + 1] = read_u8(mesh + 644 + i) end
  return out
end

-- Pressing the model you already are again: their next variation.
-- Reload Character: the body rebuilt with the model it has (the model
-- change's own steps, behind a fade), which gives it a fresh animation
-- player - for animations that are stuck or won't play.
function F.reload_character(ctx, p)
  if F.model_job then return "Already changing model" end
  if p == 0 then return "Load a game first" end
  if not G.playing(p) or read_f32(p + G.P.HEALTH) <= 0 then return "Wait until you are back on foot" end
  F.end_preview_move(ctx, p)
  F.release_player(ctx, p)
  -- Explicit recovery for the old preview's persistent holster() lock.
  G.script(ctx, "unholster()")
  local M = F.model
  F.model_job = { name = M.name, label = M.label or "your character", phase = "start", user = true, reload = true }
  return "Reloading your character..."
end
function F.request_model(p, character, look)
  if F.model_job then return "Already changing model" end
  local M = F.model
  local label = character and character[2] or "your own character"
  if character and not look and M.name == character[1] and p ~= 0 and read_u32(p + G.HUMAN_DEF) == M.def then
    local mesh = mesh_of(p)
    local n = mesh and read_u32(mesh + 4) or 0
    if n < 2 or n > 64 then return character[2] .. " has no other variations" end
    look = { variant = (read_u8(mesh + 644) + 1) % n }
  end
  F.model_job = { name = character and character[1] or nil, label = label, phase = "start", user = not (look and look.quick), look = look }
  if look and look.variant then
    local v = VARIANTS[character[1]] and VARIANTS[character[1]][look.variant + 1]
    return string.format("Changing %s to variation %d%s...", label, look.variant + 1, v and (" (" .. v[1] .. ")") or "")
  end
  return character and ("Changing into " .. label .. "...") or "Changing back to your own character..."
end

-- " (asian ho, variation 2 of 3)" for a model with variations, else "".
function F.variation_text(p)
  local M, mesh = F.model, mesh_of(p)
  local n = mesh and read_u32(mesh + 4) or 0
  if not M.name or n < 2 or n > 64 or read_u32(mesh + 640) == 0 then return "" end
  local v = read_u8(mesh + 644)
  local data = VARIANTS[M.name]
  local name = data and #data == n and data[v + 1] and data[v + 1][1]
  return string.format(" (%svariation %d of %d)", name and (name .. ", ") or "", v + 1, n)
end

-- ======================================================= Customize (EXPERIMENTAL)
--
-- A character's look, the way the game builds it: a variation (race, outfit
-- set), then one roll per part group (hair, dress, hat ...) and one per
-- material group (skin, colours), then a few for the mesh itself. The game
-- records the rolls on the mesh (+644) and can replay a list instead of
-- rolling (0x8370DC0C), so a look is a list of rolls. Part groups may be
-- rolled "none" (255: the game skips a roll past the end), material groups
-- may not. With "Mix every variation" the variation the game is given is a
-- copy of the chosen one holding every variation's part groups (they're all
-- pieces of the same mesh), each "none" unless chosen; afterwards the mesh
-- keeps rolls that are valid for the chosen variation alone, for anything
-- the game rebuilds later. Group and choice names come from variants.lua.
local LOOK_CATS = { "Head", "Hair", "Top", "Bottom", "Shoes", "Accessories", "Body" }
local CAT_WORDS = {
  { "Shoes", { "shoe", "boot", "sock" } },
  { "Hair", { "hair", "cornrow", "wig" } },
  { "Accessories", { "bling", "neck", "watch", "ear", "belt", "chain", "pendant", "cig", "ring", "brace", "jewel", "key",
      "bag", "wrist", "elbow", "pencil", "phone", "hat", "cap", "helmet", "bandana", "headband", "headwear", "glass",
      "goggle", "prop", "tie", "scarf" } },
  { "Bottom", { "pant", "leg", "lower", "short", "skirt", "bottom", "bikini" } },
  { "Top", { "shirt", "torso", "upper", "jacket", "vest", "blouse", "top", "sleeve", "dress", "cloth", "outfit",
      "collar", "fur", "armor", "hood" } },
  { "Head", { "head", "face", "mustache", "mask" } },
}
function F.part_category(name)
  name = name:lower()
  for _, c in ipairs(CAT_WORDS) do
    for _, w in ipairs(c[2]) do if name:find(w, 1, true) then return c[1] end end
  end
  return "Body"
end

-- Every variation's part (+20/+24) and material (+36/+40) groups as the
-- game holds them (8-byte entries: choices, choice list), those with a
-- choice, matched to variants.lua by count; nil if they don't match.
local function look_groups(mesh, data)
  local vars, n = read_u32(mesh), read_u32(mesh + 4)
  if not G.pointer_ok(vars) or n ~= #data or n > 32 then return nil end
  local out = {}
  for v = 0, n - 1 do
    local rec = vars + v * 44
    local function entries(count_at, list_at, names)
      local cnt, arr = read_u32(rec + count_at), read_u32(rec + list_at)
      if cnt > 128 or (cnt > 0 and not G.pointer_ok(arr)) then return nil end
      local list = {}
      for k = 0, cnt - 1 do
        local c = read_u32(arr + k * 8)
        if c > 0 and c < 256 then list[#list + 1] = { at = arr + k * 8, count = c } end
      end
      if #list ~= #names then return nil end
      for i, g in ipairs(names) do
        if #g[2] ~= list[i].count then return nil end
        list[i].name, list[i].choices, list[i].cat = g[1], g[2], F.part_category(g[1])
        -- Part choices: the mesh pieces each shows (12-byte choices: how
        -- many, the list), so the same piece in two variations is one part.
        if count_at == 20 then
          local sigs, chs = {}, read_u32(list[i].at + 4)
          for c = 0, list[i].count - 1 do
            local ch = chs + c * 12
            local nv, vl = math.min(read_u32(ch), 32), read_u32(ch + 4)
            local ids = {}
            for j = 0, nv - 1 do ids[#ids + 1] = read_u32(vl + j * 4) end
            sigs[c + 1] = table.concat(ids, ",")
          end
          list[i].sigs = sigs
        end
      end
      return list
    end
    local a, b = entries(20, 24, data[v + 1][2]), entries(36, 40, data[v + 1][3])
    if not a or not b then return nil end
    out[v] = { rec = rec, a = a, b = b, name = data[v + 1][1] }
  end
  out.n = n
  return out
end

F.look = { mix = false }
local NONE = 255
local NO_LOOK = { { false, "none for this model" } }

-- The rolls of a look: the variation, every part group in play, the
-- variation's material groups, the mesh's own; and for a mix the part
-- groups' entries.
-- Material groups in play: the variation's own, and with Mix on every other
-- variation's groups it doesn't have (patterns of their clothes).
local function look_mats(L)
  local race = L.groups[L.state.race]
  local list, names = {}, {}
  for _, g in ipairs(race.b) do list[#list + 1] = g; names[g.name:lower()] = true end
  if L.mix then
    for v = 0, L.groups.n - 1 do
      if v ~= L.state.race then
        for _, g in ipairs(L.groups[v].b) do
          if not names[g.name:lower()] then list[#list + 1] = g; names[g.name:lower()] = true end
        end
      end
    end
  end
  return list
end
F.look_mats = look_mats

local function look_rolls(L)
  local st, var = L.state, L.groups[L.state.race]
  local bytes, entries = { st.race }, {}
  for v = 0, L.groups.n - 1 do
    if L.mix or v == st.race then
      for k, g in ipairs(L.groups[v].a) do
        local c = st.a[v .. ":" .. k]
        if c == nil then c = (v == st.race) and 0 or NONE end
        bytes[#bytes + 1] = c
        entries[#entries + 1] = g.at
      end
    end
  end
  for k = 1, #look_mats(L) do bytes[#bytes + 1] = st.b[k] or 0 end
  for _, x in ipairs(st.tail) do bytes[#bytes + 1] = x end
  return bytes, entries
end

-- Reads the look you wear (when it isn't one the menu made) and rebuilds the rows.
function F.look_refresh(p)
  local L, M = F.look, F.model
  L.ok, L.groups = false, nil
  local data = M.name and VARIANTS[M.name]
  local mesh = data and p ~= 0 and read_u32(p + G.HUMAN_DEF) == M.def and mesh_of(p)
  local groups = mesh and look_groups(mesh, data)
  if L.model ~= M.name then L.model, L.state, L.mix = M.name, nil, false; F.items.look_mix.v = 1 end
  if groups then
    L.groups = groups
    if not L.state then
      local r = rolls(mesh)
      local var = groups[r[1] or 0]
      if var and #r >= 1 + #var.a + #var.b then
        local st = { race = r[1], a = {}, b = {}, tail = {} }
        for k = 1, #var.a do st.a[r[1] .. ":" .. k] = r[1 + k] end
        for k = 1, #var.b do st.b[k] = r[1 + #var.a + k] end
        for i = 2 + #var.a + #var.b, #r do st.tail[#st.tail + 1] = r[i] end
        L.state = st
      end
    end
    L.ok = L.state ~= nil and groups[L.state.race] ~= nil
  end
  F.look_rows()
end

-- The rows: the variation, one per kind of part, the colours.
function F.look_rows()
  local L = F.look
  local items = F.items
  if not L.ok then
    items.look_race.items = NO_LOOK
    for _, cat in ipairs(LOOK_CATS) do items["look_" .. cat:lower()].items = NO_LOOK end
    items.look_colours.items = NO_LOOK
    for _, id in ipairs({ "look_race", "look_colours" }) do items[id].v = 1 end
    for _, cat in ipairs(LOOK_CATS) do items["look_" .. cat:lower()].v = 1 end
    return
  end
  local st, groups = L.state, L.groups
  local race = {}
  for v = 0, groups.n - 1 do race[#race + 1] = { { race = v }, groups[v].name } end
  items.look_race.items, items.look_race.v = race, st.race + 1
  for _, cat in ipairs(LOOK_CATS) do
    local list, at = {}, nil
    -- Groups with the same name (dress in every variation) are one choice.
    local names, order = {}, {}
    for v = 0, groups.n - 1 do
      if L.mix or v == st.race then
        for k, g in ipairs(groups[v].a) do
          if g.cat == cat then
            local key = g.name:lower()
            if not names[key] then names[key] = { label = g.name, slots = {} }; order[#order + 1] = key end
            local slots = names[key].slots
            if v == st.race then table.insert(slots, 1, { v, k }) else slots[#slots + 1] = { v, k } end
          end
        end
      end
    end
    for _, key in ipairs(order) do
      local entry, seen, named = names[key], {}, {}
      local on, on_sig
      for _, s in ipairs(entry.slots) do
        local g = groups[s[1]].a[s[2]]
        local c = st.a[s[1] .. ":" .. s[2]]
        if c == nil then c = (s[1] == st.race) and 0 or NONE end
        for idx, choice in ipairs(g.choices) do
          -- The same pieces under the same name are one part; another
          -- variation's different pieces are listed under its name.
          local sig = g.sigs and g.sigs[idx] or tostring(idx)
          if not seen[choice .. "|" .. sig] then
            seen[choice .. "|" .. sig] = true
            local label = choice
            if named[choice] and named[choice] ~= sig then label = choice .. " (" .. groups[s[1]].name .. ")" end
            named[choice] = named[choice] or sig
            list[#list + 1] = { { key = key, choice = choice, sig = sig }, entry.label .. ": " .. label }
          end
          if c == idx - 1 and not on then on, on_sig = choice, sig end
        end
      end
      -- Accessories can be left off; in a mix, so can anything the
      -- chosen variation doesn't have.
      if cat == "Accessories" or entry.slots[1][1] ~= st.race then
        list[#list + 1] = { { key = key, choice = false }, entry.label .. ": none" }
      end
      for i, e in ipairs(list) do
        if not at and e[1].key == key and e[1].choice == (on or false) and (not on or e[1].sig == on_sig) then at = i end
      end
    end
    local row = items["look_" .. cat:lower()]
    row.items, row.v = #list > 0 and list or NO_LOOK, at or 1
    row.slot_names = names
  end
  local colours = {}
  for k, g in ipairs(look_mats(L)) do
    if #g.choices > 1 then
      for idx, choice in ipairs(g.choices) do
        colours[#colours + 1] = { { b = k, choice = idx - 1 }, g.name .. ": " .. choice }
      end
    end
  end
  items.look_colours.items, items.look_colours.v = #colours > 0 and colours or NO_LOOK, 1
  for i, e in ipairs(colours) do if st.b[e[1].b] == e[1].choice then items.look_colours.v = i break end end
end

-- A choice from a row: the state changed, rebuilt half a second after the
-- last change (scrolling through doesn't rebuild at every step).
function F.look_pick(it)
  local L = F.look
  local e = it.items[it.v] and it.items[it.v][1]
  if not L.ok or not e then return end
  local st = L.state
  if e.race then
    if e.race == st.race then return end
    if L.mix then
      st.race, st.b = e.race, {}
    else
      L.race_only = e.race          -- the game rolls the new variation's parts
    end
  elseif e.b then
    st.b[e.b] = e.choice
  elseif e.key then
    local entry = it.slot_names and it.slot_names[e.key]
    if not entry then return end
    local done = false
    for _, s in ipairs(entry.slots) do
      local g = L.groups[s[1]].a[s[2]]
      local id = s[1] .. ":" .. s[2]
      local idx
      if e.choice and not done then
        for i, c in ipairs(g.choices) do
          if c == e.choice and (not e.sig or not g.sigs or g.sigs[i] == e.sig) then idx = i - 1 break end
        end
      end
      if idx then st.a[id] = idx; done = true else st.a[id] = NONE end
    end
  end
  L.pending, L.custom = F.tick + 25, true
end

function F.look_apply(p)
  local L, M = F.look, F.model
  L.pending = nil
  if not L.ok or not M.name then return "Change into a character with options first" end
  if L.race_only then
    local v = L.race_only
    L.race_only, L.state = nil, nil
    return F.request_model(p, { M.name, M.label or M.name }, { variant = v, quick = true })
  end
  local bytes, entries = look_rolls(L)
  if #bytes > 64 then return "Too many parts to mix on this model" end
  local look = { replay = bytes, quick = true }
  if L.mix then
    local st, var = L.state, L.groups[L.state.race]
    local b = {}
    for _, g in ipairs(look_mats(L)) do b[#b + 1] = g.at end
    look.synth = { record = var.rec, a = entries, b = b }
    local safe = { st.race }
    for k = 1, #var.a do
      local c = st.a[st.race .. ":" .. k]
      safe[#safe + 1] = c == nil and 0 or c
    end
    for k = 1, #var.b do safe[#safe + 1] = st.b[k] or 0 end
    for _, x in ipairs(st.tail) do safe[#safe + 1] = x end
    look.safe = safe
  end
  return F.request_model(p, { M.name, M.label or M.name }, look)
end

function F.look_random(p)
  local L = F.look
  if not L.ok then return "Change into a character with options first" end
  local st = L.state
  for v = 0, L.groups.n - 1 do
    if L.mix or v == st.race then
      for k, g in ipairs(L.groups[v].a) do
        local id = v .. ":" .. k
        if v == st.race or math.random() < 0.3 then st.a[id] = math.random(0, g.count - 1) else st.a[id] = NONE end
      end
    end
  end
  for k, g in ipairs(look_mats(L)) do st.b[k] = math.random(0, g.count - 1) end
  return F.look_apply(p)
end

-- ====================================================== Your look (as yourself)
--
-- Everything the game's creator, surgeon, salon, clothing and jewelry
-- stores and tattoo parlour change, in pages laid out like theirs, free.
-- Things you wear are customization items (custom.lua: item, the name the
-- game shows, its wear options, its variants, where it goes), put on as the
-- game's own wear_customization_item does it: the item by name
-- (0x82318070), its wear option (0x823180D8) and variant (0x82318158),
-- 0x823182A8(your record, item, wear option, variant, 0), then the clothing
-- update (0x8248CFC8); taken off with 0x8248D198. Each piece put on goes
-- into your wardrobe too. Like a store, moving onto something tries it on,
-- Enter keeps it and Back puts back what you had.
--
-- What you wear is the game's table for your record's slot: a count at
-- 0x83039440 + slot*4 and 20-byte entries at 0x83039470 + slot*1080 (item,
-- record, wear option, variant, part; the part's +32 is the slot it fills,
-- 0 to 4 for hair, beard, mustache, sideburns and eyebrows; your record's
-- own list holds the parts). A piece comes off with 0x82318498 (record,
-- slot): off the table as well as the record, or the slot would stay taken
-- and nothing new would show there.
--
-- Hair colours are the game's list (*0x8370E804, 76 bytes each, how many at
-- +4); the colour of a hair slot is kept at 0x8304D160 (a count per player
-- slot, entries of record, slot, colour at 0x8304D190 + player slot*60) by
-- 0x82321E88 and put on the hair worn there by 0x823220D0, as loading a save
-- does; wearing new hair keeps it.
--
-- Face and body are your record's sliders (record +4: 12 bytes each, the
-- value at +4, 0 to 1); the game's n-th slider in player_creation.xtbl is at
-- +24 of its n-th entry at 0x831169B8, and the game re-bakes any slider whose
-- value changed.
(function()   -- (a function of its own: the file is at Lua's limit of local names)
local STORES = require("stores")
local CUSTOM = require("custom")

-- Your wardrobe: { item, variant } at player+4488, how many at +20872.
local function owned_set(p)
  local set = {}
  for i = 0, math.min(read_u32(p + G.OWNED_COUNT), G.OWNED_MAX) - 1 do
    local a = p + G.OWNED + i * 8
    set[read_u32(a) .. ":" .. read_u32(a + 4)] = true
  end
  return set
end
local function own_piece(p, item, variant, set)
  set = set or owned_set(p)
  if set[item .. ":" .. variant] then return false end
  local n = read_u32(p + G.OWNED_COUNT)
  if n >= G.OWNED_MAX then return false end
  write_u32(p + G.OWNED + n * 8, item); write_u32(p + G.OWNED + n * 8 + 4, variant)
  write_u32(p + G.OWNED_COUNT, n + 1)
  set[item .. ":" .. variant] = true
  return true
end
local item_recs = {}
local function item_rec(ctx, name)
  local r = item_recs[name]
  if r then return r end
  r = G.call(ctx, G.ITEM_FIND, { G.cstr(ctx, name, 0) })
  if not G.pointer_ok(r) then return nil end
  item_recs[name] = r
  return r
end
function F.forget_items() for k in pairs(item_recs) do item_recs[k] = nil end end
local function each_variant(ctx, names, fn)
  for _, name in ipairs(names) do
    local item = item_rec(ctx, name)
    if item then
      local list, n = read_u32(item + 36), math.min(read_u32(item + 40), 64)
      for k = 0, n - 1 do fn(item, list + k * 92) end
    end
  end
end
function F.unlock_clothing(ctx, p)
  if p == 0 then return "Load a game first" end
  local set, added = owned_set(p), 0
  for _, which in ipairs({ "clothing", "jewelry" }) do
    each_variant(ctx, STORES[which], function(item, v) if own_piece(p, item, v, set) then added = added + 1 end end)
  end
  if added == 0 then return read_u32(p + G.OWNED_COUNT) >= G.OWNED_MAX and "Your wardrobe is full" or "You already own every piece" end
  return string.format("%d pieces of clothing and jewelry added to your wardrobe", added)
end
-- Clothes no store sells (customization_items.xtbl): multiplayer's own,
-- and the activities' rewards (unlockables.xtbl). Unlock multiplayer /
-- reward clothing (extras.lua) add them the same way.
F.MP_CLOTHING = { "wool socks", "mp short chain", "mp mid-length chain", "mp long chain", "Cross pennant",
  "cards medallion", "mp pimp hats", "zoot pants suspenders", "gamestop t-shirts" }
F.REWARD_CLOTHING = { "zoot pants", "pimp pants", "pimp hats", "fluffy collared jackets", "racing pants", "racing jerseys",
  "large wheel B medallion", "pimp medallion", "long chain", "long chain5", "mid-length chain5", "short chain5" }
function F.unlock_items(ctx, p, names)
  if p == 0 then return "Load a game first" end
  local set, added = owned_set(p), 0
  each_variant(ctx, names, function(item, v) if own_piece(p, item, v, set) then added = added + 1 end end)
  if added == 0 then return read_u32(p + G.OWNED_COUNT) >= G.OWNED_MAX and "Your wardrobe is full" or "You already own every piece" end
  return string.format("%d pieces added to your wardrobe", added)
end

local function record_of(p)
  local record = p ~= 0 and read_u32(p + G.CUSTOM) or 0
  if not G.pointer_ok(record) or read_u32(record + 8) >= 12 then return nil end
  return record
end
-- What you wear: { item, mesh (wear option), variant, slot }.
local function worn(p)
  local record = record_of(p)
  if not record then return {} end
  local ps = read_u32(record + 8)
  local list = {}
  for i = 0, math.min(read_u32(G.WORN_COUNT + ps * 4), 54) - 1 do
    local a = G.WORN_TABLE + ps * 1080 + i * 20
    local part = read_u32(a + 16)
    list[#list + 1] = { item = read_u32(a), mesh = read_u32(a + 8), variant = read_u32(a + 12),
      slot = G.pointer_ok(part) and read_u32(part + 32) or -1 }
  end
  return list
end
F.worn = worn

-- A set of entries (custom.lua's) by item record.
local function set_of(ctx, entries)
  local set = {}
  for _, e in ipairs(entries) do
    local r = item_rec(ctx, e[1])
    if r then set[r] = e end
  end
  return set
end
local function snapshot(p, set)
  local list = {}
  for _, w in ipairs(worn(p)) do if set[w.item] then list[#list + 1] = w end end
  return list
end
local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i].item ~= b[i].item or a[i].mesh ~= b[i].mesh or a[i].variant ~= b[i].variant then return false end
  end
  return true
end
local relayer   -- (below: what's layered over or under a change follows it)
local function take_off(ctx, p, set)
  local record = record_of(p)
  if not record then return 0 end
  local n, done = 0, {}
  for _, w in ipairs(worn(p)) do
    if set[w.item] and not done[w.slot] then
      done[w.slot] = true
      n = n + G.call(ctx, G.WORN_REMOVE_SLOT, { record, w.slot, 0 })
    end
  end
  G.call(ctx, G.CLOTHING_FINISH, {})
  if n > 0 then relayer(ctx, p, nil) end
  return n
end

-- Hair colours.
local HAIR_KINDS = { Hair = true, Beard = true, Mustache = true, Sideburns = true, Eyebrows = true }
F.hair_colour = {}   -- kind -> the colour picked (1 = the game's first), put on whatever of it you wear
local function colour_entry(n)
  local base, count = read_u32(G.HAIR_COLOURS), read_u32(G.HAIR_COLOURS + 4)
  if not G.pointer_ok(base) or n < 1 or n > count then return nil end
  return base + (n - 1) * 76
end
local function colour_now(record, slot)
  local ps = read_u32(record + 8)
  for i = 0, math.min(read_u32(G.HAIR_KEPT_COUNT + ps * 4), 5) - 1 do
    local a = G.HAIR_KEPT + ps * 60 + i * 12
    if read_u32(a) == record and read_u32(a + 4) == slot then
      local base = read_u32(G.HAIR_COLOURS)
      return math.floor((read_u32(a + 8) - base) / 76) + 1
    end
  end
  return nil
end
local function put_colour(ctx, p, set, n)
  local record, entry = record_of(p), colour_entry(n)
  if not record or not entry then return false end
  local done = false
  for _, w in ipairs(worn(p)) do
    if set[w.item] and w.slot >= 0 and w.slot <= 4 then
      G.call(ctx, G.HAIR_COLOUR_KEEP, { record, w.slot, entry })
      G.call(ctx, G.HAIR_COLOUR_PUT, { record, w.slot, entry })
      done = true
    end
  end
  return done
end

-- Layers. A wear option sets flags (a shirt: OVERSHIRT TUCKED, a pant
-- height ...), needs some and can't go with others; options with the same
-- name are one choice the game makes from what else you wear (a chain inside
-- or outside the shirt, a shirt tucked over high or low pants). So the menu
-- offers each name once, and puts on the one your other clothes call for -
-- and when you change a top or pants, what's layered over or under it
-- changes with it.
local flag_cache = {}
local function way_flags(e)
  local list = flag_cache[e[1]]
  if list then return list end
  list = {}
  for i, s in ipairs(e[8] or {}) do
    local parts, out = {}, { set = {}, need = {}, deny = {} }
    for part in (s .. ";"):gmatch("([^;]*);") do parts[#parts + 1] = part end
    for k, key in ipairs({ "set", "need", "deny" }) do
      for fl in (parts[k] or ""):gmatch("[^|]+") do out[key][#out[key] + 1] = fl end
    end
    list[i] = out
  end
  flag_cache[e[1]] = list
  return list
end
local by_rec
local forget = F.forget_items
F.forget_items = function() forget(); by_rec = nil; flag_cache = {} end
local function entry_of(ctx, rec)
  if not by_rec then
    by_rec = {}
    for _, list in pairs(CUSTOM.items) do
      for _, e in ipairs(list) do
        local r = item_rec(ctx, e[1])
        if r then by_rec[r] = e end
      end
    end
  end
  return by_rec[rec]
end
local function mesh_index(e, mesh)
  local name = G.pointer_ok(mesh) and cstring(read_u32(mesh + 4), 64) or nil
  for i, m in ipairs(e[3]) do if m == name then return i end end
  return nil
end
-- The flags everything you wear sets (but `except`).
local function active_flags(ctx, p, except)
  local on = {}
  for _, w in ipairs(worn(p)) do
    local e = w.item ~= except and entry_of(ctx, w.item)
    local i = e and mesh_index(e, w.mesh)
    if i then for _, fl in ipairs(way_flags(e)[i].set) do on[fl] = true end end
  end
  return on
end
local function fits(fl, on)
  for _, f in ipairs(fl.need) do if not on[f] then return false end end
  for _, f in ipairs(fl.deny) do if on[f] then return false end end
  return true
end
-- Of the options named like the mi-th, the one that goes with what's on.
-- If none of that name goes, any way that does (tucked becomes untucked,
-- or the other way round, rather than clipping through what's around it).
local function best_way(e, mi, on)
  local flags = way_flags(e)
  if flags[mi] and fits(flags[mi], on) then return mi end
  for i, name in ipairs(e[4]) do
    if name == e[4][mi] and flags[i] and fits(flags[i], on) then return i end
  end
  for i in ipairs(e[4]) do
    if flags[i] and fits(flags[i], on) then return i end
  end
  return mi
end
-- The choices to offer: each name once (index into e[3] of its first).
local function way_choices(e)
  local names, first, seen = {}, {}, {}
  for i, name in ipairs(e[4]) do
    if not seen[name] then seen[name] = true; names[#names + 1] = name; first[#first + 1] = i end
  end
  return names, first
end
F.way_choices = way_choices
-- After a change: anything worn the way that no longer goes, the way that does.
function relayer(ctx, p, changed)
  local record = record_of(p)
  if not record then return end
  local moved = false
  for _, w in ipairs(worn(p)) do
    local e = w.item ~= changed and entry_of(ctx, w.item)
    local i = e and mesh_index(e, w.mesh)
    if i then
      local best = best_way(e, i, active_flags(ctx, p, w.item))
      if best ~= i then
        local mesh = G.call(ctx, G.WEAR_OPTION_FIND, { w.item, G.cstr(ctx, e[3][best], 1) })
        if G.pointer_ok(mesh) then
          G.call(ctx, G.WEAR_ITEM, { record, w.item, mesh, w.variant, 0 })
          moved = true
        end
      end
    end
  end
  if moved then G.call(ctx, G.CLOTHING_FINISH, {}) end
end

-- Puts on entry e (custom.lua's) worn its mi-th way in its vi-th variant.
local function wear(ctx, p, e, mi, vi, cat, set)
  local record = record_of(p)
  if not record then return "Your look can't be changed right now" end
  local item = item_rec(ctx, e[1])
  if not item then return "The game doesn't have " .. e[2] end
  mi = best_way(e, mi or 1, active_flags(ctx, p, item))
  local mesh = G.call(ctx, G.WEAR_OPTION_FIND, { item, G.cstr(ctx, e[3][mi] or e[3][1], 1) })
  local variant = G.call(ctx, G.VARIANT_FIND, { item, G.cstr(ctx, e[5][vi] or e[5][1], 2) })
  if not G.pointer_ok(mesh) or not G.pointer_ok(variant) then return "That one can't be worn" end
  local ok = (G.call(ctx, G.WEAR_ITEM, { record, item, mesh, variant, 0 }) & 0xFF) ~= 0
  if not ok then
    -- What's in its slot first, then again (a piece left listed there by
    -- an earlier change, or one that doesn't go with it).
    local done = {}
    for _, w in ipairs(worn(p)) do
      if (w.item == item or (set and set[w.item])) and not done[w.slot] then
        done[w.slot] = true
        G.call(ctx, G.WORN_REMOVE_SLOT, { record, w.slot, 0 })
      end
    end
    ok = (G.call(ctx, G.WEAR_ITEM, { record, item, mesh, variant, 0 }) & 0xFF) ~= 0
  end
  G.call(ctx, G.CLOTHING_FINISH, {})
  if not ok then return "You currently cannot wear this article of clothing" end
  own_piece(p, item, variant)
  relayer(ctx, p, item)
  if cat and HAIR_KINDS[cat] and F.hair_colour[cat] then put_colour(ctx, p, { [item] = e }, F.hair_colour[cat]) end
  return nil
end
-- (hair put back keeps its colour: a slot just emptied has lost it, and the
-- game would give the first one - blonde)
local function restore(ctx, p, set, kept, cat)
  local record = record_of(p)
  if not record then return end
  take_off(ctx, p, set)
  for _, w in ipairs(kept) do G.call(ctx, G.WEAR_ITEM, { record, w.item, w.mesh, w.variant, 0 }) end
  G.call(ctx, G.CLOTHING_FINISH, {})
  if cat and HAIR_KINDS[cat] and F.hair_colour[cat] then put_colour(ctx, p, set, F.hair_colour[cat]) end
end
local function reset_to_kept(ctx, p, S)
  if not same(snapshot(p, S.set), S.kept) then restore(ctx, p, S.set, S.kept, S.cat) end
end

-- Trying on: a moment after the cursor stops (so scrolling down a long list
-- doesn't load every piece on the way). `S` (a store page's session): what
-- was tried before comes off first, so only the piece under the cursor shows
-- (pieces in slots of their own - piercings, rings - would pile up).
local function try_on(fn, S)
  if S then
    local inner = fn
    fn = function(c, pp) reset_to_kept(c, pp, S) return inner(c, pp) end
  end
  F.wear_pending = { at = F.tick + 12, fn = fn }
end
local function now(ctx, p)
  local W = F.wear_pending
  F.wear_pending = nil
  if W then return W.fn(ctx, p) end
  return nil
end
function F.update_wear(ctx, p)
  -- (a try-on that can't be worn just doesn't show; Enter says why)
  local W = F.wear_pending
  if W and F.tick >= W.at and p ~= 0 then
    local msg = now(ctx, p)
    if msg then wml.log("try on: " .. msg) end
  end
end

-- A store session: what you had when you came in, put back when you leave
-- without keeping what you tried.
local function session(ctx, p, entries, cat)
  local S = { set = set_of(ctx, entries), cat = cat }
  S.kept = snapshot(p, S.set)
  return S
end
local function leave(S)
  return function(ctx, why)
    F.wear_pending = nil
    local p = G.player()
    if p ~= 0 and not same(snapshot(p, S.set), S.kept) then restore(ctx, p, S.set, S.kept, S.cat) end
  end
end
-- Enter: this row's piece on (even before its try-on came round), kept.
-- For B: has something been tried on and not accepted? And accepting it.
local function changed(S)
  return function()
    local p = G.player()
    return p ~= 0 and (F.wear_pending ~= nil or not same(snapshot(p, S.set), S.kept))
  end
end
local function accept(S)
  return function(ctx)
    local p = G.player()
    if p == 0 then return end
    now(ctx, p)
    S.kept = snapshot(p, S.set)
  end
end
local function keep(S, label, apply)
  return function(ctx, p)
    F.wear_pending = nil
    local msg = apply(ctx, p)
    if msg then return msg end
    S.kept = snapshot(p, S.set)
    return label and ("Wearing " .. label) or "Taken off"
  end
end
local function wearing(p, S, e, vi)
  local item = item_recs[e[1]]
  for _, w in ipairs(S.kept) do
    if w.item == item then
      if not vi then return true end
      return w.variant ~= 0 and read_u32(w.variant + 4) ~= 0 and cstring(read_u32(w.variant + 4), 64) == e[5][vi]
    end
  end
  return false
end
local function worn_way(e, S)
  -- Which of its ways and variants you have it on now, if you do.
  local item = item_recs[e[1]]
  for _, w in ipairs(snapshot(G.player(), S.set)) do
    if w.item == item then
      local mi, vi = 1, 1
      local mname, vname = cstring(read_u32(w.mesh + 4), 64), cstring(read_u32(w.variant + 4), 64)
      for i, m in ipairs(e[3]) do if m == mname then mi = i end end
      for i, v in ipairs(e[5]) do if v == vname then vi = i end end
      return mi, vi
    end
  end
  return nil
end

-- The colours page of one piece: its wear option, then each colour.
local function page_colours(ctx, p, e, S)
  local rows, cursor = {}, nil
  local pg = { title = e[2], rows = rows, back = leave(S), dirty = changed(S), accept = accept(S) }
  local mi, vi = worn_way(e, S)
  local names, first = way_choices(e)
  local function choice_of(m)
    for k, i in ipairs(first) do if e[4][i] == e[4][m or 1] then return k end end
    return 1
  end
  -- way.mi: the option to wear (the first of the chosen name; wear() picks the layer)
  local way = { v = choice_of(mi), mi = first[choice_of(mi)] }
  if #names > 1 and not HAIR_KINDS[S.cat] then
    way = { id = "look_way", label = "Wear Option", kind = "choice", options = names, v = choice_of(mi), mi = first[choice_of(mi)],
      change = function(_, _, _, it)
        it.mi = first[it.v]
        try_on(function(c, pp)
          local _, cur = worn_way(e, S)
          local msg = wear(c, pp, e, it.mi, cur or vi or 1, S.cat, S.set)
          -- (how it's worn is kept as soon as it's on: it goes with the colour you chose)
          if not msg then S.kept = snapshot(pp, S.set) end
          return msg
        end)
      end }
    rows[#rows + 1] = way
  end
  for i, name in ipairs(e[6]) do
    rows[#rows + 1] = { label = name, kind = "action", vi = i,
      note = function() return wearing(G.player(), S, e, i) and "WEARING" or "" end,
      hover = function() try_on(function(c, pp) return wear(c, pp, e, way.mi, i, S.cat, S.set) end, S) end,
      run = function(c, pp)
        local msg = keep(S, e[2] .. " (" .. name .. ")", function(c2, p2) return wear(c2, p2, e, way.mi, i, S.cat, S.set) end)(c, pp)
        -- Then how to wear it, at the top.
        if way.id and msg and msg:find("^Wearing") then pg.focus = 1 end
        return msg
      end }
    if vi == i then cursor = #rows end
  end
  pg.cursor = cursor or (way.id and 2 or 1)
  return pg
end

-- The rows of a list of pieces: None (when it can come off), then each piece,
-- which opens its colours when it has more than one way or colour.
local function piece_rows(ctx, p, entries, S, removable, rows)
  rows = rows or {}
  local cursor
  if removable then
    rows[#rows + 1] = { label = "None", kind = "action",
      note = function() return #S.kept == 0 and "WEARING" or "" end,
      -- (moving onto None takes nothing off; only pressing it does. What
      -- you were trying on goes back to what you had.)
      hover = function()
        try_on(function(c, pp)
          if not same(snapshot(pp, S.set), S.kept) then restore(c, pp, S.set, S.kept, S.cat) end
        end)
      end,
      run = keep(S, nil, function(c, pp) take_off(c, pp, S.set) end) }
  end
  for _, e in ipairs(entries) do
    if item_rec(ctx, e[1]) then
      local more = #e[5] > 1 or (#(way_choices(e)) > 1 and not HAIR_KINDS[S.cat])
      local row = { label = e[2],
        note = function() return wearing(G.player(), S, e) and "WEARING" or "" end,
        hover = function()
          local mi, vi = worn_way(e, S)
          try_on(function(c, pp) return wear(c, pp, e, mi or 1, vi or 1, S.cat, S.set) end, S)
        end }
      if more then
        row.kind = "page"
        row.open = function(c, pp) return page_colours(c, pp, e, S) end
      else
        row.kind = "action"
        row.run = keep(S, e[2], function(c, pp)
          local mi, vi = worn_way(e, S)
          return wear(c, pp, e, mi or 1, vi or 1, S.cat, S.set)
        end)
      end
      rows[#rows + 1] = row
      if not cursor and wearing(p, S, e) then cursor = #rows end
    end
  end
  return rows, cursor
end

-- A store's page of one kind of thing.
local REMOVABLE = { Eyes = false, Skin = false }
function F.page_items(ctx, p, cat, entries, title)
  local S = session(ctx, p, entries, cat)
  local rows, cursor = piece_rows(ctx, p, entries, S, REMOVABLE[cat] ~= false)
  if #rows == 0 then return "Nothing to wear here" end
  return { title = title or CUSTOM.categories[cat] or cat, rows = rows, cursor = cursor, back = leave(S), dirty = changed(S), accept = accept(S) }
end
function F.page_store(ctx, p, title, cats)
  local rows = {}

  for _, cat in ipairs(cats) do
    local entries = CUSTOM.items[cat]
    if entries and #entries > 0 then
      rows[#rows + 1] = { label = CUSTOM.categories[cat] or cat, kind = "page",
        open = function(c, pp) return F.page_items(c, pp, cat, entries) end }
    end
  end
  return { title = title, rows = rows }
end

-- Sliders: a set's, basic then advanced, like the creator.
local function slider_addr(p, n)
  local record = record_of(p)
  if not record or n < 1 or n > read_u32(G.MORPH_COUNT) then return nil end
  local index = read_u32(G.MORPHS + (n - 1) * 36 + 24)
  local sliders = read_u32(record + 4)
  if not G.pointer_ok(sliders) or index > 127 then return nil end
  return sliders + index * 12 + 4
end
function F.slider_value(p, n)
  local a = slider_addr(p, n)
  if not a then return nil end
  local v = read_f32(a)
  if v ~= v then return nil end
  return math.floor(math.max(0, math.min(1, v)) * 100 + 0.5)
end
function F.set_slider(p, n, amount)
  local a = slider_addr(p, n)
  if a then write_f32(a, math.max(0, math.min(100, amount)) / 100) end
end
local function slider_rows(p, set, rows)
  rows = rows or {}
  for _, kind in ipairs({ "basic", "advanced", "none" }) do
    local first = true
    for n, s in ipairs(CUSTOM.sliders) do
      if s[1] == set and s[3] == kind then
        if first and kind ~= "none" then rows[#rows + 1] = { label = kind == "basic" and "Basic" or "Advanced", kind = "header" } end
        first = false
        rows[#rows + 1] = { label = s[4], kind = "value", bar = true, min = 0, max = 100, step = 2, default = 50,
          v = F.slider_value(p, n) or 50, live = true, fmt = function(v) return string.format("%d", math.floor(v + 0.5)) end,
          read = function(pp) return F.slider_value(pp, n) end,
          change = function(_, pp, _, it) F.set_slider(pp, n, it.v) end }
      end
    end
  end
  return rows
end
F.slider_rows = slider_rows
function F.page_sliders(ctx, p, set, title)
  return { title = title, rows = slider_rows(p, set) }
end
local HEAD = { "Face_Scale", "Brow", "Nose", "Mouth", "Jaws", "Cheeks", "Ears" }
function F.page_head(ctx, p)
  local rows = {}
  for _, set in ipairs(HEAD) do
    local shown = set
    for _, s in ipairs(CUSTOM.sets) do if s[1] == set then shown = s[2] end end
    rows[#rows + 1] = { label = shown, kind = "page", 
      open = function(c, pp) return F.page_sliders(c, pp, set, shown) end }
  end
  return { title = "Head", rows = rows }
end
function F.page_eyes(ctx, p)
  local S = session(ctx, p, CUSTOM.items.Eyes or {}, "Eyes")
  local rows = { { label = "Color", kind = "header" } }
  for _, e in ipairs(CUSTOM.items.Eyes or {}) do
    local mi, vi = worn_way(e, S)
    for i, name in ipairs(e[6]) do
      rows[#rows + 1] = { label = name, kind = "action",
        note = function() return wearing(G.player(), S, e, i) and "WEARING" or "" end,
        hover = function() try_on(function(c, pp) return wear(c, pp, e, mi or 1, i, "Eyes", S.set) end) end,
        run = keep(S, name .. " eyes", function(c, pp) return wear(c, pp, e, mi or 1, i, "Eyes", S.set) end) }
    end
  end
  slider_rows(p, "Eyes", rows)
  return { title = "Eyes", rows = rows, cursor = 2, back = leave(S), dirty = changed(S), accept = accept(S) }
end
-- Skin: its sliders (saturation, luminosity); the skin itself is your race's.
function F.page_skin(ctx, p)
  return { title = "Skin", rows = slider_rows(p, "Skin") }
end

-- The salon: each kind of hair, its colour, then its styles.
local HAIR = { "Hair", "Beard", "Mustache", "Sideburns", "Eyebrows" }
function F.page_hair_kind(ctx, p, kind)
  local entries = CUSTOM.items[kind] or {}
  local S = session(ctx, p, entries, kind)
  local record = record_of(p)
  local now_colour
  if record then
    for _, w in ipairs(S.kept) do if w.slot >= 0 and w.slot <= 4 then now_colour = colour_now(record, w.slot) end end
  end
  -- The colour you wear goes on every style you try (left to the game, a
  -- style in a slot just emptied came out blonde).
  if not F.hair_colour[kind] and now_colour then F.hair_colour[kind] = now_colour end
  local colours = {}
  for i, name in ipairs(CUSTOM.hair_colours) do colours[i] = name end
  local rows = {
    { label = "Color", kind = "choice", options = colours, v = F.hair_colour[kind] or now_colour or 1,
      change = function(c, pp, _, it)
        F.hair_colour[kind] = it.v
        if not put_colour(c, pp, S.set, it.v) then return "Pick a style first" end
      end },
  }
  if kind == "Hair" then slider_rows(p, "Hair", rows); rows[#rows].label = "Hair Length" end
  rows[#rows + 1] = { label = "Style", kind = "header" }
  local _, cursor = piece_rows(ctx, p, entries, S, true, rows)
  return { title = CUSTOM.categories[kind] or kind, rows = rows, cursor = cursor or #rows, back = leave(S), dirty = changed(S), accept = accept(S) }
end
function F.page_hair(ctx, p)
  local rows = {}
  for _, kind in ipairs(HAIR) do
    rows[#rows + 1] = { label = CUSTOM.categories[kind] or kind, kind = "page", 
      open = function(c, pp) return F.page_hair_kind(c, pp, kind) end }
  end
  return { title = "Hair", rows = rows }
end

-- Rusty's Needle: where it goes, then the designs.
local AREAS = { "Back", "Chest", "Left Shoulder", "Right Shoulder", "Left Forearm", "Right Forearm", "Left Leg", "Right Leg" }
-- Remove Clothing (Style): every piece of clothing off - hat to shoes - for a
-- clean slate; underwear and jewelry stay, and a plain pair of socks goes on
-- (your feet are the socks' and shoes' meshes: with neither, no feet).
function F.remove_clothing(ctx, p)
  local all = {}
  for _, cat in ipairs(CLOTHES) do
    if cat ~= "Underwear" then for _, e in ipairs(CUSTOM.items[cat] or {}) do all[#all + 1] = e end end
  end
  local n = take_off(ctx, p, set_of(ctx, all))
  local plain = CUSTOM.items.Socks and CUSTOM.items.Socks[1]
  if plain then wear(ctx, p, plain, 1, 1, "Socks", set_of(ctx, CUSTOM.items.Socks)) end
  return n > 0 and "Clothing removed" or "Nothing to take off"
end

-- Like the parlour: down to your underwear and socks while you choose
-- (jewelry, hair and the rest stay), dressed again when you leave Tattoos.
local STRIP_FOR_TATTOOS = { "Hat", "Eyewear", "Coat", "Overshirt", "Undershirt", "Special T-Shirts", "Pants", "Belt", "Shoes" }   -- (socks stay: no bare stumps)
function F.page_tattoos(ctx, p)
  local clothes = {}
  for _, cat in ipairs(STRIP_FOR_TATTOOS) do for _, e in ipairs(CUSTOM.items[cat] or {}) do clothes[#clothes + 1] = e end end
  local dressed = set_of(ctx, clothes)
  local outfit = snapshot(p, dressed)
  if #outfit > 0 then take_off(ctx, p, dressed) end
  -- No socks on: a plain pair while you choose (feet are the socks' and shoes' meshes).
  local socks = set_of(ctx, CUSTOM.items.Socks or {})
  local lent = nil
  if #snapshot(p, socks) == 0 and CUSTOM.items.Socks and CUSTOM.items.Socks[1] then
    if not wear(ctx, p, CUSTOM.items.Socks[1], 1, 1, "Socks", socks) then lent = socks end
  end
  local by, order = {}, {}
  for _, e in ipairs(CUSTOM.items.Tattoo or {}) do
    local area = e[7] ~= "" and e[7] or "Other"
    if not by[area] then by[area] = {}; order[#order + 1] = area end
    by[area][#by[area] + 1] = e
  end
  local rank = {}
  for i, a in ipairs(AREAS) do rank[a] = i end
  table.sort(order, function(a, b) return (rank[a] or 99) < (rank[b] or 99) or ((rank[a] or 99) == (rank[b] or 99) and a < b) end)
  local rows = {}
  for _, area in ipairs(order) do
    local shown = area == "Chest" and "Front" or area
    rows[#rows + 1] = { label = shown, kind = "page", 
      open = function(c, pp) return F.page_items(c, pp, "Tattoo", by[area], "Tattoo " .. shown) end }
  end
  return { title = "Tattoos", rows = rows,
    back = function(c)
      F.wear_pending = nil
      local pp = G.player()
      if pp ~= 0 and lent then take_off(c, pp, lent) end
      if pp ~= 0 and #outfit > 0 then restore(c, pp, dressed, outfit) end
    end }
end

-- Saved Presets (your face and body, skin, eyes, hair and facial hair with
-- their colours, tattoos) and Saved Outfits (clothes and jewelry), 10 of
-- each, kept in saved_looks.txt: a "[look n]" / "[outfit n]" line, then
-- "slider n value", "piece item|wear option|variant", "colour kind n".
local PRESET_FILE = wml.mod_folder .. "/saved_looks.txt"
local PRESET_MAX = 10
local PRESET_CATS = {
  look = { "Hair", "Beard", "Mustache", "Sideburns", "Eyebrows", "Tattoo", "Eyes", "Skin" },
  outfit = { "Underwear" },
}
for _, c in ipairs(CLOTHES) do table.insert(PRESET_CATS.outfit, c) end
for _, c in ipairs(JEWELRY) do table.insert(PRESET_CATS.outfit, c) end
F.presets = { look = {}, outfit = {} }
do
  local file = io.open(PRESET_FILE, "rb")
  if file then
    local cur
    for raw in file:lines() do
      local line = raw:gsub("\r$", "")
      local kind, n = line:match("^%[(%a+) (%d+)%]$")
      if kind and F.presets[kind] then
        cur = { sliders = {}, pieces = {}, colours = {} }
        F.presets[kind][tonumber(n)] = cur
      elseif cur then
        local sn, sv = line:match("^slider (%d+) ([%d%.%-e]+)$")
        local item, mesh, variant = line:match("^piece ([^|]*)|([^|]*)|(.*)$")
        local ck, cn = line:match("^colour (%a+) (%d+)$")
        if sn then cur.sliders[tonumber(sn)] = tonumber(sv)
        elseif item then cur.pieces[#cur.pieces + 1] = { item, mesh, variant }
        elseif ck then cur.colours[ck] = tonumber(cn) end
      end
    end
    file:close()
  end
end
local function save_presets()
  local file = io.open(PRESET_FILE, "wb")
  if not file then return false end
  for _, kind in ipairs({ "look", "outfit" }) do
    for n = 1, PRESET_MAX do
      local pr = F.presets[kind][n]
      if pr then
        file:write(string.format("[%s %d]\n", kind, n))
        for i = 1, #CUSTOM.sliders do
          if pr.sliders[i] then file:write(string.format("slider %d %.4f\n", i, pr.sliders[i])) end
        end
        for _, pc in ipairs(pr.pieces) do file:write("piece ", pc[1], "|", pc[2], "|", pc[3], "\n") end
        for k, c in pairs(pr.colours) do file:write(string.format("colour %s %d\n", k, c)) end
      end
    end
  end
  file:close()
  return true
end
local function preset_entries(kind)
  local list = {}
  for _, cat in ipairs(PRESET_CATS[kind]) do for _, e in ipairs(CUSTOM.items[cat] or {}) do list[#list + 1] = e end end
  return list
end
local function capture(ctx, p, kind)
  local pr = { sliders = {}, pieces = {}, colours = {} }
  local set = set_of(ctx, preset_entries(kind))
  for _, w in ipairs(worn(p)) do
    local e = set[w.item]
    if e and G.pointer_ok(w.mesh) and G.pointer_ok(w.variant) then
      pr.pieces[#pr.pieces + 1] = { e[1], cstring(read_u32(w.mesh + 4), 64) or "", cstring(read_u32(w.variant + 4), 64) or "" }
    end
  end
  if kind == "look" then
    for n = 1, #CUSTOM.sliders do
      local v = F.slider_value(p, n)
      if v then pr.sliders[n] = v end
    end
    local record = record_of(p)
    for _, hk in ipairs(HAIR) do
      local hs = set_of(ctx, CUSTOM.items[hk] or {})
      for _, w in ipairs(worn(p)) do
        if hs[w.item] and w.slot >= 0 and w.slot <= 4 and record then pr.colours[hk] = colour_now(record, w.slot) or F.hair_colour[hk] end
      end
    end
  end
  return pr
end
local function apply_preset(ctx, p, kind, pr)
  local record = record_of(p)
  if not record then return "Your look can't be changed right now" end
  local set = set_of(ctx, preset_entries(kind))
  take_off(ctx, p, set)
  for _, pc in ipairs(pr.pieces) do
    local item = item_rec(ctx, pc[1])
    if item then
      local mesh = G.call(ctx, G.WEAR_OPTION_FIND, { item, G.cstr(ctx, pc[2], 1) })
      local variant = G.call(ctx, G.VARIANT_FIND, { item, G.cstr(ctx, pc[3], 2) })
      if G.pointer_ok(mesh) and G.pointer_ok(variant) then
        G.call(ctx, G.WEAR_ITEM, { record, item, mesh, variant, 0 })
        own_piece(p, item, variant)
      end
    end
  end
  G.call(ctx, G.CLOTHING_FINISH, {})
  relayer(ctx, p, nil)
  for n, v in pairs(pr.sliders) do F.set_slider(p, n, v) end
  for hk, c in pairs(pr.colours) do
    F.hair_colour[hk] = c
    put_colour(ctx, p, set_of(ctx, CUSTOM.items[hk] or {}), c)
  end
  return nil
end
-- The page: Save Current, then the 10 slots (a saved one opens Load,
-- Overwrite and Delete; overwriting and deleting ask first).
function F.page_presets(ctx, p, kind)
  local what = kind == "look" and "Preset" or "Outfit"
  local rows = {}
  local pg = { title = kind == "look" and "Saved Presets" or "Saved Outfits", rows = rows }
  local function confirm(title, yes)
    return function()
      return { title = title, rows = {
        { label = "Yes", kind = "action", run = function(c, pp) local msg = yes(c, pp); pg.close_after = 2; return msg end },
        { label = "No", kind = "action", run = function() pg.close_after = 1 end } } }
    end
  end
  local build
  local function store(c, pp, n)
    F.presets[kind][n] = capture(c, pp, kind)
    save_presets(); build()
    return string.format("Saved to %s %d", what, n)
  end
  build = function()
    for k in pairs(rows) do rows[k] = nil end
    rows[1] = { label = "Save Current", kind = "action", run = function(c, pp)
      for n = 1, PRESET_MAX do if not F.presets[kind][n] then return store(c, pp, n) end end
      return string.format("No empty slots: all %d %ss are in use. Overwrite or delete one first.", PRESET_MAX, what:lower())
    end }
    rows[2] = { label = what .. "s", kind = "header" }
    for n = 1, PRESET_MAX do
      if F.presets[kind][n] then
        rows[#rows + 1] = { label = string.format("%s %d", what, n), kind = "page", open = function()
          return { title = string.format("%s %d", what, n), rows = {
            { label = "Load", kind = "action", run = function(c, pp)
                local msg = apply_preset(c, pp, kind, F.presets[kind][n])
                return msg or string.format("%s %d loaded", what, n)
              end },
            { label = "Overwrite", kind = "page", open = confirm(string.format("Overwrite %s %d?", what, n), function(c, pp) return store(c, pp, n) end) },
            { label = "Delete", kind = "page", open = confirm(string.format("Delete %s %d?", what, n), function()
                F.presets[kind][n] = nil; save_presets(); build()
                return string.format("%s %d deleted", what, n)
              end) },
          } }
        end }
      else
        rows[#rows + 1] = { label = string.format("%s %d", what, n), kind = "action", note = function() return "EMPTY" end,
          run = function(c, pp) return store(c, pp, n) end }
      end
    end
  end
  build()
  return pg
end

function F.style_refresh(ctx, p) end
-- Voices: every gang's, for your character: their lines, grunts and
-- screams (falling, on fire); only being out of breath (situation 73) stays
-- your own race's voice. None leaves your own sounds. Remembered in
-- player_voice.txt and given back after loading and respawning; only while
-- you're yourself. By the game's races (its creator's names), men then women; each race's
-- voices numbered across the gangs that have them: Vice Kings, Los
-- Carnales, Rollerz, then the Saints.
local RACES = { { "B", "African American" }, { "W", "Caucasian" }, { "A", "Asian" }, { "H", "Hispanic" } }
local GANG_RACES = { VK = "BW", LC = "HW", WR = "AW", ["3SS"] = "BWAH" }
local VOICE_LIST = {}
for _, sex in ipairs({ "M", "F" }) do
  for _, r in ipairs(RACES) do
    local n = 0
    for _, g in ipairs({ "VK", "LC", "WR", "3SS" }) do
      if GANG_RACES[g]:find(r[1], 1, true) then
        for k = 1, 3 do
          n = n + 1
          VOICE_LIST[#VOICE_LIST + 1] = { r[1] .. sex .. "_" .. g .. k, string.format("%s %s %d", r[2], sex == "M" and "Male" or "Female", n), sex }
        end
      end
    end
  end
end
F.VOICE_LIST = VOICE_LIST
local VOICE_FILE = wml.mod_folder .. "/player_voice.txt"
F.voice = { want = nil, own = nil, own_ptr = nil }
do
  local file = io.open(VOICE_FILE, "rb")
  if file then
    local name = (file:read("*a") or ""):match("^%s*([%w_]+)")
    file:close()
    if name and name ~= "own" then F.voice.want = name end
  end
end
local function persona_name(p) return cstring(read_u32(p + G.PERSONA_NOW), 24) or "" end
-- Your own voice (SP_BMPLAYER ...), remembered the first time it's seen.
local function remember_own(p)
  if p == 0 or F.model.name then return end
  local now = persona_name(p)
  if now:find("^SP_%uMPLAYER$") then F.voice.own, F.voice.own_ptr = now, read_u32(p + G.PERSONA_NOW) end
end
function F.voice_items(p)
  remember_own(p)
  local items = {}
  for _, v in ipairs(VOICE_LIST) do items[#items + 1] = { v[1], v[2] } end
  return items
end
local function apply_voice(ctx, name, sample)
  local code = string.format('human_set_persona("#PLAYER#", "%s")', name)
  if sample then code = code .. ' audio_play_persona_line_do("#PLAYER#", "combat - congratulate self", -1)' end
  F.menu_line = sample or nil
  G.script(ctx, code)
  F.menu_line = nil
end
function F.sample_voice(ctx, p, name)
  if not name or F.model.name then return end
  apply_voice(ctx, name, true)
  F.voice.sampling, F.voice.sample = true, name
end
-- The Voice page: None (your character's own sounds only), then every voice.
-- Moving onto one plays it; A keeps it; B puts back the one you had.
function F.page_voice(ctx, p)
  local Vo = F.voice
  remember_own(p)
  local rows, cursor = {}, nil
  local function current(name) return function() return Vo.want == name and "CURRENT" or "" end end
  rows[1] = { label = "None", kind = "action", note = current(nil),
    hover = function() F.wear_pending = { at = F.tick + 12, fn = function(c, pp)
      if Vo.own then apply_voice(c, Vo.own, false) end
      Vo.sampling, Vo.sample = true, nil
    end } end,
    run = function(c, pp) F.wear_pending = nil; return F.set_voice(c, pp, nil, true) end }
  local sex
  for _, v in ipairs(VOICE_LIST) do
    if v[3] ~= sex then
      sex = v[3]
      rows[#rows + 1] = { label = sex == "M" and "Male" or "Female", kind = "header" }
    end
    local name = v[1]
    rows[#rows + 1] = { label = v[2], kind = "action", note = current(name),
      hover = function() F.wear_pending = { at = F.tick + 12, fn = function(c, pp) F.sample_voice(c, pp, name) end } end,
      run = function(c, pp) F.wear_pending = nil; return F.set_voice(c, pp, name) end }
    if Vo.want == name then cursor = #rows end
  end
  return { title = "Voice", rows = rows, cursor = cursor or 1,
    dirty = function() return F.wear_pending ~= nil or (Vo.sampling and Vo.sample ~= Vo.want) end,
    accept = function(c)
      local pp = G.player()
      F.wear_pending = nil
      if Vo.sampling and pp ~= 0 then F.set_voice(c, pp, Vo.sample, Vo.sample == nil) end
    end,
    back = function(c)
      F.wear_pending = nil
      if Vo.sampling then
        Vo.sampling = false
        local pp = G.player()
        if pp ~= 0 and not F.model.name then apply_voice(c, Vo.want or Vo.own or persona_name(pp), false) end
      end
    end }
end
function F.set_voice(ctx, p, name, off)
  local Vo = F.voice
  Vo.sampling = false
  if off or not name then
    Vo.want = nil
    if Vo.own and p ~= 0 and not F.model.name then apply_voice(ctx, Vo.own, false) end
    local file = io.open(VOICE_FILE, "wb"); if file then file:write("own\n"); file:close() end
    return "Voice: None"
  end
  Vo.want = name
  apply_voice(ctx, name, false)
  local file = io.open(VOICE_FILE, "wb"); if file then file:write(name .. "\n"); file:close() end
  for _, v in ipairs(VOICE_LIST) do if v[1] == name then return "Voice: " .. v[2] end end
  return "Voice changed"
end
-- A voice for a model that can take one: Lin any Caucasian or Asian woman's
-- gang voice. Kept per model in model_voice.txt (your Playa's voice is
-- apart) and put on whenever you're that model; Default is the model's own.
F.MODEL_VOICES = { TS_A_F_Lin = { WF = true, AF = true } }
local MODEL_VOICE_FILE = wml.mod_folder .. "/model_voice.txt"
F.model_voice = {}
do
  local file = io.open(MODEL_VOICE_FILE, "rb")
  if file then
    for line in (file:read("*a") or ""):gmatch("[^\r\n]+") do
      local model, name = line:match("^%s*([%w_]+)%s*=%s*([%w_]+)")
      if model then F.model_voice[model] = name end
    end
    file:close()
  end
end
local function save_model_voices()
  local file = io.open(MODEL_VOICE_FILE, "wb")
  if not file then return end
  for model, name in pairs(F.model_voice) do file:write(model, "=", name, "\n") end
  file:close()
end
-- The model's own voice (as the swap gave it).
local function model_own_voice(p)
  local def = F.model.def
  if not def or read_u32(def + G.D.PERSONA_COUNT) == 0 then return nil end
  return read_u32(def + G.D.PERSONAS)
end
local function model_voice_back(ctx, p)
  local want = F.model.name and F.model_voice[F.model.name]
  if want then apply_voice(ctx, want, false)
  else
    local own = model_own_voice(p)
    if own then write_u32(p + G.PERSONA_NOW, own) end
  end
end
local MV = { sampling = false }
function F.page_model_voice(ctx, p)
  local model = F.model.name
  local allowed = model and F.MODEL_VOICES[model]
  if not allowed then return "This character keeps their own voice" end
  local rows, cursor = {}, 1
  local function current(name) return function() return F.model_voice[model] == name and "CURRENT" or "" end end
  rows[1] = { label = "Default", kind = "action", note = current(nil),
    hover = function() F.wear_pending = { at = F.tick + 12, fn = function(c, pp)
      local own = model_own_voice(pp)
      if own then write_u32(pp + G.PERSONA_NOW, own) end
      MV.sampling, MV.sample = true, nil
    end } end,
    run = function(c, pp)
      F.wear_pending, MV.sampling = nil, false
      F.model_voice[model] = nil; save_model_voices()
      model_voice_back(c, pp)
      return "Voice: Default"
    end }
  for _, v in ipairs(VOICE_LIST) do
    if allowed[v[1]:match("^(%u%u)_") or ""] then
      local name = v[1]
      rows[#rows + 1] = { label = v[2], kind = "action", note = current(name),
        hover = function() F.wear_pending = { at = F.tick + 12, fn = function(c, pp)
          apply_voice(c, name, true)
          MV.sampling, MV.sample = true, name
        end } end,
        run = function(c, pp)
          F.wear_pending, MV.sampling = nil, false
          F.model_voice[model] = name; save_model_voices()
          apply_voice(c, name, false)
          return "Voice: " .. v[2]
        end }
      if F.model_voice[model] == name then cursor = #rows end
    end
  end
  return { title = "Voice", rows = rows, cursor = cursor,
    dirty = function() return F.wear_pending ~= nil or (MV.sampling and MV.sample ~= F.model_voice[model]) end,
    accept = function(c)
      local pp = G.player()
      F.wear_pending = nil
      if MV.sampling and pp ~= 0 then
        MV.sampling = false
        F.model_voice[model] = MV.sample; save_model_voices()
        model_voice_back(c, pp)
      end
    end,
    back = function(c)
      F.wear_pending = nil
      local pp = G.player()
      if MV.sampling and pp ~= 0 then MV.sampling = false; model_voice_back(c, pp) end
    end }
end
function F.update_model_voice(ctx, p, menu_open)
  if p == 0 or not F.model.name then MV.sampling = false return end
  if MV.sampling and not menu_open then MV.sampling = false; model_voice_back(ctx, p) end
  local want = F.model_voice[F.model.name]
  if want and not MV.sampling and F.tick % 100 == 50 and persona_name(p) ~= want then apply_voice(ctx, want, false) end
end-- Out of breath: your own voice for that one line.
function F.own_breath(p, situation)
  local Vo = F.voice
  if situation ~= 73 or not Vo.want or not Vo.own_ptr or F.model.name or p == 0 then return nil end
  local was = read_u32(p + G.PERSONA_NOW)
  write_u32(p + G.PERSONA_NOW, Vo.own_ptr)
  return was
end
function F.update_voice(ctx, p, menu_open)
  local Vo = F.voice
  if p == 0 or F.model.name then return end
  remember_own(p)
  -- Dying with a voice chosen: its death scream (situation 70), unless the
  -- game screamed already.
  local alive = read_f32(p + G.P.HEALTH) > 0
  if Vo.want and Vo.alive and not alive then Vo.died_at = F.tick end
  Vo.alive = alive
  if Vo.died_at and F.tick >= Vo.died_at + 10 then
    if (Vo.screamed_at or -1) < Vo.died_at and F.has_voice_line(p, 70) then
      G.script(ctx, 'audio_play_persona_line("#PLAYER#", "voice - death scream")')
    end
    Vo.died_at = nil
  end
  -- A sample heard but not chosen goes back once the menu is closed.
  if Vo.sampling and not menu_open then
    Vo.sampling = false
    apply_voice(ctx, Vo.want or Vo.own or persona_name(p), false)
  end
  if Vo.want and not Vo.sampling and F.tick % 100 == 0 and persona_name(p) ~= Vo.want then apply_voice(ctx, Vo.want, false) end
end
end)()

-- Made for a mix: the variation the game rolls is this copy.
F.look_synth = nil
G.hook(G.VARIANT_ROLL, function(ctx)
  local s = F.look_synth
  if s then F.look_synth = nil; ctx:set_r(4, s) end
  ctx:call_original()
end)
-- The loaded character model with this stream id (what attaching needs).
local function resident(ctx, id)
  if (G.call(ctx, G.MODEL_RESIDENT, { id }) & 0xFF) == 0 then return false end
  for i = 0, 23 do
    if read_u32(G.MODEL_RESIDENT_TABLE + i * 112 + 108) == id then return true end
  end
  return false
end

local function stream_ref(ctx, id, take)
  local group = G.STREAM_TABLE + (id >> 24) * 204
  if take then G.call(ctx, G.STREAM_REF, { group, id, 5, 0, 1 })
  else
    F.own_release = true
    G.call(ctx, G.STREAM_RELEASE, { group, id, 5, 0, 0 })
    F.own_release = nil
  end
end

-- The model you wear as someone else must stay loaded. A cutscene with that
-- character in it (Aisha in Aisha's scenes) loads the same model and, when
-- it ends, gives back every reference to it at once (last argument 1) -
-- ours too: the model was unloaded under you (invisible, then a crash). That
-- one call gives back one reference instead; and if the model is ever gone
-- anyway, it's loaded again at once.
-- Any reference to it given back by something else is taken again at once
-- (and given back with ours when you change back), so the count never
-- reaches nothing while you wear it.
G.hook(G.STREAM_RELEASE, function(ctx)
  local M = F.model
  local group, id, kind = ctx:r(3) & 0xFFFFFFFF, ctx:r(4) & 0xFFFFFFFF, ctx:r(5) & 0xFFFFFFFF
  local foreign = M.name and M.ref and id == M.ref and not F.own_release
  if foreign and (ctx:r(7) & 0xFF) ~= 0 then
    wml.log(string.format("player model: something gave back every reference to %s's model (a cutscene?); only one given back", M.name))
    ctx:set_r(7, 0)
  end
  ctx:call_original()
  if foreign then
    G.call(ctx, G.STREAM_REF, { group, id, kind, 0, 1 })
    M.extra_refs = (M.extra_refs or 0) + 1
    wml.log(string.format("player model: a reference to %s's model was given back by the game; taken again (%d extra)", M.name, M.extra_refs))
  end
end)
local function keep_model_loaded(ctx)
  local M = F.model
  if not (M.name and M.ref) or F.tick % 25 ~= 3 or resident(ctx, M.ref) then return end
  wml.log(string.format("player model: %s's model was unloaded; loading it again", M.name))
  stream_ref(ctx, M.ref, true)
  M.extra_refs = (M.extra_refs or 0) + 1
  G.call(ctx, G.MODEL_LOAD_NOW, { M.ref, 5, 0 })
end

-- ------------------------------------------------------------ the outfit
--
-- Taken off while you're someone else (the pieces would be drawn on their
-- skeleton, twisted), kept in player_outfit.txt, and put back on when you're
-- yourself again - also if a game was saved in between.
local OUTFIT_FILE = wml.mod_folder .. "/player_outfit.txt"
do
  local file = io.open(OUTFIT_FILE, "rb")
  if file then
    local hex = (file:read("*a") or ""):match("^%s*(%x+)")
    file:close()
    if hex and #hex >= 2 and #hex % 2 == 0 then
      F.model.outfit = hex:gsub("%x%x", function(b) return string.char(tonumber(b, 16)) end)
    end
  end
end
-- player_outfit_last.txt keeps the last outfit taken off for good (Settings
-- > Put my outfit back on), in case a game was saved while it was off.
local OUTFIT_LAST = wml.mod_folder .. "/player_outfit_last.txt"
local function hex_of(bytes) return (bytes:gsub(".", function(c) return string.format("%02X", c:byte()) end)) end
local function save_outfit(bytes)
  if not bytes then os.remove(OUTFIT_FILE) return end
  local file = io.open(OUTFIT_FILE, "wb")
  if file then file:write(hex_of(bytes), "\n"); file:close() end
  file = io.open(OUTFIT_LAST, "wb")
  if file then file:write(hex_of(bytes), "\n"); file:close() end
end
local function last_outfit()
  local file = io.open(OUTFIT_LAST, "rb")
  if not file then return nil end
  local hex = (file:read("*a") or ""):match("^%s*(%x+)")
  file:close()
  if not hex or #hex < 2 or #hex % 2 ~= 0 then return nil end
  return (hex:gsub("%x%x", function(b) return string.char(tonumber(b, 16)) end))
end

local function worn_count(p)
  local record = read_u32(p + G.CUSTOM)
  if not G.pointer_ok(record) then return 0 end
  local slot = read_u32(record + 8)
  return slot < 12 and read_u32(G.WORN_COUNT + slot * 4) or 0
end

-- What the player wears, packed as the game packs it, or nil.
local function read_outfit(ctx, p)
  local record = read_u32(p + G.CUSTOM)
  if not G.pointer_ok(record) or worn_count(p) == 0 then return nil end
  local writer, buffer = G.buffer(ctx, 1), G.buffer(ctx, 2)
  write_u32(writer, 0); write_u32(writer + 4, buffer)
  -- For the local player's own record the game reads a wardrobe copy that
  -- isn't kept up to date; hidden for the call, it reads what's worn.
  write_u32(p + G.CUSTOM, 0)
  G.call(ctx, G.OUTFIT_PACK, { writer, record })
  write_u32(p + G.CUSTOM, record)
  local length = read_u32(writer)
  if length < 5 or length > 512 or read_u8(buffer) == 0 then return nil end
  local bytes = {}
  for i = 0, length - 1 do bytes[#bytes + 1] = string.char(read_u8(buffer + i)) end
  return table.concat(bytes)
end

local function take_off_outfit(ctx, p)
  local record = read_u32(p + G.CUSTOM)
  if not G.pointer_ok(record) then return end
  local outfit = read_outfit(ctx, p)
  if outfit then
    F.model.outfit = outfit; save_outfit(outfit)
  elseif worn_count(p) > 0 and not F.model.outfit then
    -- Never take off what couldn't be written down.
    wml.log("player model: couldn't read your outfit; leaving it on")
    return
  end
  F.strip_outfit(ctx, p)
end

-- Every piece off, the way the game takes one off: out of the worn table
-- too (0x823183C8: record, index, 1 = more to come, 0 = done, rebuild), not
-- only off your record - a piece still listed there keeps its slot "taken",
-- and nothing put on in that slot later shows (or is saved). Then the rest.
function F.strip_outfit(ctx, p)
  local record = read_u32(p + G.CUSTOM)
  if not G.pointer_ok(record) then return end
  local slot = read_u32(record + 8)
  local before, after_items = worn_count(p), nil
  if slot < 12 then
    for i = math.min(54, read_u32(G.WORN_COUNT + slot * 4)) - 1, 0, -1 do
      G.call(ctx, G.WORN_REMOVE_AT, { record, i, i > 0 and 1 or 0 })
    end
    G.call(ctx, G.CLOTHING_FINISH, {})
    after_items = worn_count(p)
  end
  G.call(ctx, G.OUTFIT_REMOVE, { record })
  G.call(ctx, G.CLOTHING_FINISH, {})
  wml.log(string.format("player model: outfit taken off, %d items still listed (record %08X slot %d: %d before, %s after one by one)",
    worn_count(p), record, slot, before, tostring(after_items)))
end

local function wear_outfit(ctx, p, bytes)
  local record = read_u32(p + G.CUSTOM)
  if not bytes or not G.pointer_ok(record) then return false end
  -- (whatever is still listed comes off first, or it would keep its slots)
  if worn_count(p) > 0 then F.strip_outfit(ctx, p) end
  local reader, buffer = G.buffer(ctx, 1), G.buffer(ctx, 2)
  local cursor = reader + 16
  for i = 1, #bytes do write_u8(buffer + i - 1, bytes:byte(i)) end
  write_u32(reader, #bytes); write_u32(reader + 4, buffer); write_u32(cursor, 0)
  G.call(ctx, G.OUTFIT_WEAR, { record, reader, cursor, 0 })
  G.call(ctx, G.CLOTHING_FINISH, {})
  wml.log(string.format("player model: outfit put back on (%d items, %d of %d bytes read, %d now worn)", bytes:byte(1), read_u32(cursor), #bytes, worn_count(p)))
  return true
end
local function put_on_outfit(ctx, p)
  local M = F.model
  if not M.outfit or not wear_outfit(ctx, p, M.outfit) then return end
  M.outfit = nil
  save_outfit(nil)
end
-- Settings: the last outfit taken off, back on (a game saved while you were
-- someone else, or undressed by the old bug).
function F.outfit_back(ctx, p)
  if p == 0 then return "Load a game first" end
  if F.model.name then return "Change back to yourself first" end
  local bytes = F.model.outfit or last_outfit()
  if not bytes then return "No outfit kept to put back" end
  wear_outfit(ctx, p, bytes)
  F.model.outfit = nil
  os.remove(OUTFIT_FILE)
  return string.format("Your outfit is back on (%d pieces)", bytes:byte(1))
end
F.read_outfit, F.worn_count = read_outfit, worn_count

-- ------------------------------------------------------------ the sliders
--
-- The game bakes the player's body and face sliders into the model of the
-- body the player has (0x824904B0: customization record +16 = the body,
-- body +3732 = its model), as differences from what it baked before. On
-- someone else's model those shapes crumple the face (and every copy of
-- that model in the world shares it), so while you're someone else the
-- bake doesn't run. Your sliders themselves are never changed.
G.hook(G.SLIDER_BAKE, function(ctx)
  local M = F.model
  if M.name and M.def then
    local p = read_u32(G.PLAYER)
    if p ~= 0 and read_u32(p + G.HUMAN_DEF) == M.def then return end
  end
  ctx:call_original()
end)
-- The body's own simulations (hair, ponytail, coat, chains) as the
-- player's, so the game runs them.
local function body_sims(p)
  local inst = read_u32(p + G.ANIM_OWNER)
  if not G.pointer_ok(inst) then return {} end
  local sims = {}
  for i = 0, math.min(read_u32(inst + G.OWNER_SIM_COUNT), G.PLAYER_SIM_MAX) - 1 do
    sims[#sims + 1] = read_u32(inst + G.OWNER_SIMS + i * 4)
  end
  return sims
end
local function player_sims(p)
  local sims = {}
  for i = 0, math.min(read_u32(p + G.PLAYER_SIM_COUNT), G.PLAYER_SIM_MAX) - 1 do
    sims[#sims + 1] = read_u32(p + G.PLAYER_SIMS + i * 4)
  end
  return sims
end
local function set_player_sims(p, sims)
  for i, s in ipairs(sims) do write_u32(p + G.PLAYER_SIMS + (i - 1) * 4, s) end
  write_u32(p + G.PLAYER_SIM_COUNT, #sims)
end
local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end
F.body_sims, F.player_sims = body_sims, player_sims
-- The sims a swapped body runs: its own, or none when hair and clothing are held still.
local function wanted_sims(p)
  if F.items.loose_parts.v == 2 then return {} end
  return body_sims(p)
end

local DIAG = { 120, 200, 212, 216, 476, 508, 784, 2496, 3016, 3592, 3593, 3594, 3616, 3619, 4040 }
local function diag(p, inst, when)
  local parts = {}
  for _, off in ipairs(DIAG) do parts[#parts + 1] = string.format("+%d=%08X", off, read_u32(p + off)) end
  local ctrl = read_u32(p + 476)
  local ent = G.pointer_ok(ctrl) and read_u32(ctrl + G.CONTROLLER_ENTITY) or 0
  local layer = G.pointer_ok(ent) and read_u32(ent + G.ENTITY_LAYER) or 0
  wml.log(string.format("player model %s: %s entity %08X layer %08X inst set %08X anim %08X", when, table.concat(parts, " "),
    ent, layer, read_u32(inst + G.OWNER_SET), read_u32(inst + G.OWNER_ANIM_PLAYER)))
  return ent, layer
end

local function swap_body(ctx, p, def, look)
  local inst = read_u32(p + G.ANIM_OWNER)
  local rig = read_u32(def + G.D.RIG)
  if not G.pointer_ok(inst) or not G.pointer_ok(rig) then return false end
  local M = F.model
  local leaving_own = own_definition(read_u32(p + G.HUMAN_DEF))
  if leaving_own then
    M.own_variant = read_u32(inst + G.OWNER_VARIANT)
    M.own_sims = M.own_sims or player_sims(p)
    take_off_outfit(ctx, p)
  end
  local _, layer = diag(p, inst, "before")
  -- Where and how the body stands, put back afterwards as the game's own
  -- unstash (0x8240B228) does.
  local x, y, z = G.vec(p + G.P.POS)
  local rows = {}
  for i = 0, 8 do rows[i] = read_f32(p + 32 + i * 4) end
  local health, health_max = read_f32(p + G.P.HEALTH), read_u32(p + G.P.HEALTH_MAX)
  local flags = {}
  for i = 0, 7 do flags[i] = read_u8(p + G.PLAYER_FLAGS + i) end
  if leaving_own then M.own_persona = read_u32(p + G.PERSONA_NOW) end
  local bits = read_u32(p + G.HUMAN_ACTIVE)
  for b = 0, 1 do
    if (bits & (1 << b)) ~= 0 then G.call(ctx, G.HUMAN_DEACTIVATE, { p, b, 0 }) end
  end
  write_u32(p + G.HUMAN_DEF, def)
  local variant = look and look.variant or MASK
  write_u32(inst + G.OWNER_VARIANT, own_definition(def) and (M.own_variant or MASK) or variant)
  -- Their own way of moving, unless a Movement style holds the body.
  if F.move.srt == 0 or read_u32(inst + G.OWNER_SET) ~= F.move.srt then
    local set = G.call(ctx, G.ANIM_SET_FIND, { read_u32(def + G.D.ANIM_SET) })
    if G.pointer_ok(set) then write_u32(inst + G.OWNER_SET, set) end
  end
  for _, bone in ipairs(G.PLAYER_BONES) do
    write_u32(p + bone[1], G.call(ctx, G.RIG_BONE, { rig, G.cstr(ctx, bone[2], 0) }))
  end
  -- A mix: the variation the game rolls is a copy of the chosen one with
  -- every variation's part groups (record in buffer 1, materials in 0).
  local synth = look and look.synth
  if synth and #synth.a <= 120 and #synth.b <= 120 then
    local rec, mats = G.buffer(ctx, 1), G.buffer(ctx, 0)
    for i = 0, 10 do write_u32(rec + i * 4, read_u32(synth.record + i * 4)) end
    local parts = rec + 48
    for i, at in ipairs(synth.a) do write_u32(parts + (i - 1) * 8, read_u32(at)); write_u32(parts + (i - 1) * 8 + 4, read_u32(at + 4)) end
    for i, at in ipairs(synth.b) do write_u32(mats + (i - 1) * 8, read_u32(at)); write_u32(mats + (i - 1) * 8 + 4, read_u32(at + 4)) end
    write_u32(rec + 20, #synth.a); write_u32(rec + 24, parts)
    write_u32(rec + 36, #synth.b); write_u32(rec + 40, mats)
    F.look_synth = rec
  end
  -- A chosen set of parts: the rolls replayed (the variant first).
  local replay_was
  if look and look.replay then
    local buf = G.buffer(ctx, 2)
    for i, b in ipairs(look.replay) do write_u8(buf + i - 1, b) end
    replay_was = { read_u8(G.REPLAY_ON), read_u32(G.REPLAY), read_u32(G.REPLAY + 4) }
    write_u8(G.REPLAY_ON, 1); write_u32(G.REPLAY, 0); write_u32(G.REPLAY + 4, buf)
  end
  G.call(ctx, G.HUMAN_ACTIVATE, { p, 0, 0, 0, 0 })
  if replay_was then
    write_u8(G.REPLAY_ON, replay_was[1]); write_u32(G.REPLAY, replay_was[2]); write_u32(G.REPLAY + 4, replay_was[3])
  end
  F.look_synth = nil
  -- After a mix the mesh keeps rolls the chosen variation alone can replay.
  if look and look.safe then
    local mesh = mesh_of(p)
    if mesh then
      for i, b in ipairs(look.safe) do write_u8(mesh + 643 + i, b) end
      write_u32(mesh + 640, #look.safe)
    end
  end
  -- The player's state flags and voice, as they were (the voice of the
  -- character you become is theirs; your own comes back with your body).
  for i = 0, 7 do write_u8(p + G.PLAYER_FLAGS + i, flags[i]) end
  if own_definition(def) then
    if M.own_persona then write_u32(p + G.PERSONA_NOW, M.own_persona) end
  elseif read_u32(def + G.D.PERSONA_COUNT) > 0 then
    write_u32(p + G.PERSONA_NOW, read_u32(def + G.D.PERSONAS))      -- their own voice (SP_JULIUS ...)
  end
  wml.log("player model: voice " .. tostring(cstring(read_u32(p + G.PERSONA_NOW), 32)))
  G.call(ctx, G.HUMAN_PLACE, { p, G.floats(ctx, { x, y, z, 0 }, 0), 0, MASK })
  for i = 0, 8 do write_f32(p + 32 + i * 4, rows[i]) end
  write_u32(p + G.P.HEALTH_MAX, health_max); write_f32(p + G.P.HEALTH, health)
  -- Back on the collision layer the body had: left on the "inactive" one it
  -- can't push off the ground and runs on the spot.
  local ent, now = diag(p, inst, "after")
  if G.pointer_ok(ent) and layer ~= 0 and now ~= layer then
    write_u32(ent + G.ENTITY_LAYER, layer)
    G.call(ctx, G.COLLISION_UPDATE, { read_u32(G.COLLISION_WORLD), ent, 1 })
    wml.log(string.format("player model: collision layer %08X -> %08X put back", now, layer))
  end
  if own_definition(def) then
    put_on_outfit(ctx, p)
    if M.own_sims then set_player_sims(p, M.own_sims); M.own_sims = nil end
  else
    local sims = wanted_sims(p)
    set_player_sims(p, sims)
    F.bones.dirty = true
    wml.log(string.format("player model: %d animation simulations (hair, coat, chains)", #sims))
  end
  F.move.dirty = true
  F.update_movement(ctx, p)
  M.watch = { x = x, z = z, until_tick = F.tick + 250, next = F.tick + 50 }
  return (read_u32(p + G.HUMAN_ACTIVE) & 3) == 3 and read_u32(inst + G.OWNER_ANIM_PLAYER) ~= MASK
end

local function end_job(ctx, job, msg, ok)
  if job.faded then G.script(ctx, "fade_in(0.3)") end
  if not ok and job.ref then stream_ref(ctx, job.ref, false) end
  if msg and (job.user or not ok) then G.hud(msg) end
  if msg then wml.log("player model: " .. msg) end
  F.model_job = nil
end

function F.update_model(ctx, p, vehicle)
  local M, job = F.model, F.model_job
  if p == 0 then
    -- Out of the game (front end, loading): the next game starts in the
    -- player's own body; the remembered model is put back once in.
    if job then F.model_job = nil end
    M.in_game, M.def, M.name = nil, nil, nil
    if M.ref then M.ref = nil end
    return
  end
  local w = M.watch
  if w and F.tick >= w.next then
    local x, _, z = G.vec(p + G.P.POS)
    wml.log(string.format("player model: %.1f m from the swap spot, state %d, +216 %08X, worn %d", math.sqrt((x - w.x) ^ 2 + (z - w.z) ^ 2),
      read_u32(p + G.P.STATE), read_u32(p + 216), worn_count(p)))
    w.next = F.tick + 50
    if F.tick >= w.until_tick then M.watch = nil end
  end
  local def_now = read_u32(p + G.HUMAN_DEF)
  if own_definition(def_now) then M.own_def = def_now end
  if M.name and def_now == M.def and F.tick % 10 == 0 then
    local sims = wanted_sims(p)
    if not same(sims, player_sims(p)) then set_player_sims(p, sims) end
  end
  -- Your clothes stay off while you're someone else: the game can still be
  -- putting them on when the swap happens (just after loading a game), and
  -- left on they're drawn over the other model and fill the model memory.
  if M.name and def_now == M.def and F.tick % 50 == 25 and worn_count(p) > 0 and not job and (M.strips or 0) < 20 then
    M.strips = (M.strips or 0) + 1
    if not M.outfit then
      local outfit = read_outfit(ctx, p)
      if outfit then M.outfit = outfit; save_outfit(outfit) end
    end
    if M.outfit then
      F.strip_outfit(ctx, p)
      wml.log(string.format("player model: your clothes came back on; taken off again (%d left)", worn_count(p)))
    end
  end
  if not M.in_game then M.in_game = F.tick end
  -- The model you wear unloaded under you (a cutscene can do it: Tanya and
  -- Tony as Aisha): your own body at once - loading it again while the body
  -- still points at the old one crashed. Cutscenes that leave it alone keep
  -- it. Once any cutscene is over and you're back in control, it goes back on.
  if M.name and M.ref and def_now == M.def and not job and (G.in_cutscene() or F.tick % 25 == 3) and not resident(ctx, M.ref) then
    local own = M.own_def
    local own_id = own and G.pointer_ok(own) and read_u32(own + G.D.STREAM_ID)
    if own_id and resident(ctx, own_id) then
      local name = M.name
      local ok = swap_body(ctx, p, own)
      for _ = 0, (M.extra_refs or 0) do stream_ref(ctx, M.ref, false) end
      M.ref, M.extra_refs = nil, 0
      M.name, M.def = nil, nil
      M.cut = {}
      wml.log("player model: " .. name .. "'s model was unloaded; yourself until you're back in control (" .. (ok and "ok" or "body not fully back") .. ")")
    elseif own_id and not M.cut_pumped then
      M.cut_pumped = true
      G.call(ctx, G.MODEL_LOAD_NOW, { own_id, 5, 0 })
    end
  end
  local C = M.cut
  if C then
    if G.in_cutscene() then C.off = nil elseif not C.off then C.off = F.tick end
    if C.off and F.tick - C.off > 60 then M.cut, M.cut_pumped, M.last_auto = nil, nil, nil end
  end
  keep_model_loaded(ctx)
  -- Rebuilt by the game (respawn, a new game): our model is gone.
  if M.name and def_now ~= M.def then
    wml.log("player model: the game rebuilt the player; " .. M.name .. " goes back on")
    if M.ref then
      for _ = 0, (M.extra_refs or 0) do stream_ref(ctx, M.ref, false) end
      M.ref, M.extra_refs = nil, 0
    end
    M.name, M.def = nil, nil
  end
  if not job then
    if M.want and not M.name and not M.cut and not G.in_cutscene() and F.tick - M.in_game > 150 and F.tick - (M.last_auto or -100000) > 500
        and G.playing(p) and read_f32(p + G.P.HEALTH) > 0 then
      M.last_auto = F.tick
      local label = M.want
      for _, list in pairs(HOMIE_BY_GROUP) do
        for _, c in ipairs(list) do if c[1] == M.want then label = c[2] end end
      end
      F.model_job = { name = M.want, label = label, phase = "start" }
    end
    return
  end

  if job.phase == "start" then
    if not G.playing(p) or vehicle ~= 0 or read_f32(p + G.P.HEALTH) <= 0 then
      return end_job(ctx, job, "Changing model needs you on foot", false)
    end
    local def
    if job.name then
      def = G.call(ctx, G.MODEL_LOOKUP, { G.cstr(ctx, job.name, 0), 0 })
      if not G.pointer_ok(def) or not F.model_usable(ctx, job.name) then
        if not job.user then M.want = nil end
        return end_job(ctx, job, "That character can't be used as a model", false)
      end
    else
      def = M.own_def
      if not def or not G.pointer_ok(def) then return end_job(ctx, job, "Your own model isn't known yet", false) end
    end
    if def == def_now and not job.look and not job.reload then
      M.want = job.name; save_model(job.name)
      return end_job(ctx, job, job.name and ("You already look like " .. job.label) or "You're already yourself", true)
    end
    if F.posing or F.repeating or F.release_at then F.release_player(ctx, p) end
    job.def, job.id = def, read_u32(def + G.D.STREAM_ID)
    -- Another look of the model you wear keeps the model you hold.
    if job.name and def ~= def_now then stream_ref(ctx, job.id, true); job.ref = job.id end
    -- A new look on the model you wear: rebuilt at once, no fade.
    if job.look and job.look.quick and def == def_now then
      job.t, job.phase = F.tick - 18, "load"
      return
    end
    G.script(ctx, "fade_out_do(0.3, 0, 0, 0)")
    job.faded, job.t, job.phase = true, F.tick, "load"
    return
  end

  if job.phase == "load" then
    if F.tick - job.t < 18 then return end           -- the fade
    if not resident(ctx, job.id) then
      if not job.pumped and F.tick - job.t > 30 then
        job.pumped = true
        G.call(ctx, G.MODEL_LOAD_NOW, { job.id, 5, 0 })
      end
      if F.tick - job.t > 450 then return end_job(ctx, job, "Their model wouldn't load; try again in another spot", false) end
      return
    end
    if vehicle ~= 0 or read_f32(p + G.P.HEALTH) <= 0 then return end_job(ctx, job, "Model change stopped", false) end
    local before = def_now
    local ok = swap_body(ctx, p, job.def, job.look)
    if not ok then
      wml.log(string.format("player model: %s didn't attach (bits %X); putting the old body back", tostring(job.name), read_u32(p + G.HUMAN_ACTIVE)))
      swap_body(ctx, p, before)
      return end_job(ctx, job, "That model didn't fit; you're back as before", false)
    end
    if job.ref then
      if M.ref and M.ref ~= job.ref then
        for _ = 0, (M.extra_refs or 0) do stream_ref(ctx, M.ref, false) end
      end
      M.ref, M.extra_refs = job.ref, 0
    end
    M.name = job.name
    M.def = job.name and job.def or nil
    M.strips = 0
    M.want = job.name
    save_model(job.name)
    job.ref = nil
    M.label = job.label
    -- The look the menu shows: read again after the game rolled one; a look
    -- you made is put back on after a respawn.
    local L = F.look
    if not job.look or job.look.variant then
      if not job.look and L.model == job.name and L.custom then
        L.pending = F.tick + 10
      else
        L.state, L.custom = nil, false
      end
    end
    F.look_refresh(p)
    if job.reload then return end_job(ctx, job, "Character reloaded", true) end
    return end_job(ctx, job, job.name and ("You're now " .. job.label .. F.variation_text(p)) or "You're yourself again", true)
  end
end

-- ------------------------------------------------------------ homie heads
--
-- A bodyguard or character homie whose voice has no head picture gets the
-- Saints fleur-de-lis on the HUD instead of no head (or a stranger's).
F.guard_heads = {}
-- HUD pictures by name, looked up once the HUD has them.
local bitmaps = {}
local function bitmap(ctx, name)
  local h = bitmaps[name]
  if h == nil and ctx then
    h = G.call(ctx, G.BITMAP_FIND, { G.BITMAP_TABLE, G.cstr(ctx, name, 0) }) & 0xFFFF
    if h == 0xFFFF or h == 0 then return nil end   -- unknown (or not loaded yet): asked again later
    bitmaps[name] = h
  end
  return h
end
F.bitmap = bitmap

-- Women and girls get the female head: their definition's name says _F_
-- (TS_X_F_Thug, VK_B_F_Aisha ...) or they move with a female set.
local function is_female(obj) return F.def_female(read_u32(obj + G.HUMAN_DEF)) end

-- The co-op partner (Whompays Co-op) is a person wearing a player body
-- (StyleTest_PC, StyleTest_PC_MP..) who isn't you.
local player_bodies = {}
local function coop_partner(obj)
  local def = read_u32(obj + G.HUMAN_DEF)
  local body = player_bodies[def]
  if body == nil then
    body = def_name(def):lower():find("^styletest_pc") ~= nil
    if G.pointer_ok(def) then player_bodies[def] = body end
  end
  return body and obj ~= read_u32(G.PLAYER)
end

local GANG_HEADS = { ["Vice Lords"] = "recruit_vicekingz", ["Los Carnales"] = "recruit_carnales", Rollerz = "recruit_wrollerz" }
local function apply_head(obj, ctx)
  local picture
  if coop_partner(obj) then
    picture = "recruit_coop_player"
  else
    -- Gang members get their gang's head, everyone else a No Render head
    -- (all added to the HUD sheets by patch.lua), hers or his. A gang member
    -- recruited in person is given a Saints recruit's voice (and with it a
    -- Saints recruit's head): only a story character's own voice keeps its head.
    local persona = (cstring(read_u32(obj + G.PERSONA), 24) or ""):upper()
    local gang = F.gang_of and F.gang_of(ctx, read_u32(obj + G.HUMAN_DEF))
    if HEAD_PERSONAS[persona] and (not gang or persona:find("^SP_")) then return end
    picture = (GANG_HEADS[gang] or "recruit_norender") .. (is_female(obj) and "_f" or "_m")
  end
  -- The Saints logo if the pictures aren't there.
  local icon = bitmap(ctx, picture)
  if not icon then
    icon = read_u32(G.SAINTS_LOGO)
    if icon == MASK or icon == 0 then icon = read_u32(G.SAINTS_ICON) end
    if icon == MASK or icon == 0 then return end
  end
  if read_u32(obj + G.HUD_HEAD) ~= icon then write_u32(obj + G.HUD_HEAD, icon) end
end
F.apply_head = apply_head

-- Everyone following you on the HUD: bodyguards, character homies and
-- gang members you recruited yourself.
function F.fix_guard_heads(ctx)
  local n = math.min(read_u32(G.FOLLOWER_COUNT), 10)
  for i = 0, n - 1 do
    local h = read_u32(G.FOLLOWER_SLOTS + i * G.FOLLOWER_SLOT_SIZE + 188)
    local index = h & 0xFFFF
    local obj = (h ~= 0 and index < 4096) and read_u32(G.OBJECTS + 12 + index * 16) or 0
    if obj ~= 0 and read_u32(obj + 68) == h and read_u32(obj + 72) == 1 then apply_head(obj, ctx) end
  end
  for i = #F.guard_heads, 1, -1 do
    local h = F.guard_heads[i]
    local index = h & 0xFFFF
    local obj = index < 4096 and read_u32(G.OBJECTS + 12 + index * 16) or 0
    if obj == 0 or read_u32(obj + 68) ~= h then table.remove(F.guard_heads, i) else apply_head(obj, ctx) end
  end
  -- The co-op partner, wherever the HUD shows them.
  local first = read_u32(G.HUMAN_LIST)
  local obj = first
  for _ = 1, 400 do
    if not G.pointer_ok(obj) then break end
    if coop_partner(obj) then apply_head(obj, ctx) end
    obj = read_u32(obj + G.HUMAN_NEXT)
    if obj == first then break end
  end
end
-- Puts a held animation back if the game moved the person on.
local function hold_anim(ctx, h, tok)
  if tok.file then
    if read_u32(h + 756) ~= G.CUSTOM_STATE then play_file(ctx, h, tok.file, tok.hold) end
  elseif read_u32(h + G.ANIM_STATE) ~= tok.number then
    write_u32(h + G.ANIM_STATE, tok.number)
    G.call(ctx, G.ANIM_APPLY, { h, 0xFFFFFFFF, 0xFFFFFFFF, 0 })
  end
end

-- One action (anim_actions) on a person, the way play_action_do plays it.
local action_numbers = {}
local action_missed = {}   -- (a name not found is asked again after a while, not every update)
function F.forget_actions() action_missed = {} end
function F.action_number(ctx, name)
  local n = action_numbers[name]
  if n == nil then
    local miss = action_missed[name]
    if miss and F.tick - miss < 600 and F.tick >= miss then return nil end
    n = G.call(ctx, G.ACTION_INDEX, { G.cstr(ctx, name, 0) })
    if n == 0xFFFFFFFF then
      if not miss then wml.log("unknown action '" .. name .. "'") end
      action_missed[name] = F.tick
      return nil
    end
    action_numbers[name] = n
  end
  return n
end

function F.play_action(ctx, h, name)
  local n = F.action_number(ctx, name)
  if not n then return false, "That action isn't available" end
  if not in_set(ctx, h, 227 + n) then
    if F.debug then wml.log("action: " .. name .. " not in this person's animation set") end
    return false, h == read_u32(G.PLAYER) and "Your character can't do that one" or "They can't do that one"
  end
  local owner = read_u32(h + G.ANIM_OWNER)
  if not G.pointer_ok(owner) then return false, "Not now" end
  if h == read_u32(G.PLAYER) then F.capture_player(h); F.save_player_state(h) end
  F.free_held_tracks(ctx)
  local player = read_u32(owner + 3592)
  if player ~= 0 then
    G.call(ctx, G.ANIM_STOP, { player })
    G.call(ctx, G.ANIM_RESET, { player, 0 })
  end
  local ok = G.call(ctx, G.ACTION_PLAY, { h, n, 0, 1, 0, 0, 0, 0xFFFFFFFF }, { 0.0, 1.0, -1.0 })
  if F.debug then wml.log(string.format("action: %s (%d) on %08X -> %s", name, n, h, (ok & 0xFF) ~= 0 and "played" or "refused")) end
  if h == read_u32(G.PLAYER) then
    if (ok & 0xFF) ~= 0 then F.lock_player(h) else F.release_player(ctx, h) end
  end
  return (ok & 0xFF) ~= 0, "Not now (busy)"
end

function F.spawn_scene_actor(ctx, p, a)
  local model, anim = a[1], a[2]
  local def = G.call(ctx, G.MODEL_LOOKUP, { G.cstr(ctx, model, 0), 0 })
  if not G.pointer_ok(def) then wml.log("scene: unknown model " .. model) return end
  while #F.scene_actors >= MAX_SCENE do destroy(ctx, table.remove(F.scene_actors, 1).handle) end
  local pos = G.floats(ctx, { a[3], a[4] + 0.1, a[5], 0 }, 0)
  local rows = G.floats(ctx, rows_for(a[6]), 16)
  local stack = { { 84, 4, 0 }, { 94, 2, 8 }, { 103, 1, 0 } }
  local obj = G.call(ctx, G.HUMAN_CREATE, { 0, 2, def, pos, rows, 255, 0, 0 }, nil, stack)
  if not G.pointer_ok(obj) or obj == p or not handle_alive(read_u32(obj + 68)) then G.hud("No room for more people right now") return end
  local handle = keep_person(ctx, obj)
  -- A new person's animations may not be ready this update: the hold below
  -- starts it once they are.
  local tok, why = F.start_anim(ctx, obj, anim)
  F.scene_actors[#F.scene_actors + 1] = { handle = handle, anim = anim, tok = tok, born = F.tick }
  if F.debug then
    wml.log(string.format("scene: %s at %.1f %.1f %.1f, %s -> %s", model, a[3], a[4], a[5],
      type(anim) == "table" and anim.file or anim, tok and (tok.number and ("state " .. tok.number) or "file") or ("failed: " .. tostring(why))))
  end
end

-- Puts scene people back into their animation if the game moved them on.
function F.hold_scene(ctx)
  for i = #F.scene_actors, 1, -1 do
    local a = F.scene_actors[i]
    local index = a.handle & 0xFFFF
    local o = index < 4096 and read_u32(G.OBJECTS + 12 + index * 16) or 0
    if o == 0 or read_u32(o + 68) ~= a.handle or read_f32(o + G.P.HEALTH) <= 0 then
      table.remove(F.scene_actors, i)
    elseif a.tok and F.tick - a.born < 200 and not a.tok.file then
      -- Just made: apply again until the animation has had time to take.
      write_u32(o + G.ANIM_STATE, a.tok.number)
      G.call(ctx, G.ANIM_APPLY, { o, 0xFFFFFFFF, 0xFFFFFFFF, 0 })
    elseif a.tok then
      hold_anim(ctx, o, a.tok)
    else
      a.tok = F.start_anim(ctx, o, a.anim)
    end
  end
end

function F.clear_scene(ctx)
  local n = 0
  F.scene_queue = {}
  for i = #F.scene_actors, 1, -1 do
    local a = table.remove(F.scene_actors, i)
    if handle_alive(a.handle) then n = n + 1 end
    destroy(ctx, a.handle)
  end
  return string.format("Cleared %d %s", n, n == 1 and "person" or "people")
end

-- ------------------------------------------------------------- poses
--
-- A pose holds while you stand still; moving more than half a metre ends
-- it (the game takes over your animation again). If the game moves you on
-- while you are still, the pose is put back.
-- Emotes: every pose and action the game has (emotes.lua). Your body
-- animates with your own animation set, which has few of them and none of
-- the props: a state's prop (a 40oz, a blunt, a magazine) comes with the
-- set that plays it. So while an emote plays, your body borrows the set that
-- has it with its prop for your build (else the gang set for your build) -
-- the prop appears in your hand as on anyone else - and gets its own back
-- when the emote ends.
F.EMOTES = require("emotes")
-- The sets to try for an emote, best for your build first: the sex letter
-- of the set name (xML men, xFL women, xHL big) like your model's, then the
-- rest; a set that holds the emote's prop before one that doesn't. Each is
-- { set, animation file }; only those whose file is loaded right now count
-- (an animation set lists moves whose files are only in memory while
-- someone who uses them is about).
local function candidates(ctx, p, name, sets)
  local def = read_u32(p + G.HUMAN_DEF)
  local mine = F.def_female(def) and "F" or ((F.fill_set(def) == "GHL1") and "H" or "M")
  local with_prop = {}
  for _, e in ipairs(F.EMOTES.props[name:lower()] or {}) do with_prop[e[1]:upper()] = true end
  local list = {}
  for pair in (sets or ""):gmatch("[^,]+") do
    local s, file = pair:match("^([^=]+)=?(.*)$")
    if s and file ~= "" and anim_file_id(ctx, file) ~= 0xFFFFFFFF then list[#list + 1] = { s, file } end
  end
  local function rank(c)
    local u = c[1]:upper()
    return (with_prop[u] and 0 or 2) + (u:sub(2, 2) == mine and 0 or 1)
  end
  table.sort(list, function(a, b) local ra, rb = rank(a), rank(b) if ra ~= rb then return ra < rb end return a[1] < b[1] end)
  return list, next(with_prop) ~= nil
end
F.emote_candidates = candidates
local function borrow_set(ctx, p, name, is_action, list, prop)
  local inst = read_u32(p + G.ANIM_OWNER)
  if not G.pointer_ok(inst) then return false end
  local function can() if is_action then return F.can_act(ctx, p, name) end return F.can_play(ctx, p, name) end
  -- Your own set does it (and there's no prop to show): nothing to borrow.
  if not prop and can() then return true end
  local was = read_u32(inst + G.OWNER_SET)
  for _, c in ipairs(list) do
    local set = F.style_entry(ctx, c[1])
    if G.pointer_ok(set) then
      write_u32(inst + G.OWNER_SET, set)
      if can() then
        F.emote_set = F.emote_set or { inst = inst, was = was }
        return true
      end
    end
  end
  write_u32(inst + G.OWNER_SET, was)
  return can()
end
function F.end_emote_set(p)
  local E = F.emote_set
  F.emote_set = nil
  if not E or p == 0 or not G.pointer_ok(E.inst) or read_u32(p + G.ANIM_OWNER) ~= E.inst then return end
  write_u32(E.inst + G.OWNER_SET, E.was)
  F.move.refresh = true
end
local function emote_sets(kind, name)
  for _, g in ipairs(F.EMOTES[kind == "action" and "actions" or "poses"]) do
    for _, e in ipairs(g[2]) do if e[1]:lower() == name:lower() then return e[3] end end
  end
end
-- Plays an emote: through the set that has it (its prop with it), else its
-- animation file straight from memory; says why when neither can.
function F.emote(ctx, p, kind, name, shown, sets)
  if p == 0 then return "Load a game first" end
  if G.vehicle_object(p) then return "Get out of the vehicle first" end
  if not G.playing(p) or read_f32(p + G.P.HEALTH) <= 0 then return "Not now" end
  F.release_player(ctx, p)
  local list, prop = candidates(ctx, p, name, sets or emote_sets(kind, name))
  if #list == 0 then return "That animation is not available for your character right now" end
  local is_action = kind == "action"
  local through_set = borrow_set(ctx, p, name, is_action, list, prop)
  if through_set and is_action then
    local ok = F.play_action(ctx, p, name)
    if ok then
      -- Looped: played again each time it ends, until you move or stop it
      -- (Repeat action adds its pause between plays).
      F.looping = { name = name, slot = 227 + (F.action_number(ctx, name) or 0), started = F.tick,
        x = read_f32(p + G.P.POS), z = read_f32(p + G.P.POS + 8) }
      return shown .. " (move or RB + D-pad Up to stop)"
    end
  elseif through_set then
    F.save_player_state(p)
    local tok = F.start_anim(ctx, p, name)
    if tok then
      F.posing = { tok = tok, x = read_f32(p + G.P.POS), z = read_f32(p + G.P.POS + 8) }
      return shown
    end
  end
  -- The animation file itself, if it's in memory.
  F.end_emote_set(p)
  for _, c in ipairs(list) do
    if c[2] ~= "" then
      F.save_player_state(p)
      local tok = F.start_anim(ctx, p, { file = c[2], hold = true })
      if tok then
        F.posing = { tok = tok, x = read_f32(p + G.P.POS), z = read_f32(p + G.P.POS + 8) }
        return shown
      end
    end
  end
  F.release_player(ctx, p)
  if F.debug or #list == 0 then
    wml.log(string.format("emote: %s %s - %s", kind, name, #list == 0 and "no animation file of it is loaded now" or "no set or file would play it"))
  end
  return #list == 0 and "That one isn't loaded right now (it is when someone who does it is about)" or "Your character can't do that one"
end
-- The pages: by the game's categories; an emote whose animation isn't in
-- memory right now is left out (looked at each time a page opens).
function F.page_emotes(kind)
  return function(ctx)
    local function available_rows(c, group)
      local rows, p = {}, G.player()
      if p == 0 then return rows end
      for _, e in ipairs(group[2]) do
        if #candidates(c, p, e[1], e[3]) > 0 then
          rows[#rows + 1] = { label = e[2], kind = "action", run = function(cc, pp)
            return F.emote(cc, pp, kind == "actions" and "action" or "pose", e[1], e[2], e[3])
          end }
        end
      end
      return rows
    end
    local rows = {}
    for _, g in ipairs(F.EMOTES[kind]) do
      if #available_rows(ctx, g) > 0 then
        rows[#rows + 1] = { label = g[1], kind = "page", open = function(c)
          local r = available_rows(c, g)
          if #r == 0 then return "None of these are available right now" end
          return { title = g[1], rows = r }
        end }
      end
    end
    if #rows == 0 then return "No animations are available right now" end
    return { title = kind == "poses" and "Poses" or "Actions", rows = rows }
  end
end

function F.stop_pose(ctx, p)
  local was = F.posing or F.repeating or lock_saved
  F.release_player(ctx, p)
  return was and "Stopped" or "Not posing"
end

function F.hold_pose(ctx, p)
  local pose = F.posing
  local dx, dz = read_f32(p + G.P.POS) - pose.x, read_f32(p + G.P.POS + 8) - pose.z
  if dx * dx + dz * dz > 0.25 or G.vehicle_object(p) then F.release_player(ctx, p) return end
  hold_anim(ctx, p, pose.tok)
end

-- ------------------------------------------------------------- everybody...
--
-- Puts every person in the world (not you, nobody in a car, nobody dead)
-- into an animation state, the way set_animation_state does it. Several
-- states (the four dances) are shared out so the street doesn't move in
-- lockstep. Only people not already in their state are touched, so a
-- dance isn't restarted; the choice is applied again every 2 seconds for
-- new passers-by. Returns how many people were set.
local state_numbers = {}
local function state_number(ctx, name)
  local n = state_numbers[name]
  if n == nil then
    n = G.call(ctx, G.ANIM_STATE_INDEX, { G.cstr(ctx, name, 0) })
    if n == 0xFFFFFFFF then
      wml.log("unknown animation state '" .. name .. "'")
    else
      state_numbers[name] = n   -- only found names are remembered
    end
  end
  return n
end
state_number_of = state_number

-- Whether at least one person near the player (up to 40 looked at) has
-- one of these states in their animation set.
function F.someone_can(ctx, p, names)
  local head = read_u32(G.HUMAN_LIST)
  local h, me = head, read_u32(p + 68)
  for _ = 1, 40 do
    if not G.pointer_ok(h) then return false end
    if read_u32(h + 68) ~= me then
      for _, name in ipairs(names) do if F.can_play(ctx, h, name) then return true end end
    end
    h = read_u32(h + G.HUMAN_NEXT)
    if h == head then return false end
  end
  return false
end

-- Kill Yourself: whatever keeps you alive comes off (god mode, the damage
-- factor, the game's invulnerability), then the damage the game's own
-- "suicide" command deals (-1: dead at once); the game respawns you.
function F.kill_self(ctx, p)
  if F.items.god and F.items.god.v then F.items.god.v = false end
  F.killing_self = true
  write_f32(p + G.P.DAMAGE_FACTOR, 1.0)
  G.script(ctx, 'turn_vulnerable("#PLAYER#")')
  G.call(ctx, G.TAKE_DAMAGE, { p, p, 0, 0, 0, 0, 0, 0 }, { -1.0 })
  F.killing_self = false
  if read_f32(p + G.P.HEALTH) > 0 then write_f32(p + G.P.HEALTH, 0) end
  return "Wasted"
end
-- Kill Everyone: every person near you but you and your homies, as if you'd
-- killed them (-1: dead at once).
function F.kill_everyone(ctx, p)
  local spare = { [read_u32(p + 68)] = true }
  for i = 0, math.min(read_u32(G.FOLLOWER_COUNT), 16) - 1 do
    spare[read_u32(G.FOLLOWER_SLOTS + i * G.FOLLOWER_SLOT_SIZE + 188)] = true
  end
  local h, n = read_u32(G.HUMAN_LIST), 0
  local victims = {}
  for _ = 1, 300 do
    if not G.pointer_ok(h) then break end
    if not spare[read_u32(h + 68)] and read_u32(h + G.P.TYPE) == 1 and read_f32(h + G.P.HEALTH) > 0 then victims[#victims + 1] = h end
    h = read_u32(h + G.HUMAN_NEXT)
    if h == read_u32(G.HUMAN_LIST) then break end
  end
  for _, v in ipairs(victims) do
    G.call(ctx, G.TAKE_DAMAGE, { v, p, 0, 0, 0, 0, 0, 0 }, { -1.0 })
    n = n + 1
  end
  return n > 0 and string.format("%d killed", n) or "Nobody around"
end

-- Unlock all music: every song the music store has becomes yours, for
-- your playlists, as the game's own unlock-all does it.
function F.unlock_music(ctx)
  local genres, n = read_u32(G.MUSIC_GENRES), read_u32(G.MUSIC_GENRE_COUNT)
  if not G.pointer_ok(genres) or n == 0 or n > 64 then return "The music store isn't loaded yet" end
  local songs = 0
  for g = 0, n - 1 do
    local list, count = read_u32(genres + g * 12 + 4), read_u32(genres + g * 12 + 8)
    if G.pointer_ok(list) and count < 1000 then
      for k = 0, count - 1 do
        if read_u32(list + k * 44 + 24) ~= 2 then write_u32(list + k * 44 + 24, 2); songs = songs + 1 end
      end
    end
  end
  return songs > 0 and string.format("%d songs unlocked for your playlists", songs) or "Every song is already yours"
end
-- Unlock all collectibles: all 60 CDs found, the six bonus songs they give
-- unlocked, and the "CDs found" statistic up to date.
function F.unlock_collectibles(ctx, p)
  local have = read_u32(p + G.P_CDS)
  if have >= G.CD_MAX then return "All 60 CDs already found" end
  local buf = G.buffer(ctx, 3)
  write_u32(buf, G.CD_MAX - have)
  G.call(ctx, G.STAT_ADD, { G.STAT_CDS, buf })
  write_u32(p + G.P_CDS, G.CD_MAX)
  for k = 1, 6 do
    G.call(ctx, G.UNLOCK, { G.call(ctx, G.UNLOCK_HASH, { G.cstr(ctx, "cd_collectible" .. k, 0), 0 }) })
  end
  return "All 60 CDs found: every bonus song unlocked"
end

function F.apply_everybody(ctx, p, names)
  local numbers, kept = {}, {}
  for _, name in ipairs(names) do
    local n = state_number(ctx, name)
    if n ~= 0xFFFFFFFF then numbers[#numbers + 1] = n; kept[#kept + 1] = name end
  end
  names = kept
  if #numbers == 0 then return 0 end
  local head = read_u32(G.HUMAN_LIST)
  local h, set, me = head, 0, read_u32(p + 68)
  for _ = 1, 200 do
    if not G.pointer_ok(h) then break end
    if read_u32(h + 68) ~= me and read_u32(h + G.P.VEHICLE) == 0 and read_f32(h + G.P.HEALTH) > 0 then
      -- Each person gets one of the states their own animation set has.
      local own = {}
      for k, name in ipairs(names) do if F.can_play(ctx, h, name) then own[#own + 1] = numbers[k] end end
      local want = #own > 0 and own[(read_u32(h + 68) % #own) + 1] or nil
      if F.debug and not want then
        local key = string.format("%08X %s", h, names[1])
        F.everybody_logged = F.everybody_logged or {}
        if not F.everybody_logged[key] then
          F.everybody_logged[key] = true
          wml.log(string.format("everybody: %08X can't do %s", h, table.concat(names, "/")))
        end
      end
      if want and read_u32(h + G.ANIM_STATE) ~= want then
        write_u32(h + G.ANIM_STATE, want)
        G.call(ctx, G.ANIM_APPLY, { h, 0xFFFFFFFF, 0xFFFFFFFF, 0 })
        set = set + 1
      end
    end
    h = read_u32(h + G.HUMAN_NEXT)
    if h == head then break end
  end
  return set
end

-- ------------------------------------------------------------- one person
--
-- Spawned people are checked 3 seconds later: anyone the game has removed
-- by then is logged and named on the HUD, to find models that don't stay.
F.watch_people = {}
function F.check_spawned()
  for i = #F.watch_people, 1, -1 do
    local w = F.watch_people[i]
    if F.tick - w.at >= 150 then
      table.remove(F.watch_people, i)
      local index = w.handle & 0xFFFF
      local o = index < 4096 and read_u32(G.OBJECTS + 12 + index * 16) or 0
      if o == 0 or read_u32(o + 68) ~= w.handle then
        wml.log("spawn person: " .. w.model .. " was removed by the game within 3 seconds")
        G.hud(w.model .. " didn't stay")
      elseif F.debug then
        local desc = read_u32(o + G.HUMAN_DEF)
        wml.log(string.format("spawn person: %s still here after 3 s (health %.0f, model %s)", w.model,
          read_f32(o + G.P.HEALTH), G.pointer_ok(desc) and string.format("%08X", read_u32(desc + 608)) or "none"))
      end
    end
  end
end
--
-- Any person model, made the way scene people are (a scripted character the
-- game leaves in place), three metres in front of you and facing you. They
-- count with the crowds for Remove spawned people.
function F.spawn_character(ctx, p, model)
  local def = G.call(ctx, G.MODEL_LOOKUP, { G.cstr(ctx, model, 0), 0 })
  if not G.pointer_ok(def) then wml.log("spawn person: unknown model " .. model) return false end
  make_room(ctx, F.spawned_people, MAX_SPAWNED_PEOPLE)
  -- A new kind of person when the menu already holds MAX_PERSON_MODELS:
  -- the oldest spawned people go first, so their model can be let go.
  local id, made_room = read_u32(def + 608), false
  local n, seen = person_models()
  while not seen[id] and n >= MAX_PERSON_MODELS and #F.spawned_people > 0 do
    destroy(ctx, table.remove(F.spawned_people, 1))
    made_room = true
    n, seen = person_models()
  end
  local x, y, z = person_spot(p)
  local px, _, pz = G.vec(p + G.P.POS)
  local yaw = math.atan(px - x, pz - z)          -- facing you
  local s, c = math.sin(yaw), math.cos(yaw)
  local pos = G.floats(ctx, { x, y, z, 0 }, 0)
  local rows = G.floats(ctx, { c, 0, -s, 0, 1, 0, s, 0, c }, 16)
  G.call(ctx, G.NUDGE_SPOT, { pos })             -- off anyone already standing there
  local stack = { { 84, 4, 0 }, { 94, 2, 8 }, { 103, 1, 0 } }
  local obj = G.call(ctx, G.HUMAN_CREATE, { 0, 2, def, pos, rows, 255, 0, 0 }, nil, stack)
  if not G.pointer_ok(obj) or obj == p then G.hud("No room for another person right now") return false end
  if not handle_alive(read_u32(obj + 68)) then G.hud("Couldn't place them there") return false end
  -- Gang members, gang story characters and police come on their team, and
  -- the game clears those away within seconds when no gang or cop is meant
  -- to be there. As civilians they stay (and don't start a fight).
  local team = read_u32(obj + 232)
  local civilian = G.call(ctx, G.TEAM_LOOKUP, { G.cstr(ctx, "Civilian", 1) })
  if civilian ~= 0xFFFFFFFF then write_u32(obj + 232, civilian) end
  local handle = keep_person(ctx, obj)
  F.spawned_people[#F.spawned_people + 1] = handle
  F.watch_people[#F.watch_people + 1] = { handle = handle, model = model, at = F.tick }
  if F.debug then
    wml.log(string.format("spawn person: %s at %.1f %.1f %.1f, team %d -> %d, %d kinds held, %d people in the game", model, x, y, z,
      team, civilian, (person_models()), read_u32(0x8309ABAC)))
  end
  return true, made_room
end

-- ------------------------------------------------------------- bodyguards
--
-- A bodyguard is made like a crowd member, but as a scripted character
-- (kind 0) the game leaves in place, then: the Saints team (human+232),
-- a gun with ammo in hand, three times the health, attack-enemies on
-- (human+3697 bit 0x40), and the game's own party insert (forced), which
-- sets them up to follow and fight, plus their HUD head. A character that
-- was only just created may not be ready to join, so joining is retried
-- for a few seconds.
local function guard_place(p)
  local x, y, z = G.vec(p + G.P.POS)
  local fx, fz = read_f32(G.CAMERA + 104), read_f32(G.CAMERA + 112)
  local len = math.sqrt(fx * fx + fz * fz)
  if len < 0.01 then fx, fz, len = 0, 1, 1 end
  local side = (#F.guards_joining % 2 == 0) and 1 or -1
  -- Beside and a little behind you.
  return x - fx / len * 1.5 + fz / len * 2 * side, y + 0.5, z - fz / len * 1.5 - fx / len * 2 * side
end

function F.spawn_guard(ctx, p, g)
  local def = G.call(ctx, G.MODEL_LOOKUP, { G.cstr(ctx, g[1], 0), 0 })
  if not G.pointer_ok(def) then wml.log("bodyguard: unknown model " .. g[1]) return end
  -- A new kind of person needs a model slot: spawned people go first, and
  -- with the slots full of your homies (and the model you wear) it waits.
  local id = read_u32(def + G.D.STREAM_ID)
  local function count()
    local n, seen = person_models()
    local worn = F.model.ref
    if worn and not seen[worn] then n = n + 1; seen[worn] = true end
    return n, seen
  end
  local n, seen = count()
  while not seen[id] and n >= MAX_PERSON_MODELS and #F.spawned_people > 0 do
    destroy(ctx, table.remove(F.spawned_people, 1))
    n, seen = count()
  end
  if not seen[id] and n >= MAX_PERSON_MODELS then
    G.hud("Too many kinds of people with you; dismiss a homie first")
    return
  end
  local x, y, z = guard_place(p)
  local pos = G.floats(ctx, { x, y, z, 0 }, 0)
  local rows = G.floats(ctx, { 1, 0, 0, 0, 1, 0, 0, 0, 1 }, 16)
  G.call(ctx, G.NUDGE_SPOT, { pos })
  local stack = { { 84, 4, 0 }, { 94, 2, 8 }, { 103, 1, 0 } }
  local obj = G.call(ctx, G.HUMAN_CREATE, { 0, 2, def, pos, rows, 255, 0, 0 }, nil, stack)
  if not G.pointer_ok(obj) or obj == p or not handle_alive(read_u32(obj + 68)) then G.hud("No room for another person right now") return end
  keep_person(ctx, obj)
  -- Your team, whichever it is (the Saints, or the gang you play with Saints
  -- are enemies on): never one against you in your own party.
  local team = read_u32(p + 232)
  if team == 0xFFFFFFFF then team = G.call(ctx, G.TEAM_LOOKUP, { G.cstr(ctx, "Playas", 1) }) end
  if team ~= 0xFFFFFFFF then write_u32(obj + 232, team) end
  local record = G.call(ctx, G.WEAPON_ITEM, { G.cstr(ctx, g[3], 2) })
  if G.pointer_ok(record) then
    local item = G.call(ctx, G.INV_ADD, { obj, record, 1 })
    if G.pointer_ok(item) then
      G.call(ctx, G.INV_ADD_AMMO, { obj, item, 999, 999 })
      G.call(ctx, G.NPC_EQUIP, { obj, item })
    end
  end
  local max = read_u32(obj + G.P.HEALTH_MAX)
  if max > 0 and max < 100000 then write_u32(obj + G.P.HEALTH_MAX, max * 3); write_f32(obj + G.P.HEALTH, max * 3) end
  write_u8(obj + 3697, read_u8(obj + 3697) | 0x40)
  F.guards_joining[#F.guards_joining + 1] = { handle = read_u32(obj + 68), tries = 0, name = g[2] }
  if F.debug then wml.log(string.format("bodyguard: %s created (object %08X, team %d)", g[2], obj, team)) end
end

-- Tries to add each new bodyguard to the party, for up to 3 seconds.
function F.join_guards(ctx, p)
  for i = #F.guards_joining, 1, -1 do
    local j = F.guards_joining[i]
    j.tries = j.tries + 1
    local index = j.handle & 0xFFFF
    local obj = index < 4096 and read_u32(G.OBJECTS + 12 + index * 16) or 0
    if obj == 0 or read_u32(obj + 68) ~= j.handle then
      table.remove(F.guards_joining, i)
    elseif j.tries % 5 == 1 then
      if read_u32(obj + 4128) == read_u32(p + 68) then
        table.remove(F.guards_joining, i)                       -- already following you
        F.guard_heads[#F.guard_heads + 1] = j.handle
        F.apply_head(obj, ctx)
      elseif read_u32(p + G.PARTY_COUNT) < 10 and (G.call(ctx, G.PARTY_ADD, { p, obj, 1 }) & 0xFF) ~= 0 then
        local slot = G.call(ctx, G.HUD_SLOT, { obj })
        if slot ~= 0xFFFFFFFF then G.call(ctx, G.HUD_ADD, { obj }) end
        F.guard_heads[#F.guard_heads + 1] = j.handle
        F.apply_head(obj, ctx)
        G.hud(j.name .. " is with you")
        if F.debug then wml.log("bodyguard: " .. j.name .. " joined after " .. j.tries .. " updates") end
        table.remove(F.guards_joining, i)
      elseif j.tries > 150 then
        G.hud(j.name .. " couldn't join your party")
        table.remove(F.guards_joining, i)
      end
    end
  end
end

-- God mode's bit must be released when switched off; the loop above only
-- clears bits it manages, so register god's release explicitly.

-- ------------------------------------------------------- Saints as enemies
--
-- People pick fights by team (human+232). While this is on, you're on the
-- team of the gang character you look like (Kings, Los Carnales, Rollerz ...)
-- or, as anyone else, Neutral Gang: the Saints see a rival and their own
-- gang sees one of theirs. Off puts your own team back.
local teams = {}
local function team(ctx, name)
  local id = teams[name]
  if id == nil then
    id = G.call(ctx, G.TEAM_LOOKUP, { G.cstr(ctx, name, 1) })
    if id == MASK then return nil end
    teams[name] = id
  end
  return id
end
-- The gang a definition belongs to ("Vice Lords", "Los Carnales", "Rollerz"), or nil.
function F.gang_of(ctx, def)
  if not G.pointer_ok(def) then return nil end
  local t = read_u32(def + G.D.TEAM)
  for _, name in ipairs({ "Vice Lords", "Los Carnales", "Rollerz" }) do
    if t == team(ctx, name) then return name end
  end
  return nil
end
-- The gang of the character you play doesn't hold it against you: hurting
-- its members never raises your notoriety with it. On their side (Saints
-- are enemies on) they treat it as the Saints do: a warning, then a fight,
-- and homies who are hit again and again leave.
local GANG_SLOT = { ["Los Carnales"] = 0, ["Vice Lords"] = 1, Rollerz = 2 }
function F.forgive_own_gang(ctx, p)
  local M = F.model
  if p == 0 or not (M.name and M.def) or read_u32(p + G.HUMAN_DEF) ~= M.def then return end
  local slot = GANG_SLOT[F.gang_of(ctx, M.def)]
  if not slot then return end
  local base = p + G.P.NOTORIETY + slot * 24
  local level, points = read_u32(base), read_f32(base + 12)
  if (level > 0 and level <= 5) or points > 0.001 then
    G.call(ctx, G.NOTORIETY_SET, { p + G.P.NOTORIETY, slot }, 0)
  end
end
F.saints = { own_team = nil, team = nil, level = 0 }
function F.saints.forget_teams() teams = {} end
function F.update_saints_enemies(ctx, p, on)
  local S = F.saints
  if p == 0 then return end
  local playas = team(ctx, "Playas")
  if not playas then return end
  team(ctx, "Vice Lords"); team(ctx, "Rollerz"); team(ctx, "Los Carnales")
  if not on then
    if S.own_team and read_u32(p + 232) == S.team then write_u32(p + 232, S.own_team) end
    S.own_team, S.team = nil, nil
    return
  end
  -- The gang picked in Gang you side with (extras.lua) comes first.
  local pick = F.join_gang_team and F.join_gang_team()
  local want = pick and team(ctx, pick) or nil
  local def = read_u32(p + G.HUMAN_DEF)
  -- Lin worked her way into the Rollerz: as her, they're your people.
  local def_name = G.pointer_ok(def) and (cstring(read_u32(def + G.D.NAME), 48) or ""):lower() or ""
  if not want and def_name:find("^ts_a_f_lin") then want = team(ctx, "Rollerz") end
  if not want and G.pointer_ok(def) then
    local t = read_u32(def + G.D.TEAM)
    if t ~= playas and t ~= team(ctx, "Civilian") and t ~= team(ctx, "Police") and t ~= MASK then want = t end
  end
  want = want or team(ctx, "Neutral Gang")
  if not want then return end
  local now = read_u32(p + 232)
  if now ~= want then
    if now ~= S.team then S.own_team = now end
    write_u32(p + 232, want)
    if F.debug then wml.log(string.format("saints enemies: your team %d -> %d", now, want)) end
  end
  S.team = want
  -- Notoriety earned since the last update (not set from inside the game's
  -- damage call, where it was earned).
  if S.pending then F.set_saints_notoriety(ctx, p, F.saints_notoriety(p) + S.pending); S.pending = nil end
end

-- Hurting Saints while they're your enemies builds a Saints notoriety
-- (the game keeps a slot for it, number 3, but never fills it), a little
-- at a time like the other gangs': about a third of a level a kill, a
-- little for each hit; the game's own decay brings it down again.
local SAINTS_PER_KILL, SAINTS_PER_HIT = 0.34, 0.05
function F.saints_hit(ctx, p, victim, killed)
  if not F.on("saints_enemies") or p == 0 then return end
  local playas = teams["Playas"]
  if not playas or read_u32(victim + 232) ~= playas then return end
  F.saints.pending = (F.saints.pending or 0) + (killed and SAINTS_PER_KILL or SAINTS_PER_HIT)
end
-- Saints notoriety as a number (level plus the part of the next one).
function F.saints_notoriety(p)
  local base = p + G.P.NOTORIETY + 3 * 24
  local level = read_u32(base)
  if level >= 0x80000000 then level = 0 end
  local points = read_f32(base + 12)
  if points ~= points or points < level or points > 6 then points = level end
  return points
end
function F.set_saints_notoriety(ctx, p, value)
  local base = p + G.P.NOTORIETY + 3 * 24
  value = math.max(0, math.min(5, value))
  if read_u32(base + 8) < 5 then write_u32(base + 8, 5) end   -- no cap below 5
  G.call(ctx, G.NOTORIETY_SET, { p + G.P.NOTORIETY, 3 }, value)
end
-- The HUD meter: when Saints notoriety is the highest, the meter shows the
-- Saints slot, with the Saints logo, in purple.
local saints_meter, saints_drawing = false, false
G.hook(G.NOTORIETY_PICK, function(ctx)
  local p = ctx:r(3) & MASK
  ctx:call_original()
  saints_meter = false
  if not F.on("saints_enemies") or p == 0 or p ~= read_u32(G.PLAYER) then return end
  local saints = read_u32(p + G.P.NOTORIETY + 3 * 24)
  if saints == 0 or saints >= 0x80000000 then return end
  local type_now = ctx:r(3) & MASK
  local slot_of = { [1] = 0, [2] = 1, [3] = 2 }
  local other = slot_of[type_now] and read_u32(p + G.P.NOTORIETY + slot_of[type_now] * 24) or 0
  if other < 0x80000000 and saints >= other then
    saints_meter = true
    ctx:set_r(3, 1)          -- a gang the meter is drawn for; slot 0 is drawn as the Saints
  end
end)
G.hook(G.NOTORIETY_METER, function(ctx)
  if not saints_meter or (ctx:r(4) & MASK) ~= 0 then ctx:call_original() return end
  ctx:set_r(4, 3)
  local icons = G.NOTORIETY_ICONS + 4 * 4
  local icon_was, logo = read_u32(icons), read_u32(G.SAINTS_ICON)   -- the small fleur-de-lis
  if logo ~= MASK and logo ~= 0 then write_u32(icons, logo) end
  saints_drawing = true
  ctx:call_original()
  saints_drawing = false
  write_u32(icons, icon_was)
end)
G.hook(G.DRAW_COLOR, function(ctx)
  if saints_drawing then ctx:set_r(3, 150); ctx:set_r(4, 70); ctx:set_r(5, 220) end
  ctx:call_original()
end)

-- The minimap: with the Saints your enemies their dots turn red, and the
-- members of the gang you belong to show in its colour - Vice Kings yellow
-- (a dot patch.lua adds to the HUD sheet), Rollerz blue, Los Carnales red.
-- The dot routines get the person's position (person+20); the picture is
-- swapped for the one draw and put back.
local function with_dot(slot, image, ctx)
  local was = read_u32(slot)
  write_u32(slot, image)
  ctx:call_original()
  write_u32(slot, was)
end
G.hook(G.DOT_SAINT, function(ctx)
  if not F.on("saints_enemies") then ctx:call_original() return end
  with_dot(G.DOT_IMAGES + 16, read_u32(G.DOT_IMAGES + 12), ctx)          -- red
end)
G.hook(G.DOT_GANG, function(ctx)
  local p = read_u32(G.PLAYER)
  if not F.on("saints_enemies") or p == 0 or not G.pointer_ok(p) then ctx:call_original() return end
  local person = (ctx:r(3) & MASK) - 20
  local their = G.pointer_ok(person) and read_u32(person + 232) or MASK
  if their ~= read_u32(p + 232) then ctx:call_original() return end
  if their == teams["Vice Lords"] then
    local yellow = bitmap(ctx, "map_other_blip_yellow")
    if yellow then with_dot(G.DOT_IMAGES + 12, yellow, ctx) return end
  elseif their == teams["Rollerz"] then
    with_dot(G.DOT_IMAGES + 12, read_u32(G.DOT_IMAGES + 8), ctx)         -- blue
    return
  end
  ctx:call_original()
end)
-- Homies' arrows on the minimap in their gang's colour: Vice Kings yellow,
-- Los Carnales red, Rollerz blue, Saints the game's purple; homies from no
-- gang (pedestrians, police, activity characters) dark grey with a purple
-- edge, drawn as four purple arrows a step out each way under the grey one.
local ARROW_COLOURS = { ["Vice Lords"] = { 255, 206, 20 }, ["Los Carnales"] = { 220, 30, 30 }, Rollerz = { 30, 120, 255 } }
local GREY, PURPLE = { 70, 70, 70 }, { 160, 0, 255 }
F.arrows = { on = false }
function F.arrow_colour(ctx, person)
  local def = G.pointer_ok(person) and read_u32(person + G.HUMAN_DEF) or 0
  if not G.pointer_ok(def) then return nil end
  local t = read_u32(def + G.D.TEAM)
  if t == team(ctx, "Playas") then return nil end
  for name, c in pairs(ARROW_COLOURS) do
    if t == team(ctx, name) then return c end
  end
  return GREY, true
end
G.hook(G.FOLLOWER_ARROWS, function(ctx)
  F.arrows.on = true
  ctx:call_original()
  F.arrows.on, F.arrows.edge = false, nil
end)
G.hook(G.ARROW_TINT, function(ctx)
  local A = F.arrows
  if A.on and ctx:f(1) == 160 and ctx:f(2) == 0 and ctx:f(3) == 255 then
    local c, edge = F.arrow_colour(ctx, (ctx:r(31) & MASK) - 20)
    A.edge = edge and ctx:f(4) or nil
    if c then ctx:set_f(1, c[1]); ctx:set_f(2, c[2]); ctx:set_f(3, c[3]) end
  end
  ctx:call_original()
end)
G.hook(G.DRAW_BITMAP, function(ctx)
  local A = F.arrows
  if A.on and A.edge and not A.busy and (ctx:r(3) & MASK) == read_u32(G.ARROW_IMAGE) then
    local alpha = math.max(0, math.min(255, math.floor(A.edge)))
    A.busy, A.edge = true, nil
    local args = { ctx:r(3), ctx:r(4), ctx:r(5), ctx:r(6), ctx:r(7), ctx:r(8) }
    local x, y, turn, size = ctx:f(1), ctx:f(2), ctx:f(3), ctx:f(4)
    G.call(ctx, G.DRAW_COLOR, { PURPLE[1], PURPLE[2], PURPLE[3], alpha })
    for _, d in ipairs({ { 1.5, 0 }, { -1.5, 0 }, { 0, 1.5 }, { 0, -1.5 } }) do
      G.call(ctx, G.DRAW_BITMAP, args, { x + d[1], y + d[2], turn, size })
    end
    G.call(ctx, G.DRAW_COLOR, { GREY[1], GREY[2], GREY[3], alpha })
    A.busy = false
  end
  ctx:call_original()
end)

-- ------------------------------------------------------------ the music
--
-- Your own playlists and the song preview hand the music player the game's
-- stock songs (game\data\audio\MP3_Player\NAME.wma), which it can't decode.
-- MP3 copies sit in game\data\audio\MP3_Stocks (a folder the player doesn't
-- list); the path in the request is switched to the copy - same length, in
-- place: MP3_Player -> MP3_Stocks, .wma -> .mp3. The game's own files are
-- left as they are.
local STOCK_DIR = wml.mod_folder .. "/../../game/data/audio/MP3_Stocks/"
local stock_ok = {}
local function have_stock(name)
  local ok = stock_ok[name]
  if ok == nil then
    local file = io.open(STOCK_DIR .. name .. ".mp3", "rb")
    ok = file ~= nil
    if file then file:close() end
    stock_ok[name] = ok
  end
  return ok
end
local function stock_path(path)
  local chars = {}
  for i = 0, 300 do
    local c = read_u16(path + i * 2)
    if c == 0 then break end
    chars[#chars + 1] = c < 128 and string.char(c) or "?"
  end
  local text = table.concat(chars)
  local lower = text:lower()
  local at = lower:find("mp3_player\\", 1, true)
  if not at or lower:sub(-4) ~= ".wma" then return false end
  local name = text:sub(at + 11, -5)
  if name:find("[\\?]") or not have_stock(name) then return false end
  local function put(pos, s) for k = 1, #s do write_u16(path + (pos + k - 2) * 2, s:byte(k)) end end
  put(at, "MP3_Stocks")
  put(#text - 3, ".mp3")
  return true
end
G.hook(G.MUSIC_PLAYLIST, function(ctx)
  local songs, count = ctx:r(4) & MASK, ctx:r(5) & MASK
  if G.pointer_ok(songs) and count > 0 and count < 4096 then
    local switched = 0
    for i = 0, count - 1 do
      local path = read_u32(songs + i * 36)
      if G.pointer_ok(path) and stock_path(path) then switched = switched + 1 end
    end
    if switched > 0 then wml.log(string.format("music: %d of %d songs played from MP3_Stocks", switched, count)) end
    if F.track_song then pcall(F.track_song, songs) end
  end
  ctx:call_original()
end)
F.stock_path = stock_path

-- The next song, and the music volume. The music player is handed one song
-- at a time; the game moves on when the player says it stopped, which it
-- doesn't always say - the song ended and nothing more played until you
-- skipped. Each song's length is read from its MP3 (the Xing frame count,
-- or its bitrate); if the game hasn't moved on 2 s after the song ends, the
-- game's own next track (0x82217118, as at a song's end: repeat-one kept)
-- is run. Only the MP3 player's playing time counts (its state at
-- 0x827E69B8 + 28 is 1), so a pause holds the count.
-- Volume: the music player keeps its remembered volume when told exactly 1
-- (it takes that for a title's "no attenuation" default), so the slider at
-- its top did nothing until moved; 1 is sent as 0.999. The volume is also
-- sent again a second after each song starts (the game's own call,
-- 0x82102BF8, with the setting at 0x827D94A8).
;(function()
local GAME_DIR = wml.mod_folder .. "/../../game/"
local MP3_STATE, NEXT_TRACK, PLAYER_STATE = 0x827E69D4, 0x82217118, 0x827E69B8
local SET_MUSIC_VOLUME, MUSIC_VOLUME, XMP_SET_VOLUME = 0x82102BF8, 0x827D94A8, 0x826599F0
local L3_RATES = { [3] = { 44100, 48000, 32000 }, [2] = { 22050, 24000, 16000 }, [0] = { 11025, 12000, 8000 } }
local L3_KBPS = { [3] = { 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320 },
  [2] = { 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160 } }
L3_KBPS[0] = L3_KBPS[2]
local function be32(s, i) local a, b, c, d = s:byte(i, i + 3) return ((a << 24) | (b << 16) | (c << 8) | d) end
function F.mp3_seconds(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local size = file:seek("end")
  file:seek("set", 0)
  local head = file:read(10) or ""
  local start = 0
  if head:sub(1, 3) == "ID3" and #head == 10 then
    local s = {}
    for k = 7, 10 do s[#s + 1] = head:byte(k) & 0x7F end
    start = 10 + ((s[1] << 21) | (s[2] << 14) | (s[3] << 7) | s[4])
    if (head:byte(6) & 0x10) ~= 0 then start = start + 10 end
  end
  file:seek("set", start)
  local data = file:read(16384) or ""
  file:close()
  for i = 1, #data - 4 do
    local b1, b2, b3, b4 = data:byte(i, i + 3)
    if b1 == 0xFF and (b2 & 0xE0) == 0xE0 and ((b2 >> 1) & 3) == 1 then
      local version, rate_i, kbps_i = (b2 >> 3) & 3, (b3 >> 2) & 3, b3 >> 4
      local rates = L3_RATES[version]
      if rates and rate_i < 3 and kbps_i > 0 and kbps_i < 15 then
        local rate = rates[rate_i + 1]
        local per_frame = version == 3 and 1152 or 576
        local mono = (b4 >> 6) == 3
        local side = version == 3 and (mono and 21 or 36) or (mono and 13 or 21)
        local tag = data:sub(i + side, i + side + 3)
        if (tag == "Xing" or tag == "Info") and #data >= i + side + 11 then
          local flags = be32(data, i + side + 4)
          if (flags & 1) ~= 0 then return be32(data, i + side + 8) * per_frame / rate end
        end
        return (size - start - (i - 1)) * 8 / (L3_KBPS[version][kbps_i] * 1000)
      end
    end
  end
  return nil
end
-- The song a playlist starts (the game's path: GAME:\... -> the game folder).
local function track_song(songs)
  local path = read_u32(songs)
  local chars = {}
  for i = 0, 300 do
    local c = G.pointer_ok(path) and read_u16(path + i * 2) or 0
    if c == 0 then break end
    chars[#chars + 1] = c < 128 and string.char(c) or "?"
  end
  local text = table.concat(chars):gsub("^[Gg][Aa][Mm][Ee]:\\", ""):gsub("\\", "/")
  local length = text ~= "" and F.mp3_seconds(GAME_DIR .. text) or nil
  F.music = { song = text, length = length, played = 0, last = os.clock(), volume_at = os.clock() + 1 }
  if F.debug then wml.log(string.format("music: '%s', %s", text, length and string.format("%.1f s", length) or "length unknown")) end
end
F.track_song = track_song
G.hook(XMP_SET_VOLUME, function(ctx)
  if ctx:f(1) >= 0.999 then ctx:set_f(1, 0.999) end
  ctx:call_original()
end)
function F.update_music(ctx)
  local M = F.music
  if not M then return end
  local now = os.clock()
  if read_u32(MP3_STATE) == 1 then M.played = M.played + math.min(now - M.last, 0.5) end
  M.last = now
  if M.volume_at and now >= M.volume_at then
    M.volume_at = nil
    local v = read_f32(MUSIC_VOLUME)
    if v >= 0 and v <= 1 then G.call(ctx, SET_MUSIC_VOLUME, {}, { v }) end
  end
  if M.length and not M.done and M.played > M.length + 2 and not G.screen_up() then
    M.done = true
    wml.log(string.format("music: '%s' ended and nothing came next; next song", M.song))
    G.call(ctx, NEXT_TRACK, { PLAYER_STATE, 0 })
  end
end
end)()
-- ------------------------------------------------------- invulnerability
--
-- One owner for the player's invulnerability bit: god mode and the short
-- shields (soft landing, waypoint teleport) each just say whether they want
-- it. The bit is on while anything wants it, and taken off only if the menu
-- put it on, so a mission that makes you invulnerable is left alone and a
-- shield that ends early can never leave god mode behind.
F.shields = {}
local we_set = false
-- Every change of the bit is logged with who made it, so a god mode that
-- shows up uninvited can be traced (wml.log, "invulnerable:").
local bit_seen = nil
local function note_bit(p, by)
  local has = G.has_bits(p + G.P.FLAGS, G.FLAG.INVULNERABLE)
  if has ~= bit_seen then
    local names = {}
    for name, until_tick in pairs(F.shields) do names[#names + 1] = string.format("%s(%ds)", name, (until_tick - F.tick) // 50) end
    wml.log(string.format("invulnerable: %s by %s; god %s, shields [%s], menu set it %s, last teleport %s",
      has and "ON" or "off", by, F.on("god") and "on" or "off", table.concat(names, " "), tostring(we_set),
      F.last_teleport and string.format("%s %ds ago", F.last_teleport[1], (F.tick - F.last_teleport[2]) // 50) or "none"))
    bit_seen = has
  end
end
F.note_invulnerable = note_bit
function F.sync_invulnerable(p)
  if p == 0 then bit_seen = nil return end
  note_bit(p, "the game or another mod")
  -- A shield lasts until it's let go, or its time limit at most.
  for name, until_tick in pairs(F.shields) do
    if F.tick >= until_tick then F.shields[name] = nil end
  end
  local want = F.on("god") or next(F.shields) ~= nil
  local has = G.has_bits(p + G.P.FLAGS, G.FLAG.INVULNERABLE)
  -- The other way the game makes you unhurtable: every hit is multiplied
  -- by human+2068 (1 normally). Walking into an activity's start sets it to
  -- 0 until the activity ends; teleporting away (or changing model) before
  -- that leaves it at 0 for good, with no flag set. Without god mode or a
  -- shield, a 0 that lasts two seconds outside cutscenes goes back to 1.
  if not want and not G.in_cutscene() and read_f32(p + G.P.DAMAGE_FACTOR) < 0.01 then
    F.zero_factor = F.zero_factor or F.tick
    if F.tick - F.zero_factor >= 100 then F.restore_damage(p, "for 2 s") end
  else
    F.zero_factor = nil
  end
  if want then
    if not has then G.player_flag(p, G.FLAG.INVULNERABLE, true) end
    we_set = true
  elseif we_set then
    if has then G.player_flag(p, G.FLAG.INVULNERABLE, false) end
    we_set = false
  end
  note_bit(p, "the menu")
end
function F.restore_damage(p, why)
  write_f32(p + G.P.DAMAGE_FACTOR, 1.0)
  F.zero_factor = nil
  wml.log("invulnerable: your damage factor was 0 (" .. why .. "); put back to 1 - hits hurt again")
end
function F.shield(name, on, p, limit)
  F.shields[name] = on and (F.tick + (limit or 1500)) or nil
  if p and p ~= 0 then F.sync_invulnerable(p) end
end
F.items.god.off = function(ctx, p) if p ~= 0 then F.sync_invulnerable(p) end end

-- Fills every gun in the player's inventory straight in memory: no game
-- function is called, so it is safe whatever else is switched on. The
-- inventory is a ring of items starting at player+2324 (item+0 = next,
-- item+16 = ammo record); the ammo record holds the rounds in the magazine
-- (+16) and in reserve (+20) and points at the weapon (+8), whose magazine
-- size (+104) and most rounds (+106) are the limits the game itself uses.
-- (An earlier version ran the game's own script functions for this and
-- froze the game.)
function F.refill_all(p)
  local head = read_u32(p + G.P.INVENTORY)
  if not G.pointer_ok(head) then return 0 end
  local item, filled = head, 0
  for _ = 1, 64 do
    local ammo = read_u32(item + 16)
    if G.pointer_ok(ammo) then
      local info = read_u32(ammo + 8)
      if G.pointer_ok(info) then
        local mag, most = read_u16(info + 104), read_u16(info + 106)
        if mag >= 1 and mag < 1000 and most < 10000 then
          write_u32(ammo + 16, mag)
          if most > 0 then write_u32(ammo + 20, most) end
          filled = filled + 1
        end
      end
    end
    item = read_u32(item)
    if item == head or not G.pointer_ok(item) then break end
  end
  return filled
end

-- Sets one team's notoriety with the game's own setter, so spawns, HUD
-- stars and decay timers follow. A mission's cap (+8) is lifted first. Below
-- level 5 the level is given half its points, as earning it would, so it
-- does not decay away at once.
function F.set_notoriety(ctx, p, gang, level)
  local base = p + G.P.NOTORIETY + gang * 24
  if read_u32(base + 8) < level then write_u32(base + 8, level) end
  local value = level
  if level > 0 and level < 5 then value = level + 0.5 end
  G.call(ctx, G.NOTORIETY_SET, { p + G.P.NOTORIETY, gang }, value)
end

function F.set_notoriety_all(ctx, p, level, gangs)
  gangs = gangs or { 4, 0, 1, 2 }
  for _, g in ipairs(gangs) do F.set_notoriety(ctx, p, g, level) end
  return "Notoriety " .. level .. " for cops and every gang"
end

-- ---------------------------------------------------------- menu actions
--
-- All of these run inside the update hook (they may call the game).

local function context(it)
  local p = G.player()
  local v = 0
  if p ~= 0 then v = G.vehicle_object(p) or 0 end
  if it.needs == "player" and p == 0 then return nil, "Load a single-player game first" end
  if it.needs == "vehicle" and v == 0 then return nil, "Get in a vehicle first" end
  return p, v
end

function F.toggle(ctx, it)
  if it.kind ~= "toggle" then return end
  it.v = not it.v
  if it.id == "master" then F.enabled = it.v end
  local p, v = context(it)
  local msg = it.change and (p or it.needs == "none") and it.change(ctx, p or 0, v or 0, it)
  return msg or (it.label .. (it.v and " on" or " off"))
end

function F.adjust(ctx, it, dir, fast)
  if it.kind == "value" then
    if it.live and it.read then
      -- Step from what is shown (the game, or an add-on, may have changed it).
      local ok, r = pcall(it.read, G.player())
      if ok and type(r) == "number" then it.v = r end
    end
    local step = it.step * (fast and 10 or 1)
    local nv = it.v + dir * step
    nv = math.max(it.min, math.min(it.max, nv))
    -- Keep floats tidy (0.1 steps).
    nv = math.floor(nv / it.step + 0.5) * it.step
    if math.abs(nv - it.v) < 1e-9 then return end
    it.v = nv
    local p, v = context(it)
    if it.change and p then it.change(ctx, p, v, it) end
    return it.label .. " " .. it.fmt(it.v)
  elseif it.kind == "choice" then
    local n = #it.options
    it.v = ((it.v - 1 + dir) % n) + 1
    local p, v = context(it)
    if it.change and p then it.change(ctx, p, v, it) end
    return it.label .. ": " .. it.options[it.v]
  elseif it.kind == "list" then
    -- Shift (keyboard) jumps ten at a time through long lists. Entries the
    -- item says can't be used right now (poses your character hasn't got)
    -- are stepped over.
    local n = #it.items
    it.v = ((it.v - 1 + dir * (fast and 10 or 1)) % n) + 1
    if it.usable then
      local p = G.player()
      if p ~= 0 then
        for _ = 1, n do
          local ok, use = pcall(it.usable, ctx, p, it.items[it.v])
          if not ok or use then break end
          it.v = ((it.v - 1 + (dir < 0 and -1 or 1)) % n) + 1
        end
      end
    end
    if it.change then
      local p, v = context(it)
      if p and p ~= 0 then it.change(ctx, p, v, it) end
    end
    return it.label .. ": " .. it.items[it.v][2]
  end
end

function F.activate(ctx, it)
  if it.kind == "toggle" then return F.toggle(ctx, it) end
  if it.kind == "value" then return F.adjust(ctx, it, 1) end
  if it.run then
    local p, v = context(it)
    if not p and it.needs ~= "none" then return v end  -- v holds the reason
    local ok, result = pcall(it.run, ctx, p or 0, v or 0, it)
    if not ok then wml.log("feature " .. it.id .. ": " .. tostring(result)); return "Error, see wml.log" end
    return result
  end
end

-- Lists with a `usable` test (poses, actions) keep the indexes usable right
-- now in it.ok, refreshed while the menu is open, so the row can show "3/12"
-- of what your character can actually do.
function F.refresh_usable(ctx)
  local p = G.player()
  if p == 0 then return end
  pcall(F.style_refresh, ctx, p)
  for _, it in pairs(F.items) do
    if it.kind == "list" and it.usable then
      local ok = {}
      for i, entry in ipairs(it.items) do
        local good, use = pcall(it.usable, ctx, p, entry)
        if good and use then ok[#ok + 1] = i end
      end
      it.ok = ok
      -- Sit on a usable entry.
      if #ok > 0 then
        local on = false
        for _, i in ipairs(ok) do if i == it.v then on = true break end end
        if not on then it.v = ok[1] end
      end
    end
  end
end

-- "k/n" for a list row: among the usable entries when known.
function F.list_position(it)
  if it.ok then
    if #it.ok == 0 then return "none available" end
    for k, i in ipairs(it.ok) do if i == it.v then return k .. "/" .. #it.ok end end
    return "?/" .. #it.ok
  end
  return it.v .. "/" .. #it.items
end

-- Text shown for an item's current value.
function F.value_text(it)
  if it.kind == "toggle" then return it.v and "[ON]" or "[OFF]" end
  if it.kind == "value" then
    local shown = it.v
    if it.live and it.read then
      local p = G.player()
      if p ~= 0 or it.needs == "none" then
        local ok, r = pcall(it.read, p)
        if ok and r then shown = r end
      end
    end
    return "< " .. it.fmt(shown) .. " >"
  end
  if it.kind == "choice" then return "< " .. it.options[it.v] .. " >" end
  if it.kind == "list" then return "< " .. it.items[it.v][2] .. " >" end
  return ""
end

function F.status_line()
  local parts = {}
  for _, it in pairs(F.items) do
    if it.kind == "toggle" and it.v and it.id ~= "master" then parts[#parts + 1] = it.label end
  end
  table.sort(parts)
  return (F.enabled and "On: " or "Tweaks OFF. Would be on: ") .. (#parts > 0 and table.concat(parts, ", ") or "nothing")
end

-- (a function of its own: this file is at Lua's 200-locals limit)
;(function()
-- ---------------------------------------------------------------- row order
--
-- In each tab the switches people reach for come first; the sliders, choices
-- and set-up rows follow. Rows missing here keep their place after these.
local ORDER = {
  Emotes = { "poses", "actions", "scene", "stop_pose", "clear_scene", "repeat_action", "repeat_every" },
  Weapons = { "infinite_ammo", "no_reload", "fire", "harder_hits", "one_hit", "rocket_ammo", "fire_ammo", "money_gun", "money_gun_cash", "explosive_punch", "punch_blast",
    "weapon_switch", "aim_style", "aim_camera_page", "fine_aim_zoom", "fine_aim_spread",
    "give_weapon", "all_weapons", "ammo_all" },
  Vehicles = { "veh_god", "veh_repair", "tank", "bulletproof", "never_flat", "no_fling", "car_grip", "nitro_all",
    "spawn_vehicle", "remove_vehicles", "garage", "vehicle_custom", "paint", "paint2", "boom", "max_speed" },
  World = { "weather", "hour", "freeze_clock", "clear", "restore_traffic", "drop", "kill_all", "everybody", "spawn_person",
    "crowd_small", "crowd_big", "remove_people", "cash_rain", "weapon_rain", "cash_drop_chance" },
  Visual = { "hide_hud", "letterbox", "free_cam", "cam_mode", "freeze_world", "filter", "render_mode", "saturation" },
  Teleport = { "places", "tp_stores", "tp_activities", "waypoint_go", "waypoint_auto" },
  Settings = { "master", "status", "settings_controls", "settings_ui_plus", "settings_unlocks", "settings_tweaks" },
}
-- Control preferences, set once, live in Settings rather than with the cheats.
local MOVE_TO = { camera_turn = "Settings", aim_button = "Settings", precise_turning = "Settings",
  precise_aim_turn = "Settings", fine_aim_turn = "Settings", weapon_dpad = "Settings", weapon_tap = "Settings" }
do
  local by_name = {}
  for _, cat in ipairs(F.categories) do by_name[cat.name] = cat end
  for _, cat in ipairs(F.categories) do
    for i = #cat.items, 1, -1 do
      local to = MOVE_TO[cat.items[i].id]
      if to and to ~= cat.name and by_name[to] then
        table.insert(by_name[to].items, table.remove(cat.items, i))
      end
    end
  end
  local settings = by_name.Settings
  if settings then
    local CONTROLS = { "camera_turn", "aim_button", "precise_turning", "precise_aim_turn", "fine_aim_turn", "weapon_dpad", "weapon_tap" }
    local rows, keep, inside = {}, {}, {}
    for _, id in ipairs(CONTROLS) do inside[id] = true end
    for _, it in ipairs(settings.items) do if inside[it.id] then rows[#rows + 1] = it else keep[#keep + 1] = it end end
    table.sort(rows, function(x, y)
      local rx, ry = 0, 0
      for k, id in ipairs(CONTROLS) do if id == x.id then rx = k end if id == y.id then ry = k end end
      return rx < ry
    end)
    local page = { id = "settings_controls", label = "Controls", kind = "page", needs = "none", page_rows = rows,
      help = "Camera turn speed, the aim button, turning while aiming and the weapon switch buttons.",
      open = function() return { title = "Controls", rows = rows } end }
    F.items.settings_controls = page
    keep[#keep + 1] = page
    settings.items = keep
  end
  -- Rows that only matter with something else on are hidden until then.
  local function style_is(n) return function() return not (F.items.aim_style and F.items.aim_style.v == n) end end
  for _, id in ipairs({ "fine_aim_zoom", "fine_aim_spread", "fine_aim_turn" }) do
    if F.items[id] then F.items[id].hidden = style_is(3) end
  end
  if F.items.precise_turning then F.items.precise_turning.hidden = style_is(2) end
  if F.items.precise_aim_turn then F.items.precise_aim_turn.hidden = style_is(2) end
  if F.items.aim_button then
    F.items.aim_button.hidden = function() return not (F.items.aim_style.v == 2 or F.items.aim_style.v == 3) end
  end
  for _, id in ipairs({ "weapon_dpad", "weapon_tap" }) do
    if F.items[id] then F.items[id].hidden = function() return not F.items.weapon_switch.v end end
  end
  -- Precise Aim's camera rows: one Aim camera page in Weapons, then Fine
  -- Aim's rows, all under Aim style.
  local weapons = by_name.Weapons
  if weapons then
    local CAM = { "aim_camera", "aim_zoom", "aim_fov", "aim_height", "aim_shoulder", "aim_reset", "aim_save" }
    local inside, rows, keep = {}, {}, {}
    for _, id in ipairs(CAM) do inside[id] = true end
    local fine = { fine_aim_zoom = true, fine_aim_spread = true }
    local fine_rows = {}
    for _, it in ipairs(weapons.items) do
      if inside[it.id] then rows[#rows + 1] = it elseif fine[it.id] then fine_rows[#fine_rows + 1] = it else keep[#keep + 1] = it end
    end
    local page = { id = "aim_camera_page", label = "Precise Aim camera", kind = "page", needs = "none", page_rows = rows,
      hidden = style_is(2),
      help = "Precise Aim's camera: its style (Saints Row 1 to 2022 or yours), zoom, field of view, height and shoulder.",
      open = function() return { title = "Precise Aim camera", rows = rows } end }
    F.items.aim_camera_page = page
    local at = #keep + 1
    for i, it in ipairs(keep) do if it.id == "aim_style" then at = i + 1 end end
    table.insert(keep, at, page)
    for i, it in ipairs(fine_rows) do table.insert(keep, at + i, it) end
    weapons.items = keep
  end
end
for _, cat in ipairs(F.categories) do
  local want = ORDER[cat.name]
  if want then
    local rank = {}
    for k, id in ipairs(want) do rank[id] = k end
    local rest = {}
    for i, it in ipairs(cat.items) do rest[it] = i end
    table.sort(cat.items, function(a, b)
      local ra, rb = rank[a.id] or (1000 + rest[a]), rank[b.id] or (1000 + rest[b])
      return ra < rb
    end)
  end
end

end)()

return F
