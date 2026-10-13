-- SR Tweak Menu - free camera (photo mode).
--
-- The camera object at 0x827D9778 is driven by a mode stack. The debug
-- "slew" camera was stripped from the retail game, so this pushes mode 5,
-- which has no handlers: the camera manager then just copies the "wanted"
-- values to the "final" ones every frame, nothing fights our writes, the
-- follow camera stops, and the First Person core mod switches itself off
-- (it only acts while the mode is 0). Every update the menu writes:
--   position     +56 (wanted)  and +44 (final)
--   rows         +116/+128/+140 (wanted) and +80/+92/+104 (final): right, up, forward
--   field of view +192 (wanted) and +188 (final), degrees
-- The camera manager runs inside the game update the menu hooks, and the
-- render snapshot reads the camera after it, so writing at the end of that
-- hook is enough. Leaving pops mode 5 again (only if it is still on the
-- stack), which restores the mode underneath and the follow camera.
--
-- Look: wml.mouse_look() (it already includes the controller's right stick
-- and the game's invert settings). Move: WASD, or the left stick and the
-- triggers read in the controller hook. The pad is blanked for the game
-- while the camera flies, and the keys the keyboard layer maps (Q opens its
-- radial menu) are taken, so the player stands still.
--
-- Your character turns their head and body towards wherever the game's
-- camera points, so before each game update the camera is put back where it
-- was when you started flying, and the flown view is written again after.
--
-- Shots: Enter / A while flying (or the Free camera mode row) leaves the
-- camera where it is and gives the pad back, so you play as seen from that
-- spot. "Tracking" keeps the camera in place but turns it to keep you in
-- frame. The game aims and turns your moves by its camera, so during the
-- update it sees an aim camera behind you instead, which the right stick /
-- mouse turns round you like a twin-stick game: it keeps one height and
-- tilt, so you only pick a direction, never a height. The shot is put
-- back after the update for the picture.

local G = require("game")

local FC = { on = false, mode = 1, pad = { lx = 0, ly = 0, buttons = 0, lt = 0, rt = 0 } }
FC.MODES = { "Fly", "Fixed shot", "Tracking shot" }
local FLY, FIXED, TRACK = 1, 2, 3
local PAD_A = 0x1000

local CAM, PUSH, POP = 0x827D9778, 0x8210A568, 0x8210A650
local MODE_FREE = 5
local KEYS = { "W", "A", "S", "D", "Q", "E", "SPACE", "SHIFT", "CTRL", "ALT", "Z", "X", "R", "F", "C", "V", "TAB", "ENTER" }
local LEASH = 150   -- metres from the player: the world only streams around them
-- The aim camera: metres behind you, height above your feet, a slight
-- downward tilt (level aim sent rounds over people's heads), and how much
-- faster than the normal camera the right stick / mouse spins it.
local AIM_BACK, AIM_UP, AIM_PITCH, AIM_TURN = 3.0, 1.0, -0.06, 2.0
FC.AIM_UP, FC.AIM_PITCH, FC.AIM_TURN = AIM_UP, AIM_PITCH, AIM_TURN

local read_u32, read_f32, write_f32 = wml.read_u32, wml.read_f32, wml.write_f32
local function put(a, v) write_f32(a, v[1]); write_f32(a + 4, v[2]); write_f32(a + 8, v[3]) end
local function get(a) return { read_f32(a), read_f32(a + 4), read_f32(a + 8) } end

-- Rows from yaw (positive turns right) and pitch (positive looks up), the
-- formula World Studio's own free camera uses on this object.
local function rows(yaw, pitch)
  local cp, sp, cy, sy = math.cos(pitch), math.sin(pitch), math.cos(yaw), math.sin(yaw)
  return { cy, 0, -sy }, { -sy * sp, cp, -cy * sp }, { sy * cp, sp, cy * cp }
end

local function mode_in_stack()
  local depth = math.min(read_u32(CAM + 36), 8)
  for i = 0, depth - 1 do if read_u32(CAM + 4 + i * 4) == MODE_FREE then return true end end
  return false
end

local function take_keys(on) for _, k in ipairs(KEYS) do pcall(wml.take_key, k, on) end end
local taken = false
local function hold_keys(on) if taken ~= on then take_keys(on); taken = on end end

function FC.flying() return FC.on and FC.mode == FLY end

-- Fly, or play from the shot (Fixed / Tracking). Can be set while off: it
-- is then used when the free camera starts.
function FC.set_mode(m)
  m = (m == FIXED or m == TRACK) and m or FLY
  if FC.on and m ~= FC.mode then
    pcall(wml.mouse_look)        -- no turn carried over from flying
    if m ~= FLY and FC.mode == FLY then
      -- Aim starts the way the shot looks (level), so forward is "into" it.
      FC.aim_yaw, FC.aim_pitch = FC.yaw, AIM_PITCH
    end
    hold_keys(m == FLY)
  end
  FC.mode = m
end

local function put_pose(pos, r, u, f)
  put(CAM + 56, pos); put(CAM + 116, r); put(CAM + 128, u); put(CAM + 140, f)
  put(CAM + 44, pos); put(CAM + 80, r); put(CAM + 92, u); put(CAM + 104, f)
end

-- Before the game update: while flying, the game sees the camera where it
-- was when flying started, so your character doesn't turn to follow it.
function FC.before_update()
  if not FC.on or read_u32(CAM) ~= MODE_FREE then return end
  if FC.mode == FLY then
    local sv = FC.saved
    put_pose(sv.pos, sv.r, sv.u, sv.f)
    return
  end
  -- Playing from the shot: the game aims from behind you.
  local p = G.player()
  if p == 0 or not FC.aim_yaw then return end
  local px, py, pz = G.vec(p + G.P.POS)
  local r, u, f = rows(FC.aim_yaw, FC.aim_pitch)
  local at = { px - f[1] * AIM_BACK, py + AIM_UP - f[2] * AIM_BACK, pz - f[3] * AIM_BACK }
  put_pose(at, r, u, f)
end

function FC.enter(ctx)
  if FC.on then return true end
  if G.player() == 0 or G.in_front_end() or G.in_cutscene() or G.screen_up() then return false end
  FC.saved = { pos = get(CAM + 44), r = get(CAM + 80), u = get(CAM + 92), f = get(CAM + 104),
               fov = read_f32(CAM + 188), wfov = read_f32(CAM + 192) }
  FC.pos = get(CAM + 44)
  local f = FC.saved.f
  FC.yaw, FC.pitch = math.atan(f[1], f[3]), math.asin(math.max(-1, math.min(1, f[2])))
  FC.fov = (FC.saved.fov > 5 and FC.saved.fov < 170) and FC.saved.fov or 70
  G.call(ctx, PUSH, { MODE_FREE })
  FC.aim_yaw, FC.aim_pitch = FC.yaw, AIM_PITCH
  taken = false
  hold_keys(FC.mode == FLY)
  pcall(wml.mouse_look)          -- drop any turn that built up before
  FC.clock = os.clock()
  FC.why = nil
  FC.prev_a = true               -- the A / Enter that opened it doesn't count
  FC.on = true
  return true
end

function FC.exit(ctx)
  if not FC.on then return end
  FC.on = false
  if mode_in_stack() then
    -- Start the normal camera from where it was before.
    put(CAM + 44, FC.saved.pos); put(CAM + 56, FC.saved.pos)
    put(CAM + 80, FC.saved.r); put(CAM + 92, FC.saved.u); put(CAM + 104, FC.saved.f)
    put(CAM + 116, FC.saved.r); put(CAM + 128, FC.saved.u); put(CAM + 140, FC.saved.f)
    G.call(ctx, POP, { MODE_FREE })
  end
  write_f32(CAM + 192, FC.saved.wfov); write_f32(CAM + 188, FC.saved.fov)
  hold_keys(false)
  pcall(wml.mouse_look)
end

-- The controller hook hands the pad over before blanking it. Returns true
-- when the game should see no input (the camera is flying).
function FC.capture(state)
  local function s16(v) return v >= 0x8000 and v - 0x10000 or v end
  FC.pad.buttons = wml.read_u16(state + 4)
  FC.pad.lt, FC.pad.rt = wml.read_u8(state + 6), wml.read_u8(state + 7)
  FC.pad.lx, FC.pad.ly = s16(wml.read_u16(state + 8)), s16(wml.read_u16(state + 10))
  return FC.flying()
end

-- At the end of the game update. `paused` = the menu is open (the camera
-- holds still while you use the menu). Returns false if it had to stop.
function FC.update(ctx, paused)
  if not FC.on then return true end
  local p = G.player()
  if p == 0 or G.in_front_end() or G.in_cutscene() or G.screen_up() or read_u32(CAM) ~= MODE_FREE then
    FC.exit(ctx)
    return false
  end
  local now = os.clock()
  local dt = math.max(0, math.min(0.05, now - FC.clock))
  FC.clock = now
  local px, py, pz = G.vec(p + G.P.POS)
  if FC.mode ~= FLY then
    -- Playing from the shot: the camera stays put (and turns to you when
    -- tracking). Too far away and the world there unloads: back to normal.
    -- The right stick / mouse turns the aim camera.
    local okl, dyaw, dpitch = pcall(wml.mouse_look)
    if okl and not paused then
      FC.aim_yaw = (FC.aim_yaw or FC.yaw) + (dyaw or 0) * AIM_TURN   -- up/down is ignored
      FC.aim_pitch = AIM_PITCH
    end
    local dx, dy, dz = px - FC.pos[1], py + 1.0 - FC.pos[2], pz - FC.pos[3]
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    if dist > LEASH then
      FC.why = "Too far from the camera: normal camera back"
      FC.exit(ctx)
      return false
    end
    if FC.mode == TRACK and dist > 0.5 then
      local yaw, pitch = math.atan(dx, dz), math.asin(dy / dist)
      local turn = (yaw - FC.yaw + math.pi) % (2 * math.pi) - math.pi
      local k = paused and 0 or math.min(1, dt * 6)   -- eases round, not snapping
      FC.yaw = FC.yaw + turn * k
      FC.pitch = FC.pitch + (math.max(-1.5, math.min(1.5, pitch)) - FC.pitch) * k
    end
    local r, u, f = rows(FC.yaw, FC.pitch)
    put_pose(FC.pos, r, u, f)
    write_f32(CAM + 192, FC.fov); write_f32(CAM + 188, FC.fov)
    return true
  end
  take_keys(true)   -- the menu gives keys back when it closes; keep ours
  taken = true
  -- Enter / A: play from this shot.
  local okk, enter = pcall(wml.key_pressed, "ENTER")
  local a = (FC.pad.buttons & PAD_A) ~= 0
  if not paused and ((okk and enter) or (a and not FC.prev_a)) then
    FC.prev_a = a
    FC.set_mode(FIXED)
    return FC.update(ctx, paused)
  end
  FC.prev_a = a
  local ok, dyaw, dpitch = pcall(wml.mouse_look)
  if paused or not ok then dyaw, dpitch = 0, 0 end
  FC.yaw = FC.yaw + (dyaw or 0)
  FC.pitch = math.max(-1.5, math.min(1.5, FC.pitch + (dpitch or 0)))
  local r, u, f = rows(FC.yaw, FC.pitch)
  if not paused then
    local function key(k) local okk, d = pcall(wml.key_down, k) return okk and d end
    local function axis(v) v = v / 32767; return math.abs(v) < 0.24 and 0 or v end
    local mf = (key("W") and 1 or 0) - (key("S") and 1 or 0) + axis(FC.pad.ly)
    local mr = (key("D") and 1 or 0) - (key("A") and 1 or 0) + axis(FC.pad.lx)
    local mu = ((key("E") or key("SPACE")) and 1 or 0) - ((key("Q") or key("CTRL")) and 1 or 0)
      + FC.pad.rt / 255 - FC.pad.lt / 255
    local speed = 8 * (key("SHIFT") and 4 or 1) * (key("ALT") and 0.25 or 1)
    local s = speed * dt
    for i = 1, 3 do FC.pos[i] = FC.pos[i] + (f[i] * mf + r[i] * mr) * s end
    FC.pos[2] = FC.pos[2] + mu * s
    local zoom = ((key("X") or (FC.pad.buttons & 0x0200) ~= 0) and 1 or 0)
      - ((key("Z") or (FC.pad.buttons & 0x0100) ~= 0) and 1 or 0)
    FC.fov = math.max(10, math.min(120, FC.fov + zoom * 40 * dt))
    -- Stay within reach of the player, where the world is loaded.
    local dx, dy, dz = FC.pos[1] - px, FC.pos[2] - py, FC.pos[3] - pz
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    if dist > LEASH then
      local k = LEASH / dist
      FC.pos = { px + dx * k, py + dy * k, pz + dz * k }
    end
  end
  put_pose(FC.pos, r, u, f)
  write_f32(CAM + 192, FC.fov); write_f32(CAM + 188, FC.fov)
  return true
end

return FC
