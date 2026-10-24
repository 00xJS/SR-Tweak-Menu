-- SR Tweak Menu - saved places: save where you stand (and the way you
-- face), go back there any time, rename and delete them. Teleport > Saved
-- places. Kept in saved_places.txt in this mod's folder, one place a line:
-- x, y, z, the nine floats of the player's rows, then the name, tab-separated.
-- Going there uses the menu's teleport (F.teleport_to): your car and homies
-- come along.
--
-- Renaming: a list of letters for the pad (Left / Right picks, Enter adds),
-- or type on the keyboard while the Rename page is open (Shift for capitals).
-- The page keeps every key from the game while it's open; the letter that
-- switches First Person (V by default) isn't typed, so it can't switch the
-- camera by accident (pick it from the list).

local G = require("game")
local read_u32, read_f32 = wml.read_u32, wml.read_f32

local P = {}
local F, MENU
local FILE = wml.mod_folder .. "/saved_places.txt"
local MAX, NAME_MAX = 50, 24

P.list = {}   -- { name, x, y, z, facing = { 9 floats } }

local function clean(name)
  name = tostring(name or ""):gsub("[%c\t]", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return name:sub(1, NAME_MAX)
end

local function load()
  P.list = {}
  local f = io.open(FILE, "r")
  if not f then return end
  for line in f:lines() do
    if not line:match("^%s*;") then
      local parts = {}
      for field in (line .. "\t"):gmatch("([^\t]*)\t") do parts[#parts + 1] = field end
      if #parts >= 13 then
        local nums, ok = {}, true
        for i = 1, 12 do
          nums[i] = tonumber(parts[i])
          if not nums[i] or nums[i] ~= nums[i] then ok = false end
        end
        if ok and #P.list < MAX then
          P.list[#P.list + 1] = { name = clean(parts[13]), x = nums[1], y = nums[2], z = nums[3],
            facing = { table.unpack(nums, 4, 12) } }
        end
      end
    end
  end
  f:close()
end

local function save()
  local f = io.open(FILE, "w")
  if not f then return false end
  f:write("; SR Tweak Menu - saved places (Teleport > Saved places): x, y, z, facing (9 numbers), name; tab-separated.\n")
  for _, pl in ipairs(P.list) do
    local fields = { string.format("%.3f", pl.x), string.format("%.3f", pl.y), string.format("%.3f", pl.z) }
    for i = 1, 9 do fields[#fields + 1] = string.format("%.5f", pl.facing[i]) end
    fields[#fields + 1] = pl.name
    f:write(table.concat(fields, "\t"), "\n")
  end
  f:close()
  return true
end

local function where(p)
  local facing = {}
  for i = 0, 8 do facing[i + 1] = read_f32(p + 32 + i * 4) end
  local x, y, z = G.vec(p + G.P.POS)
  return x, y, z, facing
end

local function free_name()
  local used = {}
  for _, pl in ipairs(P.list) do used[pl.name:lower()] = true end
  for n = 1, MAX + 1 do
    local name = "Place " .. n
    if not used[name:lower()] then return name end
  end
  return "Place"
end

-- ---------------------------------------------------------------- renaming
local LETTERS = {}
for c in ("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 -'!.&#"):gmatch(".") do
  LETTERS[#LETTERS + 1] = { c, c == " " and "(space)" or c }
end
-- Keys typed on the keyboard; the First Person key is left out.
local fp_key = "V"
do
  local f = io.open(wml.mod_folder .. "/../../core/FirstPerson/mod.ini", "r")
  if f then
    for line in f:lines() do
      local k = line:match("^%s*key%s*=%s*(%S+)")
      if k then fp_key = k:upper() end
    end
    f:close()
  end
end
local TYPE_KEYS = {}
for c in ("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"):gmatch(".") do
  if c ~= fp_key then TYPE_KEYS[#TYPE_KEYS + 1] = c end
end
-- The keys the menu doesn't already keep from the game while it's open:
-- taken here while typing, given back after.
local MENU_TAKES = { A = true, C = true, D = true, E = true, F = true, Q = true, R = true, S = true, V = true,
  W = true, X = true, Z = true }
local typed = {}          -- characters typed since the last update
local typing_page = nil   -- the Rename page open on top, or nil
local keys_held = false

local function rename_page(pl, rebuild)
  local draft = pl.name
  local pg
  local name_row = { label = "", kind = "header" }
  local function show() name_row.label = "Name: " .. (draft ~= "" and draft or "(empty)") .. "_" end
  local function add(c)
    if #draft < NAME_MAX then draft = draft .. c end
    show()
  end
  local letter
  letter = { id = "myplaces_letter", label = "Add a letter", kind = "list", needs = "none", items = LETTERS, v = 1,
    help = "Left / Right picks a letter, Enter adds it. On the keyboard you can just type (Shift for capitals).",
    run = function() add(LETTERS[letter.v][1]); return nil end }
  pg = { title = "Rename " .. pl.name, typing = true, rows = {
    name_row,
    letter,
    { label = "Space", kind = "action", needs = "none", run = function() add(" ") end },
    { label = "Delete last letter", kind = "action", needs = "none", run = function() draft = draft:sub(1, -2); show() end },
    { label = "Clear", kind = "action", needs = "none", run = function() draft = ""; show() end },
    { id = "myplaces_name", label = "Save name", kind = "action", needs = "none", run = function()
        local name = clean(draft)
        if name == "" then return "Type a name first" end
        pl.name = name
        save(); rebuild()
        pg.close_after = 2
        return "Renamed to " .. name
      end },
  } }
  pg.type = function(c) add(c) end
  show()
  return pg
end

-- ---------------------------------------------------------------- the page
local function places_page()
  local rows = {}
  local pg = { title = "Saved places", rows = rows }
  local build
  local function confirm(title, yes)
    return function()
      return { title = title, rows = {
        { id = "myplaces_yes", label = "Yes", kind = "action", needs = "player", run = function(c, pp) local msg = yes(c, pp); pg.close_after = 2; return msg end },
        { label = "No", kind = "action", needs = "none", run = function() pg.close_after = 1 end } } }
    end
  end
  build = function()
    for k in pairs(rows) do rows[k] = nil end
    rows[1] = { id = "myplaces_save", label = "Save this spot", kind = "action", needs = "player",
      help = "Saves where you stand (or sit in a car) and the way you face, to come back to any time.",
      run = function(c, p)
        if #P.list >= MAX then return string.format("All %d places are in use: delete one first", MAX) end
        local x, y, z, facing = where(p)
        local name = free_name()
        P.list[#P.list + 1] = { name = name, x = x, y = y, z = z, facing = facing }
        if not save() then return "Couldn't write saved_places.txt" end
        build()
        return "Saved as " .. name .. " (rename it in its page)"
      end }
    rows[2] = { label = #P.list > 0 and string.format("Your places (%d of %d)", #P.list, MAX) or "Nothing saved yet", kind = "header" }
    for _, pl in ipairs(P.list) do
      rows[#rows + 1] = { label = pl.name, kind = "page", needs = "none",
        help = string.format("At %.0f, %.0f, %.0f.", pl.x, pl.y, pl.z),
        open = function()
          return { title = pl.name, rows = {
            { id = "myplaces_go", label = "Go there", kind = "action", needs = "player", run = function(c, p)
                F.teleport_to(c, p, pl.x, pl.y, pl.z, pl.facing)
                return "Teleported to " .. pl.name
              end },
            { label = "Rename", kind = "page", needs = "none", open = function() return rename_page(pl, build) end },
            { label = "Save here instead", kind = "page", needs = "player", open = confirm("Move " .. pl.name .. " to where you are?", function(c, p)
                pl.x, pl.y, pl.z, pl.facing = where(p)
                save(); build()
                return pl.name .. " is now here"
              end) },
            { label = "Delete", kind = "page", needs = "none", open = confirm("Delete " .. pl.name .. "?", function()
                for i, q in ipairs(P.list) do if q == pl then table.remove(P.list, i) break end end
                save(); build()
                return pl.name .. " deleted"
              end) },
          } }
        end }
    end
  end
  build()
  return pg
end

function P.setup(features)
  F = features
  load()
  F.add_rows("Teleport", "places", {
    { id = "saved_places", label = "Saved places", kind = "page", needs = "none",
      help = "Save any spot, go back to it, rename or delete it.",
      open = function() return places_page() end },
  })
end

function P.install(menu)
  MENU = menu
  -- Typing: key presses come per drawn frame, more often than updates, so
  -- they're collected here and added in the next update.
  wml.on_frame(function()
    if not typing_page then return end
    local shift = wml.key_down("SHIFT")
    for _, k in ipairs(TYPE_KEYS) do
      if wml.key_pressed(k) then
        typed[#typed + 1] = (k:match("%a") and not shift) and k:lower() or k
      end
    end
    if wml.key_pressed("SPACE") then typed[#typed + 1] = " " end
  end)
end

function P.after()
  local top = MENU and MENU.is_open() and MENU.pages[#MENU.pages] or nil
  local now = (top and top.typing) and top or nil
  if now ~= typing_page then
    typing_page = now
    typed = {}
    local take = now ~= nil
    if take ~= keys_held then
      keys_held = take
      for _, k in ipairs(TYPE_KEYS) do
        if not MENU_TAKES[k] then pcall(wml.take_key, k, take) end
      end
    end
  end
  if typing_page and #typed > 0 then
    for _, c in ipairs(typed) do typing_page.type(c) end
    typed = {}
  end
end

return P
