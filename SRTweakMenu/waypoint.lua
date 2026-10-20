-- SR Tweak Menu - teleport to waypoint.
--
-- Ported from the author's Teleport to Waypoint mod
-- (github.com/00xJS/SR-Teleport-to-Waypoint), driven by the menu instead of
-- keys: a toggle for "teleport whenever I set a waypoint on the map" and an
-- action for "take me to my waypoint now". When that standalone mod is also
-- ticked in the loader this one stands down, so a waypoint never moves you
-- twice.
--
-- Set a waypoint on the pause map (A / left click) and you are taken there
-- instead of driving. The game's GPS is hooked at the one place the map
-- screen hands it the clicked spot (0x822A9788, called from 0x822B6988 with
-- waypoint type 0 = the player's own). The move itself is the game's own
-- player teleport (0x82481000), the one behind the mission scripts'
-- teleport("#PLAYER#", navpoint): a car you sit in and your homies come along,
-- and the world is told to load there first (0x82510520), as the scripts do.
--
-- The map only knows where you clicked, not how high the ground is there (it
-- hands the GPS a height of 0). The GPS route's last road point does carry
-- its real height, so the player is put there first; once the world around
-- has loaded, a ray is cast straight down over the clicked spot with the
-- game's own collision probe (0x82251878) and the player is moved onto the
-- highest surface there (a roof, a bridge, the road).
--
-- Single player only (and story co-op hosts, which the game counts as single
-- player); in a multiplayer session nothing happens.

local G = require("game")

local W = { enabled = false, standalone = false }

-- The GPS (route to a waypoint).
local GPS_SET            = 0x822A9788  -- (from*, to*, type, on_icon) -> true when a route was found
local MAP_SET_CALL       = 0x822B6988  -- return address of the pause map's call, after A on the map
local GPS_TYPE           = 0x8370E0EC  -- byte: type of the current route, 0 = the player's own map waypoint, 1 = a mission's
local GPS_TARGET         = 0x839E125C  -- 3 floats: where the current route ends (height 0 for plain map clicks)
local GPS_PATH           = 0x82FFE744  -- the current route (0 = none): a ring of road segments, +4 = the last one, segment+12 = its road data
local GPS_PATH_NEW       = 0x83005148  -- where the route builder puts a route first; the GPS copies it to GPS_PATH
local NEAREST_ON_ROAD    = 0x82594690  -- (road data, pos*, out*): the point on that road nearest pos, with the road's real height
-- (A mission's own waypoint, the blue one, is type 1. It is deliberately
-- never used: only your green one counts.)

-- Teleporting.
local STREAM_AT       = 0x82510520  -- (pos*, 0, 0): load the world around a spot
local PLAYER_TELEPORT = 0x82481000  -- (player, pos*, rows*): vehicle and homies come along
local VEHICLE_PLACE   = 0x82535C68  -- (vehicle, pos*, rows*, 1)

-- The game's collision probe, as its own teleport uses it to find the ground under a player.
local RAYCAST      = 0x82251878  -- (query*, result*, 1, 0) -> 1 when something was hit; result+0 -> hit record, +4 = its height
local RAYCAST_FREE = 0x820C7850  -- (result*)
local RAY_RADIUS   = 0x82038850  -- 0.425: the character capsule's radius
local RAY_FILTER   = 0x828279D0  -- the collision filter word the game's probe passes

local INVULNERABLE = 0x00100000  -- flag bit at player+216

local close_map = wml.setting("waypoint_close_map", true)
local debug_on = wml.setting("debug", false)

local read_u8, read_u32, read_f32 = wml.read_u8, wml.read_u32, wml.read_f32
local write_u16, write_u32, write_f32 = wml.write_u16, wml.write_u32, wml.write_f32
local function log(...) wml.log(...) end
local function debug(fmt, ...) if debug_on then wml.log(string.format("waypoint: " .. fmt, ...)) end end
local function vec(a) return read_f32(a), read_f32(a + 4), read_f32(a + 8) end
-- Heap pointers on the 360 can sit anywhere up into the 0xC0000000 range.
local function heap_ok(v) return v >= 0x10000 and v < 0xFFFF0000 end

-- ------------------------------------------------- the standalone mod
--
-- Teleport to Waypoint hooks the same GPS call. If it is ticked in the
-- loader, this copy stays out of the way.
local function standalone_enabled()
  local ok, found = pcall(function()
    local f = io.open(wml.mod_folder .. "/../modlist.ini", "r")
    if not f then return false end
    local on = false
    for line in f:lines() do
      if line:match("^%s*%+%s*TeleportToWaypoint%s*$") then on = true break end
    end
    f:close()
    return on
  end)
  return ok and found
end
W.standalone = standalone_enabled()

-- ------------------------------------------------------------ game calls
--
-- Called from inside the update hook. r1 is lowered to leave the callee
-- stack room (the collision probe alone takes 11 KB); our buffers live just
-- below the hook's r1, in the area G.call's own buffers leave free.
local SCRATCH = 0x6000
local BUF_POS, BUF_ROWS, BUF_VEL, BUF_QUERY, BUF_OUT = 0x1F00, 0x1E80, 0x1E40, 0x1E00, 0x1D80
local function buf(ctx, offset) return ctx:r(1) - offset end

local function call(ctx, fn, args, f1)
  local r1 = ctx:r(1)
  local saved = {}
  for i = 3, 10 do saved[i] = ctx:r(i) end
  local saved_f1 = ctx:f(1)
  ctx:set_r(1, r1 - SCRATCH)
  for i, v in ipairs(args) do ctx:set_r(2 + i, v) end
  if f1 then ctx:set_f(1, f1) end
  ctx:call(fn)
  local result = ctx:r(3)
  ctx:set_r(1, r1)
  for i = 3, 10 do ctx:set_r(i, saved[i]) end
  ctx:set_f(1, saved_f1)
  return result
end

local function write_pos(a, x, y, z)
  write_f32(a, x); write_f32(a + 4, y); write_f32(a + 8, z); write_f32(a + 12, 0)
end

-- A vehicle's physics velocity: linear at +0, angular at +16.
local function vehicle_velocity(vehicle)
  if read_u8(vehicle + 50300) ~= 1 then return nil end
  local body = read_u32(vehicle + 244)
  if not G.pointer_ok(body) then return nil end
  local motion = read_u32(body + 88)
  if not G.pointer_ok(motion) then return nil end
  return motion + 208
end

-- Fall protection for the landing: the invulnerability bit is set and the
-- fall start (+404) kept at the player, so no fall damage, stumble or
-- ragdoll. Put back as it was afterwards.
local function set_invulnerable(p, want)
  local flags = read_u32(p + 216)
  if want then flags = flags | INVULNERABLE else flags = flags & ~INVULNERABLE & 0xFFFFFFFF end
  write_u32(p + 216, flags)
  write_u32(p + 212, read_u32(p + 212) | 1)  -- the game's dirty flag
end
local shield_was, shield_until = nil, 0
local tick, rate = 0, 50
local updates, second = 0, os.time()
-- The menu owns the invulnerability bit (W.shield, set by main.lua); on
-- its own the bit is handled here.
local function shield_on(p)
  shield_was = true
  if W.shield then W.shield(true, p) else set_invulnerable(p, true) end
end
local function shield_off(p)
  if shield_was ~= nil then
    if W.shield then W.shield(false, p)
    elseif p ~= 0 then set_invulnerable(p, W.god and W.god() or false) end
    shield_was = nil
  end
  shield_until = 0
end

-- ------------------------------------------------------------- moving
local function teleport(ctx, p, x, y, z, stream)
  local pos, rows = buf(ctx, BUF_POS), buf(ctx, BUF_ROWS)
  write_pos(pos, x, y, z)
  for i = 0, 32, 4 do write_u32(rows + i, read_u32(p + 32 + i)) end  -- keep the facing
  if stream then call(ctx, STREAM_AT, { pos, 0, 0 }) end
  call(ctx, PLAYER_TELEPORT, { p, pos, rows })
  write_f32(p + 404, x); write_f32(p + 408, y); write_f32(p + 412, z)
  if W.on_teleport then W.on_teleport() end
end

-- Height of whatever is under (x, z), from `top` down to `bottom`, with the
-- game's own probe. nil when nothing is hit (the ground is not loaded yet).
local function ground_height(ctx, x, z, top, bottom)
  local q, out = buf(ctx, BUF_QUERY), buf(ctx, BUF_OUT)
  for i = 0, 92, 4 do write_u32(q + i, 0) end
  write_f32(q, x);      write_f32(q + 4, top);     write_f32(q + 8, z)
  write_f32(q + 12, x); write_f32(q + 16, bottom); write_f32(q + 20, z)
  write_f32(q + 24, read_f32(RAY_RADIUS))
  write_u32(q + 76, read_u32(RAY_FILTER))
  write_u32(out, 0); write_u32(out + 4, 0); write_u32(out + 8, 0x80000000)
  local hit = (call(ctx, RAYCAST, { q, out, 1, 0 }) & 0xFF) == 1
  local y, solid, frac
  if hit then
    local record = read_u32(out)
    if G.pointer_ok(record) then
      y = read_f32(record + 4)
      frac = read_f32(record + 36)
      -- A real surface names a shape (+48) or an object (+52); invisible
      -- volumes in the sky have neither.
      solid = read_u32(record + 52) ~= 0xFFFFFFFF or read_u32(record + 48) ~= 0xFFFFFFFF
    end
  end
  call(ctx, RAYCAST_FREE, { out })
  return y, solid, frac
end

-- The road point the route ends on, with its real height (no streaming needed).
local function route_end(ctx, target)
  local path = read_u32(GPS_PATH_NEW)
  if not heap_ok(path) then path = read_u32(GPS_PATH) end
  local last = heap_ok(path) and read_u32(path + 4) or 0
  local data = heap_ok(last) and read_u32(last + 12) or 0
  if not heap_ok(data) then return nil end
  local out = buf(ctx, BUF_VEL)
  write_pos(out, 0, 0, 0)
  call(ctx, NEAREST_ON_ROAD, { data, target or GPS_TARGET, out })
  local x, y, z = vec(out)
  if y ~= y or y < -100 or y > 600 then return nil end
  return x, y, z
end

-- ------------------------------------------------------------ the job
--
-- request: a spot to go to, picked up by the next update.
-- settle:  after landing on the road point, find the surface at the click.
local request, settle = nil, nil
local closing, close_frames = false, 0

local function land_on_road(ctx, p, rx, ry, rz, cx, cz, off)
  local vehicle = G.vehicle_object(p)
  local lift = vehicle and 0.6 or 0.2
  teleport(ctx, p, rx, ry + lift, rz, true)
  debug("on the route's road point %.1f %.1f %.1f (%.1f m from the click)", rx, ry + lift, rz, off)
  shield_until = tick + 90
  settle = { x = cx, z = cz, est = ry, updates = 0 }
end

local function settle_step(ctx, p)
  settle.updates = settle.updates + 1
  local px, py, pz = vec(p + 20)
  local dx, dz = settle.x - px, settle.z - pz
  local flat = math.sqrt(dx * dx + dz * dz)
  local vehicle = G.vehicle_object(p)
  local lift = vehicle and 1.0 or 0.2
  local function done(y)
    if vehicle then
      -- Placed the way the script function teleport_vehicle does it: settle
      -- every wheel, move body and physics, then the after-move call.
      local pos = buf(ctx, BUF_POS)
      write_pos(pos, settle.x, y + lift, settle.z)
      local wheels = math.min(call(ctx, 0x82534AE8, { vehicle }) & 0xFFFF, 16)
      for i = 0, wheels - 1 do
        local wheel = call(ctx, 0x82534EC8, { vehicle, i })
        if wheel ~= 0 then call(ctx, 0x825353C0, { vehicle, wheel }, 0.0) end
      end
      call(ctx, VEHICLE_PLACE, { vehicle, pos, vehicle + 32, 1 })
      call(ctx, 0x8253BA90, { vehicle })
      local v = vehicle_velocity(vehicle)
      if v then for i = 0, 8, 4 do write_f32(v + i, 0); write_f32(v + 16 + i, 0) end end
      write_f32(p + 404, settle.x); write_f32(p + 408, y + lift); write_f32(p + 412, settle.z)
    else
      teleport(ctx, p, settle.x, y + lift, settle.z, false)
    end
    G.hud("Teleported to your waypoint")
    debug("on the waypoint at %.1f %.1f %.1f after %d updates", settle.x, y + lift, settle.z, settle.updates)
    settle = nil
    shield_until = tick + 90
  end
  if flat < 20 then
    -- Too close for the probe (it would meet the player's own proxy).
    if settle.updates >= 5 then done(py) end
    return
  end
  local top = settle.top or (math.max(settle.est, py) + 80)
  local bottom = settle.est - 40
  if top < bottom + 5 then
    if settle.volume_y then done(settle.volume_y) return end
    G.hud("Teleported near your waypoint")
    settle = nil
    return
  end
  local y, solid, frac = ground_height(ctx, settle.x, settle.z, top, bottom)
  if y then
    local dy = y - py
    local dist = math.sqrt(flat * flat + dy * dy)
    if dist < 20 then
      -- the player's own proxy; ignored
    elseif not solid then
      -- A volume, not a surface: step down through it.
      settle.volume_y = math.min(settle.volume_y or y, y)
      settle.top = ((frac or 1) <= 0.001) and (top - 2) or (y - 0.5)
    else
      done(y)
      return
    end
  end
  if settle.updates > 4 * rate then
    G.hud("Teleported near your waypoint")
    settle = nil
  end
end

local function start(ctx, p)
  local r = request
  request = nil
  local rx, ry, rz
  if r.road then rx, ry, rz = r.road[1], r.road[2], r.road[3] else rx, ry, rz = route_end(ctx) end
  if not rx then
    G.hud("Couldn't read the route to your waypoint")
    return
  end
  local dx, dz = rx - r.x, rz - r.z
  local off = math.sqrt(dx * dx + dz * dz)
  if off >= 200 then
    G.hud("That spot is too far from any road")
    return
  end
  shield_on(p)
  land_on_road(ctx, p, rx, ry, rz, r.x, r.z, off)
end

-- "Take me to my waypoint now": your own (green) map waypoint only; a
-- mission's blue one is left alone. Returns the message for the menu.
function W.go_now()
  if W.standalone then return "Teleport to Waypoint mod is ticked; its key 8 does this" end
  if read_u32(GPS_PATH) == 0 then return "No waypoint set: put one on the map first" end
  if read_u8(GPS_TYPE) ~= 0 then return "Only your own map waypoint is used, not a mission's" end
  local x, y, z = vec(GPS_TARGET)
  request = { x = x, y = y, z = z }
  return "Going to your waypoint"
end

-- ----------------------------------------------------------------- hooks

-- The pause map setting the player's waypoint.
wml.hook(GPS_SET, function(ctx)
  local from_map = W.enabled and ctx:lr() == MAP_SET_CALL and (ctx:r(5) & 0xFF) == 0
  local x, y, z
  if from_map then x, y, z = vec(ctx:r(4)) end
  ctx:call_original()
  if not from_map then return end
  if (ctx:r(3) & 0xFF) == 0 or read_u8(G.MULTIPLAYER) ~= 0 then return end
  -- The route exists right now (it is gone again by the next update), so
  -- take its end point here; the clicked spot is still in r4's memory.
  local rx, ry, rz = route_end(ctx, ctx:r(4))
  request = { x = x, y = y, z = z, road = rx and { rx, ry, rz } or nil }
  if close_map then closing, close_frames = true, 0 end
  debug("map waypoint at %.1f %.1f %.1f; road point %s", x, y, z, rx and string.format("%.1f %.1f %.1f", rx, ry, rz) or "not readable")
end)

-- Closing the map: Backspace (VK 8) is B for the keyboard controls, and B
-- leaves the map. Tapped (4 frames down, 4 up) until no screen is up, for
-- at most 3 seconds.
local SCREEN_C, SCREEN_D = 0x82FFE434, 0x82FFE43C
local function any_screen_up()
  return read_u32(G.MENU_A) ~= 0 or read_u32(G.MENU_B) ~= 0 or read_u32(SCREEN_C) ~= 0 or read_u32(SCREEN_D) ~= 0
end
wml.on_frame(function()
  if not closing then return end
  if not any_screen_up() or close_frames > 180 then
    pcall(wml.force_key, 8, false)
    closing = false
    return
  end
  pcall(wml.force_key, 8, (close_frames % 8) < 4)
  close_frames = close_frames + 1
end)

-- Called every game update from main.lua.
function W.update(ctx)
  tick = tick + 1
  updates = updates + 1
  local now = os.time()
  if now ~= second then
    if updates > 10 then rate = updates end
    updates, second = 0, now
  end
  local p = G.player()
  if p == 0 or G.in_front_end() then
    -- Never just forgotten: a shield left raised here was a god mode that
    -- wouldn't go away.
    request, settle = nil, nil
    shield_off(p)
    return
  end
  if request then
    if G.in_cutscene() then request = nil else settle = nil; start(ctx, p) end
  end
  if settle then
    if G.in_cutscene() then settle = nil elseif not G.screen_up() then settle_step(ctx, p) end
  end
  -- Fall protection after a move, then put the flag back.
  if shield_was ~= nil then
    if tick < shield_until then
      local x, y, z = vec(p + 20)
      write_f32(p + 404, x); write_f32(p + 408, y); write_f32(p + 412, z)
    else
      shield_off(p)
    end
  end
end

if W.standalone then log("Teleport to Waypoint mod is ticked; the menu's waypoint teleport stays off") end

return W
