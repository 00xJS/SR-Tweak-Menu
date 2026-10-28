-- SR Tweak Menu - homie limit.
--
-- Ported from the core of the author's More Homies mod: the menu sets how
-- many homies may follow you, 1 to 10 (0 = the game's own rule). The game
-- keeps the party on the player object, a count at +2096 and a list of ten
-- 20-byte slots from +2100, and holds it to 3 in three places:
--
--  1. 0x824836E8 (player) -> max followers. Every recruit path asks it: 0
--     until recruiting is unlocked and on, 3 while a mission wants a full
--     party, otherwise 1 + the city-ownership awards reached. Hooked: when
--     the game allows any homies at all, the answer becomes the menu's.
--  2. 0x8247CC48 (player, npc) -> recruited?, the street recruit (D-pad up).
--     It refuses outright when the party already has 3. Hooked: with room
--     under the limit, the game's own steps for a smaller party are run
--     here (eligibility 0x8247CAB0, insert 0x82483828, HUD head 0x822D0188 /
--     0x822D1418).
--  3. 0x822DEA08 (player, f1 alpha): the HUD draws at most 3 follower heads.
--     Hooked: one more pass per further three heads, with those list
--     entries moved to the front and the head positions moved left, put back
--     afterwards.
--
-- When the standalone More Homies mod is ticked in the loader it already
-- does 2 and 3, so only 1 runs here (after More Homies, so the menu's number
-- wins). The experimental entourage past 10, the gang-wave and follower-range
-- changes stay with More Homies.

local G = require("game")

local H = { limit = 0, standalone = false }

local PARTY_MAX   = 0x824836E8  -- (player) -> max followers
local RECRUIT_ONE = 0x8247CC48  -- (player, npc) -> 1 if recruited
local CAN_RECRUIT = 0x8247CAB0  -- (player, npc) -> eligible?
local PARTY_ADD   = 0x82483828  -- (player, npc, forced) -> added?
local HUD_SLOT    = 0x822D0188  -- (npc) -> HUD head slot or -1
local HUD_ADD     = 0x822D1418  -- (npc) registers the head
local HUD_HEADS   = 0x822DEA08  -- (player, f1 alpha) draws follower heads
H.DISMISS_ALL     = 0x82483B78  -- (player) dismisses the whole party
local COUNT, LIST, MODE = 2096, 2100, 4012
local ENTRY, LIST_MAX = 20, 10
-- HUD head slots: 16 bytes each {x, y, scale, alpha}; heads 1 to 3 only.
local SLOT_BASE = 0x8301AF48
-- Per-head fade state the HUD keeps: three arrays of three words.
local FADE_BASE, FADE_BYTES = 0x840B5EB0, 36

local read_u32, write_u32 = wml.read_u32, wml.write_u32
local debug_on = wml.setting("debug", false)

local function to_int(v)
  v = v & 0xFFFFFFFF
  if v >= 0x80000000 then v = v - 0x100000000 end
  return v
end
local function in_single_player(p) return p ~= 0 and read_u32(p + MODE) == 1 end

-- r3..r5 set, stack lowered, registers given back. Returns r3.
local function call(ctx, addr, a, b, c)
  local r1, r3, r4, r5 = ctx:r(1), ctx:r(3), ctx:r(4), ctx:r(5)
  ctx:set_r(1, r1 - 0x1000)
  ctx:set_r(3, a or 0); ctx:set_r(4, b or 0); ctx:set_r(5, c or 0)
  ctx:call(addr)
  local result = ctx:r(3)
  ctx:set_r(1, r1); ctx:set_r(3, r3); ctx:set_r(4, r4); ctx:set_r(5, r5)
  return result
end

-- The standalone mod, if ticked, handles recruiting and the HUD itself.
H.standalone = (function()
  local ok, on = pcall(function()
    local f = io.open(wml.mod_folder .. "/../modlist.ini", "r")
    if not f then return false end
    local found = false
    for line in f:lines() do
      if line:match("^%s*%+%s*MoreHomies%s*$") then found = true break end
    end
    f:close()
    return found
  end)
  return ok and on
end)()

-- The limit in force: the menu's, else whatever the game (or More Homies)
-- answers.
local function limit() return math.max(0, math.min(LIST_MAX, math.floor(H.limit or 0))) end

-- ------------------------------------------------------------ party maximum
local hud_pass = false
local last_logged = nil
G.hook(PARTY_MAX, function(ctx)
  local p = ctx:r(3)
  ctx:call_original()
  if hud_pass then ctx:set_r(3, 0) return end
  local game = to_int(ctx:r(3))
  local want = limit()
  -- 0 from the game means recruiting is off or not unlocked yet: kept.
  if want == 0 or game <= 0 or not in_single_player(p) then return end
  ctx:set_r(3, want)
  if debug_on and want ~= last_logged then
    last_logged = want
    wml.log(string.format("homies: limit %d (the game said %d, party now %d)", want, game, to_int(read_u32(p + COUNT))))
  end
end)

if not H.standalone then
  -- ---------------------------------------------------------- street recruit
  G.hook(RECRUIT_ONE, function(ctx)
    local p, npc = ctx:r(3), ctx:r(4)
    if not in_single_player(p) or npc == 0 then ctx:call_original() return end
    local count = to_int(read_u32(p + COUNT))
    if count < 3 then ctx:call_original() return end            -- the game handles this itself
    local max = math.min(LIST_MAX, to_int(call(ctx, PARTY_MAX, p)))  -- through the hook above
    if count >= max then ctx:call_original() return end         -- full: the game refuses as usual
    if (call(ctx, CAN_RECRUIT, p, npc) & 0xFF) == 0 then ctx:set_r(3, 0) return end
    if read_u32(npc + 4128) ~= 0 then ctx:set_r(3, 0) return end  -- already following someone
    local added = (call(ctx, PARTY_ADD, p, npc, 1) & 0xFF) ~= 0
    if added and to_int(call(ctx, HUD_SLOT, npc)) ~= -1 then call(ctx, HUD_ADD, npc) end
    if debug_on and added then wml.log(string.format("homies: follower %d of %d recruited", count + 1, max)) end
    ctx:set_r(3, added and 1 or 0)
  end)

  -- ---------------------------------------------------------- HUD heads
  local fade_extra = {}
  local function swap_bytes(a, b, n)
    for i = 0, n - 4, 4 do
      local x, y = read_u32(a + i), read_u32(b + i)
      write_u32(a + i, y); write_u32(b + i, x)
    end
  end
  H.draw_heads = function(ctx)
    local p = ctx:r(3)
    local alpha = ctx:f(1)
    ctx:call_original()
    if not in_single_player(p) then return end
    local count = math.min(LIST_MAX, to_int(read_u32(p + COUNT)))
    if count <= 3 then return end
    local x0, x1, x2 = to_int(read_u32(SLOT_BASE)), to_int(read_u32(SLOT_BASE + 16)), to_int(read_u32(SLOT_BASE + 32))
    local span = (x2 - x0) + (x1 - x0)                          -- three head positions further on
    local saved_x = { read_u32(SLOT_BASE), read_u32(SLOT_BASE + 16), read_u32(SLOT_BASE + 32) }
    local fade_saved = {}
    for i = 0, FADE_BYTES - 4, 4 do fade_saved[#fade_saved + 1] = read_u32(FADE_BASE + i) end
    for pass = 1, math.ceil((count - 3) / 3) do
      local first = 3 * pass
      local extra = math.min(count - first, 3)
      if extra <= 0 then break end
      swap_bytes(p + LIST, p + LIST + first * ENTRY, 3 * ENTRY)
      write_u32(p + COUNT, extra)
      for j = 0, 2 do write_u32(SLOT_BASE + 16 * j, (to_int(saved_x[j + 1]) + span * pass) & 0xFFFFFFFF) end
      fade_extra[pass] = fade_extra[pass] or {}
      for i = 0, FADE_BYTES - 4, 4 do write_u32(FADE_BASE + i, fade_extra[pass][i] or 0) end
      require("hud_layout").homie_pass(pass)
      hud_pass = true
      ctx:set_r(3, p); ctx:set_f(1, alpha)
      local ok,why=pcall(function() ctx:call_original() end)
      hud_pass = false
      for i = 0, FADE_BYTES - 4, 4 do fade_extra[pass][i] = read_u32(FADE_BASE + i) end
      write_u32(p + COUNT, count)
      swap_bytes(p + LIST, p + LIST + first * ENTRY, 3 * ENTRY)
      if not ok then
        for i = 0, FADE_BYTES - 4, 4 do write_u32(FADE_BASE + i, fade_saved[i // 4 + 1]) end
        for j = 0, 2 do write_u32(SLOT_BASE + 16 * j, saved_x[j + 1]) end
        error(why)
      end
    end
    for i = 0, FADE_BYTES - 4, 4 do write_u32(FADE_BASE + i, fade_saved[i // 4 + 1]) end
    for j = 0, 2 do write_u32(SLOT_BASE + 16 * j, saved_x[j + 1]) end
  end
end

-- One owner for this native hook: relocation wraps every normal/extra pass.
-- More Homies can still supply its own native passes when enabled separately.
G.hook(HUD_HEADS,function(ctx)
  require("hud_layout").draw_homies(ctx,function()
    if H.draw_heads then H.draw_heads(ctx) else ctx:call_original() end
  end)
end)

-- Homies following you now.
function H.count(p) return p ~= 0 and math.max(0, to_int(read_u32(p + COUNT))) or 0 end

wml.log(H.standalone and "homies: More Homies is ticked; the menu sets the limit, More Homies does recruiting and the HUD"
  or "homies: the menu's homie limit handles recruiting and the HUD")

return H
