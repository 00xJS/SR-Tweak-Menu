-- SR Tweak Menu - the on-screen menu.
--
-- Tabs across the top (one per feature category), a cursor down the rows.
-- Keys: F5 opens and closes, Up/Down move, Left/Right adjust a value or
-- browse a list, Enter toggles or runs, Backspace closes, PgUp/PgDn change
-- tab. Controller: RB + D-pad down opens and closes (menu_pad), D-pad moves,
-- A selects, B goes back, LB/RB change tab.
--
-- Every controller reaches the game as an Xbox pad, after Saints Reborn has
-- mapped it (RB is R1 on a PlayStation pad). On Windows, and on the Mac,
-- where the same build runs under Wine, the keyboard is mapped onto that
-- pad too (Shift is RB, the arrows are the D-pad). So while the menu is open
-- every mapped key is taken from that mapping, leaving the pad to real
-- controllers, and the controller state is blanked so the player stands
-- still. Buttons still held when the menu closes stay hidden from the game
-- until they are let go, so the B that closed it doesn't also hit someone.
--
-- Drawing: Lua cannot put text on screen, so the finished text goes into a
-- mailbox in guest memory that menu_overlay.dll (same folder) shows with the
-- loader's overlay text. Without the DLL every action shows a one-line HUD
-- message instead and the menu is driven blind.

local G = require("game")
local F = require("features")
local S = wml.setting

local M = { open = false, tab = 1, cursor = {}, scroll = {}, status = "", status_until = 0, dll = false, pad = 0 }

local MAILBOX, MAGIC = 0x00F00000, 0x53524D55
local TEXT_OFFSET, TEXT_MAX = 0x40, 8192
local ROWS = S("menu_rows", 12)
local WINDOWS = package.config:sub(1, 1) == "\\"  -- the mailbox exists only in the Windows build
local use_overlay = S("menu_overlay", true) and WINDOWS

local KEY = {
  open = tostring(S("menu_key", "F5")), up = "UP", down = "DOWN", left = "LEFT", right = "RIGHT",
  enter = "ENTER", back = "BACKSPACE", prev = "PAGEUP", next = "PAGEDOWN", fast = "SHIFT",
}
-- Taken while open: the menu's own keys, and every key Saints Reborn maps
-- onto the pad on foot or in a car (kbm.cpp), so they read as keys only.
local TAKEN = { "UP", "DOWN", "LEFT", "RIGHT", "ENTER", "BACKSPACE",
  "W", "A", "S", "D", "Q", "E", "R", "F", "C", "V", "X", "Z", "SPACE", "SHIFT", "CTRL", "TAB" }
-- XINPUT_GAMEPAD bits; LT and RT are analog and get bits of their own.
local PAD = { UP = 0x1, DOWN = 0x2, LEFT = 0x4, RIGHT = 0x8, START = 0x10, BACK = 0x20, LS = 0x40, RS = 0x80,
  LB = 0x100, RB = 0x200, A = 0x1000, B = 0x2000, X = 0x4000, Y = 0x8000, LT = 0x10000, RT = 0x20000 }
M.PAD = PAD
local TRIGGER_PRESSED = 85  -- of 255: a trigger a third of the way in counts as pressed
local PAD_ALIAS = {
  R1 = "RB", L1 = "LB", R2 = "RT", L2 = "LT", R3 = "RS", L3 = "LS",
  CROSS = "A", CIRCLE = "B", SQUARE = "X", TRIANGLE = "Y",
  OPTIONS = "START", MENU = "START", SHARE = "BACK", SELECT = "BACK", VIEW = "BACK",
  DPAD_UP = "UP", DPAD_DOWN = "DOWN", DPAD_LEFT = "LEFT", DPAD_RIGHT = "RIGHT",
}
local PAD_LABEL = { UP = "D-pad Up", DOWN = "D-pad Down", LEFT = "D-pad Left", RIGHT = "D-pad Right" }
local block_input = S("menu_blocks_input", true)

