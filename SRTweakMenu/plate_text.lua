-- SR Tweak Menu - custom licence plates: your own text on your car's plate.
--
-- The game draws a plate from the plate picture (zlpm_1 Stilwater, zlpm_2
-- the Bill Ender Autos frame, 128x64) and six digit squares on top of it,
-- three, a gap, three, each square one of the ten digit pictures zlp_0..9
-- (64x64). There are no letters, so the text is drawn here, in letters of
-- our own (strokes on a 6 x 10 grid, below), across the whole plate: six
-- digit pictures become the six slices of it that sit under the squares and
-- zlpm_2 gets the plate with the text in the gap. Your car is then given
-- those six pictures and zlpm_2; other cars keep to the four digits and the
-- Stilwater plate left alone (features.lua).
--
-- Textures are in the game's memory as the 360 keeps them: DXT1 blocks of 8
-- bytes, 16-bit words big-endian, in the Xenos tiled order. A texture is
-- found by name in the game's bitmap table (0x82839BE0, records at
-- *0x832B6024, 20 bytes, +4 the peg entry, whose +0 is the pixels). Two
-- digit pictures share each 12 KB block: the one with entry byte +20 = 0x10
-- (0 to 4) sits 4 KB in.

local T = {}

local read_u8, read_u16, read_u32 = wml.read_u8, wml.read_u16, wml.read_u32
local write_u16 = wml.write_u16

T.MAX = 7            -- characters on a plate, as on a real one

-- ------------------------------------------------------------------ letters
-- Each letter: strokes on a 6 x 10 box (x right, y down). L = a line through
-- points, A = an arc (centre, radii, from and to angle in degrees, 0 right,
-- 90 down). Lower case is drawn as small capitals.
local function L(...) return { "L", { ... } } end
local function A(cx, cy, rx, ry, a0, a1) return { "A", { cx, cy, rx, ry, a0, a1 } } end
local GLYPHS = {
  ["0"] = { A(3, 5, 3, 5, 0, 360) },
  ["1"] = { L(1.2, 2.2, 3.4, 0, 3.4, 10) },
  ["2"] = { A(3, 3, 3, 3, 180, 400), L(5.3, 4.93, 0, 10, 6, 10) },
  ["3"] = { A(3, 2.6, 2.8, 2.6, 200, 450), A(3, 7.3, 3, 2.7, 270, 520) },
  ["4"] = { L(4.6, 10, 4.6, 0, 0, 7, 6.2, 7) },
  ["5"] = { L(5.6, 0, 1, 0, 0.6, 4.4), A(3, 6.8, 3, 3.2, 228, 510) },
  ["6"] = { A(3, 7, 3, 3, 0, 360), A(6.5, 7, 6.5, 7, 180, 245) },
  ["7"] = { L(0, 0, 6, 0, 2, 10) },
  ["8"] = { A(3, 2.5, 2.6, 2.5, 0, 360), A(3, 7.3, 3, 2.7, 0, 360) },
  ["9"] = { A(3, 3, 3, 3, 0, 360), A(-0.5, 3, 6.5, 7, 0, 65) },
  A = { L(0, 10, 3, 0, 6, 10), L(1.1, 6.5, 4.9, 6.5) },
  B = { L(3.5, 0, 0, 0, 0, 10, 3.8, 10), A(3.5, 2.5, 2.3, 2.5, 270, 450), L(3.5, 5, 0, 5, 3.8, 5), A(3.8, 7.5, 2.2, 2.5, 270, 450) },
  C = { A(3.3, 5, 3.2, 5, 40, 320) },
  D = { L(2.5, 0, 0, 0, 0, 10, 2.5, 10), A(2.5, 5, 3.5, 5, 90, -90) },
  E = { L(6, 0, 0, 0, 0, 10, 6, 10), L(0, 5, 4.5, 5) },
  F = { L(6, 0, 0, 0, 0, 10), L(0, 5, 4.5, 5) },
  G = { A(3.2, 5, 3.2, 5, 320, 0), L(6.4, 5, 3.6, 5) },
  H = { L(0, 0, 0, 10), L(6, 0, 6, 10), L(0, 5, 6, 5) },
  I = { L(3, 0, 3, 10), L(1, 0, 5, 0), L(1, 10, 5, 10) },
  J = { L(6, 0, 6, 6.8), A(3, 6.8, 3, 3.2, 0, 170) },
  K = { L(0, 0, 0, 10), L(6, 0, 0, 6.2), L(2.2, 4.4, 6, 10) },
  L = { L(0, 0, 0, 10, 6, 10) },
  M = { L(0, 10, 0, 0, 3, 6, 6, 0, 6, 10) },
  N = { L(0, 10, 0, 0, 6, 10, 6, 0) },
  O = { A(3, 5, 3, 5, 0, 360) },
  P = { L(0, 10, 0, 0, 3.5, 0), A(3.5, 2.7, 2.5, 2.7, 270, 450), L(3.5, 5.4, 0, 5.4) },
  Q = { A(3, 5, 3, 5, 0, 360), L(3.8, 7, 6.3, 10.2) },
  R = { L(0, 10, 0, 0, 3.5, 0), A(3.5, 2.7, 2.5, 2.7, 270, 450), L(3.5, 5.4, 0, 5.4), L(3, 5.4, 6, 10) },
  S = { A(3, 2.6, 2.9, 2.6, 340, 90), A(3, 7.45, 3, 2.55, 270, 520) },
  T = { L(0, 0, 6, 0), L(3, 0, 3, 10) },
  U = { L(0, 0, 0, 6.8), A(3, 6.8, 3, 3.2, 180, 0), L(6, 6.8, 6, 0) },
  V = { L(0, 0, 3, 10, 6, 0) },
  W = { L(0, 0, 1.5, 10, 3, 3.5, 4.5, 10, 6, 0) },
  X = { L(0, 0, 6, 10), L(6, 0, 0, 10) },
  Y = { L(0, 0, 3, 5, 6, 0), L(3, 5, 3, 10) },
  Z = { L(0, 0, 6, 0, 0, 10, 6, 10) },
  ["-"] = { L(1, 5.2, 5, 5.2) },
  ["."] = { L(3, 9.6, 3, 9.7) },
  [" "] = {},
}
T.CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 -."

