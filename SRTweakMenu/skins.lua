-- SR Tweak Menu - weapon skins: a colour for each weapon, after the forum's
-- "Color Tints" mods (which replaced each gun's texture in
-- preload_lower.vpp_xbox2). No picture is shipped: the game's own textures
-- are recoloured where they lie in memory, and put back from a copy.
--
-- The weapon textures load once at start (preload_lower) and stay at a
-- fixed address; the GPU reads them from there, and Saints Reborn's texture
-- cache notices writes to them (as with its own button-prompt swap). They
-- are DXT: 8-byte blocks of two 565 colours and 2-bit picks between them
-- (DXT5: the colour half is the second 8 bytes). A skin maps both colours of
-- every block through a colour table, keeping each block's mode, so the
-- 360's tiled layout doesn't matter and the shading stays the gun's own.
-- Wood (brown, fairly saturated) is left alone on guns that have some.
--
-- Finding a texture: the game's texture records (*0x832B6024, 20 bytes,
-- how many at 0x832B61CC) point at their peg entries (+4); an entry has the
-- pixels at +0, width / height / format at +4 / +6 / +8, the name at +0x17
-- and the next copy of the same name at +56. Every copy found is checked
-- for the size and format the gun's peg has before anything is written,
-- and only that texture's own bytes (its span in the peg) are touched.

local G = require("game")
local read_u8, read_u32 = wml.read_u8, wml.read_u32
local write_u32 = wml.write_u32

local K = {}
local F

local TEX_TABLE, TEX_COUNT = 0x832B6024, 0x832B61CC
local E_W, E_H, E_FMT, E_NAME, E_NEXT = 4, 6, 8, 0x17, 56
local DXT1, DXT5 = 0x190, 0x192
local BLOCKS_PER_UPDATE = 512
local function log(...) if G.debug then wml.log(...) end end

-- { row id, label, textures { name, width, height, format, span }, keeps wood }
local WEAPONS = {
  { "skin_k6_krukov", "K6 Krukov", { { "ak1_me.tga", 256, 256, DXT1, 0x10000 }, { "ak2_me.tga", 256, 256, DXT1, 0x10000 } }, true },
  { "skin_vice_9", "Vice 9", { { "beretta_me.tga", 256, 256, DXT1, 0x10000 } } },
  { "skin_nr4", "NR4", { { "glock21c_256.tga", 256, 256, DXT1, 0x10000 } } },
  { "skin_ar40_xtnd", "AR-40 Xtnd", { { "m4_1.tga", 256, 256, DXT1, 0x10000 }, { "m4_2.tga", 64, 64, DXT1, 0x6000 } } },
  { "skin_skr7_spree", "SKR-7 Spree", { { "mac_10_256.tga", 256, 256, DXT1, 0x10000 } } },
  { "skin_44_shepherd", ".44 Shepherd", { { "colt_anaconda.tga", 256, 256, DXT1, 0x10000 } }, true },
  { "skin_tombstone", "Tombstone", { { "cut_shotgun.tga", 256, 256, DXT1, 0x10000 } }, true },
  { "skin_12_gauge", "12 Gauge", { { "dblb_shotgun_256.tga", 256, 256, DXT1, 0x10000 } }, true },
  { "skin_as12_riot", "AS12 Riot", { { "spas12_256.tga", 256, 256, DXT1, 0x10000 } } },
  { "skin_mcmanus", "McManus", { { "p_sniper.tga", 256, 256, DXT1, 0x10000 } } },
  { "skin_rpg", "RPG", { { "rpg7_02.tga", 256, 128, DXT1, 0xA000 } } },
  { "skin_platinum_rpg", "Platinum RPG", { { "p_laser_rocket.tga", 256, 256, DXT5, 0x22000 } } },
  { "skin_nightstick", "Nightstick", { { "p_tonfa.tga", 128, 128, DXT1, 0x8000 } } },
  { "skin_crowbar", "Crowbar", { { "tire_iron.tga", 128, 128, DXT1, 0x8000 } } },
  { "skin_knife", "Knife", { { "p_knife.tga", 64, 128, DXT1, 0x6000 } } },
  { "skin_baseball_bat", "Baseball Bat", { { "woodbat1.tga", 32, 64, DXT1, 0x4000 } } },
  { "skin_pimp_slap", "Pimp Slap", { { "pimpslapfront_d.tga", 64, 32, DXT1, 0x4000 }, { "pimpslapinside_d_s.tga", 32, 32, DXT1, 0x4000 } } },
  { "skin_pcp", "PCP", { { "drugsyringe_gl.tga", 64, 128, DXT1, 0x6000 } } },
}
-- The gun shop's peg keeps a copy of the NR4's texture on top of this one;
-- that copy is left alone.
local SHARED_WITH = { ["glock21c_256.tga"] = "shd_whiteopaque.tga" }

-- ---------------------------------------------------------------- colours
local function hsv(h, s, v)
  h = (h % 1) * 6
  local i = math.floor(h)
  local f = h - i
  local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
  if i == 0 then return v, t, p elseif i == 1 then return q, v, p elseif i == 2 then return p, v, t
  elseif i == 3 then return p, q, v elseif i == 4 then return t, p, v end
  return v, p, q
