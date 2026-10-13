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
-- Alphabetical by the name shown in the menu.
table.sort(VEHICLES, function(a, b) return a[2]:lower() < b[2]:lower() end)
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
  { "TS_X_F_Thug-01",    "Saints thug (her)",  "tec9" },
  { "TS_A_M_JohnnyGat",  "Johnny Gat",         "desert_eagle_gold" },
  { "TS_W_M_Troy-01",    "Troy",               "glock" },
  { "TS_B_M_Dex-01",     "Dex",                "beretta" },
  { "TS_B_M_Julius",     "Julius",             "magnum" },
  { "lw_w_m_swat01",     "SWAT officer",       "m16" },
  { "LW_X_M_Officer_01", "Police officer",     "glock" },
  { "PD_B_M_Bouncer-01", "Bouncer",            "baseball_bat" },
}
F.BODYGUARDS = BODYGUARDS

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

-- Weapons, given the way the game's own weapon cheats give them (the
-- routine the trainer uses): these are the weapons those cheats hand out.
-- Alphabetical by the name shown.
local WEAPONS = {
  { "rpg_launcher", "RPG" }, { "ak47", "AR-40 Xtnd" }, { "m16", "AR-50" }, { "spas12", "AS12 Riot" },
  { "baseball_bat", "Baseball Bat" }, { "desert eagle", "GDHC .50" }, { "tec9", "GAL 43" }, { "grenade", "Grenades" },
  { "knife", "Knife" }, { "sniper_rifle", "McManus" }, { "molotov", "Molotovs" }, { "nightstick", "Nightstick" },
  { "beretta", "NR4" }, { "pimpcane", "Pimp Cane" }, { "pipe_bomb", "Pipe Bombs" }, { "magnum", "Shepherd .44" },
  { "mac10", "T3K Urban" }, { "tire_iron", "Tire Iron" }, { "twelve_gauge", "Tombstone" }, { "glock", "Vice 9" },
  { "pump_action_shotgun", "12 Gauge" },
}
table.sort(WEAPONS, function(a, b) return a[2]:lower() < b[2]:lower() end)
F_WEAPON_QUEUE = {}

local WEATHER = { "Game's own", "Clear Skies", "Partly Cloudy", "Light Rain", "Medium Rain", "Heavy Rain", "Overcast", "Thunderstorm" }

