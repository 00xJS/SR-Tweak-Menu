-- SR Tweak Menu - your character talks back, in your voice: lines for what
-- happens to you, as in Saints Row 2. How often follows Character Dialogue
-- (Off: never; Rarely, Sometimes, Often scale every chance).
--
-- Detectors raise flags (R.flag(kind)); each flag has a chance and a group
-- of lines. A group plays round in a shuffled order and, once every line in
-- it has been heard, rests for five minutes. Flags come from:
--   TAKE_DAMAGE      hit (gun, melee, vehicle) - the first hit after 15 s quiet
--   car hit hook     run over on foot
--   car damage       crashing the car you drive (update)
--   projectiles      a grenade, pipe bomb or rocket from someone else near you (with homies)
--   DISMISS_ALL      dismissing homies (and the party shrinking with nobody dying)
--   update           cash picked up, standing still ~90 s, sprinting into people
--   SAY_LINE         a cop's arrest line, a driver's hijacked line
-- Every flag and line is written to wml.log ("voice:").

local G = require("game")
local NAMES = require("voicelines")
local R = { enabled = function() return false end, rate = function() return 1 end }
local read_u32, read_f32 = wml.read_u32, wml.read_f32

local number = {}
for i, name in ipairs(NAMES) do number[name] = i - 1 end
R.number = number

local REST = 5 * 60   -- seconds a group rests after every line in it played
local GROUPS = {
  hit = { chance = 0.25, lines = { "threat - alert (group attack)", "threat - damage received (firearm)",
    "threat - damage received (melee)", "threat - damage received (vehicle)" } },
  car = { chance = 0.25, lines = { "threat - vehicle collision", "taunt - vehicle collision", "observe - accident" } },
  hijack = { chance = 0.25, lines = { "threat - vehicle hijacked", "taunt - vehicle hijacked" } },
  grenade = { chance = 0.25, lines = { "observe - grenade incoming" } },
  bump = { chance = 0.25, lines = { "misc - collision with pc" } },
  arrested = { chance = 1, lines = { "special - arrested by cop" } },
  cash = { chance = 0.15, lines = { "special - counting cash" } },
  idle = { chance = 0.20, lines = { "misc - timeout", "misc - walk by ambient" } },
  dismiss = { chance = 0.5, lines = { "group - dismiss confirm" } },
}
R.GROUPS = GROUPS
R.random = math.random
R.clock = os.clock
R.said = {}       -- (lines asked for, for the tests)
R.has_line = function() return true end   -- (set by features: the voice has the line)
R.log = function(s) wml.log("voice: " .. s) end

local state = {}
local function group_state(name)
  local s = state[name]
  if not s then s = { order = {}, at = 1 }; state[name] = s end
  return s
end
local function shuffle(lines)
  local order = {}
  for i, l in ipairs(lines) do order[i] = l end
  for i = #order, 2, -1 do
    local j = R.random(1, i)
    order[i], order[j] = order[j], order[i]
  end
  return order
end

