-- SR Tweak Menu - what's changed, and back to defaults (Settings tab).
--
-- Show active tweaks lists every setting that isn't the game's own: switches
-- that are on, sliders off their default, and the choices that stay set
-- (aim style, filter, weather ...), grouped by the tab and page they're on.
-- They are the menu's own rows, so each can be changed back right there.
--
-- Two ways back, each asking first:
--   Restore menu defaults  - every row as the menu starts it from mod.ini,
--                            and the saved tweaks forgotten;
--   Restore game defaults  - every switch off and every value the game's own.
-- A row goes back the way it would by hand: its value set and, where it has
-- one, its change handler run; switches and sliders then put the game's own
-- back on the next update, as they do when switched off.

local G = require("game")

local D = {}
local F, forget_saved

-- The game's own for the choices that stay set (the rest are pickers:
-- spawn this, give that, go there).
local CHOICE_DEFAULTS = {
  weather = 1, filter = 1, render_mode = 1, cam_mode = 1, aim_style = 1, aim_button = 1, precise_turning = 1,
  weapon_dpad = 1, weapon_tap = 1, punch_blast = 2, line_rate = 3, missing_moves = 1, loose_parts = 2, look_pose = 1,
}
-- Numbers that only say how much of something to do now, not a setting.
local NOT_SETTINGS = { give_item_count = true }

local function game_default(it)
  if it.kind == "toggle" then return false end
  if it.kind == "value" then return it.default end
  if CHOICE_DEFAULTS[it.id] then return CHOICE_DEFAULTS[it.id] end
  if it.kind == "list" and it.id and it.id:find("^move_part_") then return 1 end
  return nil
end
-- Rows this looks at: settings, not the master switch, live readouts
-- (notoriety levels, the time of day) or rows the menu doesn't keep.
local function tracked(it)
  if not it.id or it.id == "master" or it.nosave or it.live or it.retired or NOT_SETTINGS[it.id] then return false end
  return game_default(it) ~= nil
end
local function differs(a, b)
  if type(a) == "number" and type(b) == "number" then return math.abs(a - b) > 1e-6 end
  return a ~= b
end
local function changed(it) return tracked(it) and differs(it.v, game_default(it)) end

local function value_text(it)
  if it.kind == "toggle" then return it.v and "On" or "Off" end
  if it.kind == "choice" then return it.options[it.v] or "?" end
  if it.kind == "list" then return it.items[it.v] and it.items[it.v][2] or "?" end
  return it.fmt and it.fmt(it.v) or tostring(it.v)
end

-- Where each row lives: "Tab" or "Tab > Page".
local function locations()
  local where = {}
  local function walk(items, path, depth)
    for _, it in ipairs(items) do
      if it.kind == "page" and it.page_rows and depth < 4 then
        walk(it.page_rows, path .. " > " .. it.label, depth + 1)
      elseif it.id and not where[it.id] then
        where[it.id] = path
      end
    end
  end
  for _, cat in ipairs(F.categories) do walk(cat.items, cat.name, 0) end
  return where
end

-- Every tracked row as the menu starts it (mod.ini), before saved tweaks.
function D.snapshot()
  for _, it in pairs(F.items) do
    if tracked(it) then it.start_v = it.v end
  end
end

local function set_to(ctx, it, want)
  if want == nil or not differs(it.v, want) then return false end
  it.v = want
  local p = G.player()
  local v = p ~= 0 and (G.vehicle_object(p) or 0) or 0
  local ok_ctx = it.needs ~= "player" or p ~= 0
  if it.change and ok_ctx then pcall(it.change, ctx, p, v, it) end
  -- (the filter list puts its look on when picked)
  if it.id == "filter" and it.run then pcall(it.run, ctx, p, v, it) end
  return true
end

local function restore(ctx, target)
  local n = 0
  for _, it in pairs(F.items) do
    if tracked(it) then
      local want = target == "menu" and it.start_v or game_default(it)
      if set_to(ctx, it, want) then n = n + 1 end
    end
  end
  return n
end

local function confirm(title, yes)
  return function()
    local pg
    pg = { title = title, rows = {
      { id = "defaults_yes", label = "Yes", kind = "action", needs = "none", run = function(ctx) pg.close_after = 1; return yes(ctx) end },
      { id = "defaults_no", label = "No", kind = "action", needs = "none", run = function() pg.close_after = 1 end } } }
    return pg
  end
end

local function back_to_game(ctx)
  local n = restore(ctx, "game")
  return n > 0 and string.format("%d setting%s back to the game's own", n, n == 1 and "" or "s") or "Everything is already the game's own"
end

-- The Show active tweaks page.
local function changed_page()
  local where = locations()
  local list = {}
  for _, it in pairs(F.items) do
    if changed(it) then list[#list + 1] = { it = it, at = where[it.id] or "?" } end
  end
  table.sort(list, function(a, b)
    if a.at ~= b.at then return a.at < b.at end
    return a.it.label < b.it.label
  end)
  local rows = {}
  if not F.enabled then
    rows[#rows + 1] = { label = "All tweaks is off: these are kept, not in use", kind = "header" }
  end
  if #list == 0 then
    rows[#rows + 1] = { label = "Nothing changed: everything is the game's own", kind = "header" }
  else
    rows[#rows + 1] = { id = "defaults_all_back", label = "Put all of these back to the game's own", kind = "page", needs = "none",
      help = "Every switch below off and every value back to the game's own.",
      open = confirm("Put all " .. #list .. " back to the game's own?", back_to_game) }
    local at = nil
    for _, e in ipairs(list) do
      if e.at ~= at then
        at = e.at
        rows[#rows + 1] = { label = at, kind = "header" }
      end
      rows[#rows + 1] = e.it
    end
  end
  return { title = string.format("Changed settings (%d)", #list), rows = rows }
end

function D.setup(features, forget)
  F = features
  forget_saved = forget
  -- Show active tweaks becomes this page (its id stays, so layout and saved
  -- tweaks are unaffected).
  local status = F.items.status
  status.kind = "page"
  status.label = "Show active tweaks"
  status.help = "Every setting that isn't the game's own, by where it is in the menu: change any of them back right there."
  status.open = function() return changed_page() end
  status.run = nil

  F.add_rows("Settings", "forget_tweaks", {
    { id = "restore_menu", label = "Restore menu defaults", kind = "page", needs = "none",
      help = "Every row back to how the menu starts (mod.ini), and the saved tweaks forgotten.",
      open = confirm("Back to the menu's defaults, and forget saved tweaks?", function(ctx)
        local n = restore(ctx, "menu")
        local msg = forget_saved and forget_saved() or ""
        return string.format("%d setting%s back to the menu's defaults. %s", n, n == 1 and "" or "s", msg)
      end) },
    { id = "restore_game", label = "Restore game defaults", kind = "page", needs = "none",
      help = "Every switch off and every value the game's own: the game as it is without the menu.",
      open = confirm("Everything back to the game's own?", back_to_game) },
  })
end

D.changed = changed
D.game_default = game_default
return D