-- Single-shot script calls are queued and run one per update, so a burst
-- (give every weapon) never stalls a frame.
F.queue = {}
local function enqueue(code) F.queue[#F.queue + 1] = code end

-- ================================================================ Player
category("Player", {
  { id = "god", label = "God mode", kind = "toggle", pbits = G.FLAG.INVULNERABLE,
    help = "The game's own invulnerability flag (the trainer's God Mode).",
    -- The update only manages the bit while god mode is on (the landing and
    -- teleport shields use it too), so switching off clears it here.
    off = function(ctx, p) if p and p ~= 0 then G.player_flag(p, G.FLAG.INVULNERABLE, false) end end },
  { id = "health_mult", label = "Health multiplier", kind = "value", default = 1, min = 1, max = 10, step = 0.5, fmt = fmtx,
    help = "Your maximum health times this: x2 double, x3 triple. Your health bar keeps its share.",
    update = function(ctx, p, v, it) F.scale_health(p, it.v) end,
    off = function(ctx, p) F.scale_health(p, 1) end },
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
  { id = "homies", label = "Homie limit", kind = "value", needs = "none", default = 0, min = 0, max = 10, step = 1,
    v = S("homie_limit", 0), fmt = function(v) return v == 0 and "Game's own" or string.format("%d", v) end,
    help = "How many homies can follow you, 1 to 10 (the game gives 1 to 3 as you take the city). Needs recruiting unlocked." },
  { id = "bodyguard", label = "Spawn bodyguard", kind = "list", items = BODYGUARDS,
    help = "Left/Right to pick, Enter to spawn them armed at your side. They follow and fight as homies (10 at most).",
    run = function(ctx, p, _, it)
      local g = BODYGUARDS[it.v]
      if read_u32(p + G.PARTY_COUNT) + #F.guard_queue >= 10 then return "Your party is full (10)" end
      F.guard_queue[#F.guard_queue + 1] = g
      return "Bodyguard on the way: " .. g[2]
    end },
  { id = "bodyguard_squad", label = "Bodyguard squad (4)", kind = "action",
    help = "Four armed Saints at your side at once.",
    run = function(ctx, p)
      local room = 10 - read_u32(p + G.PARTY_COUNT) - #F.guard_queue
      if room <= 0 then return "Your party is full (10)" end
      for i = 1, math.min(4, room) do F.guard_queue[#F.guard_queue + 1] = BODYGUARDS[i] end
      return string.format("%d bodyguards on the way", math.min(4, room))
    end },
  { id = "dismiss_homies", label = "Dismiss all homies", kind = "action",
    help = "Sends every homie following you home, as holding recruit does.",
    run = function(ctx, p)
      local n = HOMIES.count(p)
      if n == 0 then return "No homies are following you" end
      G.call(ctx, HOMIES.DISMISS_ALL, { p })
      return string.format("Dismissed %d homie%s", n, n == 1 and "" or "s")
    end },
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
  { id = "jump", label = "High jump", kind = "toggle", v = S("high_jump", false), help = "Jump higher, by the Jump boost below." },
  { id = "jump_boost", label = "Jump boost", kind = "value", default = 1.0, min = 1, max = 10, step = 0.5, fmt = fmtx, oneshot = true,
    v = S("jump_multiplier", 4.0), help = "How much higher you jump with High jump on (x1 = the game's jump)." },
  { id = "landing", label = "Soft landing", kind = "toggle", v = S("soft_landing", false), needs = "none",
    help = "No fall damage, stumble, ragdoll or flailing from any height.",
    -- No flailing: the panic-fall speed raised for everyone while on.
    update = function() F.hold_float(G.PANIC_FALL, 100) end,
    off = function() F.release_float(G.PANIC_FALL) end },
  { id = "quick_crouch", label = "Quick crouch", kind = "toggle", needs = "none", help = "You drop into a crouch almost at once.",
    update = function()
      F.hold_float(G.CROUCH_ACCEL, 9); F.hold_float(G.CROUCH_DAMPING, 0.75)
    end,
    off = function() F.release_float(G.CROUCH_ACCEL); F.release_float(G.CROUCH_DAMPING) end },
  { id = "jump_height", label = "Jump height (game)", kind = "value", needs = "none", default = 0.85, min = 0.2, max = 6, step = 0.1, fmt = fmt2, float = G.VAR.JUMP_HEIGHT,
    help = "The engine's own jump height constant. Combine with High jump or use alone." },
  { id = "swim_speed", label = "Swim speed", kind = "value", needs = "none", default = 4.5, min = 1, max = 40, step = 0.5, fmt = fmt1, float = G.VAR.SWIM_SPEED,
    help = "The engine's swimming speed, in metres per second." },
  { id = "fall_damage", label = "Fall damage", kind = "value", needs = "none", default = 0.2, min = 0, max = 1, step = 0.05, fmt = fmt2, float = G.VAR.FALL_DAMAGE,
    help = "Share of your health a hard landing takes; 0 = none." },
  { id = "sprint", label = "Infinite sprint", kind = "toggle", needs = "none", bits = { G.VAR.CHEAT_FLAGS, 0x02000000 },
    help = "Experimental: the Infinite Sprint cheat's flag." },
  { id = "money", label = "Money +$50,000", kind = "action", help = "Adds $50,000 to your cash each press, up to the game's limit.",
    run = function(ctx, p)
      local cents = read_u32(p + G.P.CASH)
      if cents >= 0x80000000 then cents = cents - 0x100000000 end
      cents = math.min(2000000000, math.max(0, cents + 5000000))
      write_u32(p + G.P.CASH, cents)
      return "Added $50,000"
    end },
  { id = "respect", label = "Respect +5,000", kind = "action",
    help = "Adds 5,000 respect each press, enough for a mission or two, up to the game's 99 bars.",
    run = function(ctx, p)
      local most = read_u32(p + G.P.RESPECT_BAR) * 99
      local now = read_u32(p + G.P.RESPECT)
      if now >= 0x80000000 then now = 0 end
      write_u32(p + G.P.RESPECT, math.min(most, now + 5000))
      return "Added 5,000 respect"
    end },
})

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
local function file(name) return { file = name } end

local POSES = {
  { "dance b", "Dance 2" }, { "dance c", "Dance 3" }, { "dance d", "Dance 4" },
  { "react cheer", "Cheer" }, { "surrender", "Hands up" },
  { "blunt smoking", "Smoke a blunt" }, { "forty drinking", "Drink a forty" }, { "Beer Stand", "Beer" },
  { "magazine stand", "Read a magazine" }, { file("PML1_BS_RdPpr"), "Read the paper" }, { "cell stand", "On the phone" },
  { "Lounge", "Lounge" }, { "Lean", "Lean" }, { "car lean", "Lean on a car" }, { "sitting", "Sit" },
  { "Barstool sit", "Barstool" }, { "sleep", "Sleep" }, { "drunk stand", "Drunk" },
  { file("pml1_pc_sd"), "Preach" }, { "Warm Hands", "Warm hands" }, { "pose", "Pose" }, { "zombie eat", "Zombie eat" },
  { "mourn", "Mourn" }, { "cower stand", "Cower" }, { "Jackhammer", "Jackhammer" }, { "pant", "Out of breath" },
  { "tour Take Pictures", "Take pictures" }, { "eating", "Eat" }, { "drug", "Get high" },
}
-- Actions: the game's own action names (its list of 640).
local ACTIONS = {
  { "flip off", "Flip off" }, { "compliment", "Compliment" }, { "react wave", "Wave" }, { "Taunt 1", "Taunt 1" },
  { "Taunt 2", "Taunt 2" }, { "Taunt 3", "Taunt 3" }, { "interaction gang sign stand 1", "Gang sign 1" },
  { "interaction gang sign stand 2", "Gang sign 2" }, { "interaction gang sign stand 3", "Gang sign 3" },
  { "interaction gang sign stand 4", "Gang sign 4" }, { "talk yell", "Yell" }, { "call backup", "Call backup" },
  { "idle adjustCrotch", "Adjust crotch" }, { "drunk vomit", "Vomit" }, { "stand vomit", "Throw up" },
  { "drunk beg", "Beg" }, { "cower Pray", "Pray" }, { "breakdancer poplock", "Pop and lock" },
  { "breakdancer backspin", "Backspin" }, { "pole dance a", "Pole move 1" }, { "pole dance b", "Pole move 2" },
  { "stage dance a", "Stage move 1" }, { "stage dance b", "Stage move 2" }, { "smoke action", "Smoke" },
  { "drink action", "Drink" }, { "powerup liquor", "Take a swig" }, { "Beer Drink", "Sip a beer" },
  { "unique Pimp Slap", "Pimp slap" },
}

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
  { id = "pose", label = "Pose", kind = "list", items = POSES,
    usable = function(ctx, p, pose) return F.can_play(ctx, p, pose[1]) end,
    help = "Left/Right to pick (only poses your character has), Enter to strike it. RB + D-pad Up (Shift + Up) stops it.",
    run = function(ctx, p, _, it)
      if G.vehicle_object(p) then return "Get out of the vehicle first" end
      local pose = POSES[it.v]
      F.save_player_state(p)
      local tok, why = F.start_anim(ctx, p, pose[1])
      if not tok then return why end
      F.posing = { tok = tok, x = read_f32(p + G.P.POS), z = read_f32(p + G.P.POS + 8) }
      return "Pose: " .. pose[2]
    end },
  { id = "stop_pose", label = "Stop posing", kind = "action", needs = "player",
    help = "Ends any pose or repeating action and gives you your controls back. RB + D-pad Up does too.",
    run = function(ctx, p) return F.stop_pose(ctx, p) end },
  { id = "scene", label = "Stage a scene", kind = "list", items = SCENES,
    help = "Left/Right to pick, Enter: the people appear in front of you, each doing their part.",
    run = function(ctx, p, _, it) return F.stage_scene(p, SCENES[it.v]) end },
  { id = "clear_scene", label = "Clear scene", kind = "action",
    help = "Removes everyone the scenes spawned.",
    run = function(ctx) return F.clear_scene(ctx) end },
  { id = "action", label = "Action", kind = "list", items = ACTIONS,
    usable = function(ctx, p, a) return F.can_act(ctx, p, a[1]) end,
    help = "Left/Right to pick (only moves your character has), Enter to do it, once or on repeat.",
    run = function(ctx, p, _, it)
      if G.vehicle_object(p) then return "Get out of the vehicle first" end
      local a = ACTIONS[it.v]
      F.posing = nil
      local ok, why = F.play_action(ctx, p, a[1])
      F.repeating = (ok and F.on("repeat_action")) and { name = a[1], next = F.tick + math.floor(F.items.repeat_every.v * 50),
        x = read_f32(p + G.P.POS), z = read_f32(p + G.P.POS + 8) } or nil
      F.release_at = ok and F.tick + math.floor(math.max(F.items.repeat_every.v, 3) * 50) or nil
      return ok and (a[2] .. (F.on("repeat_action") and " (repeating; move to stop)" or "")) or why
    end },
  { id = "repeat_action", label = "Repeat action", kind = "toggle",
    help = "Plays the last action over and over, handy for recording. RB + D-pad Up (Shift + Up) stops it." },
  { id = "repeat_every", label = "Repeat every (s)", kind = "value", needs = "none", default = 3, min = 1, max = 15, step = 0.5,
    fmt = fmt1, oneshot = true, help = "Seconds between repeats; longer actions want more." },

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
  { id = "fire", label = "Rapid fire", kind = "toggle", needs = "none", v = S("auto_fire", false),
    help = "Your guns fire twice as fast, shotguns four times. Single-shot guns keep firing while you hold the trigger.",
    update = function() F.faster_guns(true) end,
    off = function() F.faster_guns(false) end },
  { id = "harder_hits", label = "Harder hits", kind = "toggle", needs = "none",
    help = "People you kill with a gun fly three times further.",
    update = function() F.harder_hits(true) end,
    off = function() F.harder_hits(false) end },
  { id = "one_hit", label = "One-hit kill", kind = "toggle", help = "Any hit from you kills a person outright. Experimental." },
  { id = "rocket_ammo", label = "Rocket ammo", kind = "toggle",
    help = "Your guns fire real RPG rockets at their own fire rate (one per shot). Careful up close: the blast hurts you too.",
    off = function() F.restore_guns() end },
  { id = "fire_ammo", label = "Fire ammo", kind = "toggle",
    help = "People you shoot catch fire. The game burns at most four people at once." },
  { id = "give_weapon", label = "Give weapon", kind = "list", items = WEAPONS,
    help = "Left/Right to pick, Enter to get it with 500 rounds, the way the game's cheats give it.",
    run = function(ctx, p, _, it)
      local w = WEAPONS[it.v]
      F.give_weapon(ctx, w[1])
      return "Given: " .. w[2]
    end },
  { id = "all_weapons", label = "Give every weapon", kind = "action", help = "One of each, one per update; the game's slot limits apply.",
    run = function(ctx, p)
      for _, w in ipairs(WEAPONS) do F_WEAPON_QUEUE[#F_WEAPON_QUEUE + 1] = w[1] end
      return "Giving every weapon..."
    end },
  { id = "ammo_all", label = "Refill all ammo", kind = "action", help = "Fills the magazine and reserve of every gun you carry.",
    run = function(ctx, p)
      local n = F.refill_all(p)
      return n > 0 and string.format("Ammo refilled (%d gun%s)", n, n == 1 and "" or "s") or "No guns to refill"
    end },
})

-- ================================================================ Vehicles
category("Vehicles", {
  { id = "veh_god", label = "Vehicle god mode", kind = "toggle", needs = "vehicle", vbits_a = G.VFLAG_A.INVULNERABLE,
    help = "Your car stays whole: no damage from crashes, gunfire or explosions, no parts falling off.",
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
  { id = "veh_repair", label = "Repair now", kind = "action", needs = "vehicle", help = "Fixes every dent, tyre and smoke on the car you are in.",
    run = function(ctx, p, v) G.call(ctx, G.VEHICLE_REPAIR, { v }, 1.0); return "Repaired" end },
  { id = "tank", label = "Tank mode", kind = "toggle", needs = "vehicle", vbits_b = G.VFLAG_B.INFINITE_MASS, v = S("vehicle_tank", false),
    help = "Your car is immovable in collisions; others bounce off." },
  { id = "bulletproof", label = "Bulletproof glass", kind = "toggle", needs = "vehicle", vbits_b = G.VFLAG_B.BULLETPROOF_GLASS,
    help = "Bullets no longer come through the windows of your car." },
  { id = "never_flat", label = "Never flat tyres", kind = "toggle", needs = "vehicle", vbits_b = G.VFLAG_B.NEVER_FLAT,
    help = "Your tyres cannot be shot out." },
  { id = "no_fling", label = "No explosion fling", kind = "toggle", needs = "vehicle", vbits_a = G.VFLAG_A.NO_EXPLOSION_FLING,
    help = "Explosions no longer throw your car around." },
  { id = "car_grip", label = "Extra car grip", kind = "toggle", needs = "none",
    help = "More downforce on the car you drive, so it stays on the road at speed.",
    update = function(ctx, p, v) if p ~= 0 then F.car_grip(v) end end,
    off = function() F.car_grip(nil) end },
  { id = "nitro_all", label = "Nitrous in every car", kind = "toggle", needs = "none", v = S("vehicle_nitrous_everywhere", false),
    help = "Every car has nitrous (Shift). Off: only the cars that had it in the game (the derby cars and one semi).",
    update = function() end,
    off = function() end },
  { id = "max_speed", label = "Extra top speed (mph)", kind = "value", needs = "vehicle", default = 0, min = 0, max = 300, step = 10, fmt = fmtint,
    help = "Raises your car's speed cap by this much; the engine still has to get there.",
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
  { id = "paint", label = "Paint my car", kind = "list", needs = "vehicle", items = PAINTS,
    help = "Left/Right to pick a paint (Shift jumps ten), Enter to paint the car you're in. Stays if you garage it.",
    run = function(ctx, p, v, it)
      local paint = PAINTS[it.v]
      local ok, why = F.paint_car(ctx, v, "body", paint[3], paint[4])
      if not ok then return why end
      if F.second_paint and F.second_paint.vehicle == v then
        F.paint_car(ctx, v, "second", F.second_paint.pal, F.second_paint.col)  -- the body paint covers the second tone
      end
      return "Painted " .. paint[2] .. (why and (" (" .. why .. ")") or "")
    end },
  { id = "paint2", label = "Second colour", kind = "list", needs = "vehicle", items = PAINTS,
    help = "Left/Right to pick, Enter: the second tone of a two-tone car, or the trim on others.",
    run = function(ctx, p, v, it)
      local paint = PAINTS[it.v]
      local ok, why = F.paint_car(ctx, v, "second", paint[3], paint[4])
      if not ok then return why end
      F.second_paint = { vehicle = v, pal = paint[3], col = paint[4] }
      return "Second colour " .. paint[2] .. (why and (" (" .. why .. ")") or "")
    end },
  { id = "boom", label = "Blow up my car", kind = "action", needs = "vehicle", help = "Detonates the car you are in. Get out first, or don't.",
    run = function(ctx) G.console(ctx, "boom"); return "Boom" end },
  { id = "spawn_vehicle", label = "Spawn vehicle here", kind = "list", items = VEHICLES, needs = "player",
    help = "Left/Right to pick one of 79 vehicles (Shift jumps ten), Enter to drop it in front of you.",
    run = function(ctx, p, _, it)
      local veh = VEHICLES[it.v]
      return F.spawn_vehicle(ctx, p, veh[1]) and ("Spawned " .. veh[2]) or ("Could not spawn " .. veh[2])
    end },
  { id = "remove_vehicles", label = "Remove spawned vehicles", kind = "action", needs = "player", help = "Removes every vehicle this menu spawned.",
    run = function(ctx) return F.remove_spawned(ctx, F.spawned_vehicles, "vehicle") end },
  { id = "garage", label = "Deliver to garage", kind = "list", items = VEHICLES, needs = "player",
    help = "Left/Right to pick any vehicle (Shift jumps ten), Enter to deliver it to your garage.",
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
  { id = "clear", label = "Clear traffic and peds", kind = "action", needs = "none",
    help = "Removes every ambient car and person at once; new ones arrive again after that.",
    run = function(ctx)
      G.script(ctx, "spawning_remove_all()")
      enqueue("spawning_on()")   -- spawning_remove_all leaves spawning off
      return "Cleared"
    end },
  { id = "restore_traffic", label = "Restore traffic and peds", kind = "action", needs = "none",
    help = "Switches the game's car and people spawning back on, if the streets stay empty.",
    run = function(ctx) G.script(ctx, "spawning_on()"); return "Traffic and peds back on" end },
  { id = "drop", label = "Everybody drop!", kind = "action", needs = "player", help = "Every person in the city falls over for a minute.",
    run = function(ctx) G.console(ctx, "super_ragdoll"); return "Everybody drop!" end },
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
    help = "Left/Right to pick (Shift jumps ten), Enter to spawn them in front of you. They come as civilians, so gang members don't start a fight. Up to 8 kinds at once: a ninth kind replaces the oldest.",
    run = function(ctx, p, _, it)
      local c = CHARACTERS[it.v]
      local ok, made_room = F.spawn_character(ctx, p, c[1])
      if not ok then return "Couldn't spawn " .. c[2] end
      return made_room and ("Spawned " .. c[2] .. " (the oldest spawned people made room)") or ("Spawned " .. c[2])
    end },
  { id = "crowd_small", label = "Spawn 10 random people", kind = "action", needs = "player", help = "Ten random civilians appear around you, one per update.",
    run = function(ctx) F.queue_crowd(10); return "Here they come" end },
  { id = "crowd_big", label = "Spawn a crowd (40)", kind = "action", needs = "player", help = "Forty random civilians; the oldest spawned people make room when the game's pool fills.",
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
  { id = "filter", label = "Filter", kind = "list", needs = "none", items = FILTERS,
    help = "Left/Right to pick, Enter to apply: Noir, Sepia, Vivid, Cold, Warm, Night vision, Retro. Off puts the picture back.",
    run = function(ctx, p, v, it) return F.set_filter(FILTERS[it.v]) end },
  { id = "free_cam", label = "Free camera", kind = "toggle", needs = "player",
    help = "WASD / left stick move, mouse / right stick look, E/Q or triggers up and down. Shift fast, Z/X or LB/RB zoom. Enter / A: play from this shot.",
    change = function(ctx, p, v, it)
      if it.v then
        if not FREECAM.enter(ctx) then it.v = false return "Free camera needs normal play (no cutscene or screen)" end
        FREECAM.set_mode(F.items.cam_mode.v)
        if F.items.cam_mode.v > 1 then return "Camera held here: close the menu to play" end
        return "Free camera on: close the menu to fly"
      else
        FREECAM.exit(ctx)
      end
    end,
    off = function(ctx) FREECAM.exit(ctx) end },
  { id = "cam_mode", label = "Free camera mode", kind = "choice", needs = "none", options = FREECAM.MODES,
    help = "Fly: move the camera. Fixed shot: it stays put while you play. Tracking shot: it stays put and turns to follow you. Right stick / mouse spins your aim, kept level. Enter / A while flying holds the shot.",
    change = function(ctx, p, v, it)
      FREECAM.set_mode(it.v)
      if FREECAM.on then return it.v == 1 and "Flying the camera" or "Playing from the shot" end
      return "Used when Free camera is on"
    end },
  { id = "freeze_world", label = "Freeze world", kind = "toggle", needs = "player",
    help = "For photos: everything stops while this menu is open or the free camera flies. Close the menu to play on.",
    update = function()
      local frozen = MENU_OPEN() or FREECAM.flying()
      wml.write_f32(G.TIME_DIV, frozen and 100000 or 1.0)
    end,
    off = function() wml.write_f32(G.TIME_DIV, 1.0) end },
  { id = "wireframe", label = "Wireframe world", kind = "toggle", needs = "player", help = "Draws the world as lines (the renderer's debug mode).",
    change = function(ctx, p, v, it) G.console(ctx, it.v and "R_wireframe on" or "R_wireframe off") end,
    off = function(ctx) G.console(ctx, "R_wireframe off") end },
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
  { id = "places", label = "Cribs", kind = "list", items = PLACES,
    help = "Left/Right to pick a crib, Enter to go there. Your car and homies come too.",
    run = function(ctx, p, _, it)
      local pl = PLACES[it.v]
      F.teleport_to(ctx, p, pl[4], pl[5], pl[6])
      return "Teleported to " .. pl[2]
    end },
  { id = "waypoint_auto", label = "Teleport on map waypoint", kind = "toggle", needs = "none", v = S("waypoint_teleport", false),
    help = "Set a waypoint on the pause map and you are taken there, car and homies too.",
    change = function(ctx, p, v, it)
      if it.v and WAYPOINT.standalone then
        it.v = false
        return "Teleport to Waypoint mod is ticked in the loader; it already does this"
      end
    end },
  { id = "waypoint_go", label = "Go to my waypoint", kind = "action",
    help = "Takes you to the waypoint you set on the map (your green one, not a mission's).",
    run = function() return WAYPOINT.go_now() end },
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
  if #F_WEAPON_QUEUE > 0 and p ~= 0 and G.playing(p) then F.give_weapon(ctx, table.remove(F_WEAPON_QUEUE, 1)) end
  if #F.spawn_queue > 0 and p ~= 0 and G.playing(p) then F.spawn_person(ctx, p, table.remove(F.spawn_queue, 1)) end
  F.apply_filter()
  if #F.watch_people > 0 then F.check_spawned() end
  if F.tick % 100 == 0 then F.sweep_people(ctx) end
  if p ~= 0 then F.limit_nitro(p) end
  if F.stop_requested then
    F.stop_requested = false
    if p ~= 0 and (F.posing or F.repeating or F.release_at) then
      F.release_player(ctx, p)
      G.hud("Stopped")
    end
  end
  if F.release_at and F.tick >= F.release_at and not F.posing and not F.repeating then F.release_player(ctx, p) end
  if F.repeating then F.repeat_action(ctx, p) end
  if p ~= 0 and #burn_queue > 0 then burn_queued(ctx, p) end
  if next(patched) and not F.on("rocket_ammo") then F.restore_guns() end
  if F.posing then
    if p == 0 or G.screen_up() or G.in_cutscene() then F.posing = nil else F.hold_pose(ctx, p) end
  end
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
function F.spawn_vehicle(ctx, p, name)
  local index = G.call(ctx, G.VEHICLE_INDEX, { G.cstr(ctx, name, 0) })
  if index == 0xFFFFFFFF then return false end
  make_room(ctx, F.spawned_vehicles, MAX_SPAWNED_VEHICLES)
  local x, y, z = spot_ahead(p, 7, 1.0)
  local pos = G.floats(ctx, { x, y, z, 0 }, 0)
  local rows = G.floats(ctx, { 1, 0, 0, 0, 1, 0, 0, 0, 1 }, 16)
  -- Creation type 7 is how the game's own vehicle cheat and mission scripts
  -- make cars (3 is the co-op mod's remote copy, which came without nitrous).
  local handle = G.call(ctx, G.VEHICLE_CREATE, { 7, 2, index, pos, rows, 0, 0, 0 }, 0.0,
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

wml.hook(G.FIRE, function(ctx)
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
function F.repeat_action(ctx, p)
  local r = F.repeating
  if p == 0 or not F.on("repeat_action") or G.vehicle_object(p) then F.release_player(ctx, p) return end
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
local file_ids = {}
local function anim_file_id(ctx, name)
  local id = file_ids[name]
  if id == nil then
    id = G.call(ctx, G.ANIM_FILE_ID, { G.cstr(ctx, name .. ".anim", 0) })
    if id ~= 0xFFFFFFFF then file_ids[name] = id end
  end
  return id
end

local function play_file(ctx, h, name)
  local owner = read_u32(h + G.ANIM_OWNER)
  if not G.pointer_ok(owner) then return false end
  local player = read_u32(owner + 3592)
  if player == 0 then return false end
  local id = anim_file_id(ctx, name)
  if id == 0xFFFFFFFF then return false end
  G.call(ctx, G.ANIM_RESET, { player, 0 })
  G.call(ctx, G.ANIM_STOP, { player })
  local handle = G.call(ctx, G.ANIM_PLAY_FILE, { player, id, 16, 0, 0, 0, 0, 0xFFFFFFFF }, { 0.0, 1.0, 1.0, -1.0 })
  if handle == 0xFFFFFFFF then return false end
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
function F.lock_player(h)
  if not lock_saved then
    lock_saved = { h = h, v4040 = read_u32(h + 4040), b3593 = read_u8(h + 3593),
                   v756 = read_u32(h + 756), v576 = read_u32(h + 576) }
  end
  write_u32(h + 4040, 3)
  write_u8(h + 3593, read_u8(h + 3593) | 16)
end

-- Ends any pose, repeat or action on the player and gives the controls back.
function F.release_player(ctx, p)
  F.posing, F.repeating, F.release_at = nil, nil, nil
  if p == 0 then lock_saved = nil return end
  local owner = read_u32(p + G.ANIM_OWNER)
  local player_anim = G.pointer_ok(owner) and read_u32(owner + 3592) or 0
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
-- play_action_do makes, which answers -1 for a missing one. A yes is
-- remembered per animation set.
local set_has = {}
local function in_set(ctx, h, slot)
  local owner = read_u32(h + G.ANIM_OWNER)
  if not G.pointer_ok(owner) then return false end
  local set = read_u32(owner)
  local known = set_has[set]
  if not known then known = {}; set_has[set] = known end
  if known[slot] then return true end
  -- Only a yes is remembered: a person who was only just made answers no
  -- until their animations are ready.
  local has = G.call(ctx, G.ANIM_SLOT_FOR, { read_u32(owner + 4), set, slot }) ~= 0xFFFFFFFF
  if has then known[slot] = true end
  return has
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
    if not play_file(ctx, h, anim.file) then
      if F.debug then wml.log("anim: file not loaded") end
      return nil, "That animation isn't loaded right now"
    end
    return { file = anim.file }
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

-- Puts a held animation back if the game moved the person on.
local function hold_anim(ctx, h, tok)
  if tok.file then
    if read_u32(h + 756) ~= G.CUSTOM_STATE then play_file(ctx, h, tok.file) end
  elseif read_u32(h + G.ANIM_STATE) ~= tok.number then
    write_u32(h + G.ANIM_STATE, tok.number)
    G.call(ctx, G.ANIM_APPLY, { h, 0xFFFFFFFF, 0xFFFFFFFF, 0 })
  end
end

-- One action (anim_actions) on a person, the way play_action_do plays it.
local action_numbers = {}
function F.action_number(ctx, name)
  local n = action_numbers[name]
  if n == nil then
    n = G.call(ctx, G.ACTION_INDEX, { G.cstr(ctx, name, 0) })
    if n == 0xFFFFFFFF then wml.log("unknown action '" .. name .. "'") return nil end
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
  local player = read_u32(owner + 3592)
  if player ~= 0 then
    G.call(ctx, G.ANIM_STOP, { player })
    G.call(ctx, G.ANIM_RESET, { player, 0 })
  end
  local ok = G.call(ctx, G.ACTION_PLAY, { h, n, 0, 0, 0, 0, 0, 0xFFFFFFFF }, { 0.0, 1.0, -1.0 })
  if F.debug then wml.log(string.format("action: %s (%d) on %08X -> %s", name, n, h, (ok & 0xFF) ~= 0 and "played" or "refused")) end
  if h == read_u32(G.PLAYER) then
    F.lock_player(h)
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
  local x, y, z = guard_place(p)
  local pos = G.floats(ctx, { x, y, z, 0 }, 0)
  local rows = G.floats(ctx, { 1, 0, 0, 0, 1, 0, 0, 0, 1 }, 16)
  G.call(ctx, G.NUDGE_SPOT, { pos })
  local stack = { { 84, 4, 0 }, { 94, 2, 8 }, { 103, 1, 0 } }
  local obj = G.call(ctx, G.HUMAN_CREATE, { 0, 2, def, pos, rows, 255, 0, 0 }, nil, stack)
  if not G.pointer_ok(obj) or obj == p or not handle_alive(read_u32(obj + 68)) then G.hud("No room for another person right now") return end
  keep_person(ctx, obj)
  local team = G.call(ctx, G.TEAM_LOOKUP, { G.cstr(ctx, "Playas", 1) })
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
      elseif read_u32(p + G.PARTY_COUNT) < 10 and (G.call(ctx, G.PARTY_ADD, { p, obj, 1 }) & 0xFF) ~= 0 then
        local slot = G.call(ctx, G.HUD_SLOT, { obj })
        if slot ~= 0xFFFFFFFF then G.call(ctx, G.HUD_ADD, { obj }) end
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
F.items.god.off = function(ctx, p) if p ~= 0 then G.player_flag(p, G.FLAG.INVULNERABLE, false) end end

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
  for _, cat in ipairs(F.categories) do
    for _, it in ipairs(cat.items) do
      if it.kind == "toggle" and it.v and it.id ~= "master" then parts[#parts + 1] = it.label end
    end
  end
  return (F.enabled and "On: " or "Tweaks OFF. Would be on: ") .. (#parts > 0 and table.concat(parts, ", ") or "nothing")
end

return F
