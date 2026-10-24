-- SR Tweak Menu - runtime part.
--
-- Hooks the game update (0x82209E30, ~50 Hz on the main thread) and from
-- there drives the menu (menu.lua), applies every feature (features.lua) and
-- runs the on-foot tweaks that need per-update measuring: run boost, high
-- jump and soft landing. The game keeps no table for on-foot speed or jump
-- height, so these work on the result: after every update the player's
-- movement is measured and the player is moved a little further the same way
-- with the game's own teleport (0x8243E6F8, the call the trainer's No Clip
-- uses), and the jump impulse is scaled on the physics body the moment it
-- appears.
--
-- Known limits: the extra step does not test for walls, so a very high
-- multiplier can push the player into thin geometry.

local G = require("game")
local F = require("features")
-- Quality-of-life rows after the SR2 Juiced Patch: added to their tabs, then
-- the tweaks saved from the Settings tab put on every row, before anything
-- below reads a row's start value.
local JUICED = require("juiced")
JUICED.setup(F)
-- Rows after Saints Row (2006) forum mods (extras.lua) and weapon skins
-- (skins.lua), added the same way.
local EXTRAS = require("extras")
EXTRAS.setup(F)
local SKINS = require("skins")
SKINS.setup(F)
-- Saved places on the Teleport tab (myplaces.lua).
local MYPLACES = require("myplaces")
MYPLACES.setup(F)
-- Where every row is shown: tab order, tabs and pages (layout.lua).
require("layout").apply(F)
JUICED.load_saved()
JUICED.install()
local MENU = require("menu")
EXTRAS.install(MENU)
MYPLACES.install(MENU)
local WAYPOINT = require("waypoint")
local HOMIES = require("homies")
local FREECAM = require("freecam")
local ADDONS = require("addons")

local TELEPORT = 0x8243E6F8  -- (player, position*, 0, nav node or -1)

local walk_speed = wml.setting("walk_speed", 2.5)   -- m/s; slower than this is left alone
local max_step   = wml.setting("max_step", 1.0)     -- m per update; bigger moves are teleports/cutscenes
local debug      = wml.setting("debug", false)
G.hud_seconds = wml.setting("hud_seconds", 3)
G.debug, F.debug = debug, debug
local max_fall     = wml.setting("max_fall_speed", 9)
local fire_rate  = wml.setting("auto_fire_rate", 12)

local read_u8, read_u16, read_u32, read_f32 = wml.read_u8, wml.read_u16, wml.read_u32, wml.read_f32
local write_u8, write_u16, write_u32, write_f32 = wml.write_u8, wml.write_u16, wml.write_u32, wml.write_f32

local last_pos = nil
local tick = 0
local updates, seconds, peak_speed, peak_rise = 0, os.time(), 0, 0
local last_rate = 50  -- game updates per second, measured below

-- Moves the player by (dx, dy, dz) with the game's teleport.
local function nudge(ctx, p, dx, dy, dz)
  local x, y, z = G.vec(p + G.P.POS)
  local buf = ctx:r(1) - 0x0F00
  write_f32(buf, x + dx); write_f32(buf + 4, y + dy); write_f32(buf + 8, z + dz); write_f32(buf + 12, 0)
  local node = read_u32(p + G.P.NAV_NODE)
  if tick % 30 == 0 or node == 0xFFFFFFFF then node = 0xFFFFFFFF end
  G.call(ctx, TELEPORT, { p, buf, 0, node })
end

