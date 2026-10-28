-- SR Tweak Menu - your mouth moves while you talk, as Saints Row 2 does outside
-- cutscenes (its Mouth_Fluctuation: no per-line lipsync, a running blend of mouth
-- shapes for as long as the line plays). Started by your own lines (SAY_LINE:
-- voice reactions, Play Sample, the game's own taunts). The shapes are SR2-style ones
-- made with SR2's face joints, played through the private face and facial-piece libraries
-- (juiced_runtime), so beards and moustaches move with the mouth.

local T = { clock = os.clock, random = math.random, LENGTH = 1.6, FADE = 0.15 }
-- SR2-style speech shapes made with SR2's face joints on the SR1 rig (fit/rig_v2.py TALK, baked into
-- every face and facial-piece bank as 'srt_talk_<name>'): EH, EE, mid, AH, OO, O.
T.SHAPES = { 0xE35CCF68, 0x9DEDB3D5, 0x1E5D701D, 0x87300A6C, 0x87D7B241, 0xDF1193FE }
T.CLOSED = 0.18          -- (share of beats with the lips together: consonants, pauses)

function T.start(seconds)
  local now = T.clock()
  T.till = math.max(T.till or 0, now + (seconds or T.LENGTH))
  if not T.beat_end or T.beat_end < now then T.beat_end = now end
  T.cur = T.cur or {}
end
function T.stop() T.till, T.beat_end, T.cur, T.goal, T.at = nil, nil, nil, nil, nil end
function T.active() return T.till ~= nil end

-- Advance once per update: pick the next syllable, ease the blend toward it.
function T.update()
  if not T.till then return end
  local now = T.clock()
  if now >= T.till + T.FADE then T.stop() return end
  if now >= T.beat_end then
    T.goal = {}
    if now < T.till and T.random() > T.CLOSED then
      T.goal[T.SHAPES[T.random(1, #T.SHAPES)]] = 0.45 + 0.45 * T.random()
    end
    T.beat_end = now + 0.09 + 0.07 * T.random()
  end
  local dt = math.min(0.1, now - (T.at or now)); T.at = now
  local k = 1 - math.exp(-dt / 0.05)
  for _, h in ipairs(T.SHAPES) do
    local c = T.cur[h] or 0
    T.cur[h] = c + ((T.goal and T.goal[h] or 0) - c) * k
  end
end

-- Commands for one library (a bank from juiced_runtime with .native hash -> index).
function T.commands(bank)
  if not T.cur or not bank or not bank.native then return nil end
  local out = {}
  for _, h in ipairs(T.SHAPES) do
    local w, k = T.cur[h] or 0, bank.native[h]
    if k and w > 0.02 then out[#out + 1] = { id = bank.id, target = k, weight = math.floor(math.min(1, w) * 255) } end
  end
  return #out > 0 and out or nil
end

return T
