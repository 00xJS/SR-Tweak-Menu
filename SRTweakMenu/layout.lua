-- SR Tweak Menu - where every row is shown: the tab order, each tab's rows
-- and the pages they're grouped into. Rows are made in features.lua and
-- juiced.lua; this only places them. The rule: the rows you use every
-- session sit on the tab (switches first, then set-up rows and actions),
-- the rest on pages named by what they change.
--
-- Rows keep their ids, so mod.ini keys and saved tweaks are unaffected.
-- A row that was in the menu before and isn't placed here is put back at
-- the end of its old tab (and logged), so nothing can go missing.

local L = {}

local function page(id, label, help, rows) return { page = id, label = label, help = help, rows = rows } end

-- Each tab: its rows in order; a string is a row (or an existing page) by
-- id, page() makes a new page. `keep = true` keeps the tab's own rows and
-- adds `add` at the end.
local TABS = {
  { "Player", {
    page("player_health", "Health & damage", "God mode, ragdoll, health, regen, healing and fall damage.",
      { "god", "no_ragdoll", "health_mult", "fall_damage", "no_regen", "dpad_heal", "heal", "kill_self" }),
    page("player_movement", "Movement", "No clip, sprinting, running, jumping, landing, crouching and swimming.",
      { "noclip", "sprint", "sprint_preset", "run", "run_speed", "jump", "jump_boost", "jump_height", "landing", "quick_crouch",
        "crouch_moving", "swim_speed" }),
    page("player_notoriety", "Notoriety", "Police and gangs, and the gang you side with.",
      { "never_wanted", "saints_enemies", "join_gang", "no_cops", "no_gangs", "no_bust", "max_wanted",
        "wanted_police", "wanted_carnales", "wanted_vk", "wanted_rollerz", "wanted_saints" }),
    "player_bodyguards",
    page("settings_unlocks", "Unlocks", "Music, collectibles and clothing, and rewards kept in your save.",
      { "unlock_music", "unlock_collectibles", "unlock_clothing", "unlock_mp_clothing", "unlock_reward_clothing",
        "rewards_header", "reward_free_shopping", "reward_bulletproof", "reward_blastproof", "reward_crashproof",
        "reward_police_forget", "reward_gangs_forget" }),
    "money", "respect" } },
  { "Weapons", {
    "infinite_ammo", "no_reload", "fire", "one_hit", "harder_hits", "perfect_aim", "no_melee_lock", "car_reload",
    page("weapons_special", "Special ammo", "Rocket and fire ammo, the money gun and explosive punches.",
      { "rocket_ammo", "fire_ammo", "money_gun", "money_gun_cash", "explosive_punch", "punch_blast" }),
    page("weapons_aiming", "Aiming & switching", "Aim style (Precise Aim, Fine Aim) and its camera, the aim button, turning while aiming, and weapon switch.",
      { "aim_style", "aim_camera_page", "fine_aim_zoom", "fine_aim_spread", "aim_button", "precise_turning", "precise_aim_turn",
        "fine_aim_turn", "weapon_switch", "weapon_dpad", "weapon_tap" }),
    page("weapons_skins", "Skins", "A colour for each weapon: gold, black, silver, tan, olive and more. Every copy of the gun changes, NPCs' too.",
      { "skin_k6_krukov", "skin_vice_9", "skin_nr4", "skin_ar40_xtnd", "skin_skr7_spree", "skin_44_shepherd", "skin_tombstone",
        "skin_12_gauge", "skin_as12_riot", "skin_mcmanus", "skin_rpg", "skin_platinum_rpg", "skin_nightstick", "skin_crowbar",
        "skin_knife", "skin_baseball_bat", "skin_pimp_slap", "skin_pcp", "skins_reset" }),
    "give_weapon", "give_item", "give_item_count", "all_weapons", "ammo_all" } },
  { "Vehicles", {
    "veh_god", "veh_repair",
    page("vehicles_toughness", "Toughness", "Tank mode, bulletproof glass and tires, no explosion fling.",
      { "tank", "bulletproof", "never_flat", "no_fling" }),
    page("vehicles_handling", "Handling", "Extra grip, nitrous everywhere, extra top speed, bouncy and less stiff cars.",
      { "car_grip", "nitro_all", "max_speed", "bouncy_cars", "bounce_strength", "soft_spin", "spin_damping" }),
    page("vehicles_look", "Look", "Customize the car, paint it, and brake lights when stopped.",
      { "vehicle_custom", "paint", "paint2", "brake_lights" }),
    page("vehicles_camera", "Driving camera", "How long the camera holds, how fast it swings back, slides, drive-bys and the speed field of view.",
      { "car_free_cam", "car_cam_reset", "car_cam_reset_stopped", "car_cam_follow", "car_cam_nose", "driveby_cam", "no_entry_swing", "speed_fov" }),
    "spawn_vehicle", "remove_vehicles", "garage", "boom" } },
  { "World", {
    "weather", "no_fog", "hour", "freeze_clock", "clear", "restore_traffic", "stores_24_7",
    page("world_people", "People", "Spawn people and crowds, what everybody does, and how gangs and police come at you.",
      { "spawn_person", "crowd_small", "crowd_big", "remove_people", "everybody", "drop", "kill_all", "gang_civ_cars", "no_guns" }),
    page("world_drops", "Drops", "Cash and weapons around you, money rain, and how often the dead drop cash.",
      { "cash_rain", "money_rain", "money_rain_rate", "money_rain_bill", "weapon_rain", "cash_drop_chance" }),
    page("world_districts", "Districts", "Who owns each part of Stilwater, and the whole map explored.",
      { "district", "district_owner", "district_apply", "explore_map" }) } },
  { "Visual", {
    "hide_hud", "map_arrow", "letterbox", "filter", "render_mode", "saturation",
    page("visual_camera", "Camera", "Field of view, the over-the-shoulder camera, first person and its field of view, and camera turn speed.",
      { "fov", "shoulder_cam", "shoulder_side", "shoulder_closer", "first_person", "fp_fov", "camera_turn" }),
    page("visual_free_camera", "Free camera", "Fly the camera or leave it on a shot, and freeze the world.",
      { "free_cam", "cam_mode", "freeze_world" }),
    "settings_ui_plus" } },
  { "Teleport", { keep = true } },
  { "Models", { keep = true, add = { "missing_moves", "loose_parts" } } },
  { "Customize", { keep = true, add = { "outfit_back", "look_pose" } } },
  { "Emotes", { "poses", "actions", "player_voice_lines", "scene", "stop_pose", "clear_scene", "repeat_action", "repeat_every",
    "dpad_taunts" } },
  { "Settings", {
    "master", "status", "save_tweaks", "forget_tweaks", "restore_menu", "restore_game",
    page("settings_game", "Game & saving", "Skip intro, load last save, quick save, pause cutscenes and tutorial popups.",
      { "skip_intro", "load_last_save", "load_wait", "quick_save", "cutscene_pause", "no_tutorials" }) } },
}

