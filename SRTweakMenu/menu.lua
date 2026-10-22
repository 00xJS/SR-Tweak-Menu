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
-- Two looks (Settings > Menu look, menu_style in mod.ini): the plain overlay
-- text, silent, or itsMJQ's game look - the menu drawn with the game's own
-- interface (gameui.lua: its fonts, menu pictures and sounds).
local GAMEUI = require("gameui")
local style_game = tostring(S("menu_style", "text")):lower() == "game"
local UI = setmetatable({ sound = function(ctx, name) if style_game then GAMEUI.sound(ctx, name) end end }, { __index = GAMEUI })

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
local HOLD = require("hold_button")
local back_hold = HOLD.new(math.max(0.3, tonumber(S("menu_hold_seconds", 0.8)) or 0.8))
local hold_enabled = S("menu_hold_back", true)
function M.reset_controller()
  M.pad, M.hold_toggle = 0, false
  back_hold.started, back_hold.fired, back_hold.tap, back_hold.blocked = nil, nil, nil, true
end

for i = 1, #F.categories do M.cursor[i] = 1; M.scroll[i] = 1 end

local swallow = 0   -- pad bits held when the menu closed, hidden until let go
local tap_armed, tapped = 0, 0  -- see track_taps
local device = "keys"  -- what the hints at the bottom name: "keys" or "pad"

local function say(text)
  if not text then return end
  M.status, M.status_until = text, M.tick + 150
  if not M.dll then G.hud(text) end
end

-- Rows and tabs that only apply sometimes (it.hidden / cat.hidden: the
-- Customize rows for someone else, or for you) are left out.
local function shown(x)
  if not x.hidden then return true end
  local ok, hidden = pcall(x.hidden)
  return not (ok and hidden)