-- ---------------------------------------------------------------- jumps
--
-- The player's physics body: the game's own set-velocity call (0x8243E948)
-- reads the controller at player+476, the body at controller+8, and writes
-- the velocity vector at body+16. Jumps are boosted by scaling the upward
-- velocity there the moment it appears.
-- No Clip: you fly through anything. The game sees no left stick, triggers
-- or A (no walking or jumping); the left stick / WASD moves you the way the
-- camera faces, RT / Space or E up, LT / Ctrl or Q down, A / Shift faster.
-- Each update puts you where you flew with the game's teleport, so walls and
-- gravity don't stop you. Paused while the menu is open.
local noclip = { pos = nil, clock = 0 }
local function key(k) local ok, d = pcall(wml.key_down, k) return ok and d end
local function update_noclip(ctx, p)
  local on = F.on("noclip") and p ~= 0 and G.playing(p) and (G.vehicle_object(p) or 0) == 0
    and not G.in_cutscene() and not FREECAM.on and read_f32(p + G.P.HEALTH) > 0
  F.noclip_active = on
  if not on then noclip.pos = nil return end
  local now = os.clock()
  if not noclip.pos then noclip.pos = { G.vec(p + G.P.POS) }; noclip.clock = now end
  local dt = math.max(0, math.min(0.05, now - noclip.clock))
  noclip.clock = now
  if MENU.is_open() then dt = 0 end
  local pad = FREECAM.pad
  local function axis(v) v = v / 32767 return math.abs(v) < 0.2 and 0 or v end
  local mx, mz = axis(pad.lx), axis(pad.ly)
  local up = pad.rt / 255 - pad.lt / 255 + ((key("SPACE") or key("E")) and 1 or 0) - ((key("CTRL") or key("Q")) and 1 or 0)
  local speed = (key("SHIFT") or (pad.buttons & 0x1000) ~= 0) and 30 or 10
  local function flat(x, z) local l = math.sqrt(x * x + z * z) if l < 1e-4 then return 0, 0 end return x / l, z / l end
  local rx, rz = flat(read_f32(G.CAMERA + 80), read_f32(G.CAMERA + 88))
  local fx, fz = flat(read_f32(G.CAMERA + 104), read_f32(G.CAMERA + 112))
  local pos = noclip.pos
  pos[1] = pos[1] + (rx * mx + fx * mz) * speed * dt
  pos[2] = pos[2] + up * speed * dt
  pos[3] = pos[3] + (rz * mx + fz * mz) * speed * dt
  local buf = ctx:r(1) - 0x0F00
  write_f32(buf, pos[1]); write_f32(buf + 4, pos[2]); write_f32(buf + 8, pos[3]); write_f32(buf + 12, 0)
  G.call(ctx, TELEPORT, { p, buf, 0, 0xFFFFFFFF })
end
F.update_noclip = update_noclip

-- Screen effects (Settings): low health - a dark red vignette that pulses
-- like a heartbeat, deeper, darker and quicker the lower your health; low
-- sprint - a black vignette that darkens as the sprint meter empties and
-- fades away as it fills. Both see-through, only nearing solid at the worst.
-- Drawn before the game's HUD in its 2D pass (gameui.lua), so the HUD,
-- neighbourhood names, mission text and subtitles stay on top of it.
local UI = require("gameui")
local fx = { health = 0, sprint = 0, clock = nil }
-- Soft and round: the screen as a grid of cells, each corner darkened by how
-- far it is from the middle (an oval the shape of the screen), so the shade
-- blends from the corners in - strongest in the corners, gentle along the
-- edges, nothing in the middle. `amount` (0..1) brings it further in and
-- darker. One colour, see-through; cells that would be clear aren't drawn.
local GX, GY = 16, 9
local function vignette(list, rgb, amount, max_alpha)
  if amount <= 0.01 then return end
  local W, H = 1280, 720
  local inner = 1.25 - 0.6 * amount           -- where the shade starts (1 = middle of an edge)
  local outer = 1.45                          -- where it's full (the corners)
  local function alpha_at(i, j)
    local nx, ny = i / GX * 2 - 1, j / GY * 2 - 1
    local r = math.sqrt(nx * nx + ny * ny)
    local t = math.max(0, math.min(1, (r - inner) / (outer - inner)))
    t = t * t * (3 - 2 * t)                   -- smoothstep
    return math.floor(max_alpha * amount * t)
  end
  local a = {}
  for j = 0, GY do
    a[j] = {}
    for i = 0, GX do a[j][i] = alpha_at(i, j) end
  end
  local cw, ch = W / GX, H / GY
  for j = 0, GY - 1 do
    for i = 0, GX - 1 do
      local tl, tr, bl, br = a[j][i], a[j][i + 1], a[j + 1][i], a[j + 1][i + 1]
      if tl + tr + bl + br > 0 then
        local function c(al) return { rgb[1], rgb[2], rgb[3], al } end
        list[#list + 1] = { image = "px_swatch_color", part = { 10, 8, 26, 14 }, x = i * cw, y = j * ch, w = cw, h = ch,
          colours = { c(tl), c(tr), c(bl), c(br) } }
      end
    end
  end