-- A glyph as line segments { x0, y0, x1, y1 ... } in its box.
local seg_cache = {}
local function segments(ch)
  if seg_cache[ch] then return seg_cache[ch] end
  local small = ch:match("%l") ~= nil
  local g = GLYPHS[ch:upper()] or GLYPHS[" "]
  local out = {}
  local function add(x0, y0, x1, y1)
    if small then y0, y1 = 3 + y0 * 0.7, 3 + y1 * 0.7; x0, x1 = 0.4 + x0 * 0.87, 0.4 + x1 * 0.87 end
    out[#out + 1] = { x0, y0, x1, y1 }
  end
  for _, s in ipairs(g) do
    local p = s[2]
    if s[1] == "L" then
      for i = 1, #p - 2, 2 do add(p[i], p[i + 1], p[i + 2], p[i + 3]) end
    else
      local cx, cy, rx, ry, a0, a1 = p[1], p[2], p[3], p[4], p[5], p[6]
      local n = math.max(6, math.floor(math.abs(a1 - a0) / 12))
      local px, py
      for k = 0, n do
        local a = math.rad(a0 + (a1 - a0) * k / n)
        local x, y = cx + rx * math.cos(a), cy + ry * math.sin(a)
        if px then add(px, py, x, y) end
        px, py = x, y
      end
    end
  end
  seg_cache[ch] = out
  return out
end

local function seg_dist(px, py, s)
  local x0, y0, x1, y1 = s[1], s[2], s[3], s[4]
  local dx, dy = x1 - x0, y1 - y0
  local len = dx * dx + dy * dy
  local t = len > 0 and ((px - x0) * dx + (py - y0) * dy) / len or 0
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  local ex, ey = x0 + t * dx - px, y0 + t * dy - py
  return math.sqrt(ex * ex + ey * ey)
end

-- ------------------------------------------------------------------ layout
-- Where things are on the plate picture, in its pixels (128 x 64): the six
-- squares (x0, y0, x1, y1: the square's picture's top-left and bottom-right
-- corners land there) and the text's row. Measured in game off the test
-- card (the Aqua's rear plate): 16 x 28 squares, three touching, a 14.6
-- pixel gap, the two groups mirrored about the middle.
T.SLOTS = {
  { 8.7, 20.15, 24.7, 48.15 }, { 24.7, 20.15, 40.7, 48.15 }, { 40.7, 20.15, 56.7, 48.15 },
  { 71.3, 20.15, 87.3, 48.15 }, { 87.3, 20.15, 103.3, 48.15 }, { 103.3, 20.15, 119.3, 48.15 },
}
-- The text's centre line, letter height (strokes included) and the widest
-- it may be: past that (6 or 7 characters) the letters shrink evenly, so
-- every plate sits centred inside the squares' span (8.7 to 119.3).
T.ROW = { cy = 34.15, height = 22, width = 108 }
T.STROKE = 1.05                    -- stroke radius, in letter units (a letter is 10 tall)
T.SPACING = 1.6                    -- between letters, in letter units

-- How much of each pixel the text covers, for a pixel centred at (x, y) on
-- the plate that's `foot` plate pixels wide.
local function make_text(text)
  local r = T.STROKE
  local adv = 6 + 2 * r + T.SPACING
  local n = #text
  local width = n > 0 and (n * adv - T.SPACING) or 0
  local s = T.ROW.height / (10 + 2 * r)                -- plate pixels per letter unit
  if width * s > T.ROW.width then s = T.ROW.width / width end
  local x0 = 64 - width * s / 2 + r * s                -- the first box's left edge
  local y0 = T.ROW.cy - 5 * s
  local chars = {}
  for i = 1, n do chars[i] = { segments(text:sub(i, i)), x0 + (i - 1) * adv * s } end
  return function(x, y, foot)
    local gy = (y - y0) / s
    if gy < -2 or gy > 12 then return 0 end
    local best = 1e9
    for _, c in ipairs(chars) do
      local gx = (x - c[2]) / s
      if gx > -2 and gx < 8 then
        for _, sg in ipairs(c[1]) do
          local d = seg_dist(gx, gy, sg)
          if d < best then best = d end
        end
      end
    end
    local cov = (r - best) * s / foot + 0.5
    return cov < 0 and 0 or (cov > 1 and 1 or cov)
  end
end
T.make_text = make_text

-- ------------------------------------------------------------------ DXT1
-- Block (bx, by) of a texture `bw` blocks wide: its byte offset (Xenos
-- tiling, 8-byte blocks; as tools/peg_png.py in the research repo).
local function tiled(bx, by, bw)
  local aw = math.max(32, (bw + 31) & ~31)
  local log_bpp = 3
  local macro = ((bx >> 5) + (by >> 5) * (aw >> 5)) << (log_bpp + 7)
  local micro = ((bx & 7) + ((by & 6) << 2)) << log_bpp
  local off = macro + ((micro & ~15) << 1) + (micro & 15) + ((by & 8) << (3 + log_bpp)) + ((by & 1) << 4)
  off = (((off & ~511) << 3) + ((off & 448) << 2) + (off & 63) + ((by & 16) << 7)
    + (((((by & 8) >> 2) + (bx >> 3)) & 3) << 6)) >> log_bpp
  return off * 8
end
T.tiled = tiled

local function rgb565(c) return ((c >> 11) & 31) * 255 // 31, ((c >> 5) & 63) * 255 // 63, (c & 31) * 255 // 31 end
local function to565(r, g, b) return ((r * 31 + 127) // 255 << 11) | ((g * 63 + 127) // 255 << 5) | ((b * 31 + 127) // 255) end

-- A texture's pixels: { w, h, [y * w + x + 1] = { r, g, b } }.
function T.decode(addr, w, h)
  local img = { w = w, h = h }
  local bw = w // 4
  for by = 0, h // 4 - 1 do
    for bx = 0, bw - 1 do
      local a = addr + tiled(bx, by, bw)
      local c0, c1 = read_u16(a), read_u16(a + 2)
      local bits = read_u16(a + 4) | (read_u16(a + 6) << 16)
      local r0, g0, b0 = rgb565(c0)
      local r1, g1, b1 = rgb565(c1)
      local pal
      if c0 > c1 then
        pal = { { r0, g0, b0 }, { r1, g1, b1 }, { (2 * r0 + r1) // 3, (2 * g0 + g1) // 3, (2 * b0 + b1) // 3 },
          { (r0 + 2 * r1) // 3, (g0 + 2 * g1) // 3, (b0 + 2 * b1) // 3 } }
      else
        pal = { { r0, g0, b0 }, { r1, g1, b1 }, { (r0 + r1) // 2, (g0 + g1) // 2, (b0 + b1) // 2 }, { 0, 0, 0 } }
      end
      for i = 0, 15 do
        local px, py = bx * 4 + (i & 3), by * 4 + (i >> 2)
        img[py * w + px + 1] = pal[((bits >> (2 * i)) & 3) + 1]
      end
    end
  end
  return img
end

-- Writes `img` (as decode makes) into the texture at addr.
function T.encode(addr, img)
  local w, h = img.w, img.h
  local bw = w // 4
  for by = 0, h // 4 - 1 do
    for bx = 0, bw - 1 do
      local px = {}
      local lo, hi, lo_l, hi_l = nil, nil, 1e9, -1
      for i = 0, 15 do
        local p = img[(by * 4 + (i >> 2)) * w + bx * 4 + (i & 3) + 1]
        px[i] = p
        local l = p[1] * 3 + p[2] * 6 + p[3]
        if l < lo_l then lo_l, lo = l, p end
        if l > hi_l then hi_l, hi = l, p end
      end
      local c0, c1 = to565(hi[1], hi[2], hi[3]), to565(lo[1], lo[2], lo[3])
      local bits = 0
      if c0 ~= c1 then
        if c0 < c1 then c0, c1, hi, lo = c1, c0, lo, hi end
        local r0, g0, b0 = rgb565(c0)
        local r1, g1, b1 = rgb565(c1)
        local dr, dg, db = r1 - r0, g1 - g0, b1 - b0
        local dd = dr * dr + dg * dg + db * db
        for i = 0, 15 do
          local p = px[i]
          local t = dd > 0 and ((p[1] - r0) * dr + (p[2] - g0) * dg + (p[3] - b0) * db) / dd or 0
          local q = math.floor(t * 3 + 0.5)
          if q < 0 then q = 0 elseif q > 3 then q = 3 end
          local index = q == 0 and 0 or (q == 3 and 1 or (q == 1 and 2 or 3))
          bits = bits | (index << (2 * i))
        end
      end
      local a = addr + tiled(bx, by, bw)
      write_u16(a, c0); write_u16(a + 2, c1)
      write_u16(a + 4, bits & 0xFFFF); write_u16(a + 6, (bits >> 16) & 0xFFFF)
    end
  end
end

-- ------------------------------------------------------------------ textures
local function cstr(p)
  local t = {}
  for i = 0, 63 do
    local c = read_u8(p + i)
    if c == 0 then break end
    t[#t + 1] = string.char(c)
  end
  return table.concat(t)
end
-- The game's two bitmap name tables (it looks in both).
local TABLES = { 0x82839B80, 0x82839BE0 }
-- The peg entry of a texture by name in one table, or nil.
local function entry_in(tbl, name)
  local h = 0
  local lname = name:lower()
  for i = 1, #lname do
    h = ((h << 6) | (h >> 26)) & 0xFFFFFFFF
    h = h ~ lname:byte(i)
  end
  local nb = read_u32(tbl + 80)
  local lists = read_u32(tbl + 84)
  if nb == 0 or lists == 0 then return nil end
  local list = read_u32(lists + ((h & 0xFFFF) % nb) * 4)
  if list == 0 then return nil end
  for k = 0, 255 do
    local item = list + k * 8
    local idx = read_u16(item + 4)
    if idx == 0xFFFF then return nil end
    if cstr(read_u32(item)):lower() == lname then
      local rec = read_u32(0x832B6024) + idx * 20
      local e = read_u32(rec + 4)
      return e ~= 0 and e or nil
    end
  end
end
local function entry(name)
  for _, tbl in ipairs(TABLES) do
    local e = entry_in(tbl, name)
    if e then return e end
  end
end

-- Debug: every name in the bitmap table containing `needle`, with where it leads.
function T.scan(needle, log)
  for _, tbl in ipairs(TABLES) do T.scan_table(tbl, needle, log) end
end
function T.scan_table(tbl, needle, log)
  local nb, lists = read_u32(tbl + 80), read_u32(tbl + 84)
  log(string.format("plate scan: table %08X nb %d lists %08X, records %08X", tbl, nb, lists, read_u32(0x832B6024)))
  if nb == 0 or nb > 100000 or lists == 0 then return end
  local found = 0
  for b = 0, nb - 1 do
    local list = read_u32(lists + b * 4)
    if list ~= 0 then
      for k = 0, 255 do
        local item = list + k * 8
        local idx = read_u16(item + 4)
        if idx == 0xFFFF then break end
        local name = cstr(read_u32(item))
        if name:lower():find(needle, 1, true) then
          local e = read_u32(read_u32(0x832B6024) + idx * 20 + 4)
          log(string.format("plate scan: bucket %d %s idx %d entry %08X", b, name, idx, e))
          found = found + 1
          if found > 20 then return end
        end
      end
    end
  end
  log("plate scan: " .. found .. " found")
end

-- The plate's textures: { digit = { [0..9] = { addr, w, h } }, plate = { [1] =, [2] = } }, or nil and why.
function T.find()
  local tex = { digit = {}, plate = {} }
  for d = 0, 9 do
    local e = entry(string.format("zlp_%d.tga", d))
    if not e then return nil, "zlp_" .. d .. " not loaded" end
    local addr = read_u32(e)
    if read_u8(e + 20) == 0x10 then addr = addr + 0x1000 end
    tex.digit[d] = { addr, read_u16(e + 4), read_u16(e + 6), e }
  end
  for k = 1, 2 do
    local e = entry(string.format("zlpm_%d.tga", k))
    if not e then return nil, "zlpm_" .. k .. " not loaded" end
    tex.plate[k] = { read_u32(e), read_u16(e + 4), read_u16(e + 6), e }
  end
  for d = 0, 9 do if tex.digit[d][2] ~= 64 or tex.digit[d][3] ~= 64 then return nil, "zlp_" .. d .. " isn't 64x64" end end
  for k = 1, 2 do if tex.plate[k][2] ~= 128 or tex.plate[k][3] ~= 64 then return nil, "zlpm_" .. k .. " isn't 128x64" end end
  return tex
end

-- The bytes a w x h texture uses: its blocks only (a digit picture's blocks
-- interleave with its partner's, 4 KB on).
function T.blocks(w, h)
  local t = {}
  for by = 0, h // 4 - 1 do
    for bx = 0, w // 4 - 1 do t[#t + 1] = tiled(bx, by, w // 4) end
  end
  return t
end
-- Raw words of a texture (to put back later).
function T.backup(addr, w, h)
  local t = { blocks = T.blocks(w, h) }
  for i, off in ipairs(t.blocks) do
    for k = 0, 3 do t[i * 4 + k] = read_u16(addr + off + k * 2) end
  end
  return t
end
function T.restore(addr, saved)
  for i, off in ipairs(saved.blocks) do
    for k = 0, 3 do write_u16(addr + off + k * 2, saved[i * 4 + k]) end
  end
end

-- Bilinear sample of a decoded image at (x, y) in its pixels.
local function sample(img, x, y)
  local w, h = img.w, img.h
  x, y = x - 0.5, y - 0.5
  local x0, y0 = math.floor(x), math.floor(y)
  local fx, fy = x - x0, y - y0
  local function px(ix, iy)
    if ix < 0 then ix = 0 elseif ix >= w then ix = w - 1 end
    if iy < 0 then iy = 0 elseif iy >= h then iy = h - 1 end
    return img[iy * w + ix + 1]
  end
  local a, b, c, d = px(x0, y0), px(x0 + 1, y0), px(x0, y0 + 1), px(x0 + 1, y0 + 1)
  local out = {}
  for k = 1, 3 do
    local top = a[k] + (b[k] - a[k]) * fx
    local bot = c[k] + (d[k] - c[k]) * fx
    out[k] = math.floor(top + (bot - top) * fy + 0.5)
  end
  return out
end

-- The text's colour: the blue of the game's own digits (their darkest pixels).
function T.ink(digit_img)
  local r, g, b, n = 0, 0, 0, 0
  for i = 1, digit_img.w * digit_img.h do
    local p = digit_img[i]
    if p[3] > p[1] + 40 and p[3] > p[2] + 20 then r, g, b, n = r + p[1], g + p[2], b + p[3], n + 1 end
  end
  if n == 0 then return { 50, 70, 170 } end
  return { r // n, g // n, b // n }
end

local function blend(bg, ink, a)
  return { math.floor(bg[1] + (ink[1] - bg[1]) * a + 0.5), math.floor(bg[2] + (ink[2] - bg[2]) * a + 0.5),
    math.floor(bg[3] + (ink[3] - bg[3]) * a + 0.5) }
end

-- The pictures for `text` on `base` (the decoded plate picture): the plate
-- with the text, and the six squares' slices of it.
function T.compose(text, base, ink)
  local cover = make_text(text)
  local plate = { w = 128, h = 64 }
  for y = 0, 63 do
    for x = 0, 127 do
      plate[y * 128 + x + 1] = blend(base[y * 128 + x + 1], ink, cover(x + 0.5, y + 0.5, 1))
    end
  end
  local squares = {}
  for k, sl in ipairs(T.SLOTS) do
    local img = { w = 64, h = 64 }
    local sx, sy = (sl[3] - sl[1]) / 64, (sl[4] - sl[2]) / 64
    local foot = math.max(sx, sy)
    for y = 0, 63 do
      for x = 0, 63 do
        local px, py = sl[1] + (x + 0.5) * sx, sl[2] + (y + 0.5) * sy
        img[y * 64 + x + 1] = blend(sample(base, px, py), ink, cover(px, py, foot))
      end
    end
    squares[k] = img
  end
  return plate, squares
end

-- A test card for measuring where the squares land: the plate in a grid
-- (a dark line every 8 pixels, a red one every 32), each square one colour
-- with a white border and a black corner at its top left.
T.SQUARE_COLOURS = { { 230, 40, 40 }, { 240, 150, 20 }, { 230, 220, 30 }, { 40, 190, 60 }, { 40, 110, 230 }, { 170, 50, 210 } }
function T.test_card()
  local plate = { w = 128, h = 64 }
  for y = 0, 63 do
    for x = 0, 127 do
      local c = { 235, 235, 235 }
      if x % 32 == 0 or y % 32 == 0 then c = { 220, 30, 30 }
      elseif x % 8 == 0 or y % 8 == 0 then c = { 60, 60, 60 } end
      plate[y * 128 + x + 1] = c
    end
  end
  local squares = {}
  for k, col in ipairs(T.SQUARE_COLOURS) do
    local img = { w = 64, h = 64 }
    for y = 0, 63 do
      for x = 0, 63 do
        local c = col
        if x < 4 or y < 4 or x > 59 or y > 59 then c = { 255, 255, 255 } end
        if x < 16 and y < 16 then c = { 0, 0, 0 } end
        img[y * 64 + x + 1] = c
      end
    end
    squares[k] = img
  end
  return plate, squares
end

-- ------------------------------------------------------------------ on the car
-- Square k (left to right) takes digit picture zlp_(10 - k): the car's
-- PlateB..G version k. The plate with the text goes in zlpm_2 (PlateA
-- version 1). Everything is put back by T.hide.
T.active = false     -- the textures hold a custom plate (or the test card)
local S = { tex = nil, saved = nil, base = nil, ink = nil, shown = nil }

local function ready()
  if S.tex then return S.tex end
  local tex, why = T.find()
  if not tex then return nil, why end
  S.saved = { plate = T.backup(tex.plate[2][1], 128, 64), digit = {} }
  for k = 1, 6 do S.saved.digit[k] = T.backup(tex.digit[10 - k][1], 64, 64) end
  S.base = { T.decode(tex.plate[1][1], 128, 64), T.decode(tex.plate[2][1], 128, 64) }
  S.ink = T.ink(T.decode(tex.digit[0][1], 64, 64))
  S.tex = tex
  return tex
end

local function put(tex, plate, squares)
  for k = 1, 6 do T.encode(tex.digit[10 - k][1], squares[k]) end
  T.encode(tex.plate[2][1], plate)
  T.active = true
end

-- Draws `text` on the plate picture `style` (1 Stilwater, 2 Bill Ender
-- Autos). Returns true, or nil and why.
function T.show(text, style)
  local tex, why = ready()
  if not tex then return nil, why end
  local key = text .. "|" .. style
  if S.shown == key then return true end
  local plate, squares = T.compose(text, S.base[style] or S.base[1], S.ink)
  put(tex, plate, squares)
  S.shown = key
  return true
end

function T.show_card()
  local tex, why = ready()
  if not tex then return nil, why end
  local plate, squares = T.test_card()
  put(tex, plate, squares)
  S.shown = "card"
  return true
end

-- The game's own pictures back.
function T.hide()
  if not T.active or not S.tex then return end
  T.restore(S.tex.plate[2][1], S.saved.plate)
  for k = 1, 6 do T.restore(S.tex.digit[10 - k][1], S.saved.digit[k]) end
  T.active, S.shown = false, nil
end

-- Keeps only characters the letters cover, at most T.MAX.
function T.clean(text)
  local out = {}
  for c in (text or ""):gmatch(".") do
    if T.CHARS:find(c, 1, true) and #out < T.MAX then out[#out + 1] = c end
  end
  return table.concat(out)
end

return T
