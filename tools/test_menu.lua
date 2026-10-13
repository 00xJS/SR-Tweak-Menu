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
        -- Lists pick with Left/Right on the row and act on Enter.
        local before = it.v
        press("RIGHT")
        if it.usable then
          -- With only one usable entry, Right may stay on it.
        else
          assert(it.v == before % #it.items + 1, "Right should move to the next entry")
        end
        press("ENTER")
        assert(require("menu").is_open(), "the menu stays open after picking")
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
  -- A state pose.
  F.items.pose.v = 1
  local msg = F.activate(make_ctx(), F.items.pose)
  assert(msg == "Pose: Dance 1" and read_u32(P + 952) == 159, msg)
  write_u32(P + 952, 42); update(1)                    -- the game reset it while still
  assert(read_u32(P + 952) == 159, "pose not held")
  write_f32(P + 20, read_f32(P + 20) + 2); update(1)    -- moved: the pose ends
  assert(F.posing == nil, "moving should end the pose")
  write_f32(P + 20, read_f32(P + 20) - 2)
  -- A file pose: played directly, marked as a custom animation, replayed when it ends.
  for i, pose in ipairs(F.items.pose.items) do if pose[2] == "Read the paper" then F.items.pose.v = i end end
  msg = F.activate(make_ctx(), F.items.pose)
  assert(msg == "Pose: Read the paper", msg)
  assert(played_files[#played_files] == "PML1_BS_RdPpr.anim" and read_u32(P + 756) == 297 and read_u32(P + 760) == 0x00AB0001,
    "file pose not played: " .. tostring(played_files[#played_files]) .. " " .. read_u32(P + 756) .. " " .. msg)
  write_u32(P + 756, 0); update(1)
  assert(read_u32(P + 756) == 297, "file pose not replayed")
  F.activate(make_ctx(), F.items.stop_pose)
  -- A pose your character hasn't got: picking it says so, browsing skips it.
  for i, pose in ipairs(F.items.pose.items) do if pose[2] == "Pose" then F.items.pose.v = i end end
  msg = F.activate(make_ctx(), F.items.pose)
  assert(msg == "Your character can't do that one", msg)
  F.items.pose.v = F.items.pose.v - 1
  F.adjust(make_ctx(), F.items.pose, 1)
  assert(F.items.pose.items[F.items.pose.v][2] ~= "Pose", "browsing should skip a pose the character hasn't got")
  F.activate(make_ctx(), F.items.stop_pose)
  -- Locked by an action: RB + D-pad Up frees the player and restores the lock fields.
  write_u32(P + 4040, 0); write_u8(P + 3593, 0)
  F.items.repeat_action.v = true
  F.items.action.v = 1
  F.activate(make_ctx(), F.items.action)
  assert(read_u32(P + 4040) == 3 and (read_u8(P + 3593) & 16) ~= 0, "action should mark the player busy")
  if require("menu").is_open() then press("F5") end
  keys_down["W"] = true; update(1); keys_down["W"] = nil
  assert(F.repeating ~= nil, "W alone should not stop a repeat any more")
  local PADS = 0x49000200
  local function pad(buttons)
    write_u16(PADS + 4, buttons)
    local c = make_ctx(); c.regs[3] = 0; c.regs[5] = PADS
    hooks[0x82788EC4](c)
    return read_u16(PADS + 4)
  end
  pad(0x0200)                                  -- RB held
  local seen = pad(0x0200 | 0x0001)            -- then D-pad Up
  assert((seen & 0x0001) == 0, "D-pad Up should be kept from the game while RB is held")
  update(1); pad(0)
  assert(F.repeating == nil and read_u32(P + 4040) == 0 and (read_u8(P + 3593) & 16) == 0, "RB + Up should free the player")
  -- A pose puts back exactly the state the player was in before.
  write_u32(P + 952, 77)
  F.items.pose.v = 1
  F.activate(make_ctx(), F.items.pose)
  pad(0x0200); pad(0x0201); update(1); pad(0)
  assert(read_u32(P + 952) == 77, "the player's own state should come back, got " .. read_u32(P + 952))
  F.items.repeat_action.v = false
  press("F5")
  -- Counts: the Pose row counts only what the character can do ("pose" is missing here).
  F.refresh_usable(make_ctx())
  local missing = {}
  for i, pose in ipairs(F.items.pose.items) do
    local found = false
    for _, k in ipairs(F.items.pose.ok) do if k == i then found = true end end
    if not found then missing[#missing + 1] = type(pose[1]) == "table" and pose[1].file or pose[1] end
  end
  assert(#F.items.pose.ok == #F.items.pose.items - 1, "usable count should leave out only the missing pose; missing: " .. table.concat(missing, ", "))
  assert(F.list_position(F.items.pose):match("/" .. (#F.items.pose.items - 1) .. "$"), F.list_position(F.items.pose))
  -- An action, played directly.
  local scripts_before = #scripts
  F.items.action.v = 1
  msg = F.activate(make_ctx(), F.items.action)
  assert(msg == "Flip off" and played_actions[#played_actions] == P, msg)
  assert(#scripts == scripts_before, "actions must not use the script engine")

  -- Repeat action: the last action plays again every few seconds until you move.
  F.items.repeat_action.v = true
  F.items.action.v = 1
  F.activate(make_ctx(), F.items.action)
  local plays = #played_actions
  update(math.floor(F.items.repeat_every.v * 50) + 2)
  assert(#played_actions > plays, "action not repeated")
  write_f32(P + 20, read_f32(P + 20) + 2); update(1)
  assert(F.repeating == nil, "moving should stop repeating")
  write_f32(P + 20, read_f32(P + 20) - 2)
  F.items.repeat_action.v = false

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
  wml.mouse_look = function() return 0.5, 0.3 end
  update(1)
  wml.mouse_look = function() return 0, 0 end
  F.FREECAM.before_update()
  local fx, fz = read_f32(CAM + 104), read_f32(CAM + 112)
  assert(math.abs(fx - math.sin(F.FREECAM.aim_yaw) * math.cos(F.FREECAM.aim_pitch)) < 0.01 and fx > 0.3, "aim camera not turned by the mouse")
  local bx, bz = read_f32(CAM + 44), read_f32(CAM + 52)
  assert(math.abs((10 - bx) - fx * 3.0) < 0.05 and math.abs((20 - bz) - fz * 3.0) < 0.05, "aim camera not behind the player")
  assert(F.FREECAM.aim_pitch == 0 and math.abs(read_f32(CAM + 108)) < 1e-6 and math.abs(read_f32(CAM + 48) - (5 + 1.2)) < 0.01, "aim should stay level at chest height")
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
  F.items.god.v = false; update(1)
  local cheat_name, cheat_rounds
  FAKE[0x821F56C0] = function(ctx) cheat_name = read_cstr(read_u32(ctx.regs[3])); cheat_rounds = read_u32(ctx.regs[3] + 4) end
  for i, w in ipairs(F.items.give_weapon.items) do if w[2] == "Vice 9" then F.items.give_weapon.v = i end end
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
  assert(taken["SHIFT"] and taken["R"] and taken["Q"], "keyboard keys mapped onto the pad not taken")
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
  local sp = MENU.wrap_help(F.items.spawn_person.help)
  assert(sp[2]:find("^They come as civilians") and sp[2]:find("fight%.$"), "spawn person should break after the fight sentence: " .. table.concat(sp, " | "))
end

print(string.format("\n%d script calls, %d console lines, %d HUD messages, %d errors", #scripts, #consoles, #hud_texts, errors))
for _, s in ipairs(scripts) do print("  script: " .. s) end
for _, s in ipairs(consoles) do print("  console: " .. s) end
assert(errors == 0, "there were errors")
print("OK")
