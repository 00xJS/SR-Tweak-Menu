-- Offline test of the runtime mod: a fake wml with fake guest memory, a fake
-- player and car, fake game functions, then main.lua is loaded and the menu
-- is driven through every tab and item. No game needed.
--
--   python -I tools/run_lua.py tools/test_menu.lua [SRTweakMenu]
--
-- Checks that nothing errors, that toggles set and clear the right bits,
-- and prints the rendered menu text as the overlay DLL would show it.

local folder = arg[1] or "SRTweakMenu"
package.path = folder .. "/?.lua;" .. package.path

-- ---------------------------------------------------------------- memory
local mem = {}
local function rd(a) return mem[a] or 0 end
local function wr(a, v) mem[a] = v & 0xFF end
local function read_u8(a) return rd(a) end
local function read_u16(a) return (rd(a) << 8) | rd(a + 1) end
local function read_u32(a) return (rd(a) << 24) | (rd(a + 1) << 16) | (rd(a + 2) << 8) | rd(a + 3) end
local function write_u8(a, v) wr(a, v) end
local function write_u16(a, v) wr(a, v >> 8); wr(a + 1, v) end
local function write_u32(a, v) v = v & 0xFFFFFFFF; wr(a, v >> 24); wr(a + 1, v >> 16); wr(a + 2, v >> 8); wr(a + 3, v) end
local function read_f32(a) return (string.unpack(">f", string.pack(">I4", read_u32(a)))) end
local function write_f32(a, v) write_u32(a, (string.unpack(">I4", string.pack(">f", v)))) end
local function read_cstr(a) local t = {} for i = 0, 1000 do local c = rd(a + i) if c == 0 then break end t[#t + 1] = string.char(c) end return table.concat(t) end

-- ---------------------------------------------------------------- settings
local settings = {}
for line in io.lines(folder .. "/mod.ini") do
  local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
  if k and not line:match("^%s*;") then settings[k] = v end
end

-- ---------------------------------------------------------------- fake wml
local hooks, frame_cbs, keys_down, keys_prev, taken, logs = {}, {}, {}, {}, {}, {}
wml = {
  mod_name = "test", mod_folder = folder,
  log = function(...) local parts = {} for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end logs[#logs + 1] = table.concat(parts, " ") print("[log] " .. logs[#logs]) end,
  setting = function(name, default)
    local v = settings[name]
    if v == nil then return default end
    if type(default) == "number" then return tonumber(v) end
    if type(default) == "boolean" then return v == "true" or v == "1" end
    return v
  end,
  read_u8 = read_u8, read_u16 = read_u16, read_u32 = read_u32, read_f32 = read_f32,
  write_u8 = write_u8, write_u16 = write_u16, write_u32 = write_u32, write_f32 = write_f32,
  key_down = function(k) return keys_down[k:upper()] == true end,
  key_pressed = function(k) k = k:upper() return keys_down[k] == true and not keys_prev[k] end,
  take_key = function(k, on) taken[k:upper()] = (on ~= false) end,
  force_key = function() end,
  on_frame = function(f) frame_cbs[#frame_cbs + 1] = f end,
  hook = function(addr, f) hooks[addr] = f end,
}
wml.settings = settings

-- ---------------------------------------------------------------- game world
local PLAYER_PTR, OBJECTS = 0x8309ABEC, 0x830866C8
local P = 0x40000000          -- fake player object
local V = 0x41000000          -- fake vehicle object
local ENGINE = 0x42000000
local LUA_STATE = 0x43000000
write_u32(PLAYER_PTR, P)
write_u32(P + 72, 1)
write_u32(P + 1908, 1000); write_f32(P + 1912, 400)
write_u32(P + 2320, 500 * 100)
write_u32(P + 3860, 100)
write_u32(0x8370F8C4, LUA_STATE)
write_f32(0x827D099C, 0.85); write_f32(0x827ACF34, 4.5); write_f32(0x827ACE58, 0.2); write_f32(0x827D0988, 1.5)
write_f32(0x827AD060, 1.0); write_f32(0x827AD064, 1.0); write_f32(0x827D6C0C, 1.0); write_f32(0x82B2EF40, 40)
write_u8(0x827AD06C, 1); write_u8(0x827AD06D, 1); write_u8(0x827D95C5, 1)
write_u8(0x82B2EF34, 14)
-- The overlay DLL's mailbox header.
write_u32(0x00F00000, 0x53524D55)

local function put_in_vehicle(on)
  if on then
    local handle = 0x00050007
    write_u32(P + 2496, handle)
    write_u32(OBJECTS + 12 + 7 * 16, V)
    write_u32(V + 68, handle); write_u32(V + 72, 5)
    write_u8(V + 50300, 1); write_u32(V + 224, ENGINE); write_f32(ENGINE + 396, 1.0)
    write_u32(V + 53508, 2000); write_u32(V + 53512, 900)
  else
    write_u32(P + 2496, 0)
  end
end

-- Fake game functions reached through ctx:call.
local calls, hud_texts, scripts, consoles = {}, {}, {}, {}
local FAKE = {
  [0x82367568] = function(ctx)  -- HUD message: UTF-16 at r3
    local a, t = ctx.regs[3], {}
    for i = 0, 300 do local c = read_u16(a + i * 2) if c == 0 then break end t[#t + 1] = string.char(c) end
    hud_texts[#hud_texts + 1] = table.concat(t)
  end,
  [0x824F1C70] = function(ctx) scripts[#scripts + 1] = read_cstr(ctx.regs[4]); ctx.regs[3] = 0 end,
  [0x82626AD8] = function(ctx) consoles[#consoles + 1] = read_cstr(ctx.regs[3]); ctx.regs[3] = 0 end,
  [0x8256A638] = function(ctx) local name = read_cstr(ctx.regs[3]); ctx.regs[3] = name:find("^car_") and 12 or 0xFFFFFFFF end,
  [0x821D2F50] = function(ctx) write_u32(ctx.regs[3] + ctx.regs[4] * 24, math.floor(ctx.fregs[1])) end,
  [0x82114928] = function(ctx) ctx.regs[3] = 0x44000000 end,  -- model definition
  [0x82479AB0] = function(ctx)  -- create a person: check the stack arguments the game expects
    assert(read_u32(ctx.regs[1] + 84) == 0 and read_u16(ctx.regs[1] + 94) == 8, "spawn stack args missing")
    assert(ctx.regs[3] == 3 and ctx.regs[4] == 2 and ctx.regs[5] == 0x44000000 and ctx.regs[8] == 255, "spawn registers wrong")
    assert(math.abs(read_f32(ctx.regs[6] + 4) - 0.5) < 0.01, "spawn position not written")
    people_made = (people_made or 0) + 1
    ctx.regs[3] = 0x45000000
  end,
  [0x824194A8] = function(ctx) ctx.regs[3] = 12 end,
  [0x82569700] = function(ctx)
    assert(read_u32(ctx.regs[1] + 84) == 0 and read_u32(ctx.regs[1] + 100) == 0, "vehicle stack args missing")
    assert(ctx.regs[3] == 3 and ctx.regs[4] == 2 and ctx.regs[5] == 12, "vehicle registers wrong")
    vehicles_made = (vehicles_made or 0) + 1
    ctx.regs[3] = 0x00050009
  end,
  [0x82569630] = function(ctx) ctx.regs[3] = 0x47000000 end,
  [0x823ACF50] = function(ctx) destroyed = (destroyed or 0) + 1 end,
}
write_u32(0x830866C8 + 12 + 9 * 16, 0x47000000); write_u32(0x47000000 + 68, 0x00050009)
write_u32(0x45000000 + 228, 0x46000000); write_u32(0x46000000 + 608, 0x05000001)
write_f32(0x8208978C, 12); write_f32(0x82089998, 26)
local function make_ctx()
  local ctx = { regs = {}, fregs = {} }
  for i = 0, 31 do ctx.regs[i] = 0; ctx.fregs[i] = 0 end
  ctx.regs[1] = 0x7F010000
  function ctx:r(n) return self.regs[n] end
  function ctx:set_r(n, v) self.regs[n] = v end
  function ctx:f(n) return self.fregs[n] end
  function ctx:set_f(n, v) self.fregs[n] = v end
  function ctx:lr() return 0 end
  function ctx:call_original() end
  function ctx:call(addr)
    calls[#calls + 1] = addr
    assert(self.regs[1] < 0x7F010000, "r1 not lowered before a game call")
    local f = FAKE[addr]
    if f then f(self) else self.regs[3] = 0 end
  end
  return ctx
end

-- ---------------------------------------------------------------- run
dofile(folder .. "/main.lua")
assert(hooks[0x82209E30], "update hook missing")
assert(hooks[0x82788EC4], "input hook missing")
assert(hooks[0x824470D0], "damage hook missing")

local tick = 0
local function update(n)
  for _ = 1, (n or 1) do
    tick = tick + 1
    local ctx = make_ctx()
    hooks[0x82209E30](ctx)
    assert(ctx.regs[1] == 0x7F010000, "r1 not restored")
    keys_prev = {}
    for k, v in pairs(keys_down) do keys_prev[k] = v end
  end
end
local function press(key)
  keys_down[key] = true; update(1); keys_down[key] = nil; update(1)
end
local function mailbox_text()
  local n = read_u32(0x00F00014)
  local t = {}
  for i = 0, n - 1 do t[#t + 1] = string.char(rd(0x00F00040 + i)) end
  return table.concat(t)
end

update(5)
press("F5")
assert(taken["UP"] and taken["ENTER"], "menu did not take its keys")
print("---- menu after opening ----"); print(mailbox_text())

local F = require("features")
local G = require("game")

-- Toggle god mode (first row) and check the bit.
press("ENTER"); update(2)
assert(F.items.god.v, "god not on")
assert((read_u32(P + 216) & 0x00100000) ~= 0, "god bit not set")
press("ENTER"); update(2)
assert((read_u32(P + 216) & 0x00100000) == 0, "god bit not cleared")

-- Walk every tab and every item: Left, Right, Enter must never error.
local errors = 0
for t = 1, #F.categories do
  local cat = F.categories[t]
  for i = 1, #cat.items do
    local it = cat.items[i]
    if it.needs == "vehicle" then put_in_vehicle(true) else put_in_vehicle(false) end
    update(2)
    local ok, err = pcall(function()
      if it.kind == "list" then
        -- Lists open a page: browse, pick (runs the item), leave the page.
        press("ENTER"); press("DOWN"); press("RIGHT"); press("ENTER"); press("BACKSPACE")
        assert(require("menu").page == nil, "page still open after Backspace")
      else
        press("RIGHT"); press("LEFT"); press("ENTER")
        if it.kind == "toggle" and it.v and it.id ~= "master" and it.id ~= "run" and it.id ~= "jump" and it.id ~= "landing" and it.id ~= "fire" and it.id ~= "tank" then press("ENTER") end
      end
    end)
    if not ok then errors = errors + 1; print("ERROR in " .. cat.name .. "/" .. it.id .. ": " .. tostring(err)) end
    press("DOWN")
  end
  print("---- " .. cat.name .. " ----"); print(mailbox_text())
  press("PAGEDOWN")
end
put_in_vehicle(false)
-- The walk above switched the master toggle off; back on for the checks.
F.items.master.v = true; F.enabled = true

-- Vehicle bits are applied in a car and cleared when leaving it.
put_in_vehicle(true); F.items.bulletproof.v = true; update(2)
assert((read_u32(V + 53980) & 0x02000000) ~= 0, "bulletproof bit not set")
put_in_vehicle(false); update(2)
assert((read_u32(V + 53980) & 0x02000000) == 0, "bulletproof bit not cleared on exit")

-- Value items write their float while changed and put it back.
F.items.swim_speed.v = 12; update(1)
assert(math.abs(read_f32(0x827ACF34) - 12) < 0.01, "swim speed not written")
F.items.swim_speed.v = 4.5; update(1)
assert(math.abs(read_f32(0x827ACF34) - 4.5) < 0.01, "swim speed not restored")

-- Crowd: one person per update, through the game's creator with stack args.
people_made = 0; F.queue_crowd(5); update(5)
assert(people_made == 5, "crowd not spawned: " .. tostring(people_made))


-- List items open a page; Enter on the page picks and runs.
do
  local MENU = require("menu")
  M_tab = nil
  for t, cat in ipairs(F.categories) do if cat.name == "Vehicles" then M_tab = t end end
  if not MENU.is_open() then press("F5") end
  local guard = 0
  while MENU.tab ~= M_tab and guard < 20 do press("PAGEDOWN"); guard = guard + 1 end
  assert(MENU.tab == M_tab, "could not reach the Vehicles tab")
  MENU.cursor[MENU.tab] = 1
  for i, it in ipairs(F.categories[M_tab].items) do if it.id == "spawn_vehicle" then MENU.cursor[MENU.tab] = i end end
  press("ENTER")
  assert(MENU.page and MENU.page.item.id == "spawn_vehicle", "list page did not open")
  local start = MENU.page.cursor
  press("DOWN"); press("DOWN"); press("RIGHT")
  assert(MENU.page.cursor == start + 2 + 12, "page cursor wrong: " .. MENU.page.cursor)
  print("---- vehicle page ----"); print(mailbox_text())
  press("BACKSPACE")
  assert(MENU.page == nil and MENU.is_open(), "Backspace should close the page only")
end

-- Teleport: streams the spot, then the script teleport with the facing kept.
do
  local calls_before = #calls
  F.items.places.v = 3
  F.activate(make_ctx(), F.items.places)
  assert(calls[#calls] == 0x82481000 and calls[#calls - 1] == 0x82510520, "teleport sequence wrong")
  assert(math.abs(read_f32(P + 404) - F.PLACES[3][4]) < 0.01, "fall start not moved")
end

-- Vehicle spawner: create, stream, place; removal destroys the handle.
vehicles_made, destroyed = 0, 0
assert(F.spawn_vehicle(make_ctx(), P, "car_2dr_compact01"), "vehicle spawn failed")
assert(vehicles_made == 1 and #F.spawned_vehicles == 1, "vehicle not recorded")
F.remove_spawned(make_ctx(), F.spawned_vehicles, "vehicle")
assert(destroyed == 1 and #F.spawned_vehicles == 0, "vehicle not destroyed")

-- No reload: the reload hook fills the magazine and skips the game's reload.
assert(hooks[0x82474AB0], "reload hook missing")
do
  local item, info, ammo = 0x48000000, 0x48000100, 0x48000200
  write_u32(P + 3548, item); write_u32(item + 16, ammo); write_u32(ammo + 8, info)
  write_u32(info + 100, 1); write_u16(info + 104, 30); write_u32(ammo + 16, 0); write_u32(ammo + 20, 0)
  -- The per-update top-up too.
  F.items.no_reload.v = true; update(1)
  assert(read_u32(ammo + 16) == 30, "update did not fill the magazine")
  write_u32(ammo + 16, 0)
  F.items.no_reload.v = true
  local ctx = make_ctx(); ctx.regs[3] = P
  local ran = false; ctx.call_original = function() ran = true end
  hooks[0x82474AB0](ctx)
  assert(not ran and read_u32(ammo + 16) == 30, "reload not blocked")
  F.items.no_reload.v = false
  write_u32(ammo + 16, 0)
  ctx = make_ctx(); ctx.regs[3] = P; ran = false; ctx.call_original = function() ran = true end
  hooks[0x82474AB0](ctx)
  assert(ran, "reload should run when the feature is off")
  write_u32(P + 3548, 0)
end

-- Closing hides the text and gives the keys back.
press("BACKSPACE")
assert(not taken["UP"], "keys not released")
assert(read_u32(0x00F00014) == 0, "text not hidden")

print(string.format("\n%d script calls, %d console lines, %d HUD messages, %d errors", #scripts, #consoles, #hud_texts, errors))
for _, s in ipairs(scripts) do print("  script: " .. s) end
for _, s in ipairs(consoles) do print("  console: " .. s) end
assert(errors == 0, "there were errors")
print("OK")
