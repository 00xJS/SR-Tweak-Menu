-- SR Creator: build stunt parks out of 26 kinds of piece (ramps, curves, a half
-- pipe, platforms, bridges, blocks, towers, walls, stairs). The pieces are 26
-- anchored objects in the always-loaded chunk (build_chunk.py); any of them can
-- become any kind, and this moves them. A build lasts until the game closes;
-- it is only saved and loaded when you ask. Only the game update calls the game.
local UPDATE, PLAYER, PAD_READ = 0x82209E30, 0x8309ABEC, 0x82788EC4
local LEVELS, MOVER_CREATE, BODY_MOVE, BODIES = 0x829A9900, 0x82498818, 0x82253D70, 0x83977F50
local BODY_FREE, BODY_BUILD = 0x82253450, 0x82498DA8
local MAILBOX, MAGIC = 0x00F00000, 0x53524D55
-- The tweak menu's Creator tab talks to this through a mailbox of its own:
-- +0 'SRCR' (written here), +4 command count (the menu bumps it after writing
-- +8 command and +12 argument), +16 state bits (1 creator on, 2 moving the
-- build, 4 pieces found, 8 build camera, 16 grid snap), +20 pieces placed, +24 the held piece's kind (1-based,
-- 0 none), +28 slots, +32 kinds, +36 the last command count done here.
local BOX, BOX_MAGIC = 0x00F08000, 0x53524352
local SCRATCH, BUF = 0x6000, 0x1000
-- The build camera, the way the tweak menu's free camera works: the camera
-- object at CAM gets mode 5 pushed (nothing drives it then), and the view is
-- written to its wanted (+56, rows +116/+128/+140) and final (+44, rows
-- +80/+92/+104) pose after every game update. Before the update it is put
-- back where it was, so your character doesn't turn to look where it flies.
local CAM, CAM_PUSH, CAM_POP, CAM_FREE = 0x827D9778, 0x8210A568, 0x8210A650, 5
local CAM_KEYS = { "W", "A", "S", "D", "Q", "E", "SPACE", "SHIFT", "CTRL", "ALT" }
local LEASH = 150          -- metres from the player: the world only streams around them
local GRID, GRID_Y = 1.0, 0.5
local PAD = { UP = 0x1, DOWN = 0x2, LEFT = 0x4, RIGHT = 0x8, START = 0x10, BACK = 0x20, LS = 0x40, RS = 0x80,
  LB = 0x100, RB = 0x200, A = 0x1000, B = 0x2000, X = 0x4000, Y = 0x8000 }
local DPAD = PAD.UP | PAD.DOWN | PAD.LEFT | PAD.RIGHT
local FACE = PAD.A | PAD.B | PAD.X | PAD.Y | PAD.RB | PAD.BACK | PAD.LS | PAD.RS
local TURN, RAISE, TILT, ROLL = math.rad(15), 0.25, math.rad(5), math.rad(90)
local REACH_MIN, REACH_MAX, REACH_SPEED = 4, 80, 0.6
local KEYS = { "UP", "DOWN", "LEFT", "RIGHT", "PAGEUP", "PAGEDOWN", "HOME", "END", "ENTER", "BACKSPACE",
  "INSERT", "DELETE", "PLUS", "MINUS", "F6", "F9", "F10", "F11", "G" }
-- Pieces whose top runs on at the front end (the next snapped piece starts up there).
local RISES = { ramp = true, ramp_mid = true, bigramp = true, megaramp = true, kicker = true, kicker_steep = true,
  ramp_wide = true, launch = true, stairs = true }

local function ok(v) return v and v >= 0x10000 and v < 0xC0000000 end
local function log(...) wml.log(string.format(...)) end
local function now() return os.clock() end

local P do
  local f = io.open(wml.mod_folder .. "/pieces.lua", "r")
  P = f and load(f:read("a"))() or { pieces = {}, slots = {} }
  if f then f:close() end
end
local PIECE, ORDER, INDEX = {}, {}, {}
for i, p in ipairs(P.pieces) do PIECE[p.key] = p; ORDER[i] = p.key; INDEX[p.key] = i end
-- Slot k starts as kind k; its record's shape index and its instance's mesh
-- pointer for that kind are read once the chunk is loaded (SHAPE, MESH).
local SLOTS, SHAPE, MESH = {}, {}, {}
for k, uid in ipairs(P.slots) do SLOTS[k] = { uid = uid, piece = ORDER[k], rec = 0, mover = 0, used = false } end
local function build_file(n) return string.format("%s/build_%d.txt", wml.mod_folder, n) end

local function call(ctx, fn, args)
  local r1, saved = ctx:r(1), {}
  for i = 3, 10 do saved[i] = ctx:r(i) end
  for i, v in ipairs(args) do ctx:set_r(2 + i, v & 0xFFFFFFFF) end
  ctx:set_r(1, r1 - SCRATCH)
  ctx:call(fn)
  local r3 = ctx:r(3) & 0xFFFFFFFF
  ctx:set_r(1, r1)
  for i = 3, 10 do ctx:set_r(i, saved[i]) end
  return r3