end-- Eases toward the target: in slowly as the meter drops, out slowly as it recovers.
local function ease(cur, target, dt)
  local rate = target > cur and 0.9 or 0.6
  local step = rate * dt
  if math.abs(target - cur) <= step then return target end
  return cur + (target > cur and step or -step)
end
local function update_effects(p)
  local list = {}
  local now = os.clock()
  local dt = fx.clock and math.max(0, math.min(0.1, now - fx.clock)) or 0
  fx.clock = now
  local show = p ~= 0 and not MENU.is_open() and not G.in_cutscene() and not G.screen_up() and read_f32(p + G.P.HEALTH) > 0
  -- Low health: below half health, more the lower it gets; a slow heartbeat.
  local target = 0
  if show and F.items.low_health_fx and F.items.low_health_fx.v == true then
    local max = read_u32(p + G.P.HEALTH_MAX)
    local r = (max > 0 and max < 1000000) and read_f32(p + G.P.HEALTH) / max or 1
    if r < 0.5 then target = (0.5 - r) / 0.5 end
  end
  fx.health = ease(fx.health, target, dt)
  if fx.health > 0.01 then
    local beat = now * (0.9 + 1.2 * fx.health) * 2 * math.pi
    local pulse = 0.8 + 0.2 * (0.5 + 0.5 * math.sin(beat))
    vignette(list, { 120, 0, 0 }, fx.health * pulse, 190)
  end
  -- Low sprint: from 40% left, darker as the meter empties (the meter the
  -- HUD shows, refill included).
  target = 0
  if show and F.items.low_sprint_fx and F.items.low_sprint_fx.v == true then
    local left, full = read_f32(G.SPRINT_METER), read_f32(G.SPRINT_METER_MAX)
    if left == left and full == full and full > 0 and full < 1e7 then
      local r = math.max(0, math.min(1, left / full))
      target = math.max(0, math.min(1, (0.4 - r) / 0.4))
    end
  end
  fx.sprint = ease(fx.sprint, target, dt)
  if fx.sprint > 0.01 then vignette(list, { 0, 0, 0 }, fx.sprint, 200) end
  UI.overlay = #list > 0 and list or nil
end
F.fx = fx
F.update_effects = update_effects

local function body_velocity_address(p)
  local controller = read_u32(p + G.P.CONTROLLER)
  if not G.pointer_ok(controller) then return nil end
  local body = read_u32(controller + 8)
  if not G.pointer_ok(body) then return nil end
  return body + 16
end
local last_vy, jumps = 0, 0
-- Landing protection: whatever the game takes off the player's health in
-- the update a fall ends is put straight back, and the invulnerability bit
-- is raised while falling and for a few updates after touching down.
local health_prev, landing_grace = nil, 0
local fall_shield, shield_was = 0, nil
local function drop_shield(p)
  if shield_was ~= nil then F.shield("landing", false, p) end
  shield_was = nil
  fall_shield = 0
end

