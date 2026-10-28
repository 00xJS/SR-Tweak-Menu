-- SR Tweak Menu - faces for what happens to you, as in Saints Row 2: a
-- moment's expression over the one you chose (Juiced clips), then back.
--   pain    Pain, Pain B or Pain C while you're being hurt (shot, run over, hit)
--   fire    Surprised or Scared while you're on fire
--   death   Death or Death B while you're dead
--   liquor  Inebriated while you drink a liquor powerup; smoke: Mellow while you use the bong
--   shoot   Sneer while you fire a gun; Angry 1 on shotgun / RPG shots, Insane now and then (RPG, molotov)
--   melee   Angry 1 and Disgusted in turn while the melee stance lasts; low health: Fearful (or a Pain)
--   drunk   Smarmy while throwing up; cough: Mellow while coughing after smoking
-- A stronger moment isn't cut short by a weaker one.

local G = require("game")
local X = { enabled = function() return false end, clock = os.clock, random = math.random }
local read_u32, read_f32 = wml.read_u32, wml.read_f32

X.SETS = {
  pain = { "Juiced_pain", "Juiced_pain_b", "Juiced_pain_c", "Juiced_angry" },   -- (Juiced_angry is Angry 2)
  fire = { "Juiced_surprised", "Juiced_scared" },
  death = { "Juiced_death", "Juiced_death_b" },
  liquor = { "Juiced_inebriated" },
  smoke = { "Juiced_mellow" },
  shoot = { "Juiced_sneer" },
  heavy = { "Angry" },                  -- shotgun and RPG shots: Angry 1 (the game's own Angry)
  insane = { "Juiced_insane" },         -- now and then on an RPG shot or a molotov throw
  melee = { "Angry", "Juiced_disgusted" },   -- after a melee attack: Angry 1 and Disgusted in turn
  low_health = { "Juiced_fearful" },    -- (a quarter of the time one of the Pain faces instead)
  drunk = { "Juiced_smarmy" },          -- drunk: while throwing up
  cough = { "Juiced_mellow" },          -- coughing after smoking
}
X.RANK = { death = 5, fire = 4, pain = 3, liquor = 2, smoke = 2, drunk = 2, cough = 2, shoot = 1, heavy = 1, insane = 1, melee = 2, low_health = 0 }
X.INSANE = 0.12     -- (chance of Insane on an RPG shot or a molotov)
X.CYCLE = 1.5       -- (seconds per face while the melee stance lasts)
-- How long each face lasts. Pain: every hit restarts it, so it ends just after the
-- last one. Fire: while you burn. Liquor/smoke: while the powerup animation plays.
-- Death: until you're back.
X.TIME = { pain = 0.6, shoot = 1.2, heavy = 1.2, insane = 1.6 }
X.LOW_HEALTH = 0.25
X.GRACE = 0.3       -- (seconds before "still burning / still drinking" is checked)
X.LONGEST = 15      -- (a powerup face never outlasts this, even without a track to watch)
X.burning = function(p) return p ~= 0 and (read_u32(p + 216) & G.BURNING) ~= 0 end
X.track_live = nil  -- (set by features: ctx, p, track -> the action's animation still plays)
-- The powerup actions that start the liquor and smoke faces.
X.ACTIONS = { ["powerup liquor"] = "liquor", ["powerup liquor move"] = "liquor", ["crouch liquor"] = "liquor",
  ["powerup bong"] = "smoke", ["powerup bong move"] = "smoke", ["crouch bong"] = "smoke",
  ["stand Vomit"] = "drunk", ["drunk vomit"] = "drunk", ["stand Cough"] = "cough" }

function X.trigger(kind, track)
  if not X.enabled() or not X.SETS[kind] then return end
  local now = X.clock()
  local c = X.current
  if c and not c.over then
    if X.RANK[c.kind] > X.RANK[kind] then return end
    if c.kind == kind then
      if X.TIME[kind] then c.till = now + X.TIME[kind] end
      if track then c.track, c.done = track, nil end
      return
    end
  end
  local list = X.SETS[kind]
  local name = list[X.random(1, #list)]
  if kind == "melee" then name = list[1] end
  if kind == "low_health" and X.random() < 0.25 then name = X.SETS.pain[X.random(1, 3)] end
  X.current = { kind = kind, name = name, at = now, till = X.TIME[kind] and now + X.TIME[kind], track = track }
end

-- The face to show now over your own, or nil.
function X.face(p)
  local c = X.current
  if not c then return nil end
  local now = X.clock()
  local over
  if c.kind == "death" then over = p ~= 0 and read_f32(p + G.P.HEALTH) > 0
  elseif c.kind == "fire" then over = now - c.at >= X.GRACE and not X.burning(p)
  elseif c.kind == "liquor" or c.kind == "smoke" or c.kind == "melee" or c.kind == "drunk" or c.kind == "cough" then
    over = c.done or now - c.at >= X.LONGEST
    if c.kind == "melee" then c.name = X.SETS.melee[1 + math.floor((now - c.at) / X.CYCLE) % 2] end
  elseif c.kind == "low_health" then
    local maximum=p~=0 and read_u32(p+G.P.HEALTH_MAX) or 0
    over=p==0 or maximum<=0 or read_f32(p+G.P.HEALTH)<=0 or read_f32(p+G.P.HEALTH)/maximum>X.LOW_HEALTH
  else over = now >= c.till end
  if over then c.over = true; X.current = nil return nil end
  return c.name
end

-- The equipped weapon's name (weapon record name, lower case), or "".
function X.weapon(p)
  local item = read_u32(p + G.P.EQUIPPED)
  local ammo = G.pointer_ok(item) and read_u32(item + 16) or 0
  local info = G.pointer_ok(ammo) and read_u32(ammo + 8) or 0
  local np = G.pointer_ok(info) and read_u32(info) or 0
  if not G.pointer_ok(np) then return "" end
  local s = {}
  for k = 0, 31 do local b = wml.read_u8(np + k) if b == 0 then break end s[#s + 1] = string.char(b) end
  return table.concat(s):lower()
end

local function clip_of(p)
  local item = read_u32(p + G.P.EQUIPPED)
  local ammo = G.pointer_ok(item) and read_u32(item + 16) or 0
  return G.pointer_ok(ammo) and read_u32(ammo + 16) or nil
end

-- Every update: hurt, dead, burning, firing, and whether the powerup still plays.
function X.update(p, ctx)
  if p == 0 or not X.enabled() then X.last = nil return end
  X.face(p) -- End completed higher-priority reactions before choosing a new one.
  local hp, clip = read_f32(p + G.P.HEALTH), clip_of(p)
  local L = X.last
  if L and L.p == p then
    if hp <= 0 and L.hp > 0 then X.trigger("death")
    elseif hp > 0 and hp < L.hp - 0.5 then X.trigger("pain") end
    if hp > 0 and clip and L.clip and clip < L.clip and L.item == read_u32(p + G.P.EQUIPPED) then
      local w = X.weapon(p)
      if (w:find("rpg") or w:find("molotov")) and X.random() < X.INSANE then X.trigger("insane")
      elseif w:find("rpg") or w:find("shotgun") or w:find("spas") then X.trigger("heavy")
      elseif not w:find("molotov") then X.trigger("shoot") end
    end
  end
  if hp > 0 and X.burning(p) then X.trigger("fire") end
  local c = X.current
  if c and c.track and X.track_live and ctx and not X.track_live(ctx, p, c.track) then c.done = true end
  X.face(p)
  local maximum=read_u32(p+G.P.HEALTH_MAX)
  if hp>0 and maximum>0 and hp/maximum<=X.LOW_HEALTH and not X.current then X.trigger('low_health') end
  X.last = { p = p, hp = hp, clip = clip, item = read_u32(p + G.P.EQUIPPED) }
end

-- A line you say (SAY_LINE): your fire scream.
function X.said(situation) if situation == 71 then X.trigger("fire") end end
-- An action you play (the powerups); `track` is its animation track (human+760).
function X.action(name, track) local k = X.ACTIONS[name] if k then X.trigger(k, track) end end
function X.reset() X.current, X.last = nil, nil end

return X