end

-- ------------------------------------------------------------ the objects
local level_id = 0
local function find_records()
  local want = {}
  for _, s in ipairs(SLOTS) do want[s.uid] = s end
  local found = 0
  for i = 0, 63 do
    local level = wml.read_u32(LEVELS + i * 4)
    if ok(level) then
      local base, n = wml.read_u32(level + 216), wml.read_u32(level + 212)
      if ok(base) and n and n > 0 and n < 200000 then
        for r = 0, n - 1 do
          local s = want[wml.read_u32(base + r * 80 + 40)]
          if s then s.rec = base + r * 80; level_id = wml.read_u8(level + 8); found = found + 1 end
        end
        if found > 0 then return found end
      end
    end
  end
  return found
end

local function rows(yaw, pitch, roll)
  local cy, sy, cp, sp, cr, sr = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch), math.cos(roll), math.sin(roll)
  local function turn(x, y, z)
    y, z = y * cp + z * sp, -y * sp + z * cp
    return x * cy + z * sy, y, -x * sy + z * cy
  end
  local ax, ay, az = { turn(cr, sr, 0) }, { turn(-sr, cr, 0) }, { turn(0, 0, 1) }
  return { ax[1], ax[2], ax[3], ay[1], ay[2], ay[3], az[1], az[2], az[3] }
end

local function write_vec(addr, v)
  for i = 1, #v do wml.write_f32(addr + (i - 1) * 4, v[i]) end
end

local function mover_of(ctx, s)
  if s.rec == 0 or wml.read_u32(s.rec + 40) ~= s.uid then
    if find_records() == 0 or s.rec == 0 then return 0 end
  end
  local m = wml.read_u32(s.rec + 12) or 0
  if m == 0 then
    m = call(ctx, MOVER_CREATE, { s.rec, level_id, 0, 0xFFFFFFFF, 0 })
    if not ok(m) then log("couldn't make the %s object (%08X)", s.piece, m) return 0 end
  end
  s.mover = m
  return m
end

