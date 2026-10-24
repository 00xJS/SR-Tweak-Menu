-- By itsMJQ (SR Tweak Menu 1.1 to 1.9.11).
-- SR Tweak Menu - drawing with the game's own interface.
--
-- The game draws its HUD and menus in one 2D pass (0x82200700: the HUD,
-- then its debug text). Hooked here, after that pass, the menu draws on top
-- with the same pieces the pause menu uses: its fonts (px_thin for lists,
-- px_giantvar for headings), the pictures on the HUD sheets (the gold
-- selection bar, the dark menu box, the fleur-de-lis ornaments, the scroll
-- bar, the A / B / LB / RB buttons), and its sounds (SYS_MENU_SCROLL ...).
--
-- menu.lua builds a list of things to draw each update (UI.frame); every
-- frame the pass draws the latest list. Positions are in 1280 x 720 units,
-- placed on screen the way the HUD places its own (the HUD's scale and
-- offset at 0x82FFB4E8..F4).
--
-- Text: 0x8264EAA8(r5 UTF-16 text, f1 x, f2 y, f3 size, r7 font, r8 clip),
-- in the colour 0x8263E7D8(r, g, b, a) set last; 0x8264EF48(&w, &h, text,
-- -1, font) measures. Fonts are numbers the game keeps at 0x827D6D10.. once
-- loaded (0x82184068), records at 0x832B61D0 (+20 line height).
-- Pictures: the HUD picture table (0x82FF5EC8, 20 bytes: sheet, x, y, w, h)
-- gives the sheet and rectangle; the sheet's texture (0x82FFAEC8 + 8 * sheet,
-- +4) and its size (texture records at *0x832B6024, 20 bytes, +4 -> +4/+6)
-- give the corners. Drawn the way 0x8227E720 does it: texture
-- (0x8263E960), clip (0x82641370), a quad from 0x82641418(4, 0) - four
-- vertices of 28 bytes: x, y at +0, colour (A R G B, 128 = as painted) at
-- +16, u, v at +20 - then 0x826414E8.

local G = require("game")
local UI = { frame = nil, overlay = nil, ok = true }

local read_u8, read_u16, read_u32, read_f32 = wml.read_u8, wml.read_u16, wml.read_u32, wml.read_f32
local write_u32, write_f32 = wml.write_u32, wml.write_f32

local PASS_2D = 0x82200700
local TEXT, MEASURE, COLOR = 0x8264EAA8, 0x8264EF48, 0x8263E7D8
local CLIP = 0x82839AA0
local FONT_SLOT = { thin = 0x827D6D1C, thin_outline = 0x827D6D20, giant = 0x827D6D14, giant_outline = 0x827D6D10, giant2 = 0x827D6D18 }
local FONTS = 0x832B61D0
local BMP_INFO, BMP_COUNT = 0x82FF5EC8, 0x8370DD60
local SHEETS = 0x82FFAEC8
local TEX_TABLE, TEX_COUNT = 0x832B6024, 0x832B61CC
local SET_TEXTURE, PRIM_CLIP, PRIM_BEGIN, PRIM_END = 0x8263E960, 0x82641370, 0x82641418, 0x826414E8
local SCALE_X, SCALE_Y, OFFSET_X, OFFSET_Y = 0x82FFB4E8, 0x82FFB4EC, 0x82FFB4F0, 0x82FFB4F4
local BITMAP_FIND, BITMAP_TABLE = 0x82643430, 0x82816484
-- Where the pause menu keeps the ids it looked up for its sounds.
UI.SOUND = { scroll = 0x827B05B0, lr = 0x827B05B4, select = 0x827B05B8, back = 0x827B05BC, okay = 0x827B05C0,
             yes = 0x827B05C4, no = 0x827B05C8, purchase = 0x827B05CC, resume = 0x827B05D0, quit = 0x827B05D4,
             pause = 0x827B05D8, unpause = 0x827B05DC }
local PLAY_SOUND = 0x82287FC0

local function s32(v) return v >= 0x80000000 and v - 0x100000000 or v end

