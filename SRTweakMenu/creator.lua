-- SR Tweak Menu - the Creator tab: drives the SR Creator mod (its own folder
-- next to this one, with the pieces it builds into the always-loaded chunk).
-- The two talk through a mailbox in guest memory: SR Creator writes 'SRCR'
-- and its state there, and this writes a command and bumps a count.
--
--   +0 'SRCR'   +4 command count   +8 command   +12 argument
--   +16 state bits (1 creator on, 2 moving the build, 4 pieces found, 8 build camera, 16 grid snap)
--   +20 pieces placed   +24 the held piece's kind (1-based)   +28 slots   +32 kinds
--
-- Commands: 1 creator on (argument 1) / off (0), 2 piece kind, 3 place, 4 undo,
-- 5 snap, 6 move the whole build, 7 clear, 8 save to build N, 9 load build N,
-- 10 flip, 11 pick up the nearest piece, 12 build camera on (1) / off (0),
-- 13 grid snap on (1) / off (0).

local C = {}
local BOX, MAGIC = 0x00F08000, 0x53524352
local read_u32, write_u32 = wml.read_u32, wml.write_u32

-- The pieces' names, from SR Creator's pieces.lua (its build script writes it).
local function piece_names()
  local f = io.open(wml.mod_folder .. "/../SRCreator/pieces.lua", "r")
  if not f then return nil end
  local chunk = load(f:read("a"))
  f:close()
  local ok, P = pcall(chunk or function() end)
  if not ok or type(P) ~= "table" or type(P.pieces) ~= "table" then return nil end
  local names = {}
  for i, p in ipairs(P.pieces) do names[i] = p.label end
  return #names > 0 and names or nil
end
local NAMES = piece_names()

function C.running() return read_u32(BOX) == MAGIC end
local function state() return C.running() and (read_u32(BOX + 16) or 0) or 0 end
function C.on() return state() & 1 ~= 0 end
local pending_until, mode_row, piece_row, cam_row, grid_row = 0, nil, nil, nil, nil
local function send(command, arg)
  if command == 1 or command == 2 or command == 12 or command == 13 then pending_until = os.clock() + 1.5 end
  write_u32(BOX + 8, command)
  write_u32(BOX + 12, arg or 0)
  write_u32(BOX + 4, ((read_u32(BOX + 4) or 0) + 1) & 0xFFFFFFFF)
end

local function needs_on()
  if not C.running() then return "SR Creator isn't running: tick it in the mod loader" end
  if not C.on() then return "Turn Creator mode on first" end
end
local function command(n, arg, said)
  return function()
    local why = needs_on()
    if why then return why end
    send(n, arg)
    return said
  end
end
-- The menu asks every row whether it's hidden while it draws them, so this is
-- where Creator mode's tick and the Piece row follow SR Creator (F7, LB + Back
-- and the D-pad change them too);
-- not just after the menu sent a switch, while SR Creator hasn't seen it yet.
local function sync()
  if not (mode_row and C.running()) or os.clock() <= pending_until then return end
  local st = state()
  mode_row.v = st & 1 ~= 0
  cam_row.v, grid_row.v = st & 8 ~= 0, st & 16 ~= 0
  local kind = read_u32(BOX + 24) or 0
  if kind > 0 and piece_row.options[kind] then piece_row.v = kind end
end
local hide_off = function() sync() return not C.on() end