end
local function to_hsv(r, g, b)
  local mx, mn = math.max(r, g, b), math.min(r, g, b)
  local d = mx - mn
  local h = 0
  if d > 0 then
    if mx == r then h = ((g - b) / d) % 6 elseif mx == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
    h = h / 6
  end
  return h, mx > 0 and d / mx or 0, mx
end
local function clamp(v) return v < 0 and 0 or (v > 1 and 1 or v) end
local function tint(h, s)
  return function(L)
    local t = clamp(L * 1.5 + 0.05)
    return hsv(h, s * (1 - 0.35 * t), clamp(0.07 + 0.93 * t))
  end
end
local function grey(lo, gain, hue, sat)
  return function(L) return hsv(hue or 0.6, sat or 0, clamp(lo + L * gain)) end
end
-- { name, f(brightness 0..1) -> r, g, b }; 1 is the gun as it is.
local PRESETS = {
  { "Original" },
  { "Gold", function(L) local t = clamp(L * 1.8 + 0.1) return hsv(0.125, 0.85 - 0.4 * t, clamp(0.22 + 1.0 * t)) end },
  { "Black", grey(0.03, 0.4) },
  { "Gunmetal", grey(0.08, 0.75, 0.6, 0.1) },
  { "Silver", grey(0.3, 0.95, 0.6, 0.04) },
  { "White", grey(0.55, 0.6, 0.6, 0.02) },
  { "Tan", tint(0.09, 0.45) },
  { "Olive", tint(0.19, 0.5) },
  { "Green", tint(0.33, 0.7) },
  { "Red", tint(0.0, 0.8) },
  { "Blue", tint(0.6, 0.75) },
  { "Purple", tint(0.78, 0.65) },
  { "Pink", tint(0.92, 0.5) },
}
local NAMES = {}
for i, p in ipairs(PRESETS) do NAMES[i] = p[1] end

local tables = {}   -- [preset .. wood] = { [565 colour] = new colour }
local function colour_map(preset, wood)
  local key = preset .. (wood and "w" or "")
  local map = tables[key]
  if map then return map end
  local f = PRESETS[preset][2]
  map = setmetatable({}, { __index = function(t, c)
    local r, g, b = ((c >> 11) & 31) / 31, ((c >> 5) & 63) / 63, (c & 31) / 31
    local out = c
    local h, s, v = to_hsv(r, g, b)
    if not (wood and h >= 0.02 and h <= 0.16 and s >= 0.3 and v >= 0.12) then
      local nr, ng, nb = f(0.30 * r + 0.59 * g + 0.11 * b)
      out = (math.floor(clamp(nr) * 31 + 0.5) << 11) | (math.floor(clamp(ng) * 63 + 0.5) << 5) | math.floor(clamp(nb) * 31 + 0.5)
    end
    t[c] = out
    return out
  end })
  tables[key] = map
  return map
end

-- One block's colour half (c = colour 0 << 16 | colour 1, x = the picks)
-- through the map, keeping its mode: DXT1 blocks with colour 0 > colour 1
-- have four colours, the others three and transparent black, so a swap
-- of the ends swaps the picks too. DXT5's colour half always has four.
local function recolour(c, x, map, four_always)
  local c0, c1 = c >> 16, c & 0xFFFF
  local n0, n1 = map[c0], map[c1]
  if not four_always then
    if c0 > c1 then
      if n0 < n1 then n0, n1 = n1, n0; x = x ~ 0x55555555
      elseif n0 == n1 then x = 0 end
    elseif n0 > n1 then
      n0, n1 = n1, n0
      local high = (x >> 1) & 0x55555555
      x = x ~ (~high & 0x55555555)
    end
  end
  return (n0 << 16) | n1, x & 0xFFFFFFFF
end