-- Screen placement of the 1280 x 720 layout: the HUD's scale, from the top
-- left corner (the two words after the scale aren't a top-left offset: with
-- them the menu sat at the bottom of the screen). Logged once to check.
local logged_screen = false
local function screen()
  local sx, sy = read_f32(SCALE_X), read_f32(SCALE_Y)
  local s = math.max(sx, sy)
  if not (s > 0.1 and s < 20) then s = 1 end
  if not logged_screen then
    logged_screen = true
    wml.log(string.format("menu (game look): HUD scale %.3f x %.3f, words after it %d, %d", sx, sy, s32(read_u32(OFFSET_X)), s32(read_u32(OFFSET_Y))))
  end
  return s, 0, 0
end

-- Pictures by name, once the HUD has them.
local bitmaps = {}
function UI.bitmap(ctx, name)
  local h = bitmaps[name]
  if h == nil then
    h = G.call(ctx, BITMAP_FIND, { BITMAP_TABLE, G.cstr(ctx, name, 0) }) & 0xFFFF
    if h == 0xFFFF or h >= read_u32(BMP_COUNT) then return nil end
    bitmaps[name] = h
  end
  return h
end

local function font(name)
  local f = read_u32(FONT_SLOT[name] or FONT_SLOT.thin)
  if f >= 0x80000000 or f > 64 then return nil end
  return f
end
function UI.line_height(name)
  local f = font(name)
  local rec = f and read_u32(FONTS + f * 4)
  if not rec or not G.pointer_ok(rec) then return 20 end
  local h = read_u16(rec + 20)
  return (h > 0 and h < 200) and h or 20
end

-- Widths of strings in a font (unscaled), remembered.
local widths = {}
function UI.width(ctx, name, s)
  local key = name .. "\0" .. s
  local w = widths[key]
  if w then return w end
  local f = font(name)
  if not f or not ctx then return #s * 9 end
  local out = G.buffer(ctx, 0)
  G.call(ctx, MEASURE, { out, out + 4, G.wstr(ctx, s), 0xFFFFFFFF, f })
  w = read_u32(out)
  if w > 4000 then w = #s * 9 end
  widths[key] = w
  return w
end

local function set_colour(ctx, c)
  G.call(ctx, COLOR, { c[1], c[2], c[3], c[4] or 255 })
end

local function draw_text(ctx, op, s, ox, oy)
  local f = font(op.font)
  if not f or op.text == "" then return end
  set_colour(ctx, op.colour)
  G.call(ctx, TEXT, { 0, 0, G.wstr(ctx, op.text), 0, f, CLIP }, { ox + op.x * s, oy + op.y * s, op.size * s })
end

-- A picture (or part of one) stretched over a rectangle, optionally flipped.
local function draw_quad(ctx, op, s, ox, oy)
  local h = UI.bitmap(ctx, op.image)
  if not h then return end
  local e = BMP_INFO + h * 20
  local sheet = read_u32(e)
  if sheet > 64 then return end
  local tex = read_u32(SHEETS + sheet * 8 + 4)
  if tex >= read_u32(TEX_COUNT) then return end
  local rec = read_u32(read_u32(TEX_TABLE) + tex * 20 + 4)
  if not G.pointer_ok(rec) then return end
  local tw, th = read_u16(rec + 4), read_u16(rec + 6)
  if tw == 0 or th == 0 then return end
  local bx, by, bw, bh = read_u32(e + 4), read_u32(e + 8), read_u32(e + 12), read_u32(e + 16)
  -- A part of the picture (op.part = { x, y, w, h } in its pixels).
  if op.part then bx, by, bw, bh = bx + op.part[1], by + op.part[2], op.part[3], op.part[4] end
  local u0, v0, u1, v1 = bx / tw, by / th, (bx + bw) / tw, (by + bh) / th
  if op.flip_v then v0, v1 = v1, v0 end
  if op.flip_h then u0, u1 = u1, u0 end
  local x0, y0 = ox + op.x * s, oy + op.y * s
  local x1, y1 = x0 + op.w * s, y0 + op.h * s
  local c = op.colour or { 128, 128, 128, 255 }
  local function argb_of(k) return ((k[4] or 255) << 24) | (k[1] << 16) | (k[2] << 8) | k[3] end
  local argb = argb_of(c)
  -- (op.colours: one per corner - top left, top right, bottom left, bottom
  -- right - for a gradient across the quad)
  local per = op.colours
  G.call(ctx, SET_TEXTURE, { tex })
  G.call(ctx, PRIM_CLIP, { CLIP })
  local vb = G.call(ctx, PRIM_BEGIN, { 4, 0 })
  if vb == 0 or not G.pointer_ok(vb) then return end
  local corners = { { x0, y0, u0, v0 }, { x1, y0, u1, v0 }, { x0, y1, u0, v1 }, { x1, y1, u1, v1 } }
  for i, v in ipairs(corners) do
    local a = vb + (i - 1) * 28
    write_f32(a, v[1]); write_f32(a + 4, v[2])
    write_u32(a + 16, per and argb_of(per[i]) or argb)
    write_f32(a + 20, v[3]); write_f32(a + 24, v[4])
  end
  G.call(ctx, PRIM_END, {})
