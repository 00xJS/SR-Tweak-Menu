-- A long hold toggles once; a short tap is delivered on release. The game
-- never sees the beginning of the hold (Back would otherwise open its map).
local H = {}
function H.new(seconds)
  return { seconds = seconds }
end
function H.update(h, down, now, eligible, menu_open)
  if not eligible then
    h.started, h.fired, h.tap = nil, nil, nil
    h.blocked = down -- release before rearming after a pause/disconnect
    return false, false, down and menu_open
  end
  if h.blocked then
    if not down then h.blocked = nil end
    return false, false, down
  end
  if down then
    if not h.started then h.started, h.tap = now, not menu_open end
    if not h.fired and now - h.started >= h.seconds then
      h.fired = true
      return true, false, true
    end
    return false, false, true
  end
  local tap = h.started ~= nil and not h.fired and h.tap and not menu_open
  h.started, h.fired, h.tap = nil, nil, nil
  return false, tap, false
end
return H