-- ---------------------------------------------------------------- auto fire
--
-- Single-shot guns fire once per trigger pull. The trigger is tapped at the
-- point the game reads the controller: XamInputGetState fills an
-- XINPUT_STATE at r5, buttons at +4, right trigger at +7. The same hook
-- hands the buttons to the menu and blanks the pad while the menu is open.
local AUTOMATIC = { ak47 = true, ak47l = true, m16 = true, mac10 = true, mac10l = true, tec9 = true, tec9b = true }
local weapon_tick, weapon_name = -1, ""
local function equipped_weapon(p)
  if weapon_tick == tick then return weapon_name end
  weapon_tick = tick
  weapon_name = ""
  local item = read_u32(p + G.P.EQUIPPED)
  if not G.pointer_ok(item) then return "" end
  local info = read_u32(item + 8)
  if not G.pointer_ok(info) then return "" end
  local namep = read_u32(info)
  if not G.pointer_ok(namep) then return "" end
  local chars = {}
  for i = 0, 31 do
    local c = read_u8(namep + i)
    if c == 0 then break end
    if c < 32 or c > 126 then return "" end
    chars[#chars + 1] = string.char(c)
  end
  weapon_name = table.concat(chars):lower()
  return weapon_name
end
local function want_release()
  local ups = last_rate > 0 and last_rate or 50
  local half = math.max(2, math.floor(ups / math.max(1, fire_rate) / 2 + 0.5))
  return (tick % (2 * half)) >= half
end
-- The stop combo: ends a pose or repeating action (stop_pad in mod.ini).
-- While the held buttons are down its last button is kept from the game,
-- so RB + D-pad Up never also recruits.
local stop_hold, stop_press = MENU.parse_combo(tostring(wml.setting("stop_pad", "RB+UP")))
if not stop_hold then stop_hold, stop_press = MENU.parse_combo("RB+UP") end
local stop_prev = 0
G.hook(G.INPUT_GET_STATE, function(ctx)
  local user, state = ctx:r(3), ctx:r(5)
  ctx:call_original()
  if user ~= 0 then return end
  if state == 0 or (ctx:r(3) & 0xFFFFFFFF) ~= 0 then MENU.reset_controller(); return end
  local buttons = read_u16(state + 4)
  ADDONS.set_combo(MENU.combo_down(buttons)
    or (stop_press ~= 0 and (buttons & stop_hold) == stop_hold and (buttons & stop_press) ~= 0))
  local flying = FREECAM.capture(state)
  local blank, hide = MENU.controller(buttons, read_u8(state + 6), read_u8(state + 7))
  if flying and not blank then
    -- The free camera has the pad: the game sees nothing pressed, and a new
    -- packet number so a stick held when it started doesn't keep walking.
    write_u32(state, read_u32(state) + 1)
    blank = true
  end
  if F.noclip_active and not blank then
    -- No Clip has the left stick, triggers and A.
    write_u16(state + 8, 0); write_u16(state + 10, 0); write_u8(state + 6, 0); write_u8(state + 7, 0)
    buttons = buttons & ~0x1000 & 0xFFFF
    write_u16(state + 4, buttons)
  end
  if blank then
    -- Menu open: the game sees a pad with nothing pressed.
    write_u16(state + 4, 0); write_u8(state + 6, 0); write_u8(state + 7, 0)
    for i = 8, 14, 2 do write_u16(state + i, 0) end
    write_u32(state, read_u32(state) + 1)
    return
  end
  if stop_press ~= 0 and (buttons & stop_hold) == stop_hold then
    if (buttons & stop_press) ~= 0 and (stop_prev & stop_press) == 0 then F.stop_requested = true end
    hide = hide | stop_press
  end
  stop_prev = buttons
  if hide ~= 0 then
    -- The menu combo's D-pad press, or buttons still held from the menu.
    write_u16(state + 4, (buttons & ~hide) & 0xFFFF)
    write_u32(state, read_u32(state) + 1)
    if (hide & MENU.PAD.LT) ~= 0 then write_u8(state + 6, 0) end
    if (hide & MENU.PAD.RT) ~= 0 then write_u8(state + 7, 0) end
  end
  local rt = read_u8(state + 7)
  if rt == 0 or not F.on("fire") then return end
  local p = G.player()
  if not G.playing(p) then return end
  if AUTOMATIC[equipped_weapon(p)] then return end
  if want_release() then write_u8(state + 7, 0) end
end)

-- ------------------------------------------------------------ one-hit kill
--
-- Every damage path (bullets, explosions, fire, vehicles) ends in
-- 0x824470D0(victim, attacker, ..., f1 = damage); f1 = -1 means kill.
-- God mode also covers what the invulnerability flag lets through: an
-- explosion's fire on you, and the damage it does.
G.hook(G.IGNITE, function(ctx)
  if F.on("god") and not F.killing_self and (ctx:r(3) & 0xFFFFFFFF) == read_u32(G.PLAYER) then ctx:set_r(3, 0) return end
  ctx:call_original()
end)

-- Debug: every hit on you is logged with what the game checks before it
-- lets damage through (at most twice a second).
local damage_logged = 0
local function log_damage(p, asked, before)
  if os.clock() - damage_logged < 0.5 then return end
  damage_logged = os.clock()
  wml.log(string.format("damage to you: %.1f, health %.0f -> %.0f of %d; flags %08X, +3592 %02X, +2988 %08X, +2996 %08X, state %08X, mp %d/%d",
    asked, before, read_f32(p + G.P.HEALTH), read_u32(p + G.P.HEALTH_MAX), read_u32(p + G.P.FLAGS), read_u8(p + 3592),
    read_u32(p + 2988), read_u32(p + 2996), read_u32(0x827D5798 + 2072), read_u8(0x8370E9F6), read_u8(0x8370E9DF)))
end

local blocked_logged = 0
G.hook(G.TAKE_DAMAGE, function(ctx)
  local p0 = read_u32(G.PLAYER)
  local before = debug and p0 ~= 0 and (ctx:r(3) & 0xFFFFFFFF) == p0 and read_f32(p0 + G.P.HEALTH)
  if F.on("god") and not F.killing_self and (ctx:r(3) & 0xFFFFFFFF) == read_u32(G.PLAYER) then
    ctx:set_f(1, 0.0)                           -- no damage to you at all
  end
  F.note_hit(ctx:r(3) & 0xFFFFFFFF, ctx:r(4) & 0xFFFFFFFF)
  if F.on("one_hit") then
    local victim, attacker = ctx:r(3) & 0xFFFFFFFF, ctx:r(4) & 0xFFFFFFFF
    local p = read_u32(G.PLAYER)
    if p ~= 0 and attacker == p and victim ~= p and G.pointer_ok(victim) and read_u32(victim + 72) == 1 then
      ctx:set_f(1, -1.0)
    end
  end
  local asked = ctx:f(1)
  local health_was = p0 ~= 0 and (ctx:r(3) & 0xFFFFFFFF) == p0 and read_f32(p0 + G.P.HEALTH) or nil
  local victim, attacker = ctx:r(3) & 0xFFFFFFFF, ctx:r(4) & 0xFFFFFFFF
  local alive = p0 ~= 0 and attacker == p0 and victim ~= p0 and G.pointer_ok(victim) and read_u32(victim + 72) == 1
    and read_f32(victim + G.P.HEALTH) > 0
  ctx:call_original()
  if before then log_damage(p0, asked, before) end
  -- A hit on you that took nothing while god mode is off: logged (at most
  -- every 2 s) with the flags, to find what made you invulnerable.
  if p0 ~= 0 and victim == p0 and asked > 0 and not F.on("god") and health_was and read_f32(p0 + G.P.HEALTH) >= health_was
      and os.clock() - blocked_logged > 2 then
    blocked_logged = os.clock()
    F.note_invulnerable(p0, "?")
    wml.log(string.format("invulnerable: a %.1f hit on you did nothing; flags %08X, factor %.2f, health %.0f of %d; game hold %08X, +3592 %02X, +2988 %08X, +2996 %08X, +3620 %02X, mp %d/%d, attacker %08X type %d",
      asked, read_u32(p0 + G.P.FLAGS), read_f32(p0 + G.P.DAMAGE_FACTOR), read_f32(p0 + G.P.HEALTH), read_u32(p0 + G.P.HEALTH_MAX), read_u32(G.DAMAGE_SEQUENCE),
      read_u8(p0 + 3592), read_u32(p0 + 2988), read_u32(p0 + 2996), read_u8(p0 + 3620), read_u8(0x8370E9F6), read_u8(0x8370E9DF),
      attacker, G.pointer_ok(attacker) and read_u32(attacker + 72) or -1))
    -- A hit that did nothing with the damage factor at 0: put it back now.
    if read_f32(p0 + G.P.DAMAGE_FACTOR) < 0.01 and not next(F.shields) then F.restore_damage(p0, "a hit did nothing") end
  end
  -- A kill by you: the line the character you're playing as says.
  if alive and read_f32(victim + G.P.HEALTH) <= 0 then F.character_line("combat - congratulate self", 250) end
  if alive then F.saints_hit(ctx, p0, victim, read_f32(victim + G.P.HEALTH) <= 0) end
end)

-- --------------------------------------------------------- vehicle god mode
--
-- Explosions damage a car part by part through 0x825447D0 (part, vehicle);
-- for the car you drive with Vehicle god mode on, nothing is broken.
G.hook(G.VEHICLE_PART_DAMAGE, function(ctx)
  if F.on("veh_god") then
    local p = G.player()
    local v = p ~= 0 and G.vehicle_object(p)
    if v and (ctx:r(4) & 0xFFFFFFFF) == v then
      ctx:set_r(3, 0)
      return
    end
  end
  ctx:call_original()
end)

-- People the menu made are never deleted by the game: when it pushes their
-- model out of memory it only hides them until the model is back. (Its
-- "may I delete this person" check is the one that keeps mission people.)
-- Once dead they are the game's to clear away like anyone else.
G.hook(G.CAN_DESPAWN, function(ctx)
  local h = ctx:r(3) & 0xFFFFFFFF
  if h ~= 0 and F.our_people[read_u32(h + 68)] ~= nil and wml.read_f32(h + G.P.HEALTH) > 0 then ctx:set_r(3, 0) return end
  ctx:call_original()
end)

-- Freeze world safety: if the game update stops coming while the world is
-- frozen, put time back from the render side.
local last_update = os.clock()
wml.on_frame(function()
  if os.clock() - last_update > 1.5 and wml.read_f32(G.TIME_DIV) > 2 then
    wml.write_f32(G.TIME_DIV, 1.0)
    wml.log("freeze world: the game stopped updating, time put back")
  end
end)

-- ------------------------------------------------------------ the update
G.hook(G.UPDATE, function(ctx)
  FREECAM.before_update()
  JUICED.before(ctx)
  ctx:call_original()
  tick = tick + 1
  last_update = os.clock()
  MENU.input(ctx, tick)
  F.set_menu_open(MENU.is_open())
  F.update(ctx)
  JUICED.after(ctx)
  EXTRAS.after(ctx)
  SKINS.after(ctx)
  MYPLACES.after()
  WAYPOINT.enabled = F.on("waypoint_auto") and not WAYPOINT.standalone
  HOMIES.limit = F.enabled and F.items.homies.v or 0
  if F.camera_turn_start and F.camera_turn_start > 0 and G.player() ~= 0 then
    local v = wml.read_f32(G.LOOK_SPEED_X)
    if v > 0.05 and v < 10 then
      wml.write_f32(G.LOOK_SPEED_X, F.camera_turn_start); wml.write_f32(G.LOOK_SPEED_Y, F.camera_turn_start)
      F.camera_turn_start = nil
    end
  end
  ADDONS.write_flags(F.on("weapon_switch"), MENU.is_open(), FREECAM.on,
    F.items.weapon_dpad.v == 2, F.items.weapon_tap.v == 2)
  -- The fitting room: the Customize tab open (a T-pose and the camera in
  -- front of you, you on the right of the screen), off as soon as it isn't.
  do
    local p = G.player()
    local tab = MENU.is_open() and MENU.tab_name()
    -- (the Customize Vehicle page: the camera round your car)
    local car = tab == "Vehicles" and MENU.pages[1] and MENU.pages[1].vehicle
    if car and not G.pointer_ok(car) then car = nil end
    local viewing = p ~= 0 and (tab == "Customize" or car) and not FREECAM.on and G.playing(p) and read_f32(p + G.P.HEALTH) > 0
    -- (on a movement row in Customize: a walk-in-place preview, not the T-pose)
    local row = viewing and tab == "Customize" and MENU.current()
    local previewing = row and row.part and F.model.name == nil
    if previewing then
      F.set_fitting(p, false)
      F.preview_move(ctx, p, row)
      -- (on the spot: a walk moves you, so you're put back where you stood)
      local at = F.move_preview and F.move_preview.pos
      if at then
        local x, y, z = G.vec(p + G.P.POS)
        if (x - at[1]) ^ 2 + (z - at[3]) ^ 2 > 0.0004 then
          local buf = ctx:r(1) - 0x0F00
          write_f32(buf, at[1]); write_f32(buf + 4, at[2]); write_f32(buf + 8, at[3]); write_f32(buf + 12, 0)
          G.call(ctx, TELEPORT, { p, buf, 0, 0xFFFFFFFF })
        end
      end
    else
      F.end_preview_move(ctx, p)
    end
    F.set_fitting(p, viewing and tab == "Customize" and not previewing)
    FREECAM.orbit(ctx, viewing and true or false, viewing and F.facing_yaw(car or p) or 0,
      car and { target = car, dist = 7.0, height = 0.6, min = 3.0, max = 14.0 } or nil)
  end
  update_noclip(ctx, G.player())
  update_effects(G.player())
  -- The free camera last, after everything that moves the game's camera.
  if not FREECAM.update(ctx, MENU.is_open()) and F.items.free_cam.v then
    F.items.free_cam.v = false
    G.hud(FREECAM.why or "Free camera off")
  end
  if FREECAM.on then F.items.cam_mode.v = FREECAM.mode end   -- Enter / A switches to the shot
  WAYPOINT.god = function() return F.on("god") end
  WAYPOINT.shield = function(on, p) F.shield("waypoint", on, p) end
  WAYPOINT.on_teleport = function() F.last_teleport = { "waypoint", F.tick } end
  WAYPOINT.update(ctx)
  MENU.render(tick)
  local p = G.player()
  if p ~= 0 then G.flush_hud(ctx) end
  local enabled = F.enabled
  if not G.playing(p) then
    last_pos = nil
    drop_shield(p)
    return
  end
  local x, y, z = G.vec(p + G.P.POS)
  if not last_pos then last_pos = { x, y, z } return end
  local dx, dy, dz = x - last_pos[1], y - last_pos[2], z - last_pos[3]
  last_pos = { x, y, z }
  local flat = math.sqrt(dx * dx + dz * dz)
  if flat > max_step or math.abs(dy) > max_step then return end  -- teleported, not walked

  -- Updates per second, for turning per-update distances into speeds.
  updates = updates + 1
  local now = os.time()
  local rate = updates > 0 and updates / math.max(1, now - seconds) or 30
  if now ~= seconds then
    if updates > 10 then last_rate = updates end
    if debug and (peak_speed > 0.1 or peak_rise > 0.01) then
      wml.log(string.format("on foot: %d updates/s, fastest %.2f m/s, highest rise %.3f m/update, state %d, flags %08X, health %.0f of %d, jumps %d, weapon %s",
        updates, peak_speed, peak_rise, read_u32(p + G.P.STATE), read_u32(p + G.P.FLAGS), read_f32(p + G.P.HEALTH), read_u32(p + G.P.HEALTH_MAX), jumps,
        equipped_weapon(p) ~= "" and equipped_weapon(p) or "none"))
    end
    seconds, updates, peak_speed, peak_rise = now, 0, 0, 0
  end
  local speed = flat * rate
  if speed > peak_speed then peak_speed = speed end
  if dy > peak_rise then peak_rise = dy end

  local run_mult, jump_mult = F.items.run_speed.v, F.items.jump_boost.v
  local ex, ez = 0, 0
  if run_mult ~= 1 and enabled and F.items.run.v and speed >= walk_speed then
    ex, ez = dx * (run_mult - 1), dz * (run_mult - 1)
  end
  -- Soft landing: the game measures a fall from the position saved at +404.
  -- Keeping it at the current position means every landing counts as a
  -- drop of nothing: no stumble, no ragdoll, no fall damage.
  local landing_on = enabled and F.items.landing.v
  if landing_on then
    write_f32(p + G.P.FALL_START, x); write_f32(p + G.P.FALL_START + 4, y); write_f32(p + G.P.FALL_START + 8, z)
  end

  -- A jump starts when the body's upward velocity appears from nothing.
  local swimming = (read_u32(p + G.P.STATE) == 9)
  if not swimming then
    local va = body_velocity_address(p)
    if va then
      local vy = read_f32(va + 4)
      if landing_on and max_fall > 0 and vy < -max_fall then
        write_f32(va + 4, -max_fall)
        vy = -max_fall
      end
      if not landing_on then drop_shield(p) end
      if landing_on then
        if vy < -3 then fall_shield = 5
        elseif fall_shield > 0 then fall_shield = fall_shield - 1 end
        local want = fall_shield > 0
        if want and shield_was == nil then
          shield_was = true
          F.shield("landing", true, p)
        elseif not want and shield_was ~= nil then
          F.shield("landing", false, p)
          shield_was = nil
        end
        local health = read_f32(p + G.P.HEALTH)
        if last_vy < -2 and vy > -0.5 then landing_grace = 3 end  -- just landed
        if landing_grace > 0 then
          if health_prev and health < health_prev and health_prev > 0 then
            write_f32(p + G.P.HEALTH, health_prev)
            if debug then wml.log(string.format("landing: health %.0f -> %.0f, restored", health_prev, health)) end
            health = health_prev
          end
          landing_grace = landing_grace - 1
        end
        health_prev = health
      end
      if jump_mult ~= 1 and vy > 1.5 and last_vy < 0.5 and enabled and F.items.jump.v then
        write_f32(va + 4, vy * jump_mult)
        jumps = jumps + 1
        if debug then wml.log(string.format("jump: %.2f -> %.2f m/s up", vy, vy * jump_mult)) end
      end
      last_vy = vy
    end
  end
  if ex ~= 0 or ez ~= 0 then
    nudge(ctx, p, ex, 0, ez)
    last_pos = { x + ex, y, z + ez }
  end
end)
if G.broken[G.UPDATE] then
  wml.log("SR Tweak Menu can't run here: the loader can't hook the game update (82209E30) in this saintsrow.exe")
end

wml.log(string.format("SR Tweak Menu: run x%.2f, jump x%.2f, rapid fire %s; menu key %s (debug=%s)", F.items.run_speed.v, F.items.jump_boost.v,
  F.items.fire.v and (fire_rate .. "/s") or "off", tostring(wml.setting("menu_key", "F5")), tostring(debug)))

-- ------------------------------------------------------------ add-ons
--
-- Loaded last, so their hooks sit in front of the menu's: they see the
-- controller after the menu has blanked it while the menu is open.
do
  local dir = wml.mod_folder .. "/addons"
  local function quiet() return MENU.is_open() end
  local function aim(n) return function() return F.enabled and F.items.aim_style.v == n and not FREECAM.on end end
  F.addon.precise = ADDONS.load("Precise Aim", dir .. "/precise_aim", { gate = true, quiet = quiet, live = aim(2) })
  F.addon.fine = ADDONS.load("Fine Aim", dir .. "/fine_aim", { gate = "hooks", quiet = quiet, live = aim(3) })
  F.ADDONS = ADDONS
  F.sync_aim_camera()
  F.apply_aim_button()
  F.apply_precise_turning()
end