-- The controller combo (menu_pad): hold every button but the last, press the
-- last. While the held ones are down the last one is kept from the game, so
-- RB + D-pad down never reaches the game as Cancel Activity.
local combo_hold, combo_press, combo_text = 0, 0, ""
local function parse_combo(text)
  local hold, press, names = 0, 0, {}
  for raw in text:gmatch("[^+%s]+") do
    local name = raw:upper()
    name = PAD_ALIAS[name] or name
    if not PAD[name] then return nil, raw end
    hold = hold | press
    press = PAD[name]
    names[#names + 1] = PAD_LABEL[name] or name
  end
  if press == 0 then return 0, 0, "" end
  return hold, press, table.concat(names, " + ")
end
do
  local text = tostring(S("menu_pad", "RB+DOWN"))
  local hold, press, label = parse_combo(text)
  if not hold then
    wml.log("menu_pad: unknown button '" .. press .. "' in '" .. text .. "'; using RB+DOWN")
    hold, press, label = parse_combo("RB+DOWN")
  end
  combo_hold, combo_press, combo_text = hold, press, label
end
M.combo_text = combo_text
M.parse_combo = parse_combo

for i = 1, #F.categories do M.cursor[i] = 1; M.scroll[i] = 1 end

local swallow = 0   -- pad bits held when the menu closed, hidden until let go
local tap_armed, tapped = 0, 0  -- see track_taps
local device = "keys"  -- what the hints at the bottom name: "keys" or "pad"

local function say(text)
  if not text then return end
  M.status, M.status_until = text, M.tick + 150
  if not M.dll then G.hud(text) end
end

local function current_item()
  local cat = F.categories[M.tab]
  return cat.items[M.cursor[M.tab]], cat
end

-- ------------------------------------------------------------- mailbox
local seq, last_text = 0, nil
local function mailbox_write(text)
  if text == last_text then return end
  last_text = text
  local n = math.min(#text, TEXT_MAX)
  local base = MAILBOX + TEXT_OFFSET
  local i = 1
  while i + 3 <= n do
    wml.write_u32(base + i - 1, (text:byte(i) << 24) | (text:byte(i + 1) << 16) | (text:byte(i + 2) << 8) | text:byte(i + 3))
    i = i + 4
  end
  while i <= n do wml.write_u8(base + i - 1, text:byte(i)); i = i + 1 end
  wml.write_u32(MAILBOX + 0x14, n)
  seq = seq + 1
  wml.write_u32(MAILBOX + 0x10, seq)
end

local function check_dll()
  if not use_overlay then M.dll = false return end
  local had = M.dll
  M.dll = wml.read_u32(MAILBOX) == MAGIC
  if M.dll ~= had then wml.log(M.dll and "menu: overlay DLL found" or "menu: overlay DLL not found; HUD messages instead") end
end

-- ------------------------------------------------------------- open/close
local function set_open(open)
  if open == M.open then return end
  M.open = open
  for _, k in ipairs(TAKEN) do wml.take_key(k, open) end
  tap_armed = 0
  if open then
    check_dll()
    M.refresh_now = true
    say(M.dll and "" or "Menu open (no overlay): " .. current_item().label)
  else
    last_text = nil
    if M.dll then mailbox_write("") end
  end
end

-- ------------------------------------------------------------- navigation
local function move(dir)
  local cat = F.categories[M.tab]
  local n = #cat.items
  M.cursor[M.tab] = ((M.cursor[M.tab] - 1 + dir) % n) + 1
  local c, s = M.cursor[M.tab], M.scroll[M.tab]
  if c < s then M.scroll[M.tab] = c end
  if c >= s + ROWS then M.scroll[M.tab] = c - ROWS + 1 end
  if not M.dll then
    local it = current_item()
    say(it.label .. " " .. F.value_text(it))
  end
end

local function switch_tab(dir)
  local n = #F.categories
  M.tab = ((M.tab - 1 + dir) % n) + 1
  if not M.dll then say("Tab: " .. F.categories[M.tab].name) end
end

local function adjust(ctx, dir)
  local it = current_item()
  if it.kind == "value" or it.kind == "choice" or it.kind == "list" then
    say(F.adjust(ctx, it, dir, wml.key_down(KEY.fast)))
  elseif it.kind == "toggle" then
    say(F.toggle(ctx, it))
  end
end

local function activate(ctx)
  -- Lists act on the entry shown on the row (picked with Left/Right).
  say(F.activate(ctx, current_item()))
end

-- ------------------------------------------------------------- input
-- Keys repeat while held: first after 14 updates, then every 4.
local held = {}
local function repeating(name, down)
  if not down then held[name] = nil return false end
  local h = held[name]
  if not h then held[name] = 14 return true end
  h = h - 1
  if h <= 0 then held[name] = 4 return true end
  held[name] = h
  return false
end

local pad_prev = 0
-- Buttons for menu actions: the combo's last button doesn't count while the
-- held ones are down, so the combo that closes the menu doesn't also move it.
local function nav()
  if combo_hold ~= 0 and (M.pad & combo_hold) == combo_hold then return M.pad & ~combo_press end
  return M.pad
end
local function nav_prev()
  if combo_hold ~= 0 and (pad_prev & combo_hold) == combo_hold then return pad_prev & ~combo_press end
  return pad_prev
end
local function pad_down(bit) return (nav() & bit) ~= 0 end
-- A button held for the combo (RB) acts when it is let go, and only if no
-- other button was pressed meanwhile; any other button acts when pressed.
local function track_taps()
  tap_armed = tap_armed | (M.pad & ~pad_prev & combo_hold)
  if (M.pad & ~combo_hold) ~= 0 then tap_armed = 0 end
  tapped = tap_armed & ~M.pad
  tap_armed = tap_armed & M.pad
end
local function pad_hit(bit)
  if (combo_hold & bit) ~= 0 then return (tapped & bit) ~= 0 end
  return (nav() & bit) ~= 0 and (nav_prev() & bit) == 0
end

local DEVICE_KEYS = { "UP", "DOWN", "LEFT", "RIGHT", "ENTER", "BACKSPACE", "PAGEUP", "PAGEDOWN" }
local function track_device()
  if KEY.open ~= "" and wml.key_down(KEY.open) then device = "keys" return end
  for _, k in ipairs(DEVICE_KEYS) do
    if wml.key_down(k) then device = "keys" return end
  end
  if (M.pad & ~pad_prev) ~= 0 then device = "pad" end
end

function M.input(ctx, tick)
  M.tick = tick
  -- What your character can do right now, for the Pose and Action counts.
  if M.open and (M.refresh_now or tick % 50 == 1) then M.refresh_now = false; pcall(F.refresh_usable, ctx) end
  if tick % 100 == 0 then check_dll() end
  track_taps()
  track_device()
  -- Open / close.
  if KEY.open ~= "" and wml.key_pressed(KEY.open) then set_open(not M.open) end
  if combo_press ~= 0 and (M.pad & combo_hold) == combo_hold and (M.pad & combo_press) ~= 0 and (pad_prev & combo_press) == 0 then
    set_open(not M.open)
  end
  if M.open then
    if wml.key_pressed(KEY.back) or pad_hit(PAD.B) then
      set_open(false)
    else
      if repeating("up", wml.key_down(KEY.up) or pad_down(PAD.UP)) then move(-1) end
      if repeating("down", wml.key_down(KEY.down) or pad_down(PAD.DOWN)) then move(1) end
      if repeating("left", wml.key_down(KEY.left) or pad_down(PAD.LEFT)) then adjust(ctx, -1) end
      if repeating("right", wml.key_down(KEY.right) or pad_down(PAD.RIGHT)) then adjust(ctx, 1) end
      if wml.key_pressed(KEY.enter) or pad_hit(PAD.A) then activate(ctx) end
      if wml.key_pressed(KEY.prev) or pad_hit(PAD.LB) then switch_tab(-1) end
      if wml.key_pressed(KEY.next) or pad_hit(PAD.RB) then switch_tab(1) end
    end
  end
  pad_prev = M.pad
end

-- Called from the controller-read hook with the buttons word and the two
-- triggers. Returns true when the game should see no input at all (menu
-- open), else a mask of PAD bits to hide from the game: the combo's last
-- button while the held ones are down, and whatever was still held when the
-- menu closed, until it is let go.
function M.controller(buttons, lt, rt)
  local pad = buttons | ((lt or 0) >= TRIGGER_PRESSED and PAD.LT or 0) | ((rt or 0) >= TRIGGER_PRESSED and PAD.RT or 0)
  M.pad = pad
  if M.open and block_input then
    swallow = pad
    return true, 0
  end
  swallow = swallow & pad
  if combo_press ~= 0 and (pad & combo_hold) == combo_hold then swallow = swallow | (pad & combo_press) end
  return false, swallow
end

-- ------------------------------------------------------------- drawing
local function pad_right(s, n)
  if #s >= n then return s end
  return s .. string.rep(" ", n - #s)
end

-- Help text goes under the rows a whole sentence at a time, up to
-- HELP_WIDTH characters a line; a sentence longer than that breaks at a
-- space.
local HELP_WIDTH = 90
local function wrap_help(text)
  local out, line = {}, ""
  local function flush() if line ~= "" then out[#out + 1] = line; line = "" end end
  for sentence in (text:gsub("([%.!?])%s+", "%1\n") .. "\n"):gmatch("(.-)\n") do
    if sentence ~= "" then
      if #sentence > HELP_WIDTH then
        flush()
        for word in sentence:gmatch("%S+") do
          if line ~= "" and #line + 1 + #word > HELP_WIDTH then flush() end
          line = line == "" and word or (line .. " " .. word)
        end
        flush()
      elseif line ~= "" and #line + 1 + #sentence > HELP_WIDTH then
        flush()
        line = sentence
      else
        line = line == "" and sentence or (line .. " " .. sentence)
      end
    end
  end
  flush()
  return out
end
M.wrap_help = wrap_help

function M.render(tick)
  if not M.dll then return end
  if not M.open then return end
  local lines = {}
  local tabs = {}
  for i, cat in ipairs(F.categories) do
    tabs[#tabs + 1] = (i == M.tab) and ("[ " .. cat.name .. " ]") or ("  " .. cat.name .. "  ")
  end
  lines[#lines + 1] = "SR TWEAK MENU" .. (F.enabled and "" or "   (all tweaks OFF)")
  lines[#lines + 1] = table.concat(tabs, " ")
  lines[#lines + 1] = ""
  local cat = F.categories[M.tab]
  local s = M.scroll[M.tab]
  local e = math.min(#cat.items, s + ROWS - 1)
  if s > 1 then lines[#lines + 1] = "    ..." end
  for i = s, e do
    local it = cat.items[i]
    local cursor = (i == M.cursor[M.tab]) and "> " or "  "
    local value = F.value_text(it)
    if it.kind == "action" then value = "" end
    if it.kind == "list" then
      value = (it.ok and #it.ok == 0) and "< none available >" or (F.value_text(it) .. "   " .. F.list_position(it))
    end
    lines[#lines + 1] = cursor .. pad_right(it.label, 32) .. value
  end
  if e < #cat.items then lines[#lines + 1] = "    ..." end
  lines[#lines + 1] = ""
  local it = current_item()
  local help = it.help or ""
  if it.kind == "value" then help = help .. (help ~= "" and "  " or "") .. "Default " .. it.fmt(it.default) .. "." end
  for _, l in ipairs(wrap_help(help)) do lines[#lines + 1] = l end
  if device == "pad" then
    lines[#lines + 1] = "D-pad move   Left/Right adjust   A select   LB/RB tab   B close" .. (combo_text ~= "" and ("   " .. combo_text .. " close") or "")
  else
    lines[#lines + 1] = "Up/Down move   Left/Right adjust   Enter select   PgUp/PgDn tab   " .. KEY.open .. " close"
  end
  if M.status ~= "" and tick < M.status_until then lines[#lines + 1] = M.status end
  mailbox_write(table.concat(lines, "\n"))
end

function M.is_open() return M.open end

return M