-- Turns a slot into another kind: its look (the instance's mesh), its shape
-- (the record's), and, once it has a body, a new body built from that shape.
local function set_kind(ctx, s, key)
  if s.piece == key then return true end
  local t = INDEX[key]
  if not (SHAPE[t] and MESH[t]) or s.rec == 0 then return false end
  local inst = wml.read_u32(s.rec + 60) or 0
  if not ok(inst) then return false end
  wml.write_u16(s.rec + 56, SHAPE[t])
  wml.write_u32(inst + 104, MESH[t])
  s.piece = key
  local m = wml.read_u32(s.rec + 12) or 0
  if ok(m) then
    local h = wml.read_u32(m + 116) or 0xFFFFFFFF
    if h < 5000 then call(ctx, BODY_FREE, { h }) end
    wml.write_u32(m + 116, 0xFFFFFFFF)
    call(ctx, BODY_BUILD, { m })
    s.ghost = nil
    log("slot is now %s: body %d -> %d", key, h < 5000 and h or -1, wml.read_u32(m + 116) or -1)
  end
  return true
end

-- Puts a slot's object at pos. A ghost (the piece you're holding, or a build
-- being carried) shows there but its body waits under the map, so it can't
-- shove you through the ground or catch traffic; it turns solid when placed.
local PARK_Y = -150.0
local function place_slot(ctx, s, pos, yaw, pitch, roll, ghost)
  local m = mover_of(ctx, s)
  if m == 0 then return false end
  local r = rows(yaw, pitch, roll)
  for _, at in ipairs({ 20, 236, 356 }) do write_vec(m + at, pos) end
  for _, at in ipairs({ 32, 248, 368 }) do write_vec(m + at, r) end
  local inst = wml.read_u32(s.rec + 60) or 0
  if ok(inst) then write_vec(inst + 4, pos); write_vec(inst + 16, r) end
  local p = PIECE[s.piece]
  local reach = math.sqrt(p.w * p.w + p.l * p.l + p.h * p.h)
  write_vec(s.rec, { pos[1] - reach, pos[2] - reach, pos[3] - reach })
  write_vec(s.rec + 16, { pos[1] + reach, pos[2] + reach, pos[3] + reach })
  local h = wml.read_u32(m + 116)
  if ghost and s.ghost then return true end
  if h and h < 5000 and ok(wml.read_u32(BODIES + h * 24)) then
    local buf = ctx:r(1) - BUF
    write_vec(buf, ghost and { pos[1], PARK_Y, pos[3] } or pos)
    write_vec(buf + 16, r)
    call(ctx, BODY_MOVE, { h, buf, buf + 16 })
    s.ghost = ghost or nil
  end
  return true
end

local function park(ctx, k)
  local s = SLOTS[k]
  if s.mover ~= 0 then place_slot(ctx, s, { k * 25.0, PARK_Y, 0.0 }, 0, 0, 0) end
end

-- ------------------------------------------------------------ the build
local placed = {}          -- { k, pos, yaw, pitch, roll }
local held = nil           -- { k, yaw, pitch, roll, reach, up, fixed = { pos, yaw } }
local creator, moving, message, message_until = false, nil, "", 0
local cam = nil            -- the build camera while it flies: { pos, yaw, pitch, saved, clock }
local grid = false
local pad_raw = { buttons = 0, lt = 0, rt = 0, lx = 0, ly = 0 }
local function say(text) message, message_until = text, now() + 3 end

-- A free slot, one already of that kind if there is one (no new body needed).
local function free_slot(key)
  local any
  for k, s in ipairs(SLOTS) do
    if not s.used then
      if s.piece == key then return k end
      any = any or k
    end
  end
  return any
end
local function slots_left()
  local n = 0
  for _, s in ipairs(SLOTS) do if not s.used then n = n + 1 end end
  return n
end

local function player()
  local p = wml.read_u32(PLAYER) or 0
  if not ok(p) then return nil end
  local x, y, z = wml.read_f32(p + 20), wml.read_f32(p + 24), wml.read_f32(p + 28)
  local fx, fz = wml.read_f32(p + 56), wml.read_f32(p + 64)
  if not (x and fx) or x ~= x then return nil end
  return { x, y, z }, math.atan(fx, fz)
end

-- With the build camera the piece floats where you look, `reach` metres out;
-- without it, in front of you. Grid snap rounds the spot to whole metres (half
-- a metre up and down) and the turn to 15 degree steps.
local function held_pose()
  if held.fixed then return held.fixed.pos, held.fixed.yaw end
  local pos, yaw
  if cam then
    local cp = math.cos(cam.pitch)
    local f = { math.sin(cam.yaw) * cp, math.sin(cam.pitch), math.cos(cam.yaw) * cp }
    pos = { cam.pos[1] + f[1] * held.reach, cam.pos[2] + f[2] * held.reach + held.up, cam.pos[3] + f[3] * held.reach }
    yaw = cam.yaw + held.yaw
  else
    local at, heading = player()
    if not at then return nil end
    pos = { at[1] + math.sin(heading) * held.reach, at[2] + held.up, at[3] + math.cos(heading) * held.reach }
    yaw = heading + held.yaw
  end
  if grid then
    pos = { math.floor(pos[1] / GRID + 0.5) * GRID, math.floor(pos[2] / GRID_Y + 0.5) * GRID_Y,
      math.floor(pos[3] / GRID + 0.5) * GRID }
    yaw = math.floor(yaw / TURN + 0.5) * TURN
  end
  return pos, yaw
end

-- ------------------------------------------------------------ the build camera
local function vget(a) return { wml.read_f32(a), wml.read_f32(a + 4), wml.read_f32(a + 8) } end
local function cam_rows(yaw, pitch)
  local cp, sp, cy, sy = math.cos(pitch), math.sin(pitch), math.cos(yaw), math.sin(yaw)
  return { cy, 0, -sy }, { -sy * sp, cp, -cy * sp }, { sy * cp, sp, cy * cp }
end
local function put_pose(pos, r, u, f)
  write_vec(CAM + 56, pos); write_vec(CAM + 116, r); write_vec(CAM + 128, u); write_vec(CAM + 140, f)
  write_vec(CAM + 44, pos); write_vec(CAM + 80, r); write_vec(CAM + 92, u); write_vec(CAM + 104, f)
end
local function cam_in_stack()
  for i = 0, math.min(wml.read_u32(CAM + 36) or 0, 8) - 1 do
    if wml.read_u32(CAM + 4 + i * 4) == CAM_FREE then return true end
  end
  return false
end
local function cam_enter(ctx)
  if cam then return true end
  if (wml.read_u32(MAILBOX + 0x30) or 0) & 4 ~= 0 then say("The menu's free camera is on: switch it off first") return false end
  local saved = { pos = vget(CAM + 44), r = vget(CAM + 80), u = vget(CAM + 92), f = vget(CAM + 104) }
  local f = saved.f
  call(ctx, CAM_PUSH, { CAM_FREE })
  cam = { saved = saved, pos = vget(CAM + 44), yaw = math.atan(f[1], f[3]),
    pitch = math.asin(math.max(-1, math.min(1, f[2]))), clock = now() }
  pcall(wml.mouse_look)
  say("Build camera: fly with WASD / left stick, E Q / RT LT up and down, Shift faster; the piece goes where you look")
  return true
end
local function cam_exit(ctx)
  if not cam then return end
  local sv = cam.saved
  cam = nil
  if cam_in_stack() then
    put_pose(sv.pos, sv.r, sv.u, sv.f)
    call(ctx, CAM_POP, { CAM_FREE })
  end
  pcall(wml.mouse_look)
end
local function cam_fly(paused, lb)
  local t = now()
  local dt = math.max(0, math.min(0.05, t - cam.clock))
  cam.clock = t
  local okl, dyaw, dpitch = pcall(wml.mouse_look)
  if paused or not okl then dyaw, dpitch = 0, 0 end
  cam.yaw = cam.yaw + (dyaw or 0)
  cam.pitch = math.max(-1.5, math.min(1.5, cam.pitch + (dpitch or 0)))
  local r, u, f = cam_rows(cam.yaw, cam.pitch)
  if not paused then
    local function key(k) local okk, d = pcall(wml.key_down, k) return okk and d end
    local function axis(v) v = v / 32767 return math.abs(v) < 0.24 and 0 or v end
    local mf = (key("W") and 1 or 0) - (key("S") and 1 or 0) + axis(pad_raw.ly)
    local mr = (key("D") and 1 or 0) - (key("A") and 1 or 0) + axis(pad_raw.lx)
    local mu = ((key("E") or key("SPACE")) and 1 or 0) - ((key("Q") or key("CTRL")) and 1 or 0)
    if not lb then mu = mu + pad_raw.rt / 255 - pad_raw.lt / 255 end   -- LB + triggers move the piece instead
    local step = 10 * (key("SHIFT") and 4 or 1) * (key("ALT") and 0.25 or 1) * dt
    for i = 1, 3 do cam.pos[i] = cam.pos[i] + (f[i] * mf + r[i] * mr) * step end
    cam.pos[2] = cam.pos[2] + mu * step
    local me = player()
    if me then
      local dx, dy, dz = cam.pos[1] - me[1], cam.pos[2] - me[2], cam.pos[3] - me[3]
      local d = math.sqrt(dx * dx + dy * dy + dz * dz)
      if d > LEASH then cam.pos = { me[1] + dx * LEASH / d, me[2] + dy * LEASH / d, me[3] + dz * LEASH / d } end
    end
  end
  put_pose(cam.pos, r, u, f)
end

local function take_slot(ctx, key, from)
  local k = free_slot(key)
  if not k or not set_kind(ctx, SLOTS[k], key) then return nil end
  SLOTS[k].used = true
  local h = from or { yaw = 0, pitch = 0, roll = 0, reach = 14, up = 0 }
  return { k = k, yaw = h.yaw, pitch = h.pitch, roll = h.roll, reach = h.reach, up = h.up, fixed = h.fixed }
end

-- Taking a key is shared by every mod: the tweak menu takes the arrows, Enter
-- and so on while it's open and gives them back when it closes. So the creator
-- only takes or gives back its keys while the menu is closed, and takes them
-- again after the menu closes (on_frame).
local keys_taken = {}
local function menu_open() return (wml.read_u32(MAILBOX + 0x30) or 0) & 2 ~= 0 end
local function take_keys(on)
  if menu_open() then keys_taken = {} return end
  local want = {}
  if on then
    for _, k in ipairs(KEYS) do want[k] = true end
    if cam then for _, k in ipairs(CAM_KEYS) do want[k] = true end end
  end
  for k in pairs(keys_taken) do if not want[k] then wml.take_key(k, false) end end
  for k in pairs(want) do if not keys_taken[k] then wml.take_key(k, true) end end
  keys_taken = want
end

local function set_creator(ctx, on)
  creator = on
  take_keys(on)
  if on then
    if not held then
      local key = (placed[#placed] and SLOTS[placed[#placed].k].piece) or ORDER[1]
      held = take_slot(ctx, key)
    end
    say(held and "Creator on" or "Every piece is placed: pick one up (LB + X) or undo (LB + B)")
  else
    if held then park(ctx, held.k); SLOTS[held.k].used = false; held = nil end
    moving = nil
    cam_exit(ctx)
    take_keys(false)
  end
end

local function nearest_placed(pos)
  local best, bd = nil, 1e9
  for i, e in ipairs(placed) do
    local d = (e.pos[1] - pos[1]) ^ 2 + (e.pos[2] - pos[2]) ^ 2 + (e.pos[3] - pos[3]) ^ 2
    if d < bd then best, bd = i, d end
  end
  return best, bd
end

local function clear_build(ctx)
  for _, e in ipairs(placed) do park(ctx, e.k); SLOTS[e.k].used = false end
  placed, moving = {}, nil
end

local function save_build(n)
  local f = io.open(build_file(n), "w")
  if not f then return false end
  f:write("-- SR Creator build: piece x y z yaw pitch roll (degrees)\n")
  for _, e in ipairs(placed) do
    f:write(string.format("%s %.3f %.3f %.3f %.2f %.2f %.2f\n", SLOTS[e.k].piece, e.pos[1], e.pos[2], e.pos[3],
      math.deg(e.yaw), math.deg(e.pitch), math.deg(e.roll)))
  end
  f:close()
  return true
end

local function load_build(ctx, n)
  local f = io.open(build_file(n), "r")
  if not f then return nil end
  clear_build(ctx)
  local count = 0
  for line in f:lines() do
    local key, x, y, z, yaw, pitch, roll = line:match("^([%w_]+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+)")
    local k = key and PIECE[key] and free_slot(key)
    if k and held and k == held.k then k = nil end
    if k and set_kind(ctx, SLOTS[k], key) then
      local e = { k = k, pos = { tonumber(x), tonumber(y), tonumber(z) }, yaw = math.rad(tonumber(yaw)),
        pitch = math.rad(tonumber(pitch)), roll = math.rad(tonumber(roll)) }
      if place_slot(ctx, SLOTS[k], e.pos, e.yaw, e.pitch, e.roll) then
        SLOTS[k].used = true
        placed[#placed + 1] = e
        count = count + 1
      end
    end
  end
  f:close()
  log("loaded build %d: %d pieces", n, count)
  return count
end

-- One action from the pad, the keyboard or the menu, run in the game update.
local ACT = {}
function ACT.turn(ctx, d) if held then held.yaw = held.yaw + TURN * d; if held.fixed then held.fixed.yaw = held.fixed.yaw + TURN * d end end end
function ACT.raise(ctx, d)
  if not held then return end
  if held.fixed then held.fixed.pos[2] = held.fixed.pos[2] + RAISE * d else held.up = held.up + RAISE * d end
end
function ACT.tilt(ctx, d) if held then held.pitch = math.max(-math.rad(60), math.min(math.rad(60), held.pitch + TILT * d)) end end
function ACT.flip(ctx) if held then held.roll = (held.roll + ROLL) % (2 * math.pi) end end
function ACT.reach(ctx, d)
  if not held then return end
  if held.fixed then
    local r = rows(held.fixed.yaw, 0, 0)
    held.fixed.pos[1], held.fixed.pos[3] = held.fixed.pos[1] + r[7] * d, held.fixed.pos[3] + r[9] * d
  else
    held.reach = math.max(REACH_MIN, math.min(REACH_MAX, held.reach + d))
  end
end
local function choose(ctx, key)
  if not held then return end
  if set_kind(ctx, SLOTS[held.k], key) then say(PIECE[key].label) end
end
function ACT.piece(ctx, d)
  if not held then return end
  local at = INDEX[SLOTS[held.k].piece] or 1
  choose(ctx, ORDER[((at - 1 + d) % #ORDER) + 1])
end
function ACT.kind(ctx, t) if ORDER[t] then choose(ctx, ORDER[t]) end end
function ACT.place(ctx)
  if not held then return end
  local pos, yaw = held_pose()
  if not pos then return end
  placed[#placed + 1] = { k = held.k, pos = pos, yaw = yaw, pitch = held.pitch, roll = held.roll }
  place_slot(ctx, SLOTS[held.k], pos, yaw, held.pitch, held.roll)
  local key = SLOTS[held.k].piece
  local keep = { yaw = held.yaw, pitch = held.pitch, roll = held.roll, reach = held.reach, up = held.up }
  held = take_slot(ctx, key, keep)
  say(string.format("Placed %s (%d of %d)", PIECE[key].label, #placed, #SLOTS) ..
    (held and "" or ": that was the last piece"))
end
function ACT.undo(ctx)
  local e = table.remove(placed)
  if not e then say("Nothing to undo") return end
  park(ctx, e.k)
  SLOTS[e.k].used = false
  say("Removed " .. PIECE[SLOTS[e.k].piece].label)
  if not held and creator then held = take_slot(ctx, SLOTS[e.k].piece) end
end
function ACT.pickup(ctx)
  local me = player()
  if not me then return end
  local i = nearest_placed(held and held_pose() or me)
  if not i then say("Nothing placed yet") return end
  local e = table.remove(placed, i)
  if held then park(ctx, held.k); SLOTS[held.k].used = false end
  local pos, heading = player()
  local dx, dz = e.pos[1] - pos[1], e.pos[3] - pos[3]
  held = { k = e.k, yaw = e.yaw - heading, pitch = e.pitch, roll = e.roll, reach = math.max(REACH_MIN, math.sqrt(dx * dx + dz * dz)),
    up = e.pos[2] - pos[2], fixed = { pos = e.pos, yaw = e.yaw } }
  say("Picked up " .. PIECE[SLOTS[e.k].piece].label .. ": move it, then place it again (LB + A). LB + RB carries it")
end
function ACT.snap(ctx)
  if not held then return end
  if held.fixed then
    local pos, heading = player()
    if pos then
      held.yaw = held.fixed.yaw - heading
      local dx, dz = held.fixed.pos[1] - pos[1], held.fixed.pos[3] - pos[3]
      held.reach, held.up = math.max(REACH_MIN, math.sqrt(dx * dx + dz * dz)), held.fixed.pos[2] - pos[2]
    end
    held.fixed = nil
    say("Carrying it again")
    return
  end
  local last = placed[#placed]
  if not last then say("Place a piece first, then the next one snaps on to it") return end
  local a, b = PIECE[SLOTS[last.k].piece], PIECE[SLOTS[held.k].piece]
  local r = rows(last.yaw, last.pitch, last.roll)
  local fwd = a.l / 2 + b.l / 2
  -- after a ramp, the next ramp starts on its top edge and anything flat sits flush with it
  local up = 0
  if RISES[SLOTS[last.k].piece] then up = a.front_h - (RISES[SLOTS[held.k].piece] and 0 or b.h) end
  local pos = { last.pos[1] + r[7] * fwd + r[4] * up, last.pos[2] + r[8] * fwd + r[5] * up, last.pos[3] + r[9] * fwd + r[6] * up }
  held.pitch, held.roll = last.pitch, last.roll
  held.fixed = { pos = pos, yaw = last.yaw }
  say("Snapped on to the last piece: LB + A places it")
end
function ACT.move(ctx)
  if moving then
    moving = nil
    for _, e in ipairs(placed) do place_slot(ctx, SLOTS[e.k], e.pos, e.yaw, e.pitch, e.roll) end
    say("Build put down")
    return
  end
  local pos, heading = player()
  if not pos or #placed == 0 then say("Nothing placed yet") return end
  moving = { heading = heading, items = {} }
  local c, s = math.cos(-heading), math.sin(-heading)
  for i, e in ipairs(placed) do
    local dx, dz = e.pos[1] - pos[1], e.pos[3] - pos[3]
    moving.items[i] = { x = dx * c + dz * s, y = e.pos[2] - pos[2], z = -dx * s + dz * c, yaw = e.yaw - heading }
  end
  say("Moving the whole build (it's see-through until you put it down): walk and turn, then LB + R3 puts it down")
end
local clear_armed = 0
function ACT.clear(ctx, sure)
  if sure ~= 1 and now() > clear_armed then clear_armed = now() + 3; say("Press again to clear the whole build") return end
  clear_build(ctx)
  say("Build cleared")
end
function ACT.save(ctx, n)
  if #placed == 0 then say("Place something first: an empty build isn't saved") return end
  say(save_build(n) and string.format("Saved as build %d (%d pieces)", n, #placed) or "Couldn't save")
end
function ACT.load(ctx, n)
  local count = load_build(ctx, n)
  say(count and string.format("Loaded build %d (%d pieces)", n, count) or string.format("There's no build %d saved", n))
end
function ACT.camera(ctx, v)
  if not creator then return end
  local on = (v == nil and not cam) or v == 1
  if on then cam_enter(ctx) else cam_exit(ctx); say("Build camera off") end
end
function ACT.grid(ctx, v)
  if v == nil then grid = not grid else grid = v == 1 end
  say(grid and "Grid snap on: whole metres and 15 degree turns" or "Grid snap off")
end
function ACT.toggle(ctx) log("creator %s (key or pad)", creator and "off" or "on"); set_creator(ctx, not creator) end
function ACT.on(ctx, v)
  log("menu asks for creator %s (it is %s)", v == 1 and "on" or "off", creator and "on" or "off")
  if (v == 1) ~= creator then set_creator(ctx, v == 1) end
end

local queue = {}
local function want(name, arg) queue[#queue + 1] = { name, arg } end

-- ------------------------------------------------------------ the HUD text
local last_text, menu_was_open = nil, false
local function show(text)
  if wml.read_u32(MAILBOX) ~= MAGIC then return end
  if menu_open() then menu_was_open = true return end
  if menu_was_open then menu_was_open, last_text = false, nil end
  if text == last_text then return end
  last_text = text
  local base, n = MAILBOX + 0x40, math.min(#text, 8000)
  for i = 1, n do wml.write_u8(base + i - 1, text:byte(i)) end
  wml.write_u32(MAILBOX + 0x14, n)
  wml.write_u32(MAILBOX + 0x10, ((wml.read_u32(MAILBOX + 0x10) or 0) + 1) & 0xFFFFFFFF)
end

local function hud()
  if not creator then
    if last_text and last_text ~= "" then show("") end
    return
  end
  local lines = {}
  if held then
    local key = SLOTS[held.k].piece
    lines[1] = string.format("CREATOR   %s  (kind %d of %d)   placed %d of %d%s%s", PIECE[key].label, INDEX[key], #ORDER,
      #placed, #SLOTS, held.fixed and "   [holding still]" or "", moving and "   [MOVING THE BUILD]" or "")
    lines[2] = string.format("turn %.0f   tilt %.0f   flip %.0f   height %.2f m   distance %.0f m", math.deg(held.yaw) % 360,
      math.deg(held.pitch), math.deg(held.roll), held.fixed and 0 or held.up, held.reach)
  else
    lines[1] = string.format("CREATOR   every piece is placed (%d)%s", #placed, moving and "   [MOVING THE BUILD]" or "")
  end
  lines[#lines + 1] = (cam and "BUILD CAMERA: WASD / left stick fly, E Q / RT LT up / down, Shift faster   Back: player view"
    or "Back: build camera (fly it and place where you look)") .. (grid and "   [GRID SNAP]" or "")
  lines[#lines + 1] = "D-pad: turn / raise          LB + D-pad: change piece / tilt          LB + L3: grid snap"
  lines[#lines + 1] = "LB + A place   LB + B undo   LB + X pick up nearest   LB + Y flip"
  lines[#lines + 1] = "LB + RB snap to last piece (again: carry it)   LB + RT / LT farther / closer"
  lines[#lines + 1] = "LB + R3 move the whole build   LB + Start twice: clear   LB + Back: leave creator"
  lines[#lines + 1] = "Keys: F7 on/off, F6 camera, G grid, arrows, PgUp/PgDn piece, Home/End tilt, Enter, Backspace, Insert, Delete flip, +/- distance, F9 snap, F10 move, F11 clear"
  if now() < message_until then lines[#lines + 1] = "> " .. message end
  show(table.concat(lines, "\n"))
end

-- ------------------------------------------------------------ the menu's mailbox
local MENU_ACT = { "on", "kind", "place", "undo", "snap", "move", "clear", "save", "load", "flip", "pickup", "camera", "grid" }
local box_seen = nil
local function mailbox()
  if wml.read_u32(BOX) ~= BOX_MAGIC then
    wml.write_u32(BOX, BOX_MAGIC)
    box_seen = wml.read_u32(BOX + 4) or 0
  end
  local seq = wml.read_u32(BOX + 4) or 0
  if box_seen == nil then box_seen = seq end
  if seq ~= box_seen then
    box_seen = seq
    local name = MENU_ACT[wml.read_u32(BOX + 8) or 0]
    if name then want(name, wml.read_u32(BOX + 12) or 0) end
    wml.write_u32(BOX + 36, seq)
  end
  wml.write_u32(BOX + 16, (creator and 1 or 0) | (moving and 2 or 0) | (SHAPE[#ORDER] and 4 or 0) | (cam and 8 or 0)
    | (grid and 16 or 0))
  wml.write_u32(BOX + 20, #placed)
  wml.write_u32(BOX + 24, held and INDEX[SLOTS[held.k].piece] or 0)
  wml.write_u32(BOX + 28, #SLOTS)
  wml.write_u32(BOX + 32, #ORDER)
end

-- ------------------------------------------------------------ input
local repeat_at = {}
local function held_repeat(id, down)
  local t = now()
  if not down then repeat_at[id] = nil return false end
  if not repeat_at[id] then repeat_at[id] = t + 0.35 return true end
  if t >= repeat_at[id] then repeat_at[id] = t + 0.08 return true end
  return false
end

local KEY_ACT = {
  { "LEFT", "turn", -1, true }, { "RIGHT", "turn", 1, true }, { "UP", "raise", 1, true }, { "DOWN", "raise", -1, true },
  { "PAGEUP", "piece", -1, true }, { "PAGEDOWN", "piece", 1, true }, { "HOME", "tilt", 1, true }, { "END", "tilt", -1, true },
  { "ENTER", "place" }, { "BACKSPACE", "undo" }, { "INSERT", "pickup" }, { "DELETE", "flip" },
  { "PLUS", "reach", REACH_SPEED, true }, { "MINUS", "reach", -REACH_SPEED, true },
  { "F9", "snap" }, { "F10", "move" }, { "F11", "clear" }, { "F6", "camera" }, { "G", "grid" },
}
wml.on_frame(function()
  if wml.key_pressed("F7") then want("toggle") end
  take_keys(creator)
  if not creator or menu_open() then return end
  for _, k in ipairs(KEY_ACT) do
    local hit = k[4] and held_repeat("k" .. k[1], wml.key_down(k[1])) or (not k[4] and wml.key_pressed(k[1]))
    if hit then want(k[2], k[3]) end
  end
end)

-- The controller. Creator on: the D-pad is ours, and while LB is held so are
-- the face buttons, RB, Back, the stick clicks and the triggers (LB itself is
-- hidden too). RB without LB is left alone so the tweak menu still opens.
local pad_prev = 0
wml.hook(PAD_READ, function(ctx)
  local user, state = ctx:r(3) & 0xFF, ctx:r(5)
  ctx:call_original()
  if user ~= 0 or state == 0 or (ctx:r(3) & 0xFFFFFFFF) ~= 0 then return end
  local b = wml.read_u16(state + 4) or 0
  local lt, rt = wml.read_u8(state + 6) or 0, wml.read_u8(state + 7) or 0
  local function s16(v) v = v or 0 return v >= 0x8000 and v - 0x10000 or v end
  pad_raw.buttons, pad_raw.lt, pad_raw.rt = b, lt, rt
  pad_raw.lx, pad_raw.ly = s16(wml.read_u16(state + 8)), s16(wml.read_u16(state + 10))
  local lb = b & PAD.LB ~= 0
  local press = b & ~pad_prev
  pad_prev = b
  if menu_open() then return end
  if not creator then
    if lb and press & PAD.BACK ~= 0 then want("toggle") end
    if lb and b & PAD.BACK ~= 0 then wml.write_u16(state + 4, b & ~PAD.BACK) end
    return
  end
  if b & PAD.RB ~= 0 and not lb then return end
  if lb then
    if held_repeat("piece-", b & PAD.LEFT ~= 0) then want("piece", -1) end
    if held_repeat("piece+", b & PAD.RIGHT ~= 0) then want("piece", 1) end
    if held_repeat("tilt+", b & PAD.UP ~= 0) then want("tilt", 1) end
    if held_repeat("tilt-", b & PAD.DOWN ~= 0) then want("tilt", -1) end
    if press & PAD.A ~= 0 then want("place") end
    if press & PAD.B ~= 0 then want("undo") end
    if press & PAD.X ~= 0 then want("pickup") end
    if press & PAD.Y ~= 0 then want("flip") end
    if press & PAD.RB ~= 0 then want("snap") end
    if press & PAD.RS ~= 0 then want("move") end
    if press & PAD.LS ~= 0 then want("grid") end
    if press & PAD.START ~= 0 then want("clear") end
    if press & PAD.BACK ~= 0 then want("toggle") end
    if rt > 60 and held_repeat("far", true) then want("reach", REACH_SPEED) elseif rt <= 60 then held_repeat("far", false) end
    if lt > 60 and held_repeat("near", true) then want("reach", -REACH_SPEED) elseif lt <= 60 then held_repeat("near", false) end
    wml.write_u16(state + 4, b & ~(DPAD | FACE | PAD.LB | PAD.START))
    wml.write_u8(state + 6, 0)
    wml.write_u8(state + 7, 0)
  else
    for _, d in ipairs({ { PAD.LEFT, "turn", -1 }, { PAD.RIGHT, "turn", 1 }, { PAD.UP, "raise", 1 }, { PAD.DOWN, "raise", -1 } }) do
      if held_repeat("d" .. d[1], b & d[1] ~= 0) then want(d[2], d[3]) end
    end
    if press & PAD.BACK ~= 0 then want("camera") end
    if b & (DPAD | PAD.BACK) ~= 0 then wml.write_u16(state + 4, b & ~(DPAD | PAD.BACK)) end
  end
  -- The build camera flies on the sticks and triggers: the game sees no pad,
  -- so your character stands still.
  if cam then
    wml.write_u16(state + 4, 0)
    wml.write_u8(state + 6, 0); wml.write_u8(state + 7, 0)
    for i = 8, 14, 2 do wml.write_u16(state + i, 0) end
  end
  if (wml.read_u16(state + 4) or 0) ~= b then
    wml.write_u32(state, ((wml.read_u32(state) or 0) + 1) & 0xFFFFFFFF)
  end
end)

-- ------------------------------------------------------------ the update
local ready, checked_at, looked_at, missing_logged = false, 0, 0, false
local function learn_kinds()
  for t, s in ipairs(SLOTS) do
    local inst = wml.read_u32(s.rec + 60) or 0
    SHAPE[t] = wml.read_u16(s.rec + 56)
    MESH[t] = ok(inst) and wml.read_u32(inst + 104) or nil
    if not (SHAPE[t] and SHAPE[t] ~= 0xFFFF and ok(MESH[t])) then
      log("slot %d has no shape or mesh to learn (%s, %s)", t, tostring(SHAPE[t]), tostring(MESH[t]))
      SHAPE[t], MESH[t] = nil, nil
    end
  end
end

wml.hook(UPDATE, function(ctx)
  if cam and wml.read_u32(CAM) == CAM_FREE then
    local sv = cam.saved
    put_pose(sv.pos, sv.r, sv.u, sv.f)
  end
  ctx:call_original()
  mailbox()
  if not player() then return end
  if not ready then
    if now() < looked_at then return end
    looked_at = now() + 2
    local found = find_records()
    if found < #SLOTS then
      if not missing_logged then log("the creator pieces aren't in the loaded chunk (found %d of %d)", found, #SLOTS) end
      missing_logged = true
      return
    end
    ready = true
    learn_kinds()
    log("found all %d creator pieces; %d kinds", #SLOTS, #ORDER)
  end
  for _, q in ipairs(queue) do
    local ok_, err = pcall(ACT[q[1]], ctx, q[2])
    if not ok_ then log("%s failed: %s", q[1], tostring(err)) end
  end
  queue = {}
  if moving then
    local pos, heading = player()
    local c, s = math.cos(heading), math.sin(heading)
    for i, e in ipairs(placed) do
      local m = moving.items[i]
      if m then
        e.pos = { pos[1] + m.x * c + m.z * s, pos[2] + m.y, pos[3] - m.x * s + m.z * c }
        e.yaw = heading + m.yaw
        place_slot(ctx, SLOTS[e.k], e.pos, e.yaw, e.pitch, e.roll, true)
      end
    end
  end
  if cam then
    if wml.read_u32(CAM) ~= CAM_FREE then cam = nil; say("The game took the camera back")
    else cam_fly(menu_open(), pad_raw.buttons & PAD.LB ~= 0) end
  end
  if held then
    local pos, yaw = held_pose()
    if pos then place_slot(ctx, SLOTS[held.k], pos, yaw, held.pitch, held.roll, true) end
  end
  -- The game can drop the objects (a reload, a cutscene): every 2 s, put back any that went.
  if now() > checked_at then
    checked_at = now() + 2
    for _, e in ipairs(placed) do
      local s = SLOTS[e.k]
      if s.rec ~= 0 and (wml.read_u32(s.rec + 12) or 0) ~= s.mover then
        place_slot(ctx, s, e.pos, e.yaw, e.pitch, e.roll, moving ~= nil)
      end
    end
  end
  hud()
end)

log("ready: %d pieces, %d kinds. F7 or LB + Back turns the creator on; builds last until the game closes", #SLOTS, #ORDER)
