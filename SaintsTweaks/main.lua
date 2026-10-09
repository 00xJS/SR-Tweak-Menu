-- Saints Tweaks - runtime part (experimental).
--
-- Run faster and jump higher. The game keeps no table for on-foot speed or
-- jump height, so this works on the result instead: after every game update
-- the player's movement since the last update is measured, and the player is
-- moved a little further the same way with the game's own teleport
-- (0x8243E6F8, the call the trainer's No Clip uses). Horizontal movement is
-- scaled by run_speed_multiplier, upward movement while in the air by
-- jump_multiplier. Vehicles, cutscenes, menus, swimming and multiplayer are
-- left alone.
--
-- Known limits of this approach: the extra step does not test for walls, so
-- a very high multiplier can push the player into thin geometry; landing
-- from a higher jump counts as a longer fall for the game.

local PLAYER   = 0x8309ABEC  -- pointer to the player object (0 = no game loaded)
local OBJECTS  = 0x830866C8  -- handle table, 16 bytes per entry
local UPDATE   = 0x82209E30  -- game update (the trainer hooks the same function)
local TELEPORT = 0x8243E6F8  -- (player, position*, 0, nav node or -1)
local MULTIPLAYER = 0x8370E9F6
local CUTSCENE_A, CUTSCENE_B = 0x8370D991, 0x8370D990
local MENU_A, MENU_B = 0x839E0DF8, 0x839E0FB0
local FRONT_END = 0x827B04D4  -- 0 in play, -1 in the front end (title screen, its city flyover), 1 in the character creator

local run_mult   = wml.setting("run_speed_multiplier", 1.5)
local jump_mult  = wml.setting("jump_multiplier", 1.5)
local walk_speed = wml.setting("walk_speed", 2.5)   -- m/s; slower than this is left alone
local max_step   = wml.setting("max_step", 1.0)     -- m per update; bigger moves are teleports/cutscenes
local debug      = wml.setting("debug", false)
local toggle_key = wml.setting("toggle_key", "B")
local KEYS = {
  run     = tostring(wml.setting("key_run", "1")),
  jump    = tostring(wml.setting("key_jump", "2")),
  landing = tostring(wml.setting("key_landing", "3")),
  tank    = tostring(wml.setting("key_tank", "4")),
  torque  = tostring(wml.setting("key_torque", "5")),
  fire    = tostring(wml.setting("key_fire", "6")),
  status  = tostring(wml.setting("key_status", "0")),
}
local hud_seconds = wml.setting("hud_seconds", 3)
-- Per-feature switches, all on at start; `enabled` is the master switch.
local on = { run = true, jump = true, landing = true, tank = true, torque = true, fire = true }
local LABELS = { run = "Run boost", jump = "High jump", landing = "Soft landing", tank = "Tank mode",
                 torque = "Engine boost", fire = "Auto fire" }
local tank       = wml.setting("vehicle_tank", true)
local player_torque = wml.setting("player_torque_multiplier", 1.5)
local soft_landing = wml.setting("soft_landing", true)
local max_fall     = wml.setting("max_fall_speed", 9)
local torque_offset = wml.setting("player_torque_offset", 396)
local auto_fire  = wml.setting("auto_fire", true)
local fire_rate  = wml.setting("auto_fire_rate", 12)

local enabled = true
local last_pos, last_in_air = nil, false
local tick = 0
local updates, seconds, peak_speed, peak_rise = 0, os.time(), 0, 0
local last_rate = 50  -- game updates per second, measured below

local function vec(a) return wml.read_f32(a), wml.read_f32(a + 4), wml.read_f32(a + 8) end

-- On foot: the same test First Person and the keyboard controls use.
local function in_vehicle(p)
  if wml.read_u32(p + 3456) ~= 0 then return false end
  local handle = wml.read_u32(p + 2496)
  if handle == 0 or (wml.read_u8(p + 2569) & 0x10) ~= 0 then return false end
  local state = wml.read_u32(p + 508)
  if state == 9 or state == 12 then return false end
  local index = handle & 0xFFFF
  if index >= 4096 then return false end
  local object = wml.read_u32(OBJECTS + 12 + index * 16)
  return object ~= 0 and wml.read_u32(object + 68) == handle and wml.read_u32(object + 72) == 5
end

local function playing(p)
  if p == 0 or wml.read_u32(p + 72) ~= 1 then return false end
  if wml.read_u8(MULTIPLAYER) ~= 0 then return false end
  if wml.read_u8(CUTSCENE_A) ~= 0 or wml.read_u8(CUTSCENE_B) ~= 0 then return false end
  if wml.read_u32(MENU_A) ~= 0 or wml.read_u32(MENU_B) ~= 0 then return false end
  if wml.read_u32(FRONT_END) ~= 0 then return false end
  return not in_vehicle(p)
end

-- Moves the player by (dx, dy, dz) with the game's teleport. The position
-- vector lives on the guest stack between a lowered r1 and the hook's own
-- frame, as the trainer does it.
local function nudge(ctx, p, dx, dy, dz)
  local x, y, z = vec(p + 20)
  local r1, r3, r4, r5, r6 = ctx:r(1), ctx:r(3), ctx:r(4), ctx:r(5), ctx:r(6)
  local buf = r1 - 0x1800
  wml.write_f32(buf, x + dx); wml.write_f32(buf + 4, y + dy); wml.write_f32(buf + 8, z + dz); wml.write_f32(buf + 12, 0)
  local node = wml.read_u32(p + 392)
  if tick % 30 == 0 or node == 0xFFFFFFFF then node = 0xFFFFFFFF end
  ctx:set_r(1, r1 - 0x2000)
  ctx:set_r(3, p); ctx:set_r(4, buf); ctx:set_r(5, 0); ctx:set_r(6, node)
  ctx:call(TELEPORT)
  ctx:set_r(1, r1); ctx:set_r(3, r3); ctx:set_r(4, r4); ctx:set_r(5, r5); ctx:set_r(6, r6)
end

-- -------------------------------------------------------------- HUD message
--
-- The game's script function message(text, seconds) (wrapper 0x824D1CA8)
-- turns the text into UTF-16 and, for a plain message, calls 0x82367568
-- with r3 = the wide string and f1 = seconds (0 = the game's default).
-- Messages are queued here and shown from the update hook, where the CPU
-- context needed for the call is available.
local HUD_MESSAGE = 0x82367568
local hud_queue = {}
local function hud(text) hud_queue[#hud_queue + 1] = text end
local function flush_hud(ctx)
  if #hud_queue == 0 then return end
  local text = table.remove(hud_queue, 1)
  local r1, r3 = ctx:r(1), ctx:r(3)
  local f1 = ctx:f(1)
  local buf = r1 - 0x1800
  local n = math.min(#text, 200)
  for i = 1, n do wml.write_u16(buf + (i - 1) * 2, string.byte(text, i)) end
  wml.write_u16(buf + n * 2, 0)
  ctx:set_r(1, r1 - 0x2000)
  ctx:set_r(3, buf)
  ctx:set_f(1, hud_seconds)
  ctx:call(HUD_MESSAGE)
  ctx:set_r(1, r1); ctx:set_r(3, r3); ctx:set_f(1, f1)
  if debug then wml.log("hud: " .. text) end
end

local function status_line()
  local parts = {}
  for _, k in ipairs({ "run", "jump", "landing", "tank", "torque", "fire" }) do
    parts[#parts + 1] = LABELS[k] .. (on[k] and " on" or " off")
  end
  return (enabled and "Tweaks on: " or "Tweaks OFF: ") .. table.concat(parts, ", ")
end

local function handle_keys()
  if toggle_key ~= "" and wml.key_pressed(toggle_key) then
    enabled = not enabled
    hud(enabled and "Saints Tweaks on" or "Saints Tweaks off")
    wml.log("Tweaks " .. (enabled and "on" or "off"))
  end
  for k, key in pairs(KEYS) do
    if key ~= "" and wml.key_pressed(key) then
      if k == "status" then
        hud(status_line())
      else
        on[k] = not on[k]
        hud(LABELS[k] .. (on[k] and " on" or " off"))
        wml.log(LABELS[k] .. (on[k] and " on" or " off"))
      end
    end
  end
end

-- ---------------------------------------------------------------- tank mode
--
-- The game's mission scripts call vehicle_infinite_mass(name, true) to make
-- a vehicle immovable (the campaign bus, Julius's car). Its script wrapper
-- (0x824DFC90, registered by 0x824E1AD0) looks the vehicle up by name and
-- sets bit 0x00080000 of the word at +53980 in the vehicle object. The same
-- bit is set here on whatever the player is driving, and cleared when they
-- get out.

local TANK_FLAG_OFFSET, TANK_FLAG = 53980, 0x00080000

-- The player's physics body: the game's own set-velocity call (0x8243E948)
-- reads the controller at player+476, the body at controller+8, and writes
-- the velocity vector at body+16. Jumps are boosted by scaling the upward
-- velocity there the moment it appears, which the game's own physics then
-- carries through.
local function body_velocity_address(p)
  -- Heap pointers can sit low (the controller was seen at 0x45712400).
  local controller = wml.read_u32(p + 476)
  if controller < 0x10000 or controller >= 0xC0000000 then return nil end
  local body = wml.read_u32(controller + 8)
  if body < 0x10000 or body >= 0xC0000000 then return nil end
  return body + 16
end
local last_vy, jumps = 0, 0
-- Landing protection: whatever the game takes off the player's health
-- (float at +1912, as the trainer reads it) in the update a fall ends is
-- put straight back.
local HEALTH = 1912
local health_prev, landing_grace, landings = nil, 0, 0
-- Better still, don't take the hit: the game's invulnerability bit (the
-- trainer's God Mode, 0x00100000 in the flags at +216) is set while falling
-- and for a few updates after touching down, then put back as it was.
local INVULNERABLE = 0x00100000
local fall_shield, shield_was = 0, nil
local function set_invulnerable(p, want)
  local flags = wml.read_u32(p + 216)
  if want then flags = flags | INVULNERABLE else flags = flags & ~INVULNERABLE & 0xFFFFFFFF end
  wml.write_u32(p + 216, flags)
  wml.write_u32(p + 212, wml.read_u32(p + 212) | 1)  -- the game's dirty flag
end
-- Puts the invulnerability bit back if the shield was up.
local function drop_shield(p)
  if shield_was ~= nil and p ~= 0 then set_invulnerable(p, shield_was) end
  shield_was = nil
  fall_shield = 0
end

local function vehicle_object(p)
  if wml.read_u32(p + 3456) ~= 0 then return nil end
  local handle = wml.read_u32(p + 2496)
  if handle == 0 or (wml.read_u8(p + 2569) & 0x10) ~= 0 then return nil end
  local state = wml.read_u32(p + 508)
  if state == 9 or state == 12 then return nil end
  local index = handle & 0xFFFF
  if index >= 4096 then return nil end
  local object = wml.read_u32(OBJECTS + 12 + index * 16)
  if object ~= 0 and wml.read_u32(object + 68) == handle and wml.read_u32(object + 72) == 5 then return object, handle end
  return nil
end

-- The player's torque multiplier: the script function
-- vehicle_set_torque_multiplier(name, x) (wrapper 0x824E1058) stores x at
-- +396 of the object at vehicle+224, when the byte at vehicle+50300 is 1.
-- Its neighbour at +400 is set by another (name, number) script function.
-- Setting it on the player's car only leaves traffic alone.
local function engine_object(vehicle)
  if wml.read_u8(vehicle + 50300) ~= 1 then return nil end
  local e = wml.read_u32(vehicle + 224)
  if e < 0x10000 or e >= 0xC0000000 then return nil end
  return e
end

local tank_vehicle, tank_handle = 0, 0
local function set_tank(object, on)
  local a = object + TANK_FLAG_OFFSET
  local v = wml.read_u32(a)
  if on then v = v | TANK_FLAG else v = v & ~TANK_FLAG & 0xFFFFFFFF end
  wml.write_u32(a, v)
end

local function update_tank(p)
  if not tank then return end
  local object, handle = 0, 0
  if p ~= 0 then
    local o, h = vehicle_object(p)
    object, handle = o or 0, h or 0
  end
  if object ~= tank_vehicle then
    if tank_vehicle ~= 0 then
      -- Give the old car its mass back, if it still exists.
      local still = wml.read_u32(OBJECTS + 12 + (tank_handle & 0xFFFF) * 16)
      if still == tank_vehicle and wml.read_u32(still + 68) == tank_handle then set_tank(tank_vehicle, false) end
    end
    tank_vehicle, tank_handle = object, handle
    if object ~= 0 then
      local e = engine_object(object)
      if debug then
        wml.log(string.format("vehicle: %08X flags %08X engine %s +396 %.2f +400 %.2f", object,
          wml.read_u32(object + TANK_FLAG_OFFSET), e and string.format("%08X", e) or "none",
          e and wml.read_f32(e + 396) or 0, e and wml.read_f32(e + 400) or 0))
      end
    end
  end
  if object ~= 0 then
    set_tank(object, enabled and on.tank)
    if player_torque ~= 1 then
      local e = engine_object(object)
      if e then wml.write_f32(e + torque_offset, (enabled and on.torque) and player_torque or 1.0) end
    end
  end
end

-- ---------------------------------------------------------------- auto fire
--
-- Single-shot guns fire once per trigger pull. Rather than make them
-- automatic in weapons.xtbl (which loses their per-shot sound), the trigger
-- is tapped at the point the game reads the controller: XamInputGetState
-- (0x82788EC4) fills an XINPUT_STATE at r5, with the right trigger at +7.
-- While the player holds fire on foot, the trigger is zeroed for half of
-- each tap cycle, so the game sees a release and fires again. Each weapon's
-- Refire_Delay still applies. In vehicles the trigger is the accelerator and
-- is left alone.
local INPUT_GET_STATE = 0x82788EC4

-- The equipped weapon: the script function inv_item_is_equipped
-- (0x824CFF30) reads the item at human+3548, its info at item+8 and the
-- name string at info+0. Guns that already fire while held keep their
-- looping sound only if the trigger is left alone, so they are exempt.
local AUTOMATIC = { ak47 = true, ak47l = true, m16 = true, mac10 = true, mac10l = true, tec9 = true, tec9b = true }
local function pointer_ok(v) return v >= 0x10000 and v < 0xC0000000 end
local weapon_tick, weapon_name = -1, ""
local function equipped_weapon(p)
  if weapon_tick == tick then return weapon_name end
  weapon_tick = tick
  weapon_name = ""
  local item = wml.read_u32(p + 3548)
  if not pointer_ok(item) then return "" end
  local info = wml.read_u32(item + 8)
  if not pointer_ok(info) then return "" end
  local namep = wml.read_u32(info)
  if not pointer_ok(namep) then return "" end
  local chars = {}
  for i = 0, 31 do
    local c = wml.read_u8(namep + i)
    if c == 0 then break end
    if c < 32 or c > 126 then return "" end
    chars[#chars + 1] = string.char(c)
  end
  weapon_name = table.concat(chars):lower()
  return weapon_name
end
local fire_seen, fire_polls, fire_taps = false, 0, 0
local fire_phase_tick = -1
local function want_release()
  local ups = last_rate > 0 and last_rate or 50
  local half = math.max(2, math.floor(ups / math.max(1, fire_rate) / 2 + 0.5))
  return (tick % (2 * half)) >= half
end
if auto_fire then
  wml.hook(INPUT_GET_STATE, function(ctx)
    local user, state = ctx:r(3), ctx:r(5)
    ctx:call_original()
    if user ~= 0 or state == 0 or (ctx:r(3) & 0xFFFFFFFF) ~= 0 then return end
    fire_polls = fire_polls + 1
    local rt = wml.read_u8(state + 7)
    if rt == 0 or not enabled or not on.fire then return end
    if not fire_seen then fire_seen = true; wml.log("auto fire: trigger seen at the controller read") end
    local p = wml.read_u32(PLAYER)
    if not playing(p) then return end
    if AUTOMATIC[equipped_weapon(p)] then return end
    if want_release() then
      wml.write_u8(state + 7, 0)
      fire_taps = fire_taps + 1
    end
  end)
end

-- ------------------------------------------------------- script functions
--
-- Dump the game's script function table (name -> address) once, so the
-- functions behind inv_item_is_equipped and friends can be read in the
-- recompiled code. Names live in read-only data, which is always mapped.
if debug and wml.setting("dump_script_table", false) then
  local ok, tbl = pcall(require, "script_table")
  if ok and type(tbl) == "table" then
    local out, count = {}, 0
    for _, e in ipairs(tbl) do
      local chars = {}
      for i = 0, 47 do
        local c = wml.read_u8(e[1] + i)
        if c == 0 then break end
        if c < 32 or c > 126 then chars = nil break end
        chars[#chars + 1] = string.char(c)
      end
      if chars and #chars > 0 then
        out[#out + 1] = table.concat(chars) .. "=" .. string.format("%08X", e[2])
        count = count + 1
        if #out == 8 then wml.log("script: " .. table.concat(out, " ")); out = {} end
      end
    end
    if #out > 0 then wml.log("script: " .. table.concat(out, " ")) end
    wml.log(string.format("script table: %d names", count))
  end
end

wml.hook(UPDATE, function(ctx)
  ctx:call_original()
  tick = tick + 1
  handle_keys()
  local p = wml.read_u32(PLAYER)
  if p ~= 0 then flush_hud(ctx) end
  if p ~= 0 and wml.read_u32(p + 72) == 1 and wml.read_u8(MULTIPLAYER) == 0 then update_tank(p) else update_tank(0) end
  if not playing(p) then
    last_pos = nil
    if p ~= 0 and wml.read_u32(p + 72) == 1 then drop_shield(p) else shield_was = nil; fall_shield = 0 end
    return
  end
  local x, y, z = vec(p + 20)
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
      local va = body_velocity_address(p)
      local ctrl = wml.read_u32(p + 476)
      local body = (ctrl >= 0x10000 and ctrl < 0xC0000000) and wml.read_u32(ctrl + 8) or 0
      wml.log(string.format("on foot: %d updates/s, fastest %.2f m/s, highest rise %.3f m/update, state %d, flags %08X, ctrl %08X body %08X vel %s vy %.2f, input polls %d, trigger cuts %d, jumps %d, weapon %s",
        updates, peak_speed, peak_rise, wml.read_u32(p + 508), wml.read_u32(p + 216), ctrl, body,
        va and string.format("%08X", va) or "none", va and wml.read_f32(va + 4) or 0, fire_polls, fire_taps, jumps, equipped_weapon(p) ~= "" and equipped_weapon(p) or "none"))
    end
    fire_polls, fire_taps = 0, 0
    seconds, updates, peak_speed, peak_rise = now, 0, 0, 0
  end
  local speed = flat * rate
  if speed > peak_speed then peak_speed = speed end
  if dy > peak_rise then peak_rise = dy end

  local ex, ey, ez = 0, 0, 0
  if run_mult ~= 1 and enabled and on.run and speed >= walk_speed then
    ex, ez = dx * (run_mult - 1), dz * (run_mult - 1)
  end
  -- Soft landing: the game measures a fall from the position saved at +404
  -- (the trainer's No Clip resets the same spot). Keeping it at the current
  -- position means every landing counts as a drop of nothing: no stumble,
  -- no ragdoll, no fall damage.
  local landing_on = soft_landing and enabled and on.landing
  if landing_on then
    wml.write_f32(p + 404, x); wml.write_f32(p + 408, y); wml.write_f32(p + 412, z)
  end

  -- A jump starts when the body's upward velocity appears from nothing.
  local swimming = (wml.read_u32(p + 508) == 9)
  if jump_mult ~= 1 and not swimming then
    local va = body_velocity_address(p)
    if va then
      local vy = wml.read_f32(va + 4)
      -- Landing damage goes by speed: never fall faster than max_fall.
      if landing_on and max_fall > 0 and vy < -max_fall then
        wml.write_f32(va + 4, -max_fall)
        vy = -max_fall
      end
      if not landing_on then drop_shield(p) end
      if landing_on then
        -- Shield while falling faster than a hop, and 5 updates past landing.
        if vy < -3 then fall_shield = 5
        elseif fall_shield > 0 then fall_shield = fall_shield - 1 end
        local want = fall_shield > 0
        if want and shield_was == nil then
          shield_was = (wml.read_u32(p + 216) & INVULNERABLE) ~= 0
          set_invulnerable(p, true)
        elseif not want and shield_was ~= nil then
          set_invulnerable(p, shield_was)
          shield_was = nil
        end
        local health = wml.read_f32(p + HEALTH)
        if last_vy < -2 and vy > -0.5 then landing_grace = 3 end  -- just landed
        if landing_grace > 0 then
          if health_prev and health < health_prev and health_prev > 0 then
            wml.write_f32(p + HEALTH, health_prev)
            landings = landings + 1
            if debug then wml.log(string.format("landing: health %.0f -> %.0f, restored", health_prev, health)) end
            health = health_prev
          end
          landing_grace = landing_grace - 1
        end
        health_prev = health
      end
      if vy > 1.5 and last_vy < 0.5 and enabled and on.jump then
        wml.write_f32(va + 4, vy * jump_mult)
        jumps = jumps + 1
        if debug then wml.log(string.format("jump: %.2f -> %.2f m/s up", vy, vy * jump_mult)) end
      end
      last_vy = vy
    end
  end
  if ex ~= 0 or ey ~= 0 or ez ~= 0 then
    nudge(ctx, p, ex, ey, ez)
    last_pos = { x + ex, y + ey, z + ez }
  end
end)

wml.log(string.format("Run x%.2f, jump x%.2f, tank %s, auto fire %s (%s toggles; debug=%s)", run_mult, jump_mult,
  tank and "on" or "off", auto_fire and (fire_rate .. "/s at the controller read") or "off", toggle_key, tostring(debug)))