end
local function rows(tab)
  local cat = F.categories[tab]
  F.rows_tab = cat.name   -- (a row in two tabs shows in the one that fits)
  local list = {}
  for _, it in ipairs(cat.items) do if shown(it) then list[#list + 1] = it end end
  return list, cat
end
M.rows = rows
local function step_tab(from, dir)
  local n = #F.categories
  local t = from
  for _ = 1, n do
    t = ((t - 1 + dir) % n) + 1
    if shown(F.categories[t]) then return t end
  end
  return from
end
M.step_tab = step_tab

-- Pages: a row of kind "page" opens one (it.open(ctx, p) gives { title,
-- rows, back }), like the stores' and the creator's menus: a list of
-- categories, then what's in one, then its colours. B goes back a page
-- (page.back runs first: a store puts back what you only tried on); LB / RB
-- and closing the menu leave them all. Each page keeps its own cursor.
M.pages = {}
local function page() return M.pages[#M.pages] end
local function view_rows()
  local pg = page()
  if not pg then return rows(M.tab) end
  F.rows_tab = "page"
  local list = {}
  for _, it in ipairs(pg.rows) do if shown(it) then list[#list + 1] = it end end
  return list, F.categories[M.tab]
end
M.view_rows = view_rows
local function cursor() local pg = page() if pg then return pg.cursor end return M.cursor[M.tab] end
local function scroll() local pg = page() if pg then return pg.scroll end return M.scroll[M.tab] end
local function set_view(c, s)
  local pg = page()
  if pg then pg.cursor, pg.scroll = c, s or pg.scroll else M.cursor[M.tab], M.scroll[M.tab] = c, s or M.scroll[M.tab] end
end
local function push_page(pg)
  pg.cursor, pg.scroll = pg.cursor or 1, 1
  M.pages[#M.pages + 1] = pg
  -- (headings aren't rows you can be on)
  local list = view_rows()
  local c = pg.cursor
  while list[c] and list[c].kind == "header" and c < #list do c = c + 1 end
  set_view(c, math.max(1, c - ROWS + 1))
end
local function pop_page(ctx, why)
  local pg = table.remove(M.pages)
  if pg and pg.back then pcall(pg.back, ctx, why) end
  return pg
end
local function leave_pages(ctx, why) while #M.pages > 0 do pop_page(ctx, why) end end
M.leave_pages = leave_pages
-- B on a page with something tried and not accepted asks first, like the
-- game's own customization screens: Yes keeps it, No puts back what you
-- had, B again stays.
local SAVE_TEXT = "Do you want to save your changes before exiting?"
local function back_page(ctx)
  local pg = page()
  local ok, dirty = true, false
  if pg.dirty and not pg.confirm then ok, dirty = pcall(pg.dirty) end
  if not (ok and dirty) then
    pop_page(ctx, "back")
    UI.sound(ctx, "back")
    return
  end
  UI.sound(ctx, "popup")
  push_page({ title = "Save Changes", confirm = true, rows = {
    { label = "Yes", kind = "action", help = SAVE_TEXT, run = function(c)
        pop_page(c, "confirm")
        if pg.accept then pcall(pg.accept, c) end
        pop_page(c, "back")
        return "Changes saved"
      end },
    { label = "No", kind = "action", help = SAVE_TEXT, run = function(c)
        pop_page(c, "confirm")
        pop_page(c, "back")
        return "Changes discarded"
      end },
  } })
end
M.back_page = back_page

local function current_item()
  local list, cat = view_rows()
  local c = math.max(1, math.min(cursor(), #list))
  return list[c] or cat.items[1], cat
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
local function set_open(open, how)
  if open == M.open then return end
  M.open = open
  M.free_move = false
  for _, k in ipairs(TAKEN) do wml.take_key(k, open) end
  tap_armed = 0
  UI.sound(M.ctx, open and "pause" or (how == "back" and "back" or "resume"))
  if open then
    check_dll()
    M.refresh_now = true
    say(M.dll and "" or "Menu open (no overlay): " .. current_item().label)
  else
    leave_pages(M.ctx, "close")
    last_text = nil
    if M.dll then mailbox_write("") end
  end
end

-- ------------------------------------------------------------- navigation
local function move(dir)
  local list = view_rows()
  local n = math.max(1, #list)
  local c = math.min(cursor(), n)
  for _ = 1, n do
    c = ((c - 1 + dir) % n) + 1
    if not (list[c] and list[c].kind == "header") then break end
  end
  UI.sound(M.ctx, "scroll")
  local s = scroll()
  if c < s then s = c end
  if c >= s + ROWS then s = c - ROWS + 1 end
  -- (a heading just above the top row stays in sight)
  if c == s and c > 1 and list[c - 1] and list[c - 1].kind == "header" then s = c - 1 end
  set_view(c, s)
  -- A row that shows itself when you land on it (a store's piece tried on).
  local on = list[c]
  if on and on.hover then
    local ok, err = pcall(on.hover, M.ctx, G.player(), on)
    if not ok then wml.log("hover " .. tostring(on.label) .. ": " .. tostring(err)) end
  end
  if not M.dll then
    local it = current_item()
    say(it.label .. " " .. F.value_text(it))
  end
end

local function switch_tab(dir)
  leave_pages(M.ctx, "tab")
  M.tab = step_tab(M.tab, dir)
  UI.sound(M.ctx, "lr")
  if not M.dll then say("Tab: " .. F.categories[M.tab].name) end
end

local slide
local function adjust(ctx, dir)
  local it = current_item()
  if it.kind == "value" or it.kind == "choice" or it.kind == "list" then
    UI.sound(ctx, "lr")
    say(F.adjust(ctx, it, dir, wml.key_down(KEY.fast)))
  elseif it.kind == "toggle" then
    say(F.toggle(ctx, it))
    M.toggle_sound(ctx, it)
  end
end

-- A slider (Image As Designed's, the pause menu's): held, it glides - slowly
-- at first, faster the longer it's held - with one sound as it starts, none
-- for each step, and stops at either end.
local sliding = nil
function slide(ctx, it, dir)  -- (the local declared above)
  if dir == 0 or not it then sliding = nil return end
  local now = os.clock()
  if not sliding or sliding.it ~= it or sliding.dir ~= dir then
    sliding = { it = it, dir = dir, start = now, last = now }
    if (dir < 0 and it.v > it.min) or (dir > 0 and it.v < it.max) then UI.sound(ctx, "lr") end
  end
  local dt = math.min(0.05, now - sliding.last)
  sliding.last = now
  local held = now - sliding.start
  -- (a touch moves it one step; held, from 10 a second up to 90 after ~1.5 s)
  local range = it.max - it.min
  local speed = range * (0.10 + 0.80 * math.min(1, held / 1.5) ^ 2)
  if wml.key_down(KEY.fast) then speed = speed * 2 end
  local step = held == 0 and (it.step or 1) or speed * dt
  local nv = math.max(it.min, math.min(it.max, it.v + dir * step))
  if nv == it.v then return end
  it.v = nv
  local p = G.player()
  if it.change and (p ~= 0 or it.needs == "none") then pcall(it.change, ctx, p, 0, it) end
end
M.slide = function(ctx, it, dir) return slide(ctx, it, dir) end

-- Toggles answer like the pause menu's Yes / No; the master switch like Quit.
function M.toggle_sound(ctx, it)
  if it.id == "master" then UI.sound(ctx, it.v and "okay" or "quit")
  else UI.sound(ctx, it.v and "yes" or "no") end
end
local FAILED = { "^no ", "^can't", "^couldn't", "^not ", "^that ", "^too many", "^change into", "^get in", "^load a",
  "^already", "can't ", "isn't ", " first$", "won't ", "didn't ", "^error", "^nothing", "^none" }
function M.failed(msg)
  if type(msg) ~= "string" then return false end
  local m = msg:lower()
  for _, p in ipairs(FAILED) do if m:find(p) then return true end end
  return false
end

local function activate(ctx)
  -- Lists act on the entry shown on the row (picked with Left/Right).
  local it = current_item()
  if it.kind == "header" then return end
  if it.kind == "page" then
    local p = G.player()
    if p == 0 then UI.sound(ctx, "error"); say("Load a game first") return end
    local ok, pg = pcall(it.open, ctx, p, it)
    if not ok then wml.log("page " .. tostring(it.id or it.label) .. ": " .. tostring(pg)); UI.sound(ctx, "error"); say("Error, see wml.log") return end
    if type(pg) == "string" then UI.sound(ctx, "error"); say(pg) return end
    UI.sound(ctx, "select")
    push_page(pg)
    return
  end
  if it.kind == "toggle" then
    say(F.activate(ctx, it))
    M.toggle_sound(ctx, it)
    return
  end
  UI.sound(ctx, "select")
  local result = F.activate(ctx, it)
  -- (a page that wants the cursor somewhere next: after a colour, its wear option)
  local pg = page()
  if pg and pg.focus then set_view(pg.focus, 1); pg.focus = nil end
  -- (an answer that closes pages: Yes / No on overwriting or deleting a preset)
  for i = #M.pages, 1, -1 do
    local q = M.pages[i]
    if q.close_after then
      local n = q.close_after
      q.close_after = nil
      for _ = 1, n do pop_page(ctx, "done") end
      break
    end
  end
  -- The pause menu's answers: an error beep when it couldn't be done, the
  -- shop's sound for money, weapons and ammo, OK for the rest that did something.
  if M.failed(result) then UI.sound(ctx, "error")
  elseif it.id and (it.id:find("cash") or it.id:find("respect") or it.id:find("weapon") or it.id:find("ammo") or it.id:find("refill")) then
    UI.sound(ctx, "purchase")
  elseif it.kind == "action" then UI.sound(ctx, "okay") end
  say(result)
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
  M.tick, M.ctx = tick, ctx
  -- A tab that stopped applying (Customize as someone with no options) is
  -- left; rows that came and went keep the cursor on one that's there.
  if not shown(F.categories[M.tab]) then M.tab = step_tab(M.tab, 1) end
  if #M.pages > 0 and not shown(F.categories[M.tab]) then leave_pages(ctx, "gone") end
  local n_rows = math.max(1, #view_rows())
  if cursor() > n_rows then set_view(n_rows) end
  if scroll() > cursor() then set_view(cursor(), cursor()) end
  -- What your character can do right now, for the Pose and Action counts.
  if M.open and (M.refresh_now or tick % 50 == 1) then M.refresh_now = false; pcall(F.refresh_usable, ctx) end
  if tick % 100 == 0 then check_dll() end
  track_taps()
  track_device()
  -- Open / close.
  if M.hold_toggle then
    M.hold_toggle = false
    set_open(not M.open)
  end
  if KEY.open ~= "" and wml.key_pressed(KEY.open) then set_open(not M.open) end
  if combo_press ~= 0 and (M.pad & combo_hold) == combo_hold and (M.pad & combo_press) ~= 0 and (pad_prev & combo_press) == 0 then
    set_open(not M.open)
  end
  if M.open then
    if (wml.key_pressed(KEY.back) or pad_hit(PAD.B)) and #M.pages > 0 then
      back_page(ctx)
    elseif wml.key_pressed(KEY.back) or pad_hit(PAD.B) then
      set_open(false, "back")
    else
      if repeating("up", wml.key_down(KEY.up) or pad_down(PAD.UP)) then move(-1) end
      if repeating("down", wml.key_down(KEY.down) or pad_down(PAD.DOWN)) then move(1) end
      local it = current_item()
      local l, r = wml.key_down(KEY.left) or pad_down(PAD.LEFT), wml.key_down(KEY.right) or pad_down(PAD.RIGHT)
      if it.kind == "value" and it.bar then
        slide(ctx, it, (r and 1 or 0) - (l and 1 or 0))
      else
        slide(ctx, nil, 0)
        if repeating("left", l) then adjust(ctx, -1) end
        if repeating("right", r) then adjust(ctx, 1) end
      end
      if wml.key_pressed(KEY.enter) or pad_hit(PAD.A) then activate(ctx) end
      if wml.key_pressed(KEY.prev) or pad_hit(PAD.LB) then switch_tab(-1) end
      if wml.key_pressed(KEY.next) or pad_hit(PAD.RB) then switch_tab(1) end
    end
  end
  M.update_free_move()
  pad_prev = M.pad
end

-- Called from the controller-read hook with the buttons word and the two
-- triggers. Returns true when the game should see no input at all (menu
-- open), else a mask of PAD bits to hide from the game: the combo's last
-- button while the held ones are down, and whatever was still held when the
-- menu closed, until it is let go.
-- True while the menu combo is being pressed (its held buttons and its last one).
function M.combo_down(buttons)
  return combo_hold ~= 0 and (buttons & combo_hold) == combo_hold and (buttons & combo_press) ~= 0
end
-- Moving with the menu open: everywhere but Customize (and a vehicle's
-- customizing), the game keeps the sticks, triggers and other buttons - you
-- walk, run and drive - while the D-pad, A, B, LB, RB, Start and Back (and
-- the arrows, Enter and Backspace) are the menu's.
local NAV_MASK = PAD.UP | PAD.DOWN | PAD.LEFT | PAD.RIGHT | PAD.A | PAD.B | PAD.LB | PAD.RB | PAD.START | PAD.BACK
local MENU_KEYS = { UP = true, DOWN = true, LEFT = true, RIGHT = true, ENTER = true, BACKSPACE = true }
M.free_move = false
-- Emotes: moving when you go to the tab, you keep moving (the game's camera
-- follows you); standing still, the camera goes round you and the stick turns
-- it. Either way you're held while an emote plays.
M.emote_free = false
local moving, last_pos, emote_tab = 0, nil, false
function M.emote_playing() return (F.posing or F.looping or F.repeating) ~= nil end
local function track_moving()
  local p = G.player()
  if p == 0 then moving, last_pos = 0, nil return end
  local x, _, z = G.vec(p + G.P.POS)
  local moved = last_pos and ((x - last_pos[1]) ^ 2 + (z - last_pos[2]) ^ 2) > 0.0004
  last_pos = { x, z }
  moving = moved and 10 or math.max(0, moving - 1)
end
local function free_move_now()
  if not M.open or not block_input then return false end
  local tab = F.categories[M.tab].name
  if tab == "Customize" then return false end
  local pg = M.pages[1]
  if pg and pg.vehicle then return false end
  if tab == "Emotes" then return M.emote_free and not M.emote_playing() end
  return true
end
local function update_free_move()
  track_moving()
  local on_emotes = M.open and F.categories[M.tab].name == "Emotes"
  if on_emotes and not emote_tab then M.emote_free = moving > 0 end
  emote_tab = on_emotes
  local want = free_move_now()
  if want == M.free_move then return end
  M.free_move = want
  for _, k in ipairs(TAKEN) do
    if not MENU_KEYS[k] then wml.take_key(k, M.open and not want) end
  end
end
M.update_free_move = update_free_move

function M.controller(buttons, lt, rt)
  local pad = buttons | ((lt or 0) >= TRIGGER_PRESSED and PAD.LT or 0) | ((rt or 0) >= TRIGGER_PRESSED and PAD.RT or 0)
  M.pad = pad
  local replay, held_back = 0, false
  if hold_enabled then
    local toggle, tap, hide = HOLD.update(back_hold, (pad & PAD.BACK) ~= 0, os.clock(),
      M.open or G.playing(G.player()), M.open)
    if toggle then M.hold_toggle = true end
    replay, held_back = tap and PAD.BACK or 0, hide
  end
  if M.open and block_input and M.free_move then
    swallow = (swallow & pad) | (pad & NAV_MASK)   -- (still hidden once it closes, until let go)
    return false, swallow
  end
  if M.open and block_input then
    swallow = pad
    return true, 0
  end
  swallow = swallow & pad
  if combo_press ~= 0 and (pad & combo_hold) == combo_hold then swallow = swallow | (pad & combo_press) end
  if held_back then swallow = swallow | PAD.BACK end
  return false, swallow, replay
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
local STATUS_LINES = 4
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

-- ------------------------------------------------------------- game look
--
-- The menu in the game's own interface (gameui.lua): tabs like the pause
-- menu's (LB / RB, the one you're on in gold), the dark menu box with its
-- fleur-de-lis ornaments, rows in px_thin with the gold bar on the one
-- selected, arrows round values you can change, a scroll bar, the
-- description under the box and the buttons to press. Laid out in 1280 x 720
-- units from the top left (menu_x, menu_y), all sizes times menu_scale.
-- (itsMJQ's, from 1.9.11; Settings > Menu look picks it or the plain text.)
local MX, MY = S("menu_x", 36), S("menu_y", 36)
local K = math.max(0.5, math.min(2.0, S("menu_scale", 1.0)))
local W = 470
local GOLD, WHITE, GREY, DIM = { 255, 196, 64, 255 }, { 255, 255, 255, 255 }, { 200, 200, 200, 255 }, { 140, 140, 140, 255 }
local BLACK = { 0, 0, 0, 255 }

-- The text, shortened with "..." to fit `room` layout units, and its width.
local function fit(ctx, font, size, text, room)
  local w = UI.width(ctx, font, text) * size
  if w <= room then return text, w end
  while #text > 1 do
    text = text:sub(1, -2)
    w = UI.width(ctx, font, text .. "...") * size
    if w <= room then return text .. "...", w end
  end
  return text, w
end

function M.build_frame(ctx)
  local fr = {}
  local function quad(image, x, y, w, h, colour, extra)
    local op = { image = image, x = x, y = y, w = w, h = h, colour = colour }
    if extra then for k, v in pairs(extra) do op[k] = v end end
    fr[#fr + 1] = op
  end
  local function text(font, size, s, x, y, colour)
    fr[#fr + 1] = { text = s, font = font, size = size, x = x, y = y, colour = colour }
  end
  -- Sizes: text heights in layout units, whatever the fonts' own sizes are.
  local heading = 26 * K / UI.line_height("giant")
  local row_size = 19 * K / UI.line_height("thin")
  local help_size = 16 * K / UI.line_height("thin")
  local w = W * K
  local x0, y = MX, MY
  local cat = F.categories[M.tab]
  local list = view_rows()
  local n = #F.categories
  -- Tabs: LB, the one before, the one you're on, the one after, RB.
  local tab_h = 34 * K
  quad("ui_menu_box_base_c", x0, y, w, tab_h, { 128, 128, 128, 200 })
  quad("ui_menu_box_edge", x0, y + tab_h - 3 * K, w, 3 * K)
  local prev_name = F.categories[step_tab(M.tab, -1)].name:upper()
  local next_name = F.categories[step_tab(M.tab, 1)].name:upper()
  local cur_name = cat.name:upper()
  local pad = device == "pad"
  local lb, rb = pad and "control_lb" or nil, pad and "control_rb" or nil
  local cx = x0 + w / 2
  local cur_w = UI.width(ctx, "giant", cur_name) * heading
  text("giant", heading, cur_name, cx - cur_w / 2, y + 4 * K, GOLD)
  local side = 13 * K / UI.line_height("giant") * 1.4
  local pw = UI.width(ctx, "giant", prev_name) * side
  text("giant", side, prev_name, cx - cur_w / 2 - 18 * K - pw, y + 9 * K, DIM)
  text("giant", side, next_name, cx + cur_w / 2 + 18 * K, y + 9 * K, DIM)
  if pad then
    quad(lb, x0 + 4 * K, y + 3 * K, 38 * K, 29 * K)
    quad(rb, x0 + w - 42 * K, y + 3 * K, 38 * K, 29 * K)
  else
    text("thin", help_size, "PGUP", x0 + 8 * K, y + 9 * K, DIM)
    local pw2 = UI.width(ctx, "thin", "PGDN") * help_size
    text("thin", help_size, "PGDN", x0 + w - 8 * K - pw2, y + 9 * K, DIM)
  end
  y = y + tab_h + 6 * K
  -- The box: dark base, ornaments top and bottom, heading, rows, scroll bar.
  local rows_shown = math.min(ROWS, #list)
  local row_h = 28 * K
  local head_h = 46 * K
  local box_h = head_h + rows_shown * row_h + 18 * K
  quad("ui_menu_box_base_c", x0, y, w, box_h, { 128, 128, 128, 215 })
  quad("ui_menu_box_edge", x0, y, w, 3 * K)
  quad("ui_menu_box_edge", x0, y + box_h - 3 * K, w, 3 * K, nil, { flip_v = true })
  local orn_w, orn_h = 220 * K, 41 * K
  quad("ui_menu_ornate_0", cx - orn_w / 2, y - 14 * K, orn_w, orn_h)
  quad("ui_menu_ornate_0", cx - orn_w / 2, y + box_h - orn_h + 14 * K, orn_w, orn_h, nil, { flip_v = true })
  local box = (cat.title or cat.name):upper()   -- (the box can name the tab's contents: CHARACTER in Customize)
  local title = page() and page().title:upper() or (F.enabled and box or (box .. " (ALL OFF)"))
  local tw = UI.width(ctx, "giant", title) * heading
  text("giant", heading, title, cx - tw / 2, y + 12 * K, GOLD)
  quad("ui_menu_hr", x0 + 12 * K, y + head_h - 4 * K, w - 24 * K, 2 * K)
  local s, e = scroll(), math.min(#list, scroll() + ROWS - 1)
  local ry = y + head_h
  local inner = w - 40 * K
  for i = s, e do
    local it = list[i]
    local selected = i == cursor()
    -- (on the gold bar the text is black, as in the game's menus)
    local ON = selected and BLACK or nil
    if it.kind == "header" then
      -- A heading: in the tab titles' font, gold, centred, with the rule under it.
      local hs = 21 * K / UI.line_height("giant")
      local hw = UI.width(ctx, "giant", it.label:upper()) * hs
      text("giant", hs, it.label:upper(), cx - hw / 2, ry + (row_h - 21 * K) / 2, GOLD)
      quad("ui_menu_hr", x0 + 40 * K, ry + row_h - 3 * K, w - 80 * K, 2 * K)
      ry = ry + row_h
      goto next_row
    end
    if selected then quad("ui_menu_text_selected", x0 + 10 * K, ry + 2 * K, inner + 6 * K, row_h - 4 * K) end
    local value = F.value_text(it)
    if it.kind == "action" then value = it.note and it.note() or "" end
    if it.kind == "list" then
      value = (it.ok and #it.ok == 0) and "none available" or it.items[it.v][2]
    elseif it.kind == "toggle" then
      value = it.v and "ON" or "OFF"
    elseif value:sub(1, 2) == "< " then
      value = value:sub(3, -3)
    end
    local changeable = it.kind == "value" or it.kind == "choice" or it.kind == "list" or it.kind == "toggle"
    local label_room = inner * 0.55
    local label = fit(ctx, "thin", row_size, it.label, label_room)
    local ty = ry + (row_h - 19 * K) / 2 - 1 * K
    text("thin", row_size, label, x0 + 18 * K, ty, ON or GREY)
    if it.kind == "page" then
      -- Opens a page: the arrow the game puts on a menu entry with more under it.
      quad("ui_menu_arrow_right", x0 + 10 * K + inner - 18 * K, ry + 6 * K, 11 * K, 15 * K, ON or GREY)
    elseif it.kind == "value" and it.bar then
      -- A slider like the creator's: the bar, filled to the value, the knob on it.
      local frac = (it.v - it.min) / math.max(1e-9, it.max - it.min)
      if it.live and it.read then
        local p = G.player()
        local ok, r = pcall(it.read, p)
        if ok and r then frac = (r - it.min) / math.max(1e-9, it.max - it.min) end
      end
      frac = math.max(0, math.min(1, frac))
      local bw, bh = inner * 0.40, 12 * K
      local bx, by = x0 + 10 * K + inner - bw - 22 * K, ry + (row_h - bh) / 2
      quad("ui_menu_slide_base_deselected", bx, by, bw, bh)
      quad("ui_menu_slide_base_selected", bx, by, bw * frac, bh, selected and nil or { 200, 200, 200, 255 })
      quad("ui_menu_slide_base_border", bx - 2 * K, by - 2 * K, bw + 4 * K, bh + 4 * K)
      quad("ui_menu_slide_base_control", bx + bw * frac - 6 * K, by - 4 * K, 12 * K, bh + 8 * K)
      if selected then
        quad("ui_menu_arrow_left", bx - 18 * K, ry + 6 * K, 11 * K, 15 * K)
        quad("ui_menu_arrow_right", bx + bw + 7 * K, ry + 6 * K, 11 * K, 15 * K)
      end
    elseif value ~= "" then
      local arrows = selected and changeable
      local room = inner - label_room - (arrows and 34 * K or 6 * K)
      local v, vw = fit(ctx, "thin", row_size, value, room)
      local right = x0 + 10 * K + inner - (arrows and 18 * K or 4 * K)
      text("thin", row_size, v, right - vw, ty, ON or (it.kind == "action" and GOLD) or (it.kind == "toggle" and it.v and GOLD or GREY))
      if arrows then
        quad("ui_menu_arrow_left", right - vw - 16 * K, ry + 6 * K, 11 * K, 15 * K)
        quad("ui_menu_arrow_right", right + 4 * K, ry + 6 * K, 11 * K, 15 * K)
      end
    end
    ry = ry + row_h
    ::next_row::
  end
  -- Scroll bar when the rows don't all fit.
  if #list > ROWS then
    local sx, sy, sh = x0 + w - 24 * K, y + head_h + 2 * K, rows_shown * row_h - 4 * K
    quad("ui_menu_scroll_base_top", sx, sy, 14 * K, 4 * K)
    quad("ui_menu_scroll_base_mid", sx, sy + 4 * K, 14 * K, sh - 8 * K)
    quad("ui_menu_scroll_base_bottom", sx, sy + sh - 4 * K, 14 * K, 4 * K)
    local frac = ROWS / #list
    local th = math.max(14 * K, sh * frac)
    local pos = (scroll() - 1) / math.max(1, #list - ROWS)
    quad("ui_menu_scroll_bar", sx + 2 * K, sy + (sh - th) * pos, 10 * K, th)
  end
  y = y + box_h + 8 * K
  -- The description, then the buttons.
  local it = current_item()
  local help = it.help or ""
  if it.kind == "value" and help ~= "" and not it.bar then help = help .. "  Default " .. it.fmt(it.default) .. "." end
  local lines = wrap_help(help)
  -- Messages first, in gold, wrapped like the help (at most STATUS_LINES).
  local status_n = 0
  if M.status ~= "" and M.tick < M.status_until then
    local wrapped = wrap_help(M.status)
    status_n = math.min(#wrapped, STATUS_LINES)
    for k = status_n, 1, -1 do table.insert(lines, 1, wrapped[k]) end
  end
  local line_h = 19 * K
  local help_h = (#lines + 1) * line_h + 14 * K
  quad("ui_menu_box_base_c", x0, y, w, help_h, { 128, 128, 128, 190 })
  local hy = y + 6 * K
  for li, l in ipairs(lines) do
    local shown = fit(ctx, "thin", help_size, l, w - 24 * K)
    text("thin", help_size, shown, x0 + 12 * K, hy, li <= status_n and GOLD or GREY)
    hy = hy + line_h
  end
  -- Buttons.
  local bx = x0 + 12 * K
  local function hint(image, label)
    if image then
      quad(image, bx, hy - 2 * K, 22 * K, 23 * K)
      bx = bx + 25 * K
    end
    text("thin", help_size, label, bx, hy, WHITE)
    bx = bx + UI.width(ctx, "thin", label) * help_size + 14 * K
  end
  if pad then
    hint("a_button", page() and "ACCEPT" or "SELECT"); hint("b_button", "BACK"); hint("control_dpad", "MOVE / CHANGE")
  else
    hint(nil, page() and "ENTER ACCEPT" or "ENTER SELECT"); hint(nil, "BACKSPACE BACK"); hint(nil, "ARROWS MOVE / CHANGE"); hint(nil, KEY.open .. " CLOSE")
  end
  return fr
end

-- "game" (the game's interface) or "text" (plain overlay text); live.
function M.set_style(name)
  style_game = name == "game"
  GAMEUI.ok = true
  if not style_game then GAMEUI.frame = nil end
end
function M.style() return style_game and "game" or "text" end

function M.render(tick)
  if M.open and style_game and GAMEUI.ready() and M.ctx then
    local ok, fr = pcall(M.build_frame, M.ctx)
    if ok then
      GAMEUI.frame = fr
      if M.dll and last_text ~= "" then mailbox_write("") end
      return
    end
    wml.log("menu (game look): " .. tostring(fr) .. "; plain text menu instead")
    style_game = false
  end
  GAMEUI.frame = nil
  if not M.dll then return end
  if not M.open then return end
  local lines = {}
  local tabs = {}
  for i, cat in ipairs(F.categories) do
    if shown(cat) then tabs[#tabs + 1] = (i == M.tab) and ("[" .. cat.name .. "]") or cat.name end
  end
  -- (tight, so all ten tabs fit the same 90 characters as the help)
  lines[#lines + 1] = "SR TWEAK MENU" .. (F.enabled and "" or "   (all tweaks OFF)")
  lines[#lines + 1] = table.concat(tabs, "  ")
  lines[#lines + 1] = ""
  local cat = F.categories[M.tab]
  local list = view_rows()
  if page() then lines[#lines + 1] = "> " .. page().title:upper() end
  local s = scroll()
  local e = math.min(#list, s + ROWS - 1)
  if s > 1 then lines[#lines + 1] = "    ..." end
  for i = s, e do
    local it = list[i]
    local mark = (i == cursor()) and "> " or "  "
    local value = F.value_text(it)
    if it.kind == "action" then value = it.note and it.note() or "" end
    if it.kind == "list" then
      value = (it.ok and #it.ok == 0) and "< none available >" or (F.value_text(it) .. "   " .. F.list_position(it))
    end
    if it.kind == "page" then value = ">" end
    if it.kind == "header" then lines[#lines + 1] = "  -- " .. it.label:upper() .. " --"
    else lines[#lines + 1] = mark .. pad_right(it.label, 32) .. value end
  end
  if e < #list then lines[#lines + 1] = "    ..." end
  lines[#lines + 1] = ""
  local it = current_item()
  local help = it.help or ""
  if it.kind == "value" and help ~= "" and not it.bar then help = help .. "  Default " .. it.fmt(it.default) .. "." end
  for _, l in ipairs(wrap_help(help)) do lines[#lines + 1] = l end
  if device == "pad" then
    lines[#lines + 1] = "D-pad move   Left/Right adjust   A select   LB/RB tab   B close" .. (combo_text ~= "" and ("   " .. combo_text .. " close") or "")
  else
    lines[#lines + 1] = "Up/Down move   Left/Right adjust   Enter select   PgUp/PgDn tab   " .. KEY.open .. " close"
  end
  -- Messages wrap like the help (a long "Show active tweaks" list ran off
  -- the screen), at most STATUS_LINES lines.
  if M.status ~= "" and tick < M.status_until then
    local wrapped = wrap_help(M.status)
    for i = 1, math.min(#wrapped, STATUS_LINES) do
      lines[#lines + 1] = (i == STATUS_LINES and #wrapped > STATUS_LINES) and (wrapped[i]:sub(1, HELP_WIDTH - 4) .. " ...") or wrapped[i]
    end
  end
  mailbox_write(table.concat(lines, "\n"))
end

-- Settings > Menu look: the plain text or itsMJQ's game look, switched live
-- and kept in mod.ini (menu_style).
F.add_rows("Settings", "master", {
  { id = "menu_look", label = "Menu look", kind = "choice", needs = "none", options = { "Plain text", "Game style" },
    v = style_game and 2 or 1, nosave = true,
    help = "Plain text, or the game's own menu look (its fonts, gold bar, menu box and sounds) by itsMJQ.",
    change = function(ctx, p, v, it)
      M.set_style(it.v == 2 and "game" or "text")
      if F.ADDONS then F.ADDONS.save_setting(wml.mod_folder .. "/mod.ini", "menu_style", M.style()) end
    end },
})

function M.is_open() return M.open end
function M.current() if not M.open then return nil end local it = current_item() return it end
function M.tab_name() return F.categories[M.tab].name end

return M