-- Old pages whose rows are placed one by one now, and old headers.
local DISSOLVED = { player_logic = true, settings_controls = true, settings_tweaks = true,
  qol_player = true, qol_car_camera = true, qol_driving = true, qol_visual = true, qol_startup = true }
local PAGE_ROWS = { player_logic = true, settings_controls = true, settings_tweaks = true }

-- The rows of a page built by a plain list (not one made on opening).
local function static_rows(it)
  if it.kind ~= "page" or not PAGE_ROWS[it.id] then return nil end
  local ok, pg = pcall(it.open)
  return ok and type(pg) == "table" and pg.rows or nil
end

function L.apply(F)
  -- Where every row is now: top-level, or inside a page being dissolved.
  local home, order = {}, {}
  for _, cat in ipairs(F.categories) do
    for _, it in ipairs(cat.items) do
      if it.id then home[it.id] = cat.name; order[#order + 1] = it.id end
      for _, r in ipairs(static_rows(it) or {}) do
        if r.id then home[r.id] = cat.name; order[#order + 1] = r.id end
      end
    end
  end

  local placed, by_name, cats = {}, {}, {}
  for _, cat in ipairs(F.categories) do by_name[cat.name] = cat end
  local function take(id)
    local it = F.items[id]
    if not it then wml.log("layout: no row " .. id) return nil end
    placed[id] = true
    return it
  end

  for _, t in ipairs(TABS) do
    local name, spec = t[1], t[2]
    local cat = by_name[name]
    if cat then
      local items = {}
      if spec.keep then
        for _, it in ipairs(cat.items) do
          if it.id then placed[it.id] = true end
          items[#items + 1] = it
        end
        for _, id in ipairs(spec.add or {}) do
          local it = take(id)
          if it then items[#items + 1] = it end
        end
      else
        for _, e in ipairs(spec) do
          if type(e) == "string" then
            local it = take(e)
            if it then items[#items + 1] = it end
          else
            local rows = {}
            for _, id in ipairs(e.rows) do
              local it = take(id)
              if it then rows[#rows + 1] = it end
            end
            local pg = { id = e.page, label = e.label, kind = "page", needs = "none", help = e.help, page_rows = rows,
              open = function() return { title = e.label, rows = rows } end }
            F.items[e.page] = pg
            placed[e.page] = true
            items[#items + 1] = pg
          end
        end
      end
      cat.items = items
      cats[#cats + 1] = cat
      by_name[name] = nil
    end
  end
  -- Tabs not listed keep their rows, after the listed ones.
  for _, cat in ipairs(F.categories) do
    if by_name[cat.name] then
      cats[#cats + 1] = cat
      for _, it in ipairs(cat.items) do if it.id then placed[it.id] = true end end
    end
  end
  F.categories = cats

  -- Anything missed goes back to the end of its old tab.
  for _, id in ipairs(order) do
    if not placed[id] and not DISSOLVED[id] then
      for _, cat in ipairs(F.categories) do
        if cat.name == home[id] then cat.items[#cat.items + 1] = F.items[id] end
      end
      placed[id] = true
      wml.log("layout: " .. id .. " wasn't placed; left at the end of " .. home[id])
    end
  end
end

return L