function C.rows(S)
  local rows = {
    { id = "creator_mode", label = "Creator mode", kind = "toggle", needs = "player", nosave = true,
      help = "Build stunt parks from 26 kinds of piece; the controls show on screen (F7 or LB + Back). Builds clear "
        .. "when the game closes: save one below to keep it. Needs the SR Creator mod.",
      change = function(ctx, p, v, it)
        if not C.running() then it.v = false return "SR Creator isn't running: tick it in the mod loader" end
        send(1, it.v and 1 or 0)
        return it.v and "Creator on" or "Creator off"
      end,
      hidden = function() sync() return false end },
    { id = "creator_camera", label = "Build camera", kind = "toggle", needs = "player", nosave = true, hidden = hide_off,
      help = "Fly a camera of its own and place the piece where you look: WASD / left stick, E Q / RT LT up and down, "
        .. "Shift faster. Your character waits where they are. Back on the pad, or F6, switches it.",
      change = function(ctx, p, v, it)
        local why = needs_on()
        if why then it.v = false return why end
        send(12, it.v and 1 or 0)
        return it.v and "Build camera on: close the menu to fly" or "Build camera off"
      end },
    { id = "creator_grid", label = "Grid snap", kind = "toggle", needs = "none", nosave = true, hidden = hide_off,
      help = "Puts pieces on whole metres (half metres up and down) and turns them in 15 degree steps, so they line up. "
        .. "LB + L3 or G switches it.",
      change = function(ctx, p, v, it)
        local why = needs_on()
        if why then it.v = false return why end
        send(13, it.v and 1 or 0)
      end },
    { id = "creator_piece", label = "Piece", kind = "choice", needs = "none", nosave = true,
      options = NAMES or { "(SR Creator's pieces.lua is missing)" }, hidden = hide_off,
      help = "The kind of piece you're holding: ramps, curves, a half pipe, platforms, bridges, blocks, towers, walls, a "
        .. "drum and stairs. LB + D-pad Left / Right picks too.",
      change = function(ctx, p, v, it)
        local why = needs_on()
        if why then return why end
        send(2, it.v)
      end },
    { id = "creator_place", label = "Place piece", kind = "action", hidden = hide_off,
      help = "Puts the piece down where it is and gives you the next one (LB + A).", run = command(3, 0, "Placed") },
    { id = "creator_snap", label = "Snap to last piece", kind = "action", hidden = hide_off,
      help = "Lines the piece up on the end of the last one you placed; after a ramp, the next ramp starts on its top edge "
        .. "and flat pieces sit flush with it. Snap again to carry it (LB + RB).", run = command(5, 0, "Snapped") },
    { id = "creator_flip", label = "Flip piece", kind = "action", hidden = hide_off,
      help = "Rolls the piece 90 degrees onto its side (LB + Y).", run = command(10, 0, "Flipped") },
    { id = "creator_pickup", label = "Pick up nearest", kind = "action", hidden = hide_off,
      help = "Takes back the placed piece nearest the one you're holding, to move it (LB + X).", run = command(11, 0, "Picked up") },
    { id = "creator_undo", label = "Undo last piece", kind = "action", hidden = hide_off,
      help = "Removes the last piece you placed (LB + B).", run = command(4, 0, "Removed the last piece") },
    { id = "creator_move", label = "Move whole build", kind = "action", hidden = hide_off,
      help = "Picks up everything you've placed so it moves and turns with you; press again to put it down (LB + R3).",
      run = function()
        local why = needs_on()
        if why then return why end
        local moving = state() & 2 ~= 0
        send(6, 0)
        return moving and "Build put down" or "Carrying the whole build: walk, then press again"
      end },
    { id = "creator_clear", label = "Clear build", kind = "action", hidden = hide_off,
      help = "Removes every placed piece.", run = command(7, 1, "Build cleared") },
    { id = "creator_slot", label = "Build slot", kind = "value", needs = "none", default = 1, min = 1, max = 5, step = 1,
      wrap = true, fmt = function(v) return string.format("%d", v) end, v = S("creator_build_slot", 1),
      help = "Which of the 5 saved builds Save and Load use.", },
    { id = "creator_save", label = "Save build", kind = "action",
      help = "Saves everything placed now as the chosen build slot (build_N.txt in SR Creator's folder).",
      run = function(ctx, p, _, it)
        if not C.running() then return "SR Creator isn't running: tick it in the mod loader" end
        local n = C.slot()
        send(8, n)
        return string.format("Saving build %d", n)
      end },
    { id = "creator_load", label = "Load build", kind = "action",
      help = "Clears what's placed and puts the chosen saved build back where it was built.",
      run = function()
        if not C.running() then return "SR Creator isn't running: tick it in the mod loader" end
        local n = C.slot()
        send(9, n)
        return string.format("Loading build %d", n)
      end },
  }
  mode_row, cam_row, grid_row, piece_row = rows[1], rows[2], rows[3], rows[4]
  return rows
end

C.slot = function() return 1 end
function C.attach(F) C.slot = function() return F.items.creator_slot and F.items.creator_slot.v or 1 end end
C.send = send

return C