-- A flag: say the next line of its group, if its chance comes up and it
-- isn't resting. `prefer` puts a line first (the hit's own kind).
-- Returns the line said, or nil.
function R.flag(name, say, prefer)
  local g = GROUPS[name]
  if not g or not R.enabled() then return nil end
  local s = group_state(name)
  local now = R.clock()
  if s.rest_until and now < s.rest_until then return nil end
  if s.busy_until and now < s.busy_until then return nil end
  local chance = math.min(1, g.chance * R.rate())
  if R.random() > chance then R.log(name .. " (no line this time)") return nil end
  if s.at > #s.order then s.order, s.at = shuffle(g.lines), 1 end
  if prefer then
    for i = s.at, #s.order do
      if s.order[i] == prefer then s.order[i], s.order[s.at] = s.order[s.at], s.order[i] break end
    end
  end
  local line = s.order[s.at]
  if not R.has_line(number[line]) then R.log(name .. ": your voice has no '" .. line .. "' line") return nil end
  s.at = s.at + 1
  s.busy_until = now + (#g.lines == 1 and 20 or 4)
  if s.at > #s.order and #g.lines > 1 then s.rest_until = now + REST end
  R.said[#R.said + 1] = line
  R.log(name .. ": " .. line)
  if say then say(line) end
  return line
end
-- Your own attacks never count as running into someone: an attack action you play
-- (punch, kick, melee, tackle...) or damage you deal marks it, and the person you hit.
R.ATTACK_WINDOW, R.VICTIM_WINDOW = 1.5, 4
function R.note_attack() R.attack_at = R.clock() end
function R.note_damage(victim) if victim and victim ~= 0 then R.hit_by_you[victim] = R.clock(); R.attack_at = R.clock() end end
function R.attacking() return R.clock() - (R.attack_at or -1000) < R.ATTACK_WINDOW end
function R.attacked(o) return R.clock() - (R.hit_by_you[o] or -1000) < R.VICTIM_WINDOW end
R.hit_by_you = {}
R.try = R.flag
function R.reset() state = {}; R.said = {}; R.last = nil; R.hurt_at = nil; R.attack_at = nil; R.hit_by_you = {} end

-- TAKE_DAMAGE on you: `kind` is "vehicle", "firearm" or "melee".
function R.hit(kind, say)
  local now = R.clock()
  local first = now - (R.hurt_at or -1000) > 15
  R.hurt_at = now
  if not first then return nil end
  local prefer = R.random() < 0.5 and "threat - alert (group attack)" or ("threat - damage received (" .. kind .. ")")
  return R.flag("hit", say, prefer)
end

-- A line someone else says (SAY_LINE). `say` plays a line in your voice.
function R.heard(speaker, situation, p, say)
  if p == 0 or speaker == 0 or speaker == p then return end
  local name = NAMES[situation + 1]
  if not name then return end
  if name == "misc - arrest pc" or name == "special - arrest npc" then
    R.flag("arrested", say)
  elseif name == "threat - driver extract" or name == "taunt - vehicle hijacked" then
    if read_u32(p + G.P.VEHICLE) ~= 0 then R.flag("hijack", say) end
  elseif name == "observe - grenade incoming" then
    if read_u32(p + G.PARTY_COUNT) > 0 then R.flag("grenade", say) end
  elseif name == "misc - collision with pc" then
    if not R.attacking() and not R.attacked(speaker) then R.flag("bump", say) else R.log("bump skipped (your attack)") end
  elseif name == "group - dismiss confirm" then
    R.flag("dismiss", say)
  end
end

-- Every update: the moments with no game event of their own.
-- `near` (p, radius) lists people near you with their ragdoll state.
function R.update(p, say, quiet, near)
  if p == 0 or not R.enabled() then R.last = nil return end
  local now = R.clock()
  local L = R.last
  local hp = read_f32(p + G.P.HEALTH)
  local cash = read_u32(p + G.P.CASH)
  local car = G.vehicle_object(p)
  local car_hp = car and read_u32(car + G.V.HP) or nil
  local party = read_u32(p + G.PARTY_COUNT)
  local x, _, z = G.vec(p + G.P.POS)
  if L and L.p == p and not quiet and hp > 0 then
    -- A hard knock to the car you're driving.
    if car and L.car == car and car_hp and L.car_hp and car_hp < L.car_hp - math.max(25, L.car_hp * 0.04) then
      if now - (L.crash_at or -1000) > 6 then R.flag("car", say) end
      L.crash_at = now
    end
    -- Cash picked up (a small rise, not a mission reward).
    if cash > L.cash and cash - L.cash <= 5000 then R.flag("cash", say) end
    -- The party smaller with nobody of it dying: dismissed.
    if party < L.party and now - (R.death_at or -1000) > 2 then R.flag("dismiss", say) end
    -- Sprinting into people: someone close to you knocked over while you sprint.
    -- (the people scan only runs while you sprint)
    if not car and near and R.sprinting and R.sprinting(p) and not R.attacking() then
      local down = {}
      for _, h in ipairs(near(p, 1.6)) do
        if h.ragdoll then
          down[h.object] = true
          if L.down and not L.down[h.object] and not R.attacked(h.object) then R.flag("bump", say) end
        end
      end
      L.down = down
    else
      L.down = nil
    end
    -- Standing still on foot for about 90 seconds.
    if not car and (x - L.x) ^ 2 + (z - L.z) ^ 2 < 0.01 then
      if now - L.still_at >= 90 then R.flag("idle", say); L.still_at = now end
    else
      L.still_at, L.x, L.z = now, x, z
    end
    L.hp, L.cash, L.car, L.car_hp, L.party = hp, cash, car, car_hp, party
    return
  end
  R.last = { p = p, hp = hp, cash = cash, car = car, car_hp = car_hp, party = party, x = x, z = z, still_at = now,
    crash_at = L and L.crash_at }
end

-- Dismissing your homies (the game's DISMISS_ALL, from the D-pad or the menu).
function R.dismissed(say) return R.flag("dismiss", say) end

return R