-- ---------------------------------------------------------------- textures
local function name_at(a)
  local t = {}
  for i = 0, 40 do
    local c = read_u8(a + i)
    if c == 0 then break end
    t[#t + 1] = string.char(c)
  end
  return table.concat(t):lower()
end

-- Every copy of the wanted names: { [name] = { entry, ... } }.
local found, scans, next_scan = nil, 0, 0
local function scan()
  local base, count = read_u32(TEX_TABLE), read_u32(TEX_COUNT)
  if not G.addr_ok(base) or count == 0 or count > 65535 then return nil end
  local wanted = {}
  for _, w in ipairs(WEAPONS) do for _, t in ipairs(w[3]) do wanted[t[1]] = {} end end
  for _, other in pairs(SHARED_WITH) do wanted[other] = {} end
  local seen = {}
  for i = 0, count - 1 do
    local e = read_u32(base + i * 20 + 4)
    if G.addr_ok(e) and not seen[e] then
      local name = name_at(e + E_NAME)
      local list = wanted[name]
      if list then
        for _ = 1, 8 do   -- this entry and the copies chained to it
          if not G.addr_ok(e) or seen[e] or name_at(e + E_NAME) ~= name then break end
          seen[e] = true
          list[#list + 1] = e
          e = read_u32(e + E_NEXT)
        end
      end
    end
  end
  return wanted
end

-- Each texture copy we may write: { pixels, blocks, block bytes, original words }.
-- Kept by address across scans, so a copy already recoloured keeps the
-- original colours it was read with.
local copies = {}   -- [row id] = { copy, ... }
local by_pixels = {}
local function build()
  local n = 0
  for _, w in ipairs(WEAPONS) do
    local list = {}
    for _, t in ipairs(w[3]) do
      local skip = {}
      for _, e in ipairs(found[SHARED_WITH[t[1]] or ""] or {}) do skip[read_u32(e)] = true end
      for _, e in ipairs(found[t[1]] or {}) do
        local pixels = read_u32(e)
        if G.addr_ok(pixels) and not skip[pixels] and wml.read_u16(e + E_W) == t[2] and wml.read_u16(e + E_H) == t[3]
            and wml.read_u16(e + E_FMT) == t[4] then
          local bpb = t[4] == DXT5 and 16 or 8
          local cp = by_pixels[pixels] or { pixels = pixels, blocks = t[5] // bpb, bpb = bpb, four = t[4] == DXT5, wood = w[4] }
          by_pixels[pixels] = cp
          list[#list + 1] = cp
          n = n + 1
        end
      end
    end
    copies[w[1]] = list
  end
  return n
end

-- ---------------------------------------------------------------- jobs
-- want[row] = the preset asked for; done[row] = the one on the textures.
local want, done = {}, {}
local job = nil   -- { row, preset, list, copy index, block }

local function start_job()
  for _, w in ipairs(WEAPONS) do
    local id = w[1]
    local p = want[id] or 1
    if p ~= (done[id] or 1) and copies[id] and #copies[id] > 0 then
      job = { row = id, preset = p, list = copies[id], copy = 1, block = 0 }
      return true
    end
    if p ~= (done[id] or 1) then done[id] = p end   -- nothing found to change
  end
  return false
end

local function work()
  local budget = BLOCKS_PER_UPDATE
  while budget > 0 and job do
    local cp = job.list[job.copy]
    if not cp then
      done[job.row] = job.preset
      log(string.format("skins: %s now %s", job.row, NAMES[job.preset]))
      job = nil
      break
    end
    if not cp.original then cp.original = {} end
    local orig = cp.original
    local map = job.preset > 1 and colour_map(job.preset, cp.wood) or nil
    local last = math.min(cp.blocks, job.block + budget)
    for b = job.block, last - 1 do
      local a = cp.pixels + b * cp.bpb + (cp.bpb - 8)
      local k = b * 2 + 1
      local c, x = orig[k], orig[k + 1]
      if not c then c, x = read_u32(a), read_u32(a + 4); orig[k], orig[k + 1] = c, x end
      if map then c, x = recolour(c, x, map, cp.four) end
      write_u32(a, c); write_u32(a + 4, x)
    end
    budget = budget - (last - job.block)
    job.block = last
    if job.block >= cp.blocks then job.copy, job.block = job.copy + 1, 0 end
  end
end

-- ---------------------------------------------------------------- rows
function K.setup(features)
  F = features
  local rows = {}
  for _, w in ipairs(WEAPONS) do
    local id = w[1]
    rows[#rows + 1] = { id = id, label = w[2], kind = "value", needs = "none", default = 1, min = 1, max = #PRESETS, step = 1,
      v = 1, fmt = function(v) return NAMES[math.floor(v + 0.5)] or "?" end,
      help = "The " .. w[2] .. "'s colour" .. (w[4] and " (its wood stays wood)" or "") .. ". Every copy changes, the ones NPCs carry too.",
      update = function(ctx, p, v, it) want[id] = it.v end,
      off = function() want[id] = 1 end }
  end
  rows[#rows + 1] = { id = "skins_reset", label = "All back to the original", kind = "action", needs = "none",
    help = "Every weapon gets its own colours back.",
    run = function()
      for _, w in ipairs(WEAPONS) do F.items[w[1]].v = 1 end
      return "Weapon colours back to the original"
    end }
  F.add_rows("Weapons", nil, rows)
end

function K.after(ctx)
  if not job then
    local any = false
    for _, w in ipairs(WEAPONS) do if (want[w[1]] or 1) ~= (done[w[1]] or 1) then any = true break end end
    if not any then return end
    if not found then
      if F.tick < next_scan then return end
      scans = scans + 1
      local result = scan()
      next_scan = F.tick + 500
      if not result then return end
      found = result
      local n = build()
      local missing = {}
      for _, w in ipairs(WEAPONS) do if #copies[w[1]] == 0 then missing[#missing + 1] = w[2] end end
      wml.log(string.format("skins: %d weapon textures found%s", n,
        #missing > 0 and ("; not found: " .. table.concat(missing, ", ")) or ""))
      if #missing > 0 and scans < 5 then found = nil end   -- look again a little later
      if n == 0 then return end
    end
    if not start_job() then return end
  end
  work()
end

return K