end

-- The game's 2D pass, then the menu's picture list.
local failures = 0
G.hook(PASS_2D, function(ctx)
  -- The screen effects (low health, low sprint) first, so the game's HUD,
  -- its notices and subtitles are drawn over them; the menu last, on top.
  local ov = UI.overlay
  if ov and UI.ok then
    local ok, err = pcall(function()
      local s, ox, oy = screen()
      for _, op in ipairs(ov) do draw_quad(ctx, op, s, ox, oy) end
    end)
    if not ok then wml.log("screen effects: drawing failed: " .. tostring(err)); UI.overlay = nil end
  end
  ctx:call_original()
  local fr = UI.frame
  if not fr or not UI.ok then return end
  local ok, err = pcall(function()
    local s, ox, oy = screen()
    for _, op in ipairs(fr) do
      if op.text then draw_text(ctx, op, s, ox, oy) else draw_quad(ctx, op, s, ox, oy) end
    end
  end)
  if not ok then
    failures = failures + 1
    wml.log("menu (game look): drawing failed: " .. tostring(err))
    if failures >= 3 then UI.ok = false; wml.log("menu (game look): off after three failures; plain text menu instead") end
  end
end)

-- The pause menu's sounds, by name (SYS_MENU_SCROLL ...): the game hashes
-- the name (0x82637C18) and finds it in its sound list (pointers at
-- 0x8291EB78, each to a record starting with the hash; how many at
-- 0x8370CFD4); its position there is what 0x82287FC0 plays.
local HASH, SOUND_LIST, SOUND_COUNT = 0x82637C18, 0x8291EB78, 0x8370CFD4
local sound_ids = {}
function UI.sound_id(ctx, name)
  local id = sound_ids[name]
  if id ~= nil then return id end
  local hash = G.call(ctx, HASH, { G.cstr(ctx, name, 0), 0 })
  local n = math.min(read_u32(SOUND_COUNT), 20000)
  id = false
  for i = 0, n - 1 do
    local rec = read_u32(SOUND_LIST + i * 4)
    if rec ~= 0 and read_u32(rec) == hash then id = i break end
  end
  if n > 0 then sound_ids[name] = id end
  return id
end
local NAMES = { scroll = "SYS_MENU_SCROLL", lr = "SYS_MENU_LR", select = "SYS_MENU_SELECT", back = "SYS_MENU_BACK",
  okay = "SYS_MENU_OKAY", yes = "SYS_MENU_YES", no = "SYS_MENU_NO", purchase = "SYS_MENU_PURCHASE",
  resume = "SYS_MENU_RESUME", quit = "SYS_MENU_QUIT", pause = "SYS_MENU_PAUSE", unpause = "SYS_MENU_UNPAUSE",
  error = "SYS_ERROR_BEEP", popup = "SYS_POPUP", pop_down = "SYS_POP_DOWN" }
function UI.sound(ctx, name)
  if not ctx then return end
  -- The ids the pause menu looked up itself first, then by name.
  local id = UI.SOUND[name] and read_u32(UI.SOUND[name])
  if not id or id == 0xFFFFFFFF or id == 0 then id = NAMES[name] and UI.sound_id(ctx, NAMES[name]) end
  if not id or id == 0xFFFFFFFF then return end
  pcall(G.call, ctx, PLAY_SOUND, { id, 0, 0 })
end

-- Fonts load with the game's interface; until then the text menu stands in.
function UI.ready()
  return UI.ok and font("thin") ~= nil
end

return UI
