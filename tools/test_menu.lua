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

-- ---------------------------------------------------------------- add-ons
-- The add-ons write files in their folder (camera.cfg, my_presets.ini), so the
-- tests run them from a copy and the mod folder the code sees is that copy.
local TMP = ((os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"):gsub("\\", "/")) .. "/srtm_test_mod"
local function mkdir(p)
  if os.getenv("OS") == "Windows_NT" then os.execute('mkdir "' .. p:gsub("/", "\\") .. '" >nul 2>nul')
  else os.execute("mkdir -p '" .. p .. "'") end
end
local function copy_file(src, dst)
  local f = io.open(src, "rb")
  if not f then return end
  local data = f:read("a"); f:close()
  local o = assert(io.open(dst, "wb")); o:write(data); o:close()
end
for _, a in ipairs({ { "precise_aim", { "main.lua", "presets.ini", "settings.ini" } },
                     { "fine_aim", { "main.lua", "settings.ini" } } }) do
  local dir = TMP .. "/addons/" .. a[1]
  mkdir(dir)
  for _, f in ipairs({ "camera.cfg", "my_presets.ini", "pool_backup.txt" }) do os.remove(dir .. "/" .. f) end
  for _, f in ipairs(a[2]) do copy_file(folder .. "/addons/" .. a[1] .. "/" .. f, dir .. "/" .. f) end
end

-- ---------------------------------------------------------------- fake wml
local hooks, frame_cbs, keys_down, keys_prev, taken, logs = {}, {}, {}, {}, {}, {}
wml = {
  mod_name = "test", mod_folder = TMP,
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
  -- Keys are names or Windows key codes (2 = right mouse), as in the loader.
  key_down = function(k) return keys_down[tostring(k):upper()] == true end,
  key_pressed = function(k) k = tostring(k):upper() return keys_down[k] == true and not keys_prev[k] end,
  take_key = function(k, on) taken[tostring(k):upper()] = (on ~= false) end,
  force_key = function() end,
  on_frame = function(f) frame_cbs[#frame_cbs + 1] = f end,
  -- Hooks chain like the loader's: the newest runs first, and its
  -- call_original reaches the one before it.
  hook = function(addr, f)
    local prev = hooks[addr]
    if not prev then hooks[addr] = f return end
    hooks[addr] = function(ctx)
      local outer = ctx.call_original
      local function inner(c) c.call_original = outer; prev(c); c.call_original = inner end
      ctx.call_original = inner
      f(ctx)
      ctx.call_original = outer
    end
  end,
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
ANIM_IDS, ANIM_NAMES, PLAYED_FILES = {}, {}, {}
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
    assert((ctx.regs[3] == 3 or ctx.regs[3] == 0) and ctx.regs[4] == 2 and ctx.regs[5] == 0x44000000 and ctx.regs[8] == 255, "spawn registers wrong")
    local sy = read_f32(ctx.regs[6] + 4)
    assert(sy > 0.05 and sy < 0.6, "spawn position not written")
    people_made = (people_made or 0) + 1
    ctx.regs[3] = 0x45000000
  end,
  [0x824194A8] = function(ctx) ctx.regs[3] = 12 end,
  -- Animation files: each "name.anim" gets its own id; playing records the name.
  [0x826F6BA8] = function(ctx)
    local name = read_cstr(ctx.regs[3])
    if not name:find("%.anim$") then ctx.regs[3] = 0xFFFFFFFF return end
    if not ANIM_IDS[name] then ANIM_IDS[name] = 100 + #ANIM_NAMES; ANIM_NAMES[#ANIM_NAMES + 1] = name end
    ctx.regs[3] = ANIM_IDS[name]
  end,
  [0x826F5C20] = function(ctx)
    PLAYED_FILES[#PLAYED_FILES + 1] = ANIM_NAMES[ctx.regs[4] - 99]
    ctx.regs[3] = 0x00AB0001
  end,
  -- The animation-set lookup: everything is in the set except "pose" (state 31).
  [0x82226DA8] = function(ctx) ctx.regs[3] = (ctx.regs[5] == 31) and 0xFFFFFFFF or 5 end,
  [0x82229380] = function(ctx) ctx.regs[3] = 12 end,     -- every action name -> 12
  [0x82444F88] = function(ctx) ctx.regs[3] = 1 end,
  [0x822292F8] = function(ctx)   -- animation state name -> number
    local states = { ["dance a"] = 159, ["dance b"] = 160, ["dance c"] = 161, ["dance d"] = 162, stand = 42, ["pair dance a"] = 170,
      pose = 31, ["Warm Hands"] = 30, ["zombie eat"] = 32,
      ["pole stand"] = 164, ["stage stand"] = 163, ["react cheer"] = 33, ["Beer Stand"] = 300 }
    ctx.regs[3] = states[read_cstr(ctx.regs[3])] or (100 + #read_cstr(ctx.regs[3]))   -- every built-in name has a number
  end,
  [0x82569700] = function(ctx)
    assert(read_u32(ctx.regs[1] + 84) == 0 and read_u32(ctx.regs[1] + 100) == 0, "vehicle stack args missing")
    assert(ctx.regs[3] == 7 and ctx.regs[4] == 2 and ctx.regs[5] == 12, "vehicle registers wrong")
    vehicles_made = (vehicles_made or 0) + 1
    vehicle_variant = ctx.regs[10] ~= 0 and read_cstr(ctx.regs[10]) or false
    ctx.regs[3] = 0x00050009
  end,
  [0x82569630] = function(ctx) ctx.regs[3] = 0x47000000 end,
  [0x823ACF50] = function(ctx) destroyed = (destroyed or 0) + 1 end,
}
write_u32(0x830866C8 + 12 + 9 * 16, 0x47000000); write_u32(0x47000000 + 68, 0x00050009)
write_u32(0x45000000 + 228, 0x46000000); write_u32(0x46000000 + 608, 0x05000001)
write_u32(0x44000000 + 608, 0x05000001)
write_u32(0x45000000 + 68, 0x0006000B); write_u32(0x830866C8 + 12 + 11 * 16, 0x45000000)
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
-- The game is always the Windows build (under Wine on the Mac), and menu.lua
-- draws through the overlay only there; look like it on any host.
package.config = "\\" .. package.config:sub(2)
os.remove(TMP .. "/saved_tweaks.ini"); os.remove(TMP .. "/quicksave.dat"); os.remove(TMP .. "/saved_places.txt")
-- The loader refuses some hooks (as it did for 0x8210C3F8 here, and for the
-- notoriety meter 0x82481990 on a player's PC, with an error that itself
-- failed to format): only what needs them goes, the menu loads and opens.
do
  local real_hook = wml.hook
  wml.hook = function(addr, f)
    if addr == 0x82533DA8 or addr == 0x82481990 then error("invalid option '%0' to 'lua_pushfstring'") end
    return real_hook(addr, f)
  end
end
dofile(folder .. "/main.lua")
assert(require("juiced").broken["brake lights"], "a refused hook should only switch off its own tweak")
assert(require("game").broken[0x82481990], "a refused hook in features.lua should only switch off what uses it")
assert(hooks[0x82209E30], "update hook missing")
assert(hooks[0x82788EC4], "input hook missing")
assert(hooks[0x824470D0], "damage hook missing")

-- Everything starts off: toggles off, sliders at the game's own value -
-- except the Quality of life rows meant to be on (mod.ini says so).
local F0 = require("features")
local STARTS_ON = { crouch_moving = true, car_free_cam = true }
for _, cat in ipairs(F0.categories) do
  for _, it in ipairs(cat.items) do
    if it.kind == "toggle" and it.id ~= "master" then
      assert(not it.v == not STARTS_ON[it.id], it.id .. (STARTS_ON[it.id] and " should start on" or " should start off"))
    end
  end
end
assert(F0.items.health_mult.v == 1, "health multiplier should start at x1")

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

-- Quality of life rows (juiced.lua): crouch and the car camera start on and
-- are written; switched off (or All tweaks off) they put the game's back.
do
  local J = require("juiced")
  write_f32(0x827D7AB0, 0.5); write_f32(0x827AC218, 0.006); write_f32(0x827AC224, 0.012711); write_f32(0x827D9364, 3.0)
  update(2)
  assert(math.abs(read_f32(0x827D7AB0) - 4.0) < 1e-4, "crouch while moving not written")
  assert(math.abs(read_f32(0x827AC218) - 0.006) < 1e-6 and math.abs(read_f32(0x827D9364)) < 1e-4, "free camera: the game's hold set to 0")
  -- FOV x1.2 on the follow camera, eased in.
  write_u32(0x827D9778, 0); write_f32(0x827D9778 + 192, 60); write_f32(0x827AA6C8, 1 / 30)
  -- (widened at the wanted FOV, right after the follow camera's update 0x8210F078 set it)
  for _ = 1, 40 do
    local c = make_ctx(); c.call_original = function() write_f32(0x827D9778 + 192, 60) end
    hooks[0x8210F078](c)
  end
  assert(math.abs(read_f32(0x827D9778 + 192) - 72) < 0.05, "FOV not widened: " .. read_f32(0x827D9778 + 192))
  F.items.crouch_moving.v = false; update(2)
  assert(math.abs(read_f32(0x827D7AB0) - 0.5) < 1e-4, "crouch not put back")
  F.enabled = false; update(2)
  assert(math.abs(read_f32(0x827D9364) - 3.0) < 1e-4, "All tweaks off didn't put the car camera back")
  F.enabled = true; F.items.crouch_moving.v = true; update(2)
  -- Save tweaks for next time: written, then read back over changed rows.
  F.items.god.v = true; F.items.fov.v = 1.35
  J.save_all()
  local sf = io.open(TMP .. "/saved_tweaks.ini"); local text = sf:read("a"); sf:close()
  assert(text:find("crouch_moving = true", 1, true) and text:find("fov = 1.35", 1, true) and text:find("god = true", 1, true), "saved_tweaks.ini incomplete")
  assert(not text:find("wanted_police", 1, true) and not text:find("hide_hud", 1, true), "one-shot and change-only rows must not be saved")
  F.items.god.v = false; F.items.fov.v = 1.0; F.items.crouch_moving.v = false
  J.load_saved()
  assert(F.items.god.v and math.abs(F.items.fov.v - 1.35) < 1e-9 and F.items.crouch_moving.v, "saved tweaks not read back")
  assert(J.forget_saved():find("forgotten") and not io.open(TMP .. "/saved_tweaks.ini"), "forget didn't remove the file")
  F.items.god.v, F.items.fov.v = false, 1.2
  update(2)
  print("quality of life rows: written, put back, saved and read back OK")
end

-- Toggle god mode (Player > Logic, first row) and check the bit.
local MENU0 = require("menu")
press("ENTER"); update(2)                         -- opens the Logic page
assert(#MENU0.pages == 1 and MENU0.current().id == "god", "Logic page should open on God mode")
press("ENTER"); update(2)
assert(F.items.god.v, "god not on")
assert((read_u32(P + 216) & 0x00100000) ~= 0, "god bit not set")
press("ENTER"); update(2)
assert((read_u32(P + 216) & 0x00100000) == 0, "god bit not cleared")
press("BACKSPACE"); update(1)
assert(#MENU0.pages == 0 and MENU0.is_open(), "Backspace should leave the page, not the menu")

-- Walk every tab and every row the menu shows: Left, Right, Enter must never
-- error. Rows that open a page are opened and left again (a page's own rows
-- are walked one level down; answering No to a "save changes?" question).
local errors = 0
local MENU = require("menu")
local function leave_page()
  press("BACKSPACE")
  local pg = MENU.pages[#MENU.pages]
  if pg and pg.confirm then press("DOWN"); press("ENTER") end      -- "No"
end
local function try_row(where, it)
  if it.needs == "vehicle" then put_in_vehicle(true) else put_in_vehicle(false) end
  update(2)
  local ok, err = pcall(function()
    if it.kind == "header" then return end
    if it.kind == "list" then
      local before = it.v
      press("RIGHT")
      if not it.usable and #it.items > 1 then
        assert(it.v == before % #it.items + 1, "Right should move to the next entry")
      end
      press("ENTER")
      assert(MENU.is_open(), "the menu stays open after picking")
    elseif it.kind == "page" then
      -- (opened by the caller)
    else
      press("RIGHT"); press("LEFT"); press("ENTER")
      if it.kind == "toggle" and it.v and it.id ~= "master" and it.id ~= "run" and it.id ~= "jump" and it.id ~= "landing" and it.id ~= "fire" and it.id ~= "tank" then press("ENTER") end
    end
  end)
  if not ok then errors = errors + 1; print("ERROR in " .. where .. "/" .. tostring(it.id or it.label) .. ": " .. tostring(err)) end
end
local function set_cursor(i)
  local pg = MENU.pages[#MENU.pages]
  if pg then pg.cursor = i else MENU.cursor[MENU.tab] = i end
  local s0 = math.max(1, i - 11)
  if pg then pg.scroll = s0 else MENU.scroll[MENU.tab] = s0 end
end
local SKIP = { kill_self = true, master = true }   -- (dying, or everything off, would stop the walk)
local seen_tabs = 0
for _ = 1, #F.categories do
  local cat = F.categories[MENU.tab]
  seen_tabs = seen_tabs + 1
  local list = MENU.view_rows()
  for i = 1, #list do
    local it = list[i]
    if not SKIP[it.id] then
      set_cursor(i)
      if it.kind == "page" then
        local depth = #MENU.pages
        press("ENTER")
        if #MENU.pages > depth then
          local rows = MENU.view_rows()
          for j = 1, math.min(#rows, 40) do
            local r = rows[j]
            if r.kind ~= "page" and not SKIP[r.id] then set_cursor(j); try_row(cat.name .. ">" .. it.label, r) end
          end
          while #MENU.pages > depth do leave_page() end
        end
      else
        try_row(cat.name, it)
      end
    end
    if not MENU.is_open() then press("F5") end
  end
  print("---- " .. cat.name .. " ----"); print(mailbox_text())
  press("PAGEDOWN")
end
put_in_vehicle(false)
-- The walk above switched the master toggle off; back on for the checks.
F.items.master.v = true; F.enabled = true

-- Vehicle god mode: damage gets a repair; explosions can't break parts.
put_in_vehicle(true); F.items.veh_god.v = true
write_u32(V + 53512, 500)
local repairs_before = 0
for _, a in ipairs(calls) do if a == 0x82536F30 then repairs_before = repairs_before + 1 end end
update(1)
local repairs_after = 0
for _, a in ipairs(calls) do if a == 0x82536F30 then repairs_after = repairs_after + 1 end end
assert(repairs_after > repairs_before, "damage should trigger a repair")
assert(read_u32(V + 53512) == read_u32(V + 53508), "health not refilled")
do
  local ctx = make_ctx(); ctx.regs[3], ctx.regs[4] = 0x4D000000, V
  local ran = false; ctx.call_original = function() ran = true end
  hooks[0x825447D0](ctx)
  assert(not ran, "explosion part damage should be blocked on the player's car")
  ctx = make_ctx(); ctx.regs[3], ctx.regs[4] = 0x4D000000, 0x4E000000
  ran = false; ctx.call_original = function() ran = true end
  hooks[0x825447D0](ctx)
  assert(ran, "other cars still take explosion damage")
end
F.items.veh_god.v = false; put_in_vehicle(false); update(1)

-- Nitrous toggle off: a boost on an ordinary car is cancelled; a derby car keeps it.
do
  put_in_vehicle(true)
  local INFO = 0x56000000
  write_u32(V + 50324, INFO)
  local function name(s) for i = 1, #s do write_u8(INFO + 95 + i, s:byte(i)) end write_u8(INFO + 96 + #s, 0) end
  name("car_2dr_compact01")
  F.items.nitro_all.v = false
  write_u8(ENGINE + 380, 1); update(1)
  assert(read_u8(ENGINE + 380) == 0, "boost should be cancelled with nitrous off")
  F.items.nitro_all.v = true
  write_u8(ENGINE + 380, 1); update(1)
  assert(read_u8(ENGINE + 380) == 1, "boost should stay with nitrous on")
  put_in_vehicle(false); update(1)
end

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


-- Lists: Left/Right on the row, Shift jumps ten, Enter acts on the shown entry.
do
  local MENU = require("menu")
  if not MENU.is_open() then press("F5") end
  local tab
  for t, cat in ipairs(F.categories) do if cat.name == "Vehicles" then tab = t end end
  local guard = 0
  while MENU.tab ~= tab and guard < 20 do press("PAGEDOWN"); guard = guard + 1 end
  for i, it in ipairs(F.categories[tab].items) do if it.id == "spawn_vehicle" then MENU.cursor[MENU.tab] = i end end
  local it = F.items.spawn_vehicle
  it.v = 1
  press("RIGHT"); press("RIGHT")
  assert(it.v == 3, "Right twice should show entry 3")
  keys_down["SHIFT"] = true; press("RIGHT"); keys_down["SHIFT"] = nil; update(1)
  assert(it.v == 13, "Shift + Right should jump ten, got " .. it.v)
  print("---- vehicle row ----"); print(mailbox_text())
  -- Blinged versions follow their plain car and spawn as the game's named variant.
  local list, at = it.items, {}
  for i, e in ipairs(list) do at[e[2]] = i end
  assert(#list == 103 and #F.items.garage.items == 79, "spawn list should be 79 cars + 24 blinged, got " .. #list)
  assert(at["Slingshot Blinged"] == at["Slingshot"] + 1 and at["Hollywood Blinged Yellow"] == at["Hollywood"] + 4, "blinged order")
  it.v = at["Slingshot Blinged"]; press("ENTER")
  assert(vehicle_variant == "Blinged", "Slingshot Blinged variant: " .. tostring(vehicle_variant))
  it.v = at["Vegas Blinged"]; press("ENTER")
  assert(vehicle_variant == "Bling", "Vegas Blinged variant: " .. tostring(vehicle_variant))
  it.v = at["Slingshot"]; press("ENTER")
  assert(vehicle_variant == false, "plain Slingshot should pass no variant")
  F.remove_spawned(make_ctx(), F.spawned_vehicles, "vehicle")
end

-- Everybody dance: every person but the player gets a dance state applied;
-- Back to normal puts them on "stand".
do
  local A, B = 0x50000000, 0x50001000
  write_u32(0x8309A788, A); write_u32(A + 204, B); write_u32(B + 204, A)
  write_u32(A + 68, 0x00070011); write_u32(B + 68, 0x00070012)
  write_f32(A + 1912, 100); write_f32(B + 1912, 100)
  local applied = 0
  FAKE[0x82440200] = function(ctx) applied = applied + 1 end
  -- Each person has an animation owner, so the "can they do it" check answers.
  for _, h in ipairs({ A, B }) do write_u32(h + 568, h + 0x800); write_u32(h + 0x800, 0x5E000000); write_u32(h + 0x800 + 3592, 0x5F000000) end
  F.items.everybody.v = 1
  local msg = F.activate(make_ctx(), F.items.everybody)
  assert(msg == "Everybody: Dance (2 people)", msg)
  assert(read_u32(A + 952) >= 159 and read_u32(A + 952) <= 162, "no dance state")
  assert(applied == 2, "apply not called per person")
  F.activate(make_ctx(), F.items.everybody)        -- again: nobody restarted
  assert(applied == 2, "dancers should not be restarted")
  F.items.everybody.v = #F.items.everybody.items
  F.activate(make_ctx(), F.items.everybody)
  assert(read_u32(A + 952) == 42 and read_u32(B + 952) == 42, "back to normal should stand everyone")
  write_u32(0x8309A788, 0)
end

-- Emotes, partners and scenes. Fakes for the direct animation calls:
-- every person gets an animation owner with a player handle; animation
-- files resolve to ids; playing a file returns a handle; actions resolve
-- by name and play. No script engine is used for any of it.
do
  local played_files, played_actions = PLAYED_FILES, {}
  local function give_owner(h)
    write_u32(h + 568, h + 0x1000); write_u32(h + 0x1000 + 3592, 0x5F000000)
  end
  give_owner(P)
  local shared_play = FAKE[0x826F5C20]
  FAKE[0x826F5C20] = function(ctx)                       -- play a file: check the arguments too
    assert(ctx.regs[3] == 0x5F000000 and ctx.regs[5] == 16, "play-file args")
    assert(ctx.fregs[2] == 1.0 and ctx.fregs[4] == -1.0, "play-file floats")
    shared_play(ctx)
  end
  local actions = { ["flip off"] = 12 }
  FAKE[0x82229380] = function(ctx) ctx.regs[3] = actions[read_cstr(ctx.regs[3])] or 0xFFFFFFFF end
  FAKE[0x82444F88] = function(ctx)
    assert(ctx.regs[4] == 12 and ctx.regs[10] == 0xFFFFFFFF and ctx.fregs[3] == -1.0, "action args")
    played_actions[#played_actions + 1] = ctx.regs[3]; ctx.regs[3] = 1
  end

  write_u32(P + 2496, 0)
  -- Poses and Actions (itsMJQ's emotes.lua): each opens a page of the game's
  -- categories, or says why not; neither may error.
  for _, id in ipairs({ "poses", "actions" }) do
    local it = F.items[id]
    assert(it and it.kind == "page", id .. " should be a page")
    local ok, pg = pcall(it.open, make_ctx(), P, it)
    assert(ok, id .. " page failed: " .. tostring(pg))
    assert(type(pg) == "table" or type(pg) == "string", id .. " page should open or explain")
  end
  F.activate(make_ctx(), F.items.stop_pose)

  -- Partner and scene: people spawn one per update, each in their part.
  local next_obj, next_handle = 0x51000000, 0x00080020
  local old_create = FAKE[0x82479AB0]
  FAKE[0x82479AB0] = function(ctx)
    local o = next_obj
    next_obj = next_obj + 0x2000
    write_u32(o + 68, next_handle)
    write_u32(0x830866C8 + 12 + (next_handle & 0xFFFF) * 16, o)
    write_f32(o + 1912, 100)
    give_owner(o)
    next_handle = next_handle + 1
    ctx.regs[3] = o
  end
  local destroyed_now = 0
  FAKE[0x823ACF50] = function(ctx) destroyed_now = destroyed_now + 1 end
  for i, sc in ipairs(F.items.scene.items) do if sc[2] == "Strip club" then F.items.scene.v = i end end
  msg = F.activate(make_ctx(), F.items.scene)
  assert(msg == "Staging Strip club (7 people)", msg)
  update(10)
  assert(#F.scene_actors == 7, "scene people: " .. #F.scene_actors)
  local d = F.scene_actors[2]
  local o = read_u32(0x830866C8 + 12 + (d.handle & 0xFFFF) * 16)
  local was = read_u32(o + 952)
  write_u32(o + 952, 42); update(25)                      -- the game reset one: put back
  assert(read_u32(o + 952) == was, "scene animation not held")
  msg = F.activate(make_ctx(), F.items.clear_scene)
  assert(msg == "Cleared 7 people" and destroyed_now == 7, msg)
  FAKE[0x82479AB0] = old_create
  FAKE[0x823ACF50] = function(ctx) destroyed = (destroyed or 0) + 1 end
  F.posing = nil
end

-- Paint: finds the Body Color slot, fits its paint part when none is fitted,
-- sets the colour with the garage's setter; an unallowed finish falls back
-- to gloss.
do
  put_in_vehicle(true)
  local STATE, CUST, SLOTS, TYPES, PARTS, CSLOT, PALS, PLIST = 0x52000000, 0x52001000, 0x52002000, 0x52003000, 0x52004000, 0x52005000, 0x52006000, 0x52007000
  write_u32(V + 54688, STATE); write_u32(STATE, 0); write_u32(STATE + 8, CUST)
  write_u32(0x83710108, 12); write_u32(0x8371010C, PALS); write_u32(0x8371012C, TYPES)
  for pal = 0, 11 do write_u32(PALS + pal * 24 + 16, 80); write_u32(PALS + pal * 24 + 20, 0x53000000 + pal * 0x10000) end
  write_u32(CUST, 1); write_u32(CUST + 4, SLOTS)
  write_u32(SLOTS, TYPES + 46 * 16); write_u32(SLOTS + 8, 1); write_u32(SLOTS + 12, PARTS)
  write_u32(PARTS + 36, 1); write_u32(PARTS + 40, CSLOT); write_u32(PARTS + 44, 0)
  write_u32(CSLOT + 20, 3); write_u32(CSLOT + 24, PLIST)   -- allowed: Gloss, Metallic, Iridescent
  write_u32(PLIST, PALS + 2 * 24); write_u32(PLIST + 4, PALS + 4 * 24); write_u32(PLIST + 8, PALS + 11 * 24)
  local fit, set = 0, nil
  FAKE[0x8254C848] = function(ctx) fit = fit + 1 end
  FAKE[0x8254CA48] = function(ctx) set = { ctx.regs[3], ctx.regs[4], ctx.regs[5], ctx.regs[6] } end
  F.items.paint.v = 21                                   -- Saints Purple: Iridescent 36
  local msg = F.activate(make_ctx(), F.items.paint)
  assert(msg == "Painted Saints Purple", msg)
  assert(fit == 1 and set[1] == STATE and set[2] == PARTS and set[3] == 0 and set[4] == 0x53000000 + 11 * 0x10000 + 36 * 80, "paint call args")
  F.items.paint.v = 2                                    -- Matte Black: not allowed, so gloss
  msg = F.activate(make_ctx(), F.items.paint)
  assert(msg == "Painted Matte Black (gloss on this car)" and set[4] == 0x53000000 + 2 * 0x10000 + 15 * 80, msg)
  F.items.paint2.v = 1
  msg = F.activate(make_ctx(), F.items.paint2)
  assert(msg == "This vehicle has no second colour", msg)
  write_u32(V + 54688, 0); put_in_vehicle(false); update(1)
end

-- Filters: saturation and tint written every update while on, the
-- post-process look set once; Off puts them back.
do
  local looks = {}
  wml.set_look = function(t) looks[#looks + 1] = t or "clear" end
  F.items.filter.v = 2                                    -- Noir
  local msg = F.activate(make_ctx(), F.items.filter)
  assert(msg == "Filter: Noir", msg)
  write_f32(0x827D6C0C, 1); update(1)
  assert(math.abs(read_f32(0x827D6C0C)) < 0.001, "saturation not held at 0")
  assert(type(looks[1]) == "table" and #looks[1] == 14, "look not set")
  F.items.filter.v = 1
  F.activate(make_ctx(), F.items.filter)
  assert(math.abs(read_f32(0x827D6C0C) - F.items.saturation.v) < 0.001 and read_f32(0x827DDD0C) == 1, "not restored")
  assert(looks[2] == "clear", "look not cleared")
end

-- Free camera: pushes mode 5, writes position/rows/FOV each update, moves
-- with W, pops mode 5 on exit.
do
  local CAM = 0x827D9778
  write_f32(CAM + 44, 10); write_f32(CAM + 48, 5); write_f32(CAM + 52, 20)
  write_f32(CAM + 104, 0); write_f32(CAM + 108, 0); write_f32(CAM + 112, 1)
  write_f32(CAM + 188, 70); write_f32(CAM + 192, 70)
  write_f32(P + 20, 10); write_f32(P + 24, 5); write_f32(P + 28, 20)
  wml.mouse_look = function() return 0, 0 end
  local fake_time = 0
  os.clock = function() fake_time = fake_time + 0.02 return fake_time end   -- 20 ms per call, like frames
  FAKE[0x8210A568] = function(ctx) write_u32(CAM, ctx.regs[3]); write_u32(CAM + 4, ctx.regs[3]); write_u32(CAM + 36, 1) end
  local popped = false
  FAKE[0x8210A650] = function(ctx) popped = true; write_u32(CAM, 0); write_u32(CAM + 36, 0) end
  local MENU = require("menu")
  if MENU.is_open() then press("F5") end
  F.items.free_cam.v = false
  local msg = F.toggle(make_ctx(), F.items.free_cam)
  assert(msg:find("Free camera on"), msg)
  assert(read_u32(CAM) == 5, "mode 5 not pushed")
  keys_down["W"] = true; update(10); keys_down["W"] = nil
  assert(read_f32(CAM + 52) > 20.0, "W should move the camera forward: " .. read_f32(CAM + 52))
  assert(read_f32(CAM + 64) == read_f32(CAM + 52), "wanted position not written")
  -- The pad is blanked while flying.
  local STATE = 0x49000100
  write_u16(STATE + 4, 0x1000)
  local c = make_ctx(); c.regs[3] = 0; c.regs[5] = STATE
  hooks[0x82788EC4](c)
  assert(read_u16(STATE + 4) == 0, "pad not blanked while flying")
  -- Before the game update the camera is back where flying started, so the
  -- player doesn't turn to it.
  local flown = read_f32(CAM + 52)
  F.FREECAM.before_update()
  assert(read_f32(CAM + 52) == 20 and read_f32(CAM + 64) == 20, "camera not put back before the update")
  update(1)
  assert(math.abs(read_f32(CAM + 52) - flown) < 0.5, "flown view not written after the update")
  -- A: play from the shot. The pad goes to the game and the camera stays.
  write_u16(STATE + 4, 0x1000)
  c = make_ctx(); c.regs[3] = 0; c.regs[5] = STATE
  hooks[0x82788EC4](c)
  update(1)
  assert(F.FREECAM.mode == 2 and F.items.cam_mode.v == 2, "A should hold the shot")
  write_u16(STATE + 4, 0x1000)
  c = make_ctx(); c.regs[3] = 0; c.regs[5] = STATE
  hooks[0x82788EC4](c)
  assert(read_u16(STATE + 4) == 0x1000, "the pad should reach the game when playing from the shot")
  local held = read_f32(CAM + 52)
  keys_down["W"] = true; update(10); keys_down["W"] = nil
  assert(read_f32(CAM + 52) == held, "the held camera moved")
  -- During the update the game aims from a camera behind the player, turned by the mouse.
  local yaw_before = F.FREECAM.aim_yaw
  wml.mouse_look = function() return 0.5, 0.3 end
  update(1)
  assert(math.abs(F.FREECAM.aim_yaw - yaw_before - 0.5 * F.FREECAM.AIM_TURN) < 1e-6, "aim should spin faster than the mouse")
  wml.mouse_look = function() return 0, 0 end
  F.FREECAM.before_update()
  local fx, fz = read_f32(CAM + 104), read_f32(CAM + 112)
  assert(math.abs(fx - math.sin(F.FREECAM.aim_yaw) * math.cos(F.FREECAM.aim_pitch)) < 0.01 and fx > 0.3, "aim camera not turned by the mouse")
  local bx, bz = read_f32(CAM + 44), read_f32(CAM + 52)
  assert(math.abs((10 - bx) - fx * 3.0) < 0.05 and math.abs((20 - bz) - fz * 3.0) < 0.05, "aim camera not behind the player")
  local tilt = F.FREECAM.AIM_PITCH
  assert(F.FREECAM.aim_pitch == tilt and math.abs(read_f32(CAM + 108) - math.sin(tilt)) < 1e-4, "aim should keep its slight downward tilt")
  assert(math.abs(read_f32(CAM + 48) - (5 + F.FREECAM.AIM_UP - math.sin(tilt) * 3.0)) < 0.01, "aim camera height wrong")
  update(1)
  assert(read_f32(CAM + 52) == held, "the shot not put back after the update")
  -- Tracking turns towards the player (who is ahead along +z... put them to the side).
  write_f32(P + 20, 40)
  F.adjust(make_ctx(), F.items.cam_mode, 1)
  assert(F.FREECAM.mode == 3, "tracking not set")
  update(60)
  assert(read_f32(CAM + 104) > 0.5, "tracking should turn the camera towards +x: " .. read_f32(CAM + 104))
  F.adjust(make_ctx(), F.items.cam_mode, 1)
  assert(F.FREECAM.mode == 1 and F.FREECAM.flying(), "back to flying")
  msg = F.toggle(make_ctx(), F.items.free_cam)
  assert(popped and not F.FREECAM.on, "mode 5 not popped")
  write_f32(P + 20, 0); write_f32(P + 24, 0); write_f32(P + 28, 0)
end

-- Rocket ammo: the player's gun borrows the RPG's rocket fields, is a
-- projectile only during the player's shot, and is put back when off.
-- Fire ammo: a hit from the player queues an ignite for the next update.
do
  local INFOS, RPG, AK = 0x54000000, 0x54000000, 0x54000208
  write_u32(0x832ABCA8, INFOS); write_u32(0x832ABCAC, 2)
  local function name_at(info, s, at)
    write_u32(info, at); for i = 1, #s do write_u8(at + i - 1, s:byte(i)) end; write_u8(at + #s, 0)
  end
  name_at(RPG, "rpg_launcher", 0x54100000); name_at(AK, "ak47", 0x54100100)
  write_u32(RPG + 100, 1); write_u32(RPG + 20, 4); write_u8(RPG + 12, 0x68); write_u32(RPG + 144, 0xEEEE0001); write_u32(RPG + 316, 0x42C80000)
  write_u32(AK + 100, 0); write_u32(AK + 20, 2); write_u8(AK + 12, 0x80); write_u8(AK + 164, 1); write_u32(AK + 144, 0)
  local item, ammo = 0x54200000, 0x54200100
  write_u32(P + 3548, item); write_u32(item + 16, ammo); write_u32(ammo + 8, AK)
  write_u32(P + 2496, 0)
  F.items.rocket_ammo.v = true
  local seen_type, seen_flags
  local ctx = make_ctx(); ctx.regs[3] = P
  ctx.call_original = function() seen_type, seen_flags = read_u32(AK + 100), read_u8(AK + 12) end
  hooks[0x82470A50](ctx)
  assert(seen_type == 1 and (seen_flags & 0x60) == 0x60, "the shot should be a rocket")
  assert(read_u32(AK + 100) == 0 and read_u8(AK + 12) == 0x80, "type and flags not put back after the shot")
  assert(read_u32(AK + 144) == 0xEEEE0001 and read_u32(AK + 316) == 0x42C80000, "rocket fields not borrowed")
  -- An NPC with the same gun is untouched.
  ctx = make_ctx(); ctx.regs[3] = 0x4C000000
  ctx.call_original = function() seen_type = read_u32(AK + 100) end
  hooks[0x82470A50](ctx)
  assert(seen_type == 0, "NPC shots must stay bullets")
  write_u32(0x8309A494, 0)
  F.items.rocket_ammo.v = false; update(2)
  assert(read_u32(AK + 144) == 0 and read_u32(AK + 316) == 0, "gun not restored")
  -- Fire ammo
  local V2 = 0x55000000
  write_u32(V2 + 72, 1); write_u32(V2 + 68, 0x0009002A); write_u32(V2 + 216, 0)
  write_u32(0x830866C8 + 12 + 0x2A * 16, V2)
  local lit = false
  FAKE[0x8245E3A0] = function(c)
    assert(c.regs[3] == V2 and c.regs[5] == P and c.fregs[1] > 0, "ignite args")
    lit = true; c.regs[3] = 1
  end
  F.items.fire_ammo.v = true
  local dctx = make_ctx(); dctx.regs[3], dctx.regs[4] = V2, P
  hooks[0x824470D0](dctx)
  assert(not lit, "ignite must wait for the next update")
  update(1)
  assert(lit, "victim not set alight")
  F.items.fire_ammo.v = false
  write_u32(P + 3548, 0); write_u32(0x832ABCA8, 0)
end

-- Bodyguards: created as a scripted character, Saints team, armed, then
-- joined to the party through the game's own insert.
do
  local made, joined = 0, false
  FAKE[0x8244A6A8] = function(ctx) ctx.regs[3] = 0 end            -- "Playas" -> team 0
  FAKE[0x823F7840] = function(ctx) ctx.regs[3] = 0x4F000000 end
  FAKE[0x82445C80] = function(ctx) ctx.regs[3] = 0x4F000100 end
  local GUARD = 0x45000000                                        -- the fake creator's object
  write_u32(GUARD + 68, 0x0006000B)
  write_u32(0x830866C8 + 12 + 11 * 16, GUARD)
  write_u32(GUARD + 1908, 100)
  write_u32(P + 2096, 2); write_u32(P + 68, 0x00010001)
  FAKE[0x82483828] = function(ctx)
    assert(ctx.regs[3] == P and ctx.regs[4] == GUARD and ctx.regs[5] == 1, "party insert args")
    joined = true; write_u32(P + 2096, 3); ctx.regs[3] = 1
  end
  FAKE[0x822D0188] = function(ctx) ctx.regs[3] = 2 end
  F.items.bodyguard.v = 1
  local msg = F.activate(make_ctx(), F.items.bodyguard)
  assert(msg:find("on the way"), msg)
  update(3)
  assert(joined, "bodyguard did not join the party")
  assert(read_u32(GUARD + 1908) == 300, "bodyguard health not raised")
  assert((read_u8(GUARD + 3697) & 0x40) ~= 0, "attack-enemies flag not set")
  local used = {}
  for _, a in ipairs(calls) do used[a] = true end
  assert(used[0x82446280] and used[0x82445B88] and used[0x822D1418], "weapon, ammo or HUD head missing")
  write_u32(P + 2096, 0)
end

-- God mode: no catching fire, no damage; weapons through the cheat routine;
-- freeze world only while the menu is open; one person spawned.
do
  F.items.god.v = true; update(1)
  local c = make_ctx(); c.regs[3] = P
  local lit = false; c.call_original = function() lit = true end
  hooks[0x8245E3A0](c)
  assert(not lit and c.regs[3] == 0, "god mode should stop you catching fire")
  c = make_ctx(); c.regs[3], c.regs[4] = P, 0x4C000000; c.fregs[1] = 50
  local dealt; c.call_original = function(self) dealt = self.fregs[1] end
  hooks[0x824470D0](c)
  assert(dealt == 0, "god mode should zero the damage")
  assert((read_u32(P + 216) & 0x00100000) ~= 0, "god mode should set the invulnerability bit")
  F.items.god.v = false; update(1)
  assert((read_u32(P + 216) & 0x00100000) == 0, "god mode off should clear the invulnerability bit")
  local cheat_name, cheat_rounds
  FAKE[0x821F56C0] = function(ctx) cheat_name = read_cstr(read_u32(ctx.regs[3])); cheat_rounds = read_u32(ctx.regs[3] + 4) end
  for i, w in ipairs(F.items.give_weapon.items) do if w[2] == "NR4" then F.items.give_weapon.v = i end end
  F.activate(make_ctx(), F.items.give_weapon)
  assert(cheat_name == "glock" and cheat_rounds == 500, "weapon cheat args: " .. tostring(cheat_name))
  local MENU = require("menu")
  if not MENU.is_open() then press("F5") end
  F.items.freeze_world.v = true; update(1)
  assert(read_f32(0x827AA6D4) > 1000, "frozen while the menu is open")
  press("F5"); update(1)
  assert(read_f32(0x827AA6D4) == 1.0, "closing the menu should unfreeze")
  F.items.freeze_world.v = false; update(1)
  local made_before = people_made or 0
  F.items.spawn_person.v = 1
  local msg = F.activate(make_ctx(), F.items.spawn_person)
  assert(msg:find("^Spawned "), msg)
  -- The game may never delete the menu's people; others it may.
  assert(hooks[0x8244BC40], "despawn check hook missing")
  local c = make_ctx(); c.regs[3] = 0x45000000
  local asked = false; c.call_original = function() asked = true end
  hooks[0x8244BC40](c)
  assert(c.regs[3] == 0 and not asked, "a spawned person should never be despawnable")
  c = make_ctx(); c.regs[3] = 0x4C000000; c.call_original = function() asked = true end
  hooks[0x8244BC40](c)
  assert(asked, "other people go to the game's own check")
  -- Each model reference is given back when the person goes.
  local refs, released = 0, 0
  for _, a in ipairs(calls) do if a == 0x8250C750 then refs = refs + 1 end end
  FAKE[0x8250CA48] = function(ctx)
    assert(ctx.regs[5] == 5 and ctx.regs[7] == 0, "release args")
    released = released + 1
  end
  F.remove_spawned(make_ctx(), F.spawned_people, "person")
  assert(released >= 1, "reference not given back")
  -- A ninth kind of person: the oldest spawned people make room.
  local old_lookup, old_create = FAKE[0x82114928], FAKE[0x82479AB0]
  local k, made = 0, 0
  FAKE[0x82114928] = function(ctx)
    k = k + 1
    local def = 0x5A000000 + k * 0x1000
    write_u32(def + 608, 0x05000100 + k)
    ctx.regs[3] = def
    write_u32(0x5A800000 + 4, def)              -- the next person made is of this model
  end
  local spots = {}
  FAKE[0x82479AB0] = function(ctx)
    made = made + 1
    spots[made] = { read_f32(ctx.regs[6]), read_f32(ctx.regs[6] + 8) }
    local o, handle = 0x5B000000 + made * 0x2000, 0x00070100 + made
    write_u32(o + 68, handle); write_u32(0x830866C8 + 12 + (handle & 0xFFFF) * 16, o)
    write_u32(o + 228, read_u32(0x5A800000 + 4)); write_f32(o + 1912, 100)
    ctx.regs[3] = o
  end
  local last
  for i = 1, 9 do F.items.spawn_person.v = i; last = F.activate(make_ctx(), F.items.spawn_person) end
  local kinds = {}
  for _, id in pairs(F.our_people) do kinds[id] = true end
  local n = 0
  for _ in pairs(kinds) do n = n + 1 end
  -- (the bodyguard from earlier holds one of the eight)
  assert(n == 8 and #F.spawned_people >= 7, "eight kinds at most: " .. n .. " kinds, " .. #F.spawned_people .. " people")
  assert(last:find("made room"), last)
  -- Each one stands somewhere else, all within a few metres of you.
  local px, pz = read_f32(P + 20), read_f32(P + 28)
  for i = 1, #spots do
    local d = math.sqrt((spots[i][1] - px) ^ 2 + (spots[i][2] - pz) ^ 2)
    assert(d > 2 and d < 7, "spawn spot " .. i .. " is " .. d .. " m away")
    for j = 1, i - 1 do
      assert((spots[i][1] - spots[j][1]) ^ 2 + (spots[i][2] - spots[j][2]) ^ 2 > 1, "people " .. j .. " and " .. i .. " on the same spot")
    end
  end
  local gone = {}
  for _, h in ipairs(F.spawned_people) do gone[#gone + 1] = h end
  F.remove_spawned(make_ctx(), F.spawned_people, "person")
  for _, h in ipairs(gone) do assert(F.our_people[h] == nil, "person left registered") end
  FAKE[0x82114928], FAKE[0x82479AB0] = old_lookup, old_create
  -- sorted lists
  for _, list in ipairs({ F.items.spawn_vehicle.items, F.items.give_weapon.items, F.items.spawn_person.items }) do
    for i = 2, #list do assert(list[i - 1][2]:lower() <= list[i][2]:lower(), "not alphabetical: " .. list[i][2]) end
  end
  for _, v in ipairs(F.items.spawn_vehicle.items) do assert(not v[1]:find("sp_trailer_"), "trailers should be gone") end
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

-- Refill all ammo: walks the inventory ring in memory, calls no game code.
do
  local guns = { { 0x4A000000, 30, 500 }, { 0x4A001000, 5, 50 }, { 0x4A002000, 8, 100 } }
  for i, g in ipairs(guns) do
    local item, ammo, info = g[1], g[1] + 0x100, g[1] + 0x200
    write_u32(item, guns[i % #guns + 1][1])   -- next, back to the first at the end
    write_u32(item + 16, ammo); write_u32(ammo + 8, info)
    write_u16(info + 104, g[2]); write_u16(info + 106, g[3])
    write_u32(ammo + 16, 1); write_u32(ammo + 20, 0)
  end
  local melee = 0x4A003000                      -- an item with no ammo record
  write_u32(guns[3][1], melee); write_u32(melee, guns[1][1]); write_u32(melee + 16, 0)
  write_u32(P + 2324, guns[1][1])
  local before = #calls
  local msg = F.activate(make_ctx(), F.items.ammo_all)
  assert(#calls == before, "refill should not call into the game")
  for _, g in ipairs(guns) do
    assert(read_u32(g[1] + 0x100 + 16) == g[2] and read_u32(g[1] + 0x100 + 20) == g[3], "gun not refilled")
  end
  assert(msg == "Ammo refilled (3 guns)", msg)
  write_u32(P + 2324, 0)
end

-- Closing hides the text and gives the keys back.
press("BACKSPACE")
assert(not taken["UP"], "keys not released")
assert(read_u32(0x00F00014) == 0, "text not hidden")

-- Controller: RB + D-pad down opens and closes the menu, and the D-pad press
-- never reaches the game (it is Cancel Activity there).
do
  local MENU = require("menu")
  local STATE = 0x49000000
  local RB, LB, DOWN, A, B = 0x200, 0x100, 0x2, 0x1000, 0x2000
  -- One controller read (what the game then sees) followed by one update.
  local function pad(buttons)
    write_u16(STATE + 4, buttons); write_u8(STATE + 6, 0); write_u8(STATE + 7, 0)
    local ctx = make_ctx(); ctx.regs[3] = 0; ctx.regs[5] = STATE
    hooks[0x82788EC4](ctx)
    local seen = read_u16(STATE + 4)
    update(1)
    return seen
  end
  assert(not MENU.is_open(), "menu should start closed")
  assert(pad(RB) == RB, "RB alone must reach the game (sprint)")
  assert(pad(RB | DOWN) == RB, "D-pad down leaked to the game with RB held")
  assert(MENU.is_open(), "RB + D-pad down did not open the menu")
  -- (itsMJQ) outside Customize you can still move with the menu open: the
  -- menu takes its own keys, the movement keys stay the game's.
  assert(taken["UP"] and taken["ENTER"] and not taken["W"], "menu keys taken, movement keys left to the game")
  assert(pad(RB | DOWN) == 0, "the game should see nothing while the menu is open")
  MENU.tab = 1
  pad(RB); pad(0)
  assert(MENU.tab == 1, "letting go of the RB that opened the menu changed tab")
  pad(RB)
  assert(MENU.tab == 1, "RB changed tab on press, before knowing it is not the combo")
  pad(0)
  assert(MENU.tab == 2, "an RB tap did not change tab")
  pad(LB); pad(0)
  assert(MENU.tab == 1, "LB did not change tab")
  MENU.cursor[1], MENU.scroll[1] = 1, 1          -- (the walk above left it on the last row)
  local c = MENU.cursor[1]
  pad(DOWN); pad(0)
  assert(MENU.cursor[1] == c + 1, "D-pad down did not move the cursor")
  assert(mailbox_text():find("A select", 1, true) and mailbox_text():find("RB + D-pad Down close", 1, true), "controller hints not shown")
  press("UP")
  assert(mailbox_text():find("Enter select", 1, true), "keyboard hints not back after a key")
  local cur = MENU.cursor[1]
  pad(RB); pad(RB | DOWN)
  assert(not MENU.is_open(), "the combo did not close the menu")
  assert(MENU.tab == 1 and MENU.cursor[1] == cur, "the closing combo also moved the menu")
  assert(pad(RB | DOWN) == 0, "buttons held from the menu leaked to the game")
  assert(not MENU.is_open(), "holding the combo reopened the menu")
  pad(0)
  assert(pad(RB) == RB, "RB must reach the game again once let go")
  pad(0)
  -- B closes, and that B never reaches the game.
  pad(RB); pad(RB | DOWN); pad(0)
  assert(MENU.is_open(), "menu did not reopen")
  pad(B)
  assert(not MENU.is_open(), "B did not close the menu")
  assert(pad(B) == 0, "the B that closed the menu reached the game")
  pad(0)
  assert(pad(B) == B, "B must reach the game after it is let go")
  pad(0)
  -- PlayStation names and other combos.
  local h, p = MENU.parse_combo("R1+DOWN"); assert(h == RB and p == DOWN, "R1 is not RB")
  h, p = MENU.parse_combo("l2 + cross"); assert(h == MENU.PAD.LT and p == A, "L2 + Cross wrong")
  h, p = MENU.parse_combo("LB+RB+DPAD_DOWN"); assert(h == LB | RB and p == DOWN, "three-button combo wrong")
  assert(MENU.parse_combo("RB+NOPE") == nil, "unknown button accepted")
  h, p = MENU.parse_combo(""); assert(h == 0 and p == 0, "empty combo should mean none")
  print("controller: combo, tabs, hints and swallowed buttons OK")
end

-- Health multiplier: the maximum times the slider, the bar keeps its share,
-- back to the game's own at x1; a maximum the game sets itself starts over.
do
  write_u32(P + 1908, 1000); write_f32(P + 1912, 500)
  F.items.health_mult.v = 3; update(1)
  assert(read_u32(P + 1908) == 3000 and math.abs(read_f32(P + 1912) - 1500) < 0.01, "x3 health: " .. read_u32(P + 1908))
  F.items.health_mult.v = 2; update(1)
  assert(read_u32(P + 1908) == 2000 and math.abs(read_f32(P + 1912) - 1000) < 0.01, "x2 health: " .. read_u32(P + 1908))
  write_u32(P + 1908, 1200); update(1)                  -- a health upgrade from the game
  assert(read_u32(P + 1908) == 2400, "new maximum not doubled: " .. read_u32(P + 1908))
  F.items.health_mult.v = 1; update(1)
  assert(read_u32(P + 1908) == 1200, "x1 should give the game's own maximum back: " .. read_u32(P + 1908))
  write_u32(P + 1908, 0); write_f32(P + 1912, 0)
end

-- Rapid fire: every weapon's own refire delay halved (never below 40 ms or
-- above the original), put back when off.
do
  F.items.fire.v = false; update(1)          -- an earlier test left rapid fire on
  local old_base, old_n = read_u32(0x832ABCA8), read_u32(0x832ABCAC)
  local W = 0x5C000000
  write_u32(0x832ABCA8, W); write_u32(0x832ABCAC, 3)
  write_u16(W + 122, 300); write_u16(W + 520 + 122, 60); write_u16(W + 1040 + 122, 0)
  F.items.fire.v = true; update(1)
  assert(read_u16(W + 122) == 150 and read_u16(W + 520 + 122) == 40 and read_u16(W + 1040 + 122) == 0, "refire not cut")
  update(3)
  assert(read_u16(W + 122) == 150, "cut more than once")
  F.items.fire.v = false; update(1)
  assert(read_u16(W + 122) == 300 and read_u16(W + 520 + 122) == 60, "refire not put back")
  write_u32(0x832ABCA8, old_base); write_u32(0x832ABCAC, old_n)
end

-- Rapid fire quadruples shotguns (class 3); harder hits triple the
-- killing-shot push (+304); both put back when off.
do
  local old_base, old_n = read_u32(0x832ABCA8), read_u32(0x832ABCAC)
  local W = 0x5C100000
  write_u32(0x832ABCA8, W); write_u32(0x832ABCAC, 2)
  write_u32(W + 20, 3); write_u16(W + 122, 800); write_f32(W + 304, 2.0)
  write_u32(W + 520 + 20, 0); write_u16(W + 520 + 122, 200); write_f32(W + 520 + 304, 0)
  F.items.fire.v = true; F.items.harder_hits.v = true; update(2)
  assert(read_u16(W + 122) == 200 and read_u16(W + 520 + 122) == 100, "shotgun x4 / gun x2")
  assert(read_f32(W + 304) == 6.0 and read_f32(W + 520 + 304) == 0, "harder hits")
  F.items.fire.v = false; F.items.harder_hits.v = false; update(1)
  assert(read_u16(W + 122) == 800 and read_f32(W + 304) == 2.0, "weapons not put back")
  write_u32(0x832ABCA8, old_base); write_u32(0x832ABCAC, old_n)
end

-- Soft landing raises the panic-fall speed, quick crouch the crouch camera;
-- the game's values come back off.
do
  F.items.landing.v = false; F.items.quick_crouch.v = false; update(1)   -- an earlier test left soft landing on
  write_f32(0x838F837C, 12); write_f32(0x827D9370, 3); write_f32(0x827D9374, 0.25)
  F.items.landing.v = true; F.items.quick_crouch.v = true; update(2)
  assert(read_f32(0x838F837C) == 100, "no flailing")
  assert(read_f32(0x827D9370) == 9 and read_f32(0x827D9374) == 0.75, "quick crouch")
  F.items.landing.v = false; F.items.quick_crouch.v = false; update(1)
  assert(read_f32(0x838F837C) == 12 and read_f32(0x827D9370) == 3 and read_f32(0x827D9374) == 0.25, "not put back")
end

-- Extra car grip: 5 more downforce on the car you drive, its own back when
-- you get out or switch it off.
do
  local ACT = 0x5D001000
  put_in_vehicle(true)
  write_u32(ENGINE + 216, ACT); write_f32(ACT + 28, -20)
  F.items.car_grip.v = true; update(2)
  assert(read_f32(ACT + 28) == -25, "grip not added: " .. read_f32(ACT + 28))
  put_in_vehicle(false); update(1)
  assert(read_f32(ACT + 28) == -20, "grip not put back on leaving: " .. read_f32(ACT + 28))
  put_in_vehicle(true); update(1)
  assert(read_f32(ACT + 28) == -25, "grip not added again")
  F.items.car_grip.v = false; update(1)
  assert(read_f32(ACT + 28) == -20, "grip not put back when off")
  put_in_vehicle(false); update(1)
end

-- Add-ons: Precise Aim runs only with its aim style picked and is released
-- when switched away; its camera is tuned from the Aim tab (files in the test
-- copy, never the repo); Weapon Switch gets its flags in the mailbox.
do
  local M = F.addon.precise
  assert(M and M.release and M.get, "Precise Aim not loaded")
  local function logged(text) for _, l in ipairs(logs) do if l == text then return true end end return false end
  F.items.aim_style.v = 2; update(1)
  local c = make_ctx(); c.regs[3] = 0; c.regs[5] = 0x49000300
  hooks[0x82788EC4](c)                                   -- a gated hook asks whether it is on
  assert(logged("Precise Aim on"), "Precise Aim should switch on with its aim style")
  F.items.aim_style.v = 1
  hooks[0x82788EC4](c)
  assert(logged("Precise Aim off"), "Precise Aim should switch off and release")
  -- Camera presets and sliders.
  local names = {}
  for _, e in ipairs(F.items.aim_camera.items) do names[e[1]] = e[2] end
  assert(names.SR1 == "Saints Row 1" and names.SR2022 == "Saints Row (2022)" and names.TPA, "presets missing")
  for i, e in ipairs(F.items.aim_camera.items) do if e[1] == "SR3" then F.items.aim_camera.v = i end end
  local msg = F.activate(make_ctx(), F.items.aim_camera)
  assert(msg == "Aim camera: Saints Row: The Third" and M.preset() == "SR3", msg)
  local z = M.get("zoom")
  F.adjust(make_ctx(), F.items.aim_zoom, 1)
  assert(math.abs(M.get("zoom") - (z + 0.25)) <= 0.125 + 1e-6, "zoom slider: " .. M.get("zoom"))   -- snaps to 0.25 steps
  msg = F.activate(make_ctx(), F.items.aim_reset)
  assert(math.abs(M.get("zoom") - z) < 1e-6, "reset should give the preset's zoom back")
  local f = io.open(TMP .. "/addons/precise_aim/camera.cfg", "r")
  assert(f, "camera.cfg not written in the test copy"); f:close()
  f = io.open(folder .. "/addons/precise_aim/camera.cfg", "r")
  assert(not f, "the test wrote into the repo"); if f then f:close() end
  -- Weapon Switch: on, then the menu open stands it aside.
  F.items.weapon_switch.v = true; update(1)
  assert(read_u32(0x00F00034) == 0x53524144 and read_u32(0x00F00030) == 1, "weapon switch flags")
  local MENU = require("menu")
  if not MENU.is_open() then press("F5") end
  update(1)
  assert(read_u32(0x00F00030) == 3, "menu open flag")
  press("F5")
  -- The D-pad and tap choices, and a menu combo held, reach Weapon Switch too.
  F.items.weapon_dpad.v, F.items.weapon_tap.v = 2, 2; update(1)
  assert(read_u32(0x00F00030) == 1 | 8 | 16, "D-pad / tap flags: " .. read_u32(0x00F00030))
  local PADC = 0x49000400
  write_u16(PADC + 4, 0x0200 | 0x0002)                   -- RB + D-pad Down, the menu combo
  local cc = make_ctx(); cc.regs[3] = 0; cc.regs[5] = PADC
  hooks[0x82788EC4](cc)
  assert((read_u32(0x00F00030) & 32) ~= 0, "combo flag")
  if require("menu").is_open() then press("F5") end
  write_u16(PADC + 4, 0); cc = make_ctx(); cc.regs[3] = 0; cc.regs[5] = PADC
  hooks[0x82788EC4](cc)
  assert((read_u32(0x00F00030) & 32) == 0, "combo flag cleared")
  F.items.weapon_dpad.v, F.items.weapon_tap.v = 1, 1
  F.items.weapon_switch.v = false; update(1)
  assert(read_u32(0x00F00030) == 0, "weapon switch off")
  -- Aim button: toggle / hold / the add-on's own, handed to Precise Aim.
  local own = M.toggle()
  F.items.aim_button.v = 3; F.apply_aim_button(); assert(M.toggle() == false, "hold")
  F.items.aim_button.v = 2; F.apply_aim_button(); assert(M.toggle() == true, "toggle")
  F.items.aim_button.v = 1; F.apply_aim_button(); assert(M.toggle() == own, "own setting")
  -- The aim rows are on Weapons > Aiming & switching (no Aim tab), with the
  -- turning and weapon switch rows, Aim style first.
  local tabs, in_tab = {}, {}
  for _, cat in ipairs(F.categories) do
    tabs[cat.name] = true
    for _, it in ipairs(cat.items) do in_tab[it.id] = cat.name end
  end
  assert(not tabs.Aim and in_tab.weapons_aiming == "Weapons" and not in_tab.aim_style, "aim rows not on Weapons > Aiming & switching")
  -- Precise Aim's camera rows are on their page; aim rows show only with their aim style.
  local cam = {}
  for _, it in ipairs(F.items.aim_camera_page.open().rows) do cam[it.id] = true end
  assert(cam.aim_camera and cam.aim_zoom and cam.aim_save and not in_tab.aim_camera, "Precise Aim camera page")
  local pos = {}
  for i, it in ipairs(F.items.weapons_aiming.open().rows) do pos[it.id] = i end
  assert(pos.aim_style == 1 and pos.aim_camera_page == 2 and pos.fine_aim_zoom == 3 and pos.fine_aim_spread == 4
    and pos.aim_button and pos.weapon_switch and pos.weapon_dpad, "aim rows under Aim style")
  local was = F.items.aim_style.v
  F.items.aim_style.v = 1
  assert(F.items.aim_camera_page.hidden() and F.items.fine_aim_zoom.hidden() and F.items.aim_button.hidden(), "aim rows hidden with the game's aim")
  F.items.aim_style.v = 2
  assert(not F.items.aim_camera_page.hidden() and F.items.fine_aim_zoom.hidden() and not F.items.precise_turning.hidden(), "Precise Aim rows")
  F.items.aim_style.v = 3
  assert(F.items.aim_camera_page.hidden() and not F.items.fine_aim_spread.hidden() and not F.items.aim_button.hidden(), "Fine Aim rows")
  F.items.aim_style.v = was
  local ws = F.items.weapon_switch.v
  F.items.weapon_switch.v = false; assert(F.items.weapon_dpad.hidden(), "D-pad row hidden with weapon switch off")
  F.items.weapon_switch.v = true; assert(not F.items.weapon_tap.hidden(), "wheel tap row shown with weapon switch on")
  F.items.weapon_switch.v = ws
  -- Money and respect on the Player tab; active tweaks on the Settings tab; UI+ rows are switches.
  assert(in_tab.money == "Player" and in_tab.respect == "Player" and in_tab.status == "Settings", "Player / Settings rows")
  assert(F.items.low_health_fx.kind == "toggle" and not F.items.low_health_fx.v, "UI+ rows are switches, off")
  -- The control preferences sit with what they control: camera turn speed on
  -- Visual > Camera, the aim and weapon switch rows on Weapons > Aiming &
  -- switching. None of them is loose on a tab.
  local function on_page(pg) local t = {} for _, it in ipairs(F.items[pg].open().rows) do t[it.id] = true end return t end
  local cam_page, aim_page = on_page("visual_camera"), on_page("weapons_aiming")
  assert(in_tab.visual_camera == "Visual" and cam_page.camera_turn and cam_page.fov, "Visual > Camera")
  for _, id in ipairs({ "aim_button", "precise_turning", "precise_aim_turn", "fine_aim_turn", "weapon_dpad", "weapon_tap" }) do
    assert(aim_page[id] and not in_tab[id], id .. " should be on Weapons > Aiming & switching")
  end
  assert(not in_tab.camera_turn and not F.items.settings_controls or in_tab.settings_controls == nil, "no Controls page left")
  -- Camera turn speed writes the game's look sensitivity (both axes).
  write_f32(0x827D9778 + 312, 1.0); write_f32(0x827D9778 + 316, 1.0)
  F.items.camera_turn.v = 1.0
  F.adjust(make_ctx(), F.items.camera_turn, 1)
  assert(math.abs(read_f32(0x827D9778 + 312) - 1.1) < 1e-4 and math.abs(read_f32(0x827D9778 + 316) - 1.1) < 1e-4, "camera turn speed")
  -- Precise Aim turning: the game's own by default.
  F.items.precise_turning.v = 2; F.apply_precise_turning()
  F.items.precise_turning.v = 1; F.apply_precise_turning()
  local pa = M.aim_sens(); F.adjust(make_ctx(), F.items.precise_aim_turn, -1)
  assert(math.abs(M.aim_sens() - (pa - 0.1)) < 1e-6, "Precise aim turn speed")
end

-- Help text: whole sentences, at most 90 characters a line and 3 lines;
-- Spawn person breaks after its "start a fight." sentence.
do
  local MENU = require("menu")
  for _, cat in ipairs(F.categories) do
    for _, it in ipairs(cat.items) do
      local help = it.help or ""
      if it.kind == "value" then help = help .. "  Default " .. it.fmt(it.default) .. "." end
      local lines = MENU.wrap_help(help)
      if os.getenv("SHOW_HELP") then for _, l in ipairs(lines) do print("HELP " .. it.id .. ": " .. l) end end
      assert(#lines <= 3, it.id .. " help takes " .. #lines .. " lines")
      for _, l in ipairs(lines) do assert(#l <= 90, it.id .. " help line too long: " .. l) end
    end
  end
end

-- Pickups: cash around the player, the money gun's bill thrown from the
-- player to where the bullet stopped, and the live cash drop chance.
do
  local F = require("features")
  local cash, vel = {}, nil
  local old_cash, old_vel = FAKE[0x82408C58], FAKE[0x82253F10]
  FAKE[0x82408C58] = function(ctx)
    local a = ctx.regs[3]
    cash[#cash + 1] = { read_f32(a), read_f32(a + 4), read_f32(a + 8), dollars = ctx.fregs[1], pop = ctx.regs[6] }
    write_u32(0x49000000 + 116, 7)
    ctx.regs[3] = 0x49000000
  end
  FAKE[0x82253F10] = function(ctx)
    assert(ctx.regs[3] == 7, "velocity on the bill's body")
    local a = ctx.regs[4]
    vel = { read_f32(a), read_f32(a + 4), read_f32(a + 8) }
  end
  write_f32(P + 20, 100); write_f32(P + 24, 10); write_f32(P + 28, 200)
  F.queue_drops("cash", 10)
  update(5)
  assert(#cash == 10, "10 bills dropped, got " .. #cash)
  for _, c in ipairs(cash) do
    local d = math.sqrt((c[1] - 100) ^ 2 + (c[3] - 200) ^ 2)
    assert(d >= 2 and d <= 7.01 and c.dollars >= 10 and c.dollars <= 500 and c.pop == 1, "bill placed badly")
  end
  -- Money gun: off, a shot does nothing; on, one bill flies at the hit.
  cash = {}
  local out = 0x49200000
  write_f32(out, 120); write_f32(out + 4, 11.3); write_f32(out + 8, 200)
  local function shot(shooter)
    local ctx = make_ctx(); ctx.regs[3] = out; ctx.regs[5] = shooter
    hooks[0x8246FD18](ctx)
  end
  F.items.money_gun.v = false; shot(P); update(1)
  assert(#cash == 0, "money gun off still dropped")
  F.items.money_gun.v = true
  shot(0x45000000); update(1)
  assert(#cash == 0, "someone else's shot dropped cash")
  F.items.money_gun_cash.v = 250
  shot(P); update(1)
  assert(#cash == 1 and cash[1].dollars == 250 and cash[1].pop == 0, "money gun bill")
  assert(math.abs(cash[1][1] - 100.8) < 0.01 and math.abs(cash[1][2] - 11.3) < 0.01, "bill starts at the gun")
  assert(vel and vel[1] > 15 and math.abs(vel[3]) < 1e-3 and vel[2] > 0, "bill thrown at the hit")
  F.items.money_gun.v = false; F.items.money_gun_cash.v = 100
  -- Cash drop chance: written while moved, the game's value back at 25%.
  F.items.cash_drop_chance.v = 25; update(1)   -- (the walk may have left it moved)
  write_f32(0x838F8520, 0.25); write_f32(0x838F8524, 0.25)
  F.items.cash_drop_chance.v = 100; update(1)
  assert(read_f32(0x838F8520) == 1 and read_f32(0x838F8524) == 1, "drop chance not written")
  F.items.cash_drop_chance.v = 25; update(1)
  assert(math.abs(read_f32(0x838F8520) - 0.25) < 1e-6, "drop chance not put back")
  -- The new rows: weapons list starts with the random mix; the bill value hides with the gun off.
  assert(F.items.weapon_rain.items[1][1] == "random" and #F.items.weapon_rain.items == #F.items.give_weapon.items + 1, "weapon drop list")
  assert(F.items.money_gun_cash.hidden(), "bill value shown with the money gun off")
  FAKE[0x82408C58], FAKE[0x82253F10] = old_cash, old_vel
end

-- Explosive punches: your melee hit on a person or a car blows it up on the
-- next update, as the console's explosion does; you're shielded first;
-- other damage (the blast's own, fire) never sets one off.
do
  local F = require("features")
  local V2 = 0x55000000
  write_u32(V2 + 72, 1); write_u32(V2 + 68, 0x0009002A); write_u32(V2 + 216, 0)
  write_u32(0x830866C8 + 12 + 0x2A * 16, V2)
  write_u32(P + 3548, 0)
  local blasts, def_name = {}, nil
  FAKE[0x82138FB0] = function(c) def_name = read_cstr(c.regs[3]); c.regs[3] = 0x4A000000 end
  FAKE[0x82138AE8] = function(c)
    assert(c.regs[3] == 0x4A000000 and c.regs[4] == P and c.regs[6] == V2 + 32 and c.regs[7] == V2 + 20, "explosion args")
    assert(read_u32(c.regs[1] + 84) == 0 and read_u32(c.regs[1] + 92) == 0, "explosion stack args")
    assert(G_shielded(), "not shielded before the blast")
    blasts[#blasts + 1] = true
  end
  function G_shielded() return F.shields.punch ~= nil end
  local function hit(target)
    local dctx = make_ctx(); dctx.regs[3], dctx.regs[4] = target or V2, P
    hooks[0x824560D8](dctx)
  end
  local function damage()
    local dctx = make_ctx(); dctx.regs[3], dctx.regs[4] = V2, P
    hooks[0x824470D0](dctx)
  end
  F.items.explosive_punch.v = false; hit(); update(1)
  assert(#blasts == 0, "punch blew up with the switch off")
  F.items.explosive_punch.v = true; F.items.punch_blast.v = 3
  damage(); update(1)
  assert(#blasts == 0, "plain damage (not a melee hit) set off a blast")
  hit(); assert(#blasts == 0, "blast must wait for the update"); update(1)
  assert(#blasts == 1 and def_name == "RPG", "punch blast: " .. tostring(def_name))
  hit(); update(1)
  assert(#blasts == 1, "a second hit inside half a second blew up again")
  -- A car: type 5.
  local CAR = 0x56000000
  write_u32(CAR + 72, 5); write_u32(CAR + 68, 0x0009002B)
  write_u32(0x830866C8 + 12 + 0x2B * 16, CAR)
  local car_ok = false
  local old_blast = FAKE[0x82138AE8]
  FAKE[0x82138AE8] = function(c) car_ok = c.regs[7] == CAR + 20 end
  local t0 = os.clock(); while os.clock() - t0 < 0.55 do end
  F.items.punch_blast.v = 1
  hit(CAR); update(1)
  assert(car_ok and def_name == "Propane Tank", "car punch: " .. tostring(def_name))
  FAKE[0x82138AE8] = old_blast
  assert(not F.items.punch_blast.hidden(), "blast size shown with punches on")
  F.items.explosive_punch.v = false
  assert(F.items.punch_blast.hidden(), "blast size hidden with punches off")
  -- The pimp slap is in the weapon lists; bills go up in hundreds.
  local found = false
  for _, w in ipairs(F.items.give_weapon.items) do if w[1] == "pimp_slap" then found = true end end
  assert(found, "Pimp Slap missing from Give weapon")
  assert(F.items.money_gun_cash.step == 100 and F.items.money_gun_cash.max == 10000, "bill value in hundreds")
end

-- Holding Back never opens the menu, and the game always gets its Back.
do
  local MENU = require("menu")
  if MENU.is_open() then press("F5") end
  for _ = 1, 100 do
    local blank, hide = MENU.controller(MENU.PAD.BACK, 0, 0)
    assert(not blank and (hide & MENU.PAD.BACK) == 0, "Back kept from the game")
    update(1)
  end
  assert(not MENU.is_open(), "holding Back opened the menu")
  MENU.controller(0, 0, 0); update(1)
end

print(string.format("\n%d script calls, %d console lines, %d HUD messages, %d errors", #scripts, #consoles, #hud_texts, errors))
for _, s in ipairs(scripts) do print("  script: " .. s) end
for _, s in ipairs(consoles) do print("  console: " .. s) end
assert(errors == 0, "there were errors")
-- Menu look: itsMJQ's game look builds a frame for every tab and page (fonts
-- faked: the test has no game textures), switches live, and goes back to
-- the plain text.
do
  local MENU = require("menu")
  local GAMEUI = require("gameui")
  local real = { width = GAMEUI.width, line_height = GAMEUI.line_height, ready = GAMEUI.ready }
  GAMEUI.width = function(_, _, s) return #s * 9 end
  GAMEUI.line_height = function() return 20 end
  GAMEUI.ready = function() return true end
  MENU.set_style("game")
  assert(MENU.style() == "game")
  if not MENU.is_open() then press("F5") end
  local frames = 0
  for _ = 1, #F.categories do
    update(1)
    assert(type(GAMEUI.frame) == "table" and #GAMEUI.frame > 10, "no game-look frame on " .. MENU.tab_name())
    frames = frames + 1
    -- one level into each page on the tab
    local cat
    for _, c in ipairs(F.categories) do if c.name == MENU.tab_name() then cat = c end end
    press("PAGEDOWN")
  end
  assert(#F.items.status.open().rows > 0, "the changed settings page")
  update(1)
  -- Every page on every tab draws in the game look too (the same rows as the
  -- plain text): lists show their position, and Menu background sets the boxes.
  local pages_drawn = 0
  for t, cat in ipairs(F.categories) do
    for _, it in ipairs(cat.items) do
      if it.kind == "page" then
        local ok, pg = pcall(it.open, make_ctx(), P)
        if ok and type(pg) == "table" and pg.rows then
          MENU.tab = t
          pg.cursor, pg.scroll = 1, 1
          MENU.pages[#MENU.pages + 1] = pg
          local built, fr = pcall(MENU.build_frame, make_ctx())
          table.remove(MENU.pages)
          assert(built and type(fr) == "table", "game look of page " .. it.label .. ": " .. tostring(fr))
          pages_drawn = pages_drawn + 1
        end
      end
    end
  end
  assert(pages_drawn > 20, "pages drawn in the game look: " .. pages_drawn)
  local list_row = F.items.give_item
  local function frame_has(fr, needle)
    for _, op in ipairs(fr) do if op.text and op.text:find(needle, 1, true) then return true end end
    return false
  end
  for t, cat in ipairs(F.categories) do
    for i, it in ipairs(cat.items) do
      if it == list_row then MENU.tab = t; MENU.cursor[t] = i; MENU.scroll[t] = math.max(1, i - 2) end
    end
  end
  F.items.menu_background.v = 100
  local fr100 = MENU.build_frame(make_ctx())
  F.items.menu_background.v = 60
  local fr60 = MENU.build_frame(make_ctx())
  local function box_alpha(fr) for _, op in ipairs(fr) do if op.image == "ui_menu_box_base_c" then return op.colour[4] end end end
  assert(box_alpha(fr60) == 200 and box_alpha(fr100) == 255, "menu background sets the game look's boxes")
  assert(frame_has(fr60, "/" .. #list_row.items), "lists show their position in the game look")
  print("game look: " .. pages_drawn .. " pages drawn")
  MENU.set_style("text"); update(1)
  assert(GAMEUI.frame == nil and MENU.style() == "text", "back to plain text")
  F.items.menu_look.v = 2; F.items.menu_look.change(make_ctx(), 0, 0, F.items.menu_look)
  assert(MENU.style() == "game", "Menu look row switches the look")
  local f = io.open(TMP .. "/mod.ini", "r")
  local saved = f and f:read("a") or ""
  if f then f:close() end
  F.items.menu_look.v = 1; F.items.menu_look.change(make_ctx(), 0, 0, F.items.menu_look)
  if MENU.is_open() then press("F5") end
  GAMEUI.width, GAMEUI.line_height, GAMEUI.ready = real.width, real.line_height, real.ready
  print("menu look: game frames built on " .. frames .. " tabs, switched live and back OK")
end

-- Rows after the forum mods (extras.lua): each one changes what it should
-- and puts the game's own back when switched off.
do
  local F = require("features")
  local MENU = require("menu")
  if MENU.is_open() then press("F5") end
  -- A name hash the fakes can tell apart.
  local function fake_hash(s) local h = 7 for i = 1, #s do h = (h * 31 + s:byte(i)) & 0xFFFFFFFF end return h end
  FAKE[0x82637C18] = function(ctx) ctx.regs[3] = fake_hash(read_cstr(ctx.regs[3])) end
  FAKE[0x82637B58] = function(ctx) ctx.regs[3] = fake_hash("b:" .. read_cstr(ctx.regs[3])) end

  -- No health regen: both regen rates to 0 and back.
  write_f32(0x838F842C, 50); write_f32(0x838F8434, 25)
  F.items.no_regen.v = true; update(1)
  assert(read_f32(0x838F842C) == 0 and read_f32(0x838F8434) == 0, "no regen should zero both rates")
  F.items.no_regen.v = false; update(1)
  assert(read_f32(0x838F842C) == 50 and read_f32(0x838F8434) == 25, "regen rates back")

  -- Sprint presets: Multiplayer's numbers, then the game's own; the spray-tag bonus untouched.
  write_f32(0x8309ABE0, 1.5)
  F.items.sprint_preset.v = 2; update(1)
  assert(read_f32(0x8309ABE4) == 3000 and read_f32(0x8309ABDC) == 6000 and math.abs(read_f32(0x8309ABCC) - 0.2) < 1e-6,
    "multiplayer sprint")
  F.items.sprint_preset.v = 1; update(1)
  assert(read_f32(0x8309ABE4) == 10000 and read_f32(0x8309ABCC) == 0, "game's own sprint back")
  assert(read_f32(0x8309ABE0) == 1.5, "the spray-tag bonus is never written")

  -- D-pad heal: the heal bit added to what the on-foot controls gave.
  F.items.dpad_heal.v = true; update(1)
  local c = make_ctx(); c.regs[3] = P
  c.call_original = function() write_u32(P + 4472, 0x2404) end
  hooks[0x82167690](c)
  assert(read_u32(P + 4472) == 0xA404, "heal bit should be added")
  F.items.dpad_heal.v = false; update(1)
  write_u32(P + 4472, 0)

  -- D-pad taunts: left plays taunt 2 (action 599) on the next update.
  local played
  FAKE[0x82444F88] = function(ctx) played = ctx.regs[4]; ctx.regs[3] = 1 end
  write_u32(P + 1956, 0xFFFFFFFF)
  F.items.dpad_taunts.v = 2; update(1)
  local PAD = 0x46000000
  c = make_ctx(); c.regs[3], c.regs[4] = 0, PAD
  c.call_original = function() write_u16(PAD + 4, 0x4) end
  hooks[0x827166D0](c)
  update(1)
  assert(played == 599, "D-pad left should play taunt 2, got " .. tostring(played))
  F.items.dpad_taunts.v = 1; update(1)

  -- Bouncy and less stiff cars, on every car in the vehicle list.
  local INFO, ACTION, DAMPER = 0x47000000, 0x47100000, 0x47200000
  write_u32(0x83289904, V); write_u32(V + 50308, V); write_u32(V + 50324, INFO)
  write_u8(V + 50300, 1); write_u32(V + 224, ENGINE)
  write_u32(ENGINE + 216, ACTION); write_f32(ACTION + 28, -20); write_f32(INFO + 652, -20)
  write_u32(ENGINE + 72, DAMPER); write_f32(DAMPER + 8, 1); write_f32(DAMPER + 12, 3)
  write_f32(INFO + 904, 1); write_f32(INFO + 908, 3)
  F.items.bouncy_cars.v = true; update(5)
  assert(read_f32(ACTION + 28) == F.items.bounce_strength.v, "bouncy cars should push cars up")
  F.items.bouncy_cars.v = false; update(1)
  assert(read_f32(ACTION + 28) == -20, "bouncy cars off: the car's own downforce back")
  F.items.soft_spin.v = true; update(10)
  assert(read_f32(DAMPER + 8) == 0.5 and read_f32(DAMPER + 12) == 1.5, "less stiff cars should halve the damping")
  F.items.soft_spin.v = false; update(1)
  assert(read_f32(DAMPER + 8) == 1 and read_f32(DAMPER + 12) == 3, "less stiff cars off: the table's damping back")

  -- Gangs drive ordinary cars: the gang paint taken off a spawn group and a notoriety team, then put back.
  local GROUP, REC = 0x48000000, 0x48100000
  write_u32(0x8370D028, GROUP); write_u32(0x8370D024, 1)
  write_u32(GROUP + 56, 1); write_u32(GROUP + 1084, REC); write_u32(REC + 4, fake_hash("Gang_LC"))
  write_u32(0x82831C18 + 472, 0x82047BA0)
  F.items.gang_civ_cars.v = true; update(100)
  assert(read_u32(GROUP + 1084) == 0 and read_u32(0x82831C18 + 472) == 0, "gang paint should be taken off")
  F.items.gang_civ_cars.v = false; update(1)
  assert(read_u32(GROUP + 1084) == REC and read_u32(0x82831C18 + 472) == 0x82047BA0, "gang paint back")

  -- Gangs and police without guns: a Thug's firearm and thrown chances to 0, melee to 100; crews get nothing.
  local RANK = 0x829A0028
  write_u32(0x8370D038, 1); write_u32(RANK, fake_hash("Thug"))
  for t = 0, 6 do
    local b = RANK + 20 + t * 204
    write_u8(b, 10); write_u8(b + 1, 2); write_u8(b + 68, 100); write_u8(b + 136, 5)
  end
  F.items.no_guns.v = true; update(100)
  assert(read_u8(RANK + 20) == 100 and read_u8(RANK + 20 + 68) == 0 and read_u8(RANK + 20 + 136) == 0, "no guns for a Thug")
  local gave = false
  c = make_ctx(); c.call_original = function() gave = true end
  hooks[0x823FC7E0](c)
  assert(not gave, "notoriety crews should get no gun")
  F.items.no_guns.v = false; update(1)
  assert(read_u8(RANK + 20) == 10 and read_u8(RANK + 20 + 68) == 100 and read_u8(RANK + 20 + 136) == 5, "ranks back")

  -- Rewards: refused until the row is in the game's table, then queued and unlocked.
  local unlocked
  FAKE[0x82226738] = function(ctx) unlocked = ctx.regs[3] end
  local pg = F.items.reward_bulletproof.open()
  local msg = pg.rows[1].run(make_ctx())
  assert(msg:find("Restart"), "a reward not in the table yet should ask for a restart: " .. tostring(msg))
  write_u32(0x82B8C294 + 60, 1); write_u32(0x82B8C294 + 68, fake_hash("srt_bulletproof"))
  pg = F.items.reward_bulletproof.open()
  pg.rows[1].run(make_ctx()); update(10)
  assert(unlocked == fake_hash("srt_bulletproof"), "the reward should be unlocked")

  -- Money rain: bills on foot.
  local before = 0
  for _, a in ipairs(calls) do if a == 0x82408C58 then before = before + 1 end end
  F.items.money_rain.v = true; update(50)
  local after = 0
  for _, a in ipairs(calls) do if a == 0x82408C58 then after = after + 1 end end
  assert(after - before >= 2, "money rain should make bills")
  F.items.money_rain.v = false; update(1)

  -- First person field of view: on top of First Person's while the camera is at your head, not otherwise.
  local CAM = 0x827D9778
  local px, py, pz = read_f32(P + 20), read_f32(P + 24), read_f32(P + 28)
  write_u32(CAM, 0); write_f32(0x827D93C0, 0)
  write_f32(CAM + 44, px); write_f32(CAM + 48, py + 1.6); write_f32(CAM + 52, pz + 0.1)
  F.items.fp_fov.v = 100; update(1)
  c = make_ctx(); c.call_original = function() write_f32(CAM + 188, 75) end
  hooks[0x82109608](c)
  assert(read_f32(CAM + 188) == 100, "first person field of view should go on top")
  write_f32(CAM + 48, py + 4); hooks[0x82109608](c)
  assert(read_f32(CAM + 188) == 75, "third person keeps its own field of view")
  F.items.fp_fov.v = F.items.fp_fov.default; update(1)
  write_f32(0x827D93C0, 3)

  -- First person row: refused without First Person 1.4; with it, a request in the shared block, and the row
  -- follows First Person (V switches it too).
  local FPS = 0x00F01000
  write_u32(FPS, 0)
  local msg2 = F.toggle(make_ctx(), F.items.first_person)
  assert(not F.items.first_person.v and msg2:find("Press V"), "first person needs First Person 1.4")
  write_u32(FPS, 0x46505357); write_u32(FPS + 4, 0); write_u32(FPS + 8, 0)
  F.toggle(make_ctx(), F.items.first_person)
  assert(read_u32(FPS + 8) == 1, "the menu should ask First Person to switch on")
  update(1)
  assert(F.items.first_person.v, "the row stays on while the request waits")
  write_u32(FPS + 8, 0); write_u32(FPS + 4, 1); update(1)
  assert(F.items.first_person.v, "first person on")
  write_u32(FPS + 4, 0); update(1)
  assert(not F.items.first_person.v, "V switched it off: the row follows")
  write_u32(FPS, 0)

  -- Give item: the picked item, as many as asked, through the game's own inv_item_add.
  F.items.give_item.v = 2; F.items.give_item_count.v = 3
  local gave_msg = F.activate(make_ctx(), F.items.give_item)
  assert(scripts[#scripts]:find('inv_item_add("blunt", 3, "#PLAYER#")', 1, true) and gave_msg:find("Blunt"),
    "give item: " .. tostring(scripts[#scripts]))

  -- Show active tweaks lists every setting that isn't the game's own, by where it is; the two restores.
  F.items.no_regen.v = true; F.items.bounce_strength.v = 40; F.items.skin_rpg.v = 3; F.items.weather.v = 4; F.items.fov.v = 1.3
  local shown = {}
  for _, r in ipairs(F.items.status.open().rows) do shown[r.id or r.label] = true end
  assert(shown.no_regen and shown.bounce_strength and shown.skin_rpg and shown.weather and shown.fov,
    "changed settings should all be listed (the field of view too)")
  assert(shown["Player > Health & damage"] and shown["Weapons > Skins"], "grouped by tab and page")
  assert(not shown.give_item_count and not shown.wanted_police, "pickers and live readouts aren't settings")
  local back = F.items.restore_game.open()
  F.activate(make_ctx(), back.rows[1]); update(2)
  assert(not F.items.no_regen.v and F.items.bounce_strength.v == 25 and F.items.skin_rpg.v == 1 and F.items.weather.v == 1
    and F.items.fov.v == 1.0 and not F.items.crouch_moving.v, "restore game defaults")
  back = F.items.restore_menu.open()
  F.activate(make_ctx(), back.rows[1]); update(2)
  assert(math.abs(F.items.fov.v - 1.2) < 1e-6 and F.items.crouch_moving.v and F.items.car_free_cam.v, "restore menu defaults (mod.ini)")
  local none = F.items.restore_game.open(); F.activate(make_ctx(), none.rows[1]); update(1)

  -- Menu background: a box under the plain text menu while it's open, as solid as the setting; none when Off.
  local GUI = require("gameui")
  if not MENU.is_open() then press("F5") end
  F.items.menu_background.v = 60; update(1)
  local bd = GUI.backdrop
  assert(bd and bd.colour[4] == 153 and bd.w > 300 and bd.h > 150 and bd.x > 0 and bd.y > 0, "menu background box")
  F.items.menu_background.v = 0; update(1)
  assert(GUI.backdrop == nil, "no box when Off")
  press("F5"); update(1)
  assert(GUI.backdrop == nil, "no box with the menu closed")
  F.items.menu_background.v = 60

  -- Pictures draw when the game keeps the texture and the vertex buffer high up (0xC0000000 and over, as
  -- some builds do), and a picture that can't be drawn says why in the log, once.
  FAKE[0x82643430] = function(ctx) ctx.regs[3] = read_cstr(ctx.regs[4]) == "test_box" and 5 or 0xFFFF end
  FAKE[0x82641418] = function(ctx) ctx.regs[3] = 0xC0002000 end
  write_u32(0x8370DD60, 100); write_u32(0x82FF5EC8 + 5 * 20, 2)
  write_u32(0x82FF5EC8 + 5 * 20 + 12, 64); write_u32(0x82FF5EC8 + 5 * 20 + 16, 64)
  write_u32(0x82FFAEC8 + 2 * 8 + 4, 3); write_u32(0x832B61CC, 10)
  write_u32(0x832B6024, 0x50000000); write_u32(0x50000000 + 3 * 20 + 4, 0xC0001000)
  write_u16(0xC0001000 + 4, 256); write_u16(0xC0001000 + 6, 256)
  GUI.backdrop = { image = "test_box", x = 10, y = 20, w = 100, h = 50, colour = { 128, 128, 128, 200 } }
  hooks[0x82200700](make_ctx())
  assert(math.abs(read_f32(0xC0002000 + 28) - 110) < 0.01 and read_u32(0xC0002000 + 16) == 0xC8808080,
    "a picture with its texture and vertex buffer high up draws")
  GUI.backdrop.image = "not_a_picture"
  local before = #logs
  hooks[0x82200700](make_ctx()); hooks[0x82200700](make_ctx())
  assert(#logs == before + 1 and logs[#logs]:find("not_a_picture skipped", 1, true), "a skipped picture is logged once")
  GUI.backdrop = nil; FAKE[0x82643430] = nil; FAKE[0x82641418] = nil

  -- Over-the-shoulder camera: eased in to the full move along the camera's right and forward rows, no drift
  -- while the game leaves the position alone, eased back out when switched off.
  put_in_vehicle(false)
  local CAMX = 0x827D9778
  write_u32(CAMX, 0); write_u32(0x827DA15C, 6); write_f32(0x827D93C0, 3)
  write_f32(CAMX + 80, 1); write_f32(CAMX + 84, 0); write_f32(CAMX + 88, 0)
  write_f32(CAMX + 104, 0); write_f32(CAMX + 108, 0); write_f32(CAMX + 112, 1)
  write_f32(CAMX + 44, 10); write_f32(CAMX + 48, 5); write_f32(CAMX + 52, 10)
  F.items.shoulder_cam.v = true; F.items.shoulder_side.v = 0.6; F.items.shoulder_closer.v = 0.8
  local cam = make_ctx()   -- the game's own camera update leaves the position where it is
  for _ = 1, 80 do hooks[0x82109608](cam) end
  assert(math.abs(read_f32(CAMX + 44) - 10.6) < 0.01 and math.abs(read_f32(CAMX + 52) - 10.8) < 0.01
    and math.abs(read_f32(CAMX + 48) - 5) < 0.001, "shoulder camera moved, without drift: "
    .. read_f32(CAMX + 44) .. " " .. read_f32(CAMX + 52))
  F.items.shoulder_cam.v = false
  for _ = 1, 80 do hooks[0x82109608](cam) end
  assert(math.abs(read_f32(CAMX + 44) - 10) < 0.01 and math.abs(read_f32(CAMX + 52) - 10) < 0.01, "shoulder camera eased out")

  -- Saved places: save where you stand, rename (typing and the letter list), go there facing the saved way, delete.
  write_f32(P + 20, 120.5); write_f32(P + 24, 15.25); write_f32(P + 28, -340.75)
  for i = 0, 8 do write_f32(P + 32 + i * 4, (i % 4 == 0) and 1 or 0) end
  local MYP = require("myplaces")
  MYP.list = {}   -- (the walk through every row above saved one)
  local places = F.items.saved_places.open()
  assert(places.rows[1].label == "Save this spot", "saved places page")
  local said = F.activate(make_ctx(), places.rows[1])
  assert(said:find("Place 1"), "save this spot: " .. tostring(said))
  assert(#MYP.list == 1 and math.abs(MYP.list[1].x - 120.5) < 1e-3, "the spot is saved")
  local entry = places.rows[3].open()
  local ren = entry.rows[2].open()
  assert(ren.typing, "the rename page takes typing")
  ren.rows[5].run()                       -- Clear
  ren.type("H"); ren.type("q")
  ren.rows[2].v = 4; F.activate(make_ctx(), ren.rows[2])   -- the letter list: D
  ren.rows[3].run()                       -- Space
  F.activate(make_ctx(), ren.rows[6])     -- Save name
  assert(MYP.list[1].name == "HqD", "renamed: " .. MYP.list[1].name)
  local f = io.open(TMP .. "/saved_places.txt", "r"); local text = f:read("a"); f:close()
  assert(text:find("\tHqD\n"), "saved to the file")
  write_f32(P + 20, 0); write_f32(P + 32, 0)
  local tp
  FAKE[0x82481000] = function(ctx) tp = { read_f32(ctx.regs[4]), read_f32(ctx.regs[4] + 8), read_f32(ctx.regs[5]) } end
  F.activate(make_ctx(), entry.rows[1])
  assert(tp and math.abs(tp[1] - 120.5) < 1e-3 and math.abs(tp[2] + 340.75) < 1e-3 and tp[3] == 1, "go there with the saved facing")
  local del = entry.rows[4].open()
  F.activate(make_ctx(), del.rows[1])
  assert(#MYP.list == 0, "deleted")
  print("forum rows: regen, sprint, D-pad heal and taunts, cars, gang cars, no guns, rewards and money rain OK")
end

print("OK")
