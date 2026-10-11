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
local S = wml.setting

local F = { categories = {}, items = {}, enabled = true, debug = false, spawn_queue = {} }

local read_u8, read_u16, read_u32, read_f32 = wml.read_u8, wml.read_u16, wml.read_u32, wml.read_f32
local write_u8, write_u16, write_u32, write_f32 = wml.write_u8, wml.write_u16, wml.write_u32, wml.write_f32

local function category(name, items)
  F.categories[#F.categories + 1] = { name = name, items = items }
  for _, it in ipairs(items) do
    it.needs = it.needs or "player"
    if it.kind == "toggle" then it.v = it.v == true
    elseif it.kind == "value" then it.v = it.v or it.default
    elseif it.kind == "choice" or it.kind == "list" then it.v = it.v or 1 end
    F.items[it.id] = it
  end
end

local function fmt1(v) return string.format("%.1f", v) end
local function fmt2(v) return string.format("%.2f", v) end
local function fmtint(v) return string.format("%d", v) end
local function fmtx(v) return string.format("x%.1f", v) end

-- Weapon names the game's inventory knows (items_inventory.xtbl).
local WEAPONS = {
  { "pimp_slap", "Fists" }, { "knife", "Knife" }, { "baseball_bat", "Baseball Bat" },
  { "nightstick", "Nightstick" }, { "tire_iron", "Tire Iron" }, { "pimpcane", "Pimp Cane" },
  { "glock", "Vice 9" }, { "beretta", "NR4" }, { "magnum", ".44 Shepherd" },
  { "desert_eagle_gold", "GDHC .50" }, { "tanya_pistol", "Tanya's Pistol" },
  { "mac10", "T3K Urban" }, { "tec9", "GAL 43" }, { "ak47", "AR-40 Xtnd" }, { "m16", "AR-50" },
  { "twelve_gauge", "Tombstone" }, { "pump_action_shotgun", "12 Gauge" }, { "spas12", "AS12 Riot" },
  { "sniper_rifle", "McManus" }, { "rpg_launcher", "RPG" }, { "rpg_laser", "RPG (laser)" },
  { "grenade", "Grenades" }, { "molotov", "Molotovs" }, { "pipe_bomb", "Pipe Bombs" },
  { "40oz", "40 oz" }, { "kabob", "Kabob" },
}

local WEATHER = { "Game's own", "Clear Skies", "Partly Cloudy", "Light Rain", "Medium Rain", "Heavy Rain", "Overcast", "Thunderstorm" }

-- Single-shot script calls are queued and run one per update, so a burst
-- (give every weapon) never stalls a frame.
F.queue = {}
local function enqueue(code) F.queue[#F.queue + 1] = code end

-- ================================================================ Player
category("Player", {
  { id = "god", label = "God mode", kind = "toggle", pbits = G.FLAG.INVULNERABLE,
    help = "The game's own invulnerability flag (the trainer's God Mode)." },
  { id = "heal", label = "Refill health", kind = "action", help = "Sets your health to its maximum once.",
    run = function(ctx, p) write_f32(p + G.P.HEALTH, read_u32(p + G.P.HEALTH_MAX)); return "Health refilled" end },
  { id = "never_wanted", label = "Never wanted", kind = "toggle",
    help = "Holds police and gang notoriety at zero.",
    update = function(ctx, p)
      for _, g in ipairs({ 0, 1, 2, 4 }) do
        local base = p + G.P.NOTORIETY + g * 24
        if read_u32(base) ~= 0 then write_u32(base, 0) end
        write_u32(base + 12, 0)
      end
    end },
  { id = "wanted_police", label = "Police level", kind = "value", default = 0, min = 0, max = 5, step = 1, fmt = fmtint, live = true, oneshot = true,
    help = "Your police notoriety, 0 to 5 stars, set with the game's own setter.",
    read = function(p) return read_u32(p + G.P.NOTORIETY + 4 * 24) end,
    change = function(ctx, p, _, it) F.set_notoriety(ctx, p, 4, it.v) end },
  { id = "wanted_carnales", label = "Los Carnales level", kind = "value", default = 0, min = 0, max = 5, step = 1, fmt = fmtint, live = true, oneshot = true,
    help = "How hard Los Carnales hunt you, 0 to 5.",
    read = function(p) return read_u32(p + G.P.NOTORIETY) end,
    change = function(ctx, p, _, it) F.set_notoriety(ctx, p, 0, it.v) end },
  { id = "wanted_vk", label = "Vice Kings level", kind = "value", default = 0, min = 0, max = 5, step = 1, fmt = fmtint, live = true, oneshot = true,
    help = "How hard the Vice Kings hunt you, 0 to 5.",
    read = function(p) return read_u32(p + G.P.NOTORIETY + 24) end,
    change = function(ctx, p, _, it) F.set_notoriety(ctx, p, 1, it.v) end },
  { id = "wanted_rollerz", label = "Rollerz level", kind = "value", default = 0, min = 0, max = 5, step = 1, fmt = fmtint, live = true, oneshot = true,
    help = "How hard the Westside Rollerz hunt you, 0 to 5.",
    read = function(p) return read_u32(p + G.P.NOTORIETY + 2 * 24) end,
    change = function(ctx, p, _, it) F.set_notoriety(ctx, p, 2, it.v) end },
  { id = "max_wanted", label = "Max notoriety (everyone)", kind = "action",
    run = function(ctx, p) return F.set_notoriety_all(ctx, p, 5) end,
    help = "Cops and every gang to level 5, lifting any mission cap." },
  { id = "no_cops", label = "No cops", kind = "toggle", needs = "none", byte = { G.VAR.ALLOW_COPS, 0, 1 },
    help = "Stops ambient police spawning (the No Cops cheat)." },
  { id = "no_gangs", label = "No gangs", kind = "toggle", needs = "none", byte = { G.VAR.ALLOW_GANGS, 0, 1 },
    help = "Stops ambient gang members spawning (the No Gangs cheat)." },
  { id = "no_bust", label = "Never busted", kind = "toggle", needs = "none", byte = { G.VAR.ALLOW_BUST, 0, 1 },
    help = "Police cannot arrest you." },
  { id = "no_ragdoll", label = "No ragdoll", kind = "toggle", pbits = G.FLAG.NO_RAGDOLL | G.FLAG.NO_FLINCH, p212 = G.FLAG212.NO_EXPLOSION_FLING | G.FLAG212.NO_KNEECAP,
    help = "No knockdowns, flinching, explosion flings or kneecapping." },
  { id = "perfect_aim", label = "Perfect aim", kind = "toggle", pbits = G.FLAG.PERFECT_AIM,
    help = "The game's perfect-aim flag: no spread, every shot lands where you point." },
  { id = "run", label = "Run boost", kind = "toggle", v = S("run_boost", false),
    help = "Run and sprint faster, by the Run speed below. Can make running stutter." },
  { id = "run_speed", label = "Run speed", kind = "value", default = 1.0, min = 1, max = 6, step = 0.25, fmt = fmtx, oneshot = true,
    v = S("run_speed_multiplier", 1.5), help = "How much faster you run with Run boost on (x1 = the game's speed)." },
  { id = "jump", label = "High jump", kind = "toggle", v = true, help = "Jump higher, by the Jump boost below." },
  { id = "jump_boost", label = "Jump boost", kind = "value", default = 1.0, min = 1, max = 10, step = 0.5, fmt = fmtx, oneshot = true,
    v = S("jump_multiplier", 4.0), help = "How much higher you jump with High jump on (x1 = the game's jump)." },
  { id = "landing", label = "Soft landing", kind = "toggle", v = true, help = "No fall damage, stumble or ragdoll from any height." },
  { id = "jump_height", label = "Jump height (game)", kind = "value", needs = "none", default = 0.85, min = 0.2, max = 6, step = 0.1, fmt = fmt2, float = G.VAR.JUMP_HEIGHT,
    help = "The engine's own jump height constant. Combine with High jump or use alone." },
  { id = "swim_speed", label = "Swim speed", kind = "value", needs = "none", default = 4.5, min = 1, max = 40, step = 0.5, fmt = fmt1, float = G.VAR.SWIM_SPEED,
    help = "The engine's swimming speed, in metres per second." },
  { id = "fall_damage", label = "Fall damage", kind = "value", needs = "none", default = 0.2, min = 0, max = 1, step = 0.05, fmt = fmt2, float = G.VAR.FALL_DAMAGE,
    help = "Share of your health a hard landing takes; 0 = none." },
  { id = "sprint", label = "Infinite sprint", kind = "toggle", needs = "none", bits = { G.VAR.CHEAT_FLAGS, 0x02000000 },
    help = "Experimental: the Infinite Sprint cheat's flag." },
  { id = "money", label = "Money +$100,000", kind = "action", help = "Adds $100,000 to your cash, up to the game's limit.",
    run = function(ctx, p)
      local cents = read_u32(p + G.P.CASH)
      if cents >= 0x80000000 then cents = cents - 0x100000000 end
      cents = math.min(2000000000, math.max(0, cents + 10000000))
      write_u32(p + G.P.CASH, cents)
      return "Added $100,000"
    end },
  { id = "respect", label = "Max respect", kind = "action", help = "Fills respect to 99 bars, so every mission is open.",
    run = function(ctx, p) write_u32(p + G.P.RESPECT, read_u32(p + G.P.RESPECT_BAR) * 99); return "Respect maxed" end },
})

-- ================================================================ Weapons
category("Weapons", {
  { id = "infinite_ammo", label = "Infinite ammo", kind = "toggle", needs = "none", byte = { G.VAR.UNLIMITED_AMMO, 1, 0 },
    help = "Reserve never runs out (reloads still happen)." },
  { id = "no_reload", label = "No reload", kind = "toggle",
    help = "Keeps the magazine of the gun in your hands full, so it never reloads.",
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
  { id = "fire", label = "Auto fire", kind = "toggle", v = true, help = "Single-shot guns keep firing while the trigger is held." },
  { id = "one_hit", label = "One-hit kill", kind = "toggle", help = "Any hit from you kills a person outright. Experimental." },
  { id = "give_weapon", label = "Give weapon", kind = "list", items = WEAPONS, help = "Left/Right to pick a weapon, Enter to put it in your hands.",
    run = function(ctx, p, _, it)
      local w = WEAPONS[it.v]
      G.script(ctx, string.format('inv_item_add("%s")', w[1]))
      return "Given: " .. w[2]
    end },
  { id = "all_weapons", label = "Give every weapon", kind = "action", help = "One of each, one per update; slot limits apply.",
    run = function(ctx, p)
      for _, w in ipairs(WEAPONS) do enqueue(string.format('inv_item_add("%s")', w[1])) end
      return "Giving every weapon..."
    end },
  { id = "ammo_all", label = "Refill all ammo", kind = "action", help = "Fills the magazine and reserve of every weapon you carry.",
    run = function(ctx, p)
      G.script(ctx, 'local t = { inv_item_get_all_do("#PLAYER#") } for i = 1, table.getn(t) do if type(t[i]) == "string" then pcall(inv_item_add_ammo, 9999, t[i], "#PLAYER#") end end')
      return "Ammo refilled"
    end },
})

-- ================================================================ Vehicles
category("Vehicles", {
  { id = "veh_god", label = "Vehicle god mode", kind = "toggle", needs = "vehicle", vbits_a = G.VFLAG_A.INVULNERABLE,
    update = function(ctx, p, v) write_u32(v + G.V.HP, read_u32(v + G.V.HP_MAX)) end,
    help = "Your car can't be damaged and stays at full health." },
  { id = "veh_repair", label = "Repair now", kind = "action", needs = "vehicle", help = "Fixes every dent, tyre and smoke on the car you are in.",
    run = function(ctx, p, v) G.call(ctx, G.VEHICLE_REPAIR, { v }, 1.0); return "Repaired" end },
  { id = "tank", label = "Tank mode", kind = "toggle", needs = "vehicle", vbits_b = G.VFLAG_B.INFINITE_MASS, v = S("vehicle_tank", true),
    help = "Your car is immovable in collisions; others bounce off." },
  { id = "bulletproof", label = "Bulletproof glass", kind = "toggle", needs = "vehicle", vbits_b = G.VFLAG_B.BULLETPROOF_GLASS,
    help = "Bullets no longer come through the windows of your car." },
  { id = "never_flat", label = "Never flat tyres", kind = "toggle", needs = "vehicle", vbits_b = G.VFLAG_B.NEVER_FLAT,
    help = "Your tyres cannot be shot out." },
  { id = "no_fling", label = "No explosion fling", kind = "toggle", needs = "vehicle", vbits_a = G.VFLAG_A.NO_EXPLOSION_FLING,
    help = "Explosions no longer throw your car around." },
  { id = "torque", label = "Nitrous strength", kind = "value", needs = "vehicle", default = 1.0, min = 0.5, max = 10, step = 0.25, fmt = fmtx,
    v = S("player_torque_multiplier", 1.5),
    help = "How hard nitrous (Shift) pushes your car. Only acts while boosting.",
    update = function(ctx, p, v, it)
      local e = G.engine_object(v)
      if e then write_f32(e + G.ENGINE.NITRO_STRENGTH, it.v) end
    end,
    off = function(ctx, p, v)
      local e = v ~= 0 and G.engine_object(v)
      if e then write_f32(e + G.ENGINE.NITRO_STRENGTH, 1.0) end
    end },
  { id = "max_speed", label = "Extra top speed (mph)", kind = "value", needs = "vehicle", default = 0, min = 0, max = 300, step = 10, fmt = fmtint,
    help = "Raises your car's speed cap by this much; the engine still has to get you there. Experimental.",
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
  { id = "boom", label = "Blow up my car", kind = "action", needs = "vehicle", help = "Detonates the car you are in. Get out first, or don't.",
    run = function(ctx) G.console(ctx, "boom"); return "Boom" end },
  { id = "spawn_vehicle", label = "Spawn vehicle here", kind = "list", items = VEHICLES, needs = "player",
    help = "Left/Right to pick any of the game's vehicles, Enter to drop it in front of you. Experimental.",
    run = function(ctx, p, _, it)
      local veh = VEHICLES[it.v]
      return F.spawn_vehicle(ctx, p, veh[1]) and ("Spawned " .. veh[2]) or ("Could not spawn " .. veh[2])
    end },
  { id = "remove_vehicles", label = "Remove spawned vehicles", kind = "action", needs = "player", help = "Removes every vehicle this menu spawned.",
    run = function(ctx) return F.remove_spawned(ctx, F.spawned_vehicles, "vehicle") end },
  { id = "garage", label = "Deliver to garage", kind = "list", items = VEHICLES, needs = "player",
    help = "Any vehicle in the game, hidden ones too, delivered to your garage.",
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
  { id = "weather", label = "Weather", kind = "choice", needs = "none", options = WEATHER, help = "Forces a weather stage; Game's own lets the weather change again.",
    change = function(ctx, p, _, it) G.script(ctx, string.format("set_weather(%d, true)", it.v - 2)) end },
  { id = "hour", label = "Time of day (hour)", kind = "value", needs = "none", default = 12, min = 0, max = 23, step = 1, fmt = fmtint, live = true, oneshot = true,
    help = "Sets the clock to that hour; the day goes on from there.",
    read = function() return read_u8(G.VAR.CLOCK_HOUR) end,
    change = function(ctx, p, _, it) G.script(ctx, string.format("set_time_of_day(%d, 0)", it.v)) end },
  { id = "freeze_clock", label = "Freeze the clock", kind = "toggle", needs = "none", help = "Stops the day/night cycle where it is.",
    update = function(ctx, p, v, it)
      local rate = read_f32(G.VAR.CLOCK_RATE)
      if rate ~= 0 then it.saved = rate; write_f32(G.VAR.CLOCK_RATE, 0) end
    end,
    off = function(ctx, p, v, it) write_f32(G.VAR.CLOCK_RATE, it.saved or 40) end },
  { id = "clear", label = "Clear traffic and peds", kind = "action", needs = "none", help = "Removes every ambient car and person at once.",
    run = function(ctx) G.script(ctx, "spawning_remove_all()"); return "Cleared" end },
  { id = "drop", label = "Everybody drop!", kind = "action", needs = "player", help = "Every person in the city falls over for a minute.",
    run = function(ctx) G.console(ctx, "super_ragdoll"); return "Everybody drop!" end },
  { id = "crowd_small", label = "Spawn 10 random people", kind = "action", needs = "player", help = "Ten random civilians appear around you, one per update. Experimental.",
    run = function(ctx) F.queue_crowd(10); return "Here they come" end },
  { id = "crowd_big", label = "Spawn a crowd (40)", kind = "action", needs = "player", help = "Forty random civilians; the oldest spawned people make room when the game's pool fills. Experimental.",
    run = function(ctx) F.queue_crowd(40); return "A crowd is forming" end },
  { id = "remove_people", label = "Remove spawned people", kind = "action", needs = "player", help = "Removes every person this menu spawned.",
    run = function(ctx) return F.remove_spawned(ctx, F.spawned_people, "person") end },
})

-- ================================================================ Visual
category("Visual", {
  { id = "hide_hud", label = "Hide HUD", kind = "toggle", needs = "player", help = "Hides the map, health and ammo for screenshots.",
    change = function(ctx, p, v, it) G.script(ctx, it.v and "hud_hide()" or "hud_show()") end,
    off = function(ctx) G.script(ctx, "hud_show()") end },
  { id = "saturation", label = "Saturation", kind = "value", needs = "none", default = 1.0, min = 0, max = 2, step = 0.1, fmt = fmt1, float = G.VAR.SATURATION,
    help = "Colour strength of the picture: 0 = black and white, 2 = vivid." },
  { id = "letterbox", label = "Letterbox", kind = "toggle", needs = "player", help = "Black bars top and bottom, as in cutscenes.",
    change = function(ctx, p, v, it) G.call(ctx, G.LETTERBOX, { it.v and 1 or 0 }) end,
    off = function(ctx) G.call(ctx, G.LETTERBOX, { 0 }) end },
  { id = "wireframe", label = "Wireframe world", kind = "toggle", needs = "player", help = "Draws the world as lines (the renderer's debug mode).",
    change = function(ctx, p, v, it) G.console(ctx, it.v and "R_wireframe on" or "R_wireframe off") end,
    off = function(ctx) G.console(ctx, "R_wireframe off") end },
})

-- ================================================================ Teleport
--
-- Spots from the game's own level files (navpoint positions), so the height
-- is right. { key, name, area, x, y, z }.
local PLACES = {
  { "church",     "Saints Row church",          "Saints Row",   -732.0,  -2.1,    81.7 },
  { "sr_crib",    "Saints Row crib",            "Saints Row",   -636.6,  -4.0,  -155.4 },
  { "pent_door",  "Penthouse crib (street)",    "Downtown",     -869.5,  22.1, -1249.4 },
  { "penthouse",  "Penthouse crib (top)",       "Downtown",     -879.0, 160.1, -1262.8 },
  { "bar_crib",   "Barrio crib (bar)",          "Barrio",        466.2,   1.7,   937.4 },
  { "sub_crib",   "Suburbs crib",               "Suburbs",       332.7,  34.1, -2134.1 },
  { "downtown",   "Downtown",                   "Downtown",     -681.9,  15.0,  -877.6 },
  { "dt_ramp",    "Downtown rooftop ramp",      "Downtown",       78.3,  43.6, -1233.5 },
  { "chopshop",   "Downtown chop shop",         "Downtown",       30.4,  21.1, -1309.3 },
  { "highend",    "High End Retail",            "Downtown",     -304.6,  29.9, -1417.9 },
  { "museum",     "Museum",                     "Downtown",     -788.6,  24.1, -1383.3 },
  { "redlight",   "Red Light district",         "Red Light",      47.6,  -4.0,   -27.8 },
  { "projects",   "Projects lofts",             "Projects",      388.1,  -3.9,  -314.7 },
  { "chinatown",  "Chinatown",                  "Chinatown",     440.2,  -3.8,   696.0 },
  { "apts",       "Apartments",                 "Apartments",    764.7,  55.6,   454.2 },
  { "hospital",   "Barrio hospital",            "Barrio",        200.7,  -4.0,   736.7 },
  { "police",     "Barrio police station",      "Barrio",        121.2,  -4.0,   964.2 },
  { "airport",    "Airport",                    "Airport",       322.5,  -3.8,  1213.3 },
  { "factory",    "Factory",                    "Factory",      -729.4,  18.7,   727.8 },
  { "truckyard",  "Truck yard",                 "Truck yard",   -121.6,  27.0,   352.9 },
  { "docks",      "Docks pen",                  "Docks",       -1159.7,  -2.7,  1408.7 },
}
F.PLACES = PLACES

-- Moves the player (and their car and homies) to a spot with the game's own
-- script teleport, after telling the world to load there.
function F.teleport_to(ctx, p, x, y, z)
  local pos = G.floats(ctx, { x, y + 0.5, z, 0 }, 0)
  local rows = G.floats(ctx, {}, 16)
  for i = 0, 32, 4 do write_u32(rows + i, read_u32(p + 32 + i)) end  -- keep the facing
  G.call(ctx, G.STREAM_AT, { pos, 0, 0 })
  G.call(ctx, G.PLAYER_TELEPORT, { p, pos, rows })
  write_f32(p + G.P.FALL_START, x); write_f32(p + G.P.FALL_START + 4, y + 0.5); write_f32(p + G.P.FALL_START + 8, z)
end

category("Teleport", {
  { id = "places", label = "Go to a place", kind = "list", items = PLACES,
    help = "Enter opens the list; pick a spot and you, your car and your homies are there.",
    run = function(ctx, p, _, it)
      local pl = PLACES[it.v]
      F.teleport_to(ctx, p, pl[4], pl[5], pl[6])
      return "Teleported to " .. pl[2]
    end },
})

-- ================================================================ Settings
category("Settings", {
  { id = "master", label = "All tweaks", kind = "toggle", needs = "none", v = true, help = "Master switch for every runtime tweak." },
  { id = "status", label = "Show what is on", kind = "action", needs = "none", help = "Lists every feature that is switched on.",
    run = function() return F.status_line() end },
})

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
    wml.log(string.format("police notoriety: level %d min %d max %d points %.1f decay %d; cops allowed %d, team no-spawn %d",
      read_u32(n), read_u32(n + 4), read_u32(n + 8), read_f32(n + 12), read_u32(n + 16) & 0xFFFFFFFF,
      read_u8(G.VAR.ALLOW_COPS), read_u8(G.POLICE_TEAM + 645)))
  end
  if p ~= 0 then
    -- Player bits: set the wanted ones, clear the ones we manage but no
    -- longer want. The soft-landing shield in main.lua manages the
    -- invulnerability bit on its own while falling.
    local managed = G.FLAG.PERFECT_AIM | G.FLAG.NO_RAGDOLL | G.FLAG.NO_FLINCH
    if F.items.god.v and F.enabled then managed = managed | G.FLAG.INVULNERABLE end
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
  if #F.spawn_queue > 0 and p ~= 0 and G.playing(p) then F.spawn_person(ctx, p, table.remove(F.spawn_queue, 1)) end
end

-- ------------------------------------------------------------- no reload
--
-- The game starts a reload through one function (from an empty magazine,
-- the reload button or an idle top-up). While No reload is on, the player's
-- magazine is filled instead and the reload never starts.
wml.hook(G.RELOAD, function(ctx)
  local human = ctx:r(3) & 0xFFFFFFFF
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

local function destroy(ctx, handle)
  if handle_alive(handle) then G.call(ctx, G.OBJECT_DESTROY, { handle }) end
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
local function spot_ahead(p, dist, lift)
  local x, y, z = G.vec(p + G.P.POS)
  local fx, fz = read_f32(G.CAMERA + 104), read_f32(G.CAMERA + 112)
  local len = math.sqrt(fx * fx + fz * fz)
  if len < 0.01 then fx, fz, len = 0, 1, 1 end
  return x + fx / len * dist, y + lift, z + fz / len * dist
end

-- Drops a vehicle in front of the player: the co-op mod's create, stream,
-- place sequence.
function F.spawn_vehicle(ctx, p, name)
  local index = G.call(ctx, G.VEHICLE_INDEX, { G.cstr(ctx, name, 0) })
  if index == 0xFFFFFFFF then return false end
  make_room(ctx, F.spawned_vehicles, MAX_SPAWNED_VEHICLES)
  local x, y, z = spot_ahead(p, 7, 1.0)
  local pos = G.floats(ctx, { x, y, z, 0 }, 0)
  local rows = G.floats(ctx, { 1, 0, 0, 0, 1, 0, 0, 0, 1 }, 16)
  local handle = G.call(ctx, G.VEHICLE_CREATE, { 3, 2, index, pos, rows, 0, 0, 0 }, 0.0,
    { { 84, 4, 0 }, { 95, 1, 0 }, { 100, 4, 0 } })
  if handle == 0 then if F.debug then wml.log("spawn vehicle: the game's pool of vehicles is full") end return false end
  local vehicle = G.call(ctx, G.VEHICLE_FROM_HANDLE, { handle })
  if not G.pointer_ok(vehicle) then return false end
  local id = read_u32(G.VEHICLE_INFO_TABLE + index * G.VEHICLE_INFO_SIZE)
  G.call(ctx, G.STREAM_REF, { G.STREAM_TABLE + (id >> 24) * 204, id, 5, 0, 1 })
  G.call(ctx, G.VEHICLE_PLACE, { vehicle, pos, rows, 0 })
  F.spawned_vehicles[#F.spawned_vehicles + 1] = handle
  if F.debug then wml.log(string.format("spawn vehicle: %s index %d handle %08X at %.1f %.1f %.1f", name, index, handle, x, y, z)) end
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
  local desc = read_u32(obj + G.HUMAN_DEF)
  if G.pointer_ok(desc) then
    local id = read_u32(desc + 608)
    G.call(ctx, G.STREAM_REF, { G.STREAM_TABLE + (id >> 24) * 204, id, 5, 0, 1 })
  end
  F.spawned_people[#F.spawned_people + 1] = read_u32(obj + 68)
  if F.debug then wml.log(string.format("spawn: %s at %.1f %.1f %.1f (%d kept)", name, x, y, z, #F.spawned_people)) end
end

-- God mode's bit must be released when switched off; the loop above only
-- clears bits it manages, so register god's release explicitly.
F.items.god.off = function(ctx, p) if p ~= 0 then G.player_flag(p, G.FLAG.INVULNERABLE, false) end end

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
  if it.change and p then it.change(ctx, p, v, it) end
  return it.label .. (it.v and " on" or " off")
end

function F.adjust(ctx, it, dir, fast)
  if it.kind == "value" then
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
    local n = #it.items
    it.v = ((it.v - 1 + dir) % n) + 1
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
  for _, cat in ipairs(F.categories) do
    for _, it in ipairs(cat.items) do
      if it.kind == "toggle" and it.v and it.id ~= "master" then parts[#parts + 1] = it.label end
    end
  end
  return (F.enabled and "On: " or "Tweaks OFF. Would be on: ") .. (#parts > 0 and table.concat(parts, ", ") or "nothing")
end

return F
