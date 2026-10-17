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
local MENU = require("menu")
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
  if shield_was ~= nil and p ~= 0 then G.player_flag(p, G.FLAG.INVULNERABLE, F.on("god")) end
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
wml.hook(G.INPUT_GET_STATE, function(ctx)
  local user, state = ctx:r(3), ctx:r(5)
  ctx:call_original()
  if user ~= 0 or state == 0 or (ctx:r(3) & 0xFFFFFFFF) ~= 0 then return end
  local buttons = read_u16(state + 4)
  local flying = FREECAM.capture(state)
  local blank, hide = MENU.controller(buttons, read_u8(state + 6), read_u8(state + 7))
  if flying and not blank then
    -- The free camera has the pad: the game sees nothing pressed, and a new
    -- packet number so a stick held when it started doesn't keep walking.
    write_u32(state, read_u32(state) + 1)
    blank = true
  end
  if blank then
    -- Menu open: the game sees a pad with nothing pressed.
    write_u16(state + 4, 0); write_u8(state + 6, 0); write_u8(state + 7, 0)
    for i = 8, 14, 2 do write_u16(state + i, 0) end
    return
  end
  if stop_press ~= 0 and (buttons & stop_hold) == stop_hold then
    if (buttons & stop_press) ~= 0 and (stop_prev & stop_press) == 0 then F.stop_requested = true end
    hide = hide | stop_press
  end
  stop_prev = buttons
  if hide ~= 0 then
    -- The menu combo's D-pad press, or buttons still held from the menu.
    write_u16(state + 4, buttons & ~hide & 0xFFFF)
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
wml.hook(G.IGNITE, function(ctx)
  if F.on("god") and (ctx:r(3) & 0xFFFFFFFF) == read_u32(G.PLAYER) then ctx:set_r(3, 0) return end
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

wml.hook(G.TAKE_DAMAGE, function(ctx)
  local p0 = read_u32(G.PLAYER)
  local before = debug and p0 ~= 0 and (ctx:r(3) & 0xFFFFFFFF) == p0 and read_f32(p0 + G.P.HEALTH)
  if F.on("god") and (ctx:r(3) & 0xFFFFFFFF) == read_u32(G.PLAYER) then
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
  ctx:call_original()
  if before then log_damage(p0, asked, before) end
end)

-- --------------------------------------------------------- vehicle god mode
--
-- Explosions damage a car part by part through 0x825447D0 (part, vehicle);
-- for the car you drive with Vehicle god mode on, nothing is broken.
wml.hook(G.VEHICLE_PART_DAMAGE, function(ctx)
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
wml.hook(G.CAN_DESPAWN, function(ctx)
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
wml.hook(G.UPDATE, function(ctx)
  FREECAM.before_update()
  ctx:call_original()
  tick = tick + 1
  last_update = os.clock()
  MENU.input(ctx, tick)
  F.set_menu_open(MENU.is_open())
  F.update(ctx)
  WAYPOINT.enabled = F.on("waypoint_auto") and not WAYPOINT.standalone
  HOMIES.limit = F.enabled and F.items.homies.v or 0
  ADDONS.write_flags(F.on("weapon_switch"), MENU.is_open(), FREECAM.on)
  -- The free camera last, after everything that moves the game's camera.
  if not FREECAM.update(ctx, MENU.is_open()) and F.items.free_cam.v then
    F.items.free_cam.v = false
    G.hud(FREECAM.why or "Free camera off")
  end
  if FREECAM.on then F.items.cam_mode.v = FREECAM.mode end   -- Enter / A switches to the shot
  WAYPOINT.god = function() return F.on("god") end
  WAYPOINT.update(ctx)
  MENU.render(tick)
  local p = G.player()
  if p ~= 0 then G.flush_hud(ctx) end
  local enabled = F.enabled
  if not G.playing(p) then
    last_pos = nil
    if p ~= 0 then drop_shield(p) else shield_was = nil; fall_shield = 0 end
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
          shield_was = G.has_bits(p + G.P.FLAGS, G.FLAG.INVULNERABLE)
          G.player_flag(p, G.FLAG.INVULNERABLE, true)
        elseif not want and shield_was ~= nil then
          G.player_flag(p, G.FLAG.INVULNERABLE, F.on("god"))
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
  F.addon.fine = ADDONS.load("Fine Aim", dir .. "/fine_aim", { quiet = quiet, live = aim(3) })
  F.sync_aim_camera()
end
