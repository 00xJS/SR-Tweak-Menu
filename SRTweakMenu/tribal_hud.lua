-- Optional health/sprint/weapon layout. The native HUD still computes its
-- fades, pulses, weapon icon and formatted ammo. Only its cluster's drawing
-- is intercepted; no HUD visibility flags or player state are written.
local G, UI = require("game"), require("gameui")
local FONT=require("hud_font")
local RESERVE_FONT=require("hud_font_reserve")
local paint_alpha=require("hud_paint_alpha")
local C,M=require("hud_settings"),require("hud_motion")
local H = { enabled = function() return false end, input = function() return {} end, failed = false }
local W = require("tribal_wheel")
local N=require("native_hud")
W.enabled = function() return H.enabled() and not H.failed end
M.enabled = function() return H.enabled() and not H.failed and not G.screen_up() and not G.in_cutscene() and not G.in_front_end() end
local r16, r32, rf = wml.read_u16, wml.read_u32, wml.read_f32
H.ADDR = {
  pass = 0x822E1508, health = 0x822DD100, respect = 0x822DDF30,
  sprint = 0x822E08F0, icons = 0x822DCF10, weapon = 0x822DD428,
  after_cluster = 0x822DCB30, bitmap = 0x8227FBC8, arc = 0x8227F750,
  respect_arc = 0x8227EDB0, respect_text = 0x822E1F80, text = 0x8251D450,
}
H.ASSETS = { "srt_slate_digits",  "srt_brush_left", "srt_brush_right", "hud_act_bar_bg", "hud_act_bar_fill", "hud_act_box_c", "hud_act_box_tr",
  "hud_act_ornate_top", "hud_act_ornate_bottom_left", "hud_act_ornate_bottom_right",
  "hud_health_ico_health", "hud_health_ico_saints", "px_swatch_color", "ui_hud_infinity" }
H.LAYOUT = { x = 1015.56, y = 590.55, width = 226.44, height = 99.45, scale = .765, segments = 4 }

local function clamp(n, lo, hi)
  if type(n) ~= "number" or n ~= n then return lo end
  return math.max(lo, math.min(hi, n))
end
function H.health_threshold()
  -- gameplay_constants/player_health/low_health_threshold_pct, loaded by
  -- 821BD688 into the same value used by the native warning sound.
  local n = rf(0x838F8420)
  return n > 0 and n < 1 and n or .25
end
function H.note_combat(player)
  if H.enabled() then H.activity={player=player,until_time=os.clock()+3} end
end
function H.note_health_beat(now,player,echo)
  local b=H.beat
  local interval=b and b.player==player and now-b.at or nil
  H.beat={at=now,player=player,audible_until=now+(echo and 2.64 or 1.32),period=interval and interval>.3 and interval<1.6 and interval or nil}
end
G.hud_health_beat=function(echo) H.note_health_beat(os.clock(),G.player(),echo) end

function H.sprint_threshold()
 -- PantPercentage from metered_sprint.xtbl, converted by the native loader
 -- to an energy threshold. Compare normalised fill while energy drains too.
 local threshold,full=rf(0x8309ABD0),rf(0x8309ABDC)
 if full>0 and threshold>0 and threshold<full then return threshold/full end
 return .25
end
local function ease(t) t=clamp(t,0,1);return t*t*(3-2*t) end
function H.glow(s,id)
  local health=id=="health"
  local limit=health and (s.low_health or H.health_threshold()) or (s.sprint_threshold or H.sprint_threshold())
  local fraction=health and (s.health or 1) or (s.sprint or 1)
  local severity=clamp(1-fraction/limit,0,1)
  local period=health and (1-.5*severity) or (1.4-.95*severity)
  local phase=health and s.health_phase or s.sprint_phase
  phase=phase or (s.time or 0)/period
  local pulse=(.5+.5*math.cos(phase*math.pi*2))^3
  if health and s.health_beat_age and s.health_beat_age>=0
    and s.health_beat_age<math.max(.35,s.health_beat_period or period)*1.6 then
    -- The original warning submission is the beat. Echo requests never
    -- reach this signal. No free-running oscillator competes with the audio.
    pulse=math.exp(-math.max(0,s.health_beat_age)/(math.max(.35,s.health_beat_period or period)*.20))
  end
  if health and s.health_recovering then
    -- Complete the submitted sound's tail; never invent another oscillator
    -- beat after the player leaves low health.
    pulse=s.health_beat_age and math.exp(-math.max(0,s.health_beat_age)/(math.max(.35,s.health_beat_period or period)*.20)) or 0
  end
  local gain=health and s.health_glow or s.sprint_glow
  gain=gain==nil and 1 or gain
  return {pulse=pulse*gain,period=period,opacity=(44+24*severity+(70+50*severity)*pulse)*gain}
end

-- Actual rendered camera direction, so mouse, pad, inversion and follow
-- camera all work. No mouse/stick input is consumed by this feature.
function H.camera_pose(player,now,fx,fy,fz)
  local norm=math.sqrt(fx*fx+fy*fy+fz*fz)
  if norm<.2 or norm>2 or norm~=norm then H.camera=nil; return 0,0 end
  local yaw,pitch=math.atan(fx,fz),math.asin(clamp(fy/norm,-1,1))
  local c=H.camera
  if not c or c.player~=player or now-c.at>.25 then
    H.camera={player=player,at=now,yaw=yaw,pitch=pitch,x=0,y=0};return 0,0
  end
  local dt=now-c.at
  if dt<=0 then return c.x,c.y end
  local dyaw=math.atan(math.sin(yaw-c.yaw),math.cos(yaw-c.yaw))
  local dp=pitch-c.pitch
  local tx,ty=0,0
  if math.abs(dyaw)<.45 and math.abs(dp)<.4 then
    tx,ty=clamp(dyaw/dt*.30,-1,1),clamp(dp/dt*.30,-1,1)
  end
  local blend=1-math.exp(-dt*10)
  c.x,c.y=c.x+(tx-c.x)*blend,c.y+(ty-c.y)*blend
  c.at,c.yaw,c.pitch=now,yaw,pitch
  return c.x,c.y
end

-- Presentation state only. No inventory, controls, HUD flags or native
-- wheel state is written. Time is injected for deterministic regression tests.
function H.update(s, now)
  local m = H.motion
  if not m or m.player ~= s.player or (m.health <= 0 and s.health > 0) then
    m = { player = s.player, health = s.health, sprint = s.sprint, armed = s.armed,
      x = s.x, z = s.z, visible_until = -1, alpha = s.armed and 1 or 0, clock = now-.02 }
    H.motion = m
  end
  local dt = clamp(now - m.clock, 0, .1)
  local hurt = s.health < m.health - .0001
  local running = s.sprint < m.sprint - .0001 or (s.sprint < .999 and s.sprinting)
  if hurt or running or s.attacking then m.visible_until = now + 3 end
  if s.impact_active then m.visible_until=math.max(m.visible_until,now+1) end
  if m.armed and not s.armed then m.wait_for_walk = true; m.x, m.z = s.x, s.z end
  if m.wait_for_walk and s.on_foot and s.x and m.x and ((s.x-m.x)^2+(s.z-m.z)^2 > .16) then
    m.wait_for_walk = false
  end
  if s.armed then m.wait_for_walk = false end
  local health_low=s.health>0 and s.health<=(s.low_health or H.health_threshold())
  local sprint_low=s.health>0 and (s.exhausted==true or s.sprint<=(s.sprint_threshold or H.sprint_threshold()))
  if s.health<=0 then m.health_glow,m.sprint_glow=0,0;H.beat=nil end
  if health_low then m.health_glow=1;m.health_release=nil
  elseif (m.health_glow or 0)>0 then
    local tail=H.beat and H.beat.player==s.player and H.beat.audible_until or (m.health_release or now)
    m.health_release=math.max(m.health_release or now,tail or now)
    m.health_glow=1-ease((now-m.health_release)/.65)
  end
  if sprint_low then m.sprint_glow=1;m.sprint_release=nil
  elseif (m.sprint_glow or 0)>0 then
    m.sprint_release=m.sprint_release or now
    m.sprint_glow=1-ease((now-m.sprint_release)/.65)
  end
  s.health_glow,s.sprint_glow=m.health_glow or 0,m.sprint_glow or 0
  s.health_warning,s.sprint_warning=s.health_glow>0,s.sprint_glow>0
  s.health_recovering=not health_low
  m.health_phase=(m.health_phase or 0)+dt/H.glow(s,"health").period
  m.sprint_phase=(m.sprint_phase or 0)+dt/H.glow(s,"sprint").period
  s.health_phase,s.sprint_phase=m.health_phase,m.sprint_phase
  if H.beat and H.beat.player==s.player then
    s.health_beat_age,s.health_beat_period=now-H.beat.at,H.beat.period
  end
  if not s.health_warning then H.beat=nil end
  local respect=tonumber(s.respect_text)
  if respect and respect>=0 and respect<1e9 then
    if m.respect and respect>m.respect and now-m.clock<=.5 and s.health>0 then
      m.respect_change={from=tostring(m.respect),at=now}
      m.visible_until=math.max(m.visible_until,now+2)
    elseif m.respect and respect<m.respect then m.respect_change=nil end
    m.respect=respect
  end
  s.respect_from,s.respect_progress,s.respect_shine=nil,nil,nil
  if not C.values.motion then m.respect_change=nil end
  local change=m.respect_change
  if change and (now-change.at<0 or now-change.at>=1.6 or s.health<=0) then m.respect_change=nil;change=nil end
  if change and C.values.motion then
    local age=now-change.at
    s.respect_shine=age/1.6
    if age<.75 then s.respect_from=change.from;s.respect_progress=age/.75 end
  end
  local visible = s.armed or m.wait_for_walk or hurt or running or s.attacking
    or s.health_warning or s.sprint_warning or s.sprint < .999 or now < m.visible_until
    or (H.activity and H.activity.player==s.player and now<H.activity.until_time)
  if s.armed then m.alpha=1
  elseif visible then m.alpha = math.min(1,m.alpha+dt*4)
  else m.alpha = math.max(0, m.alpha - dt * 4) end
  s.visibility = m.alpha
  local clip = H.ammo(s.ammo_text)
  local n = clip and clip.text and tonumber(clip.text)
  if s.weapon_icon~=m.icon or not n then m.shot,m.reloaded=nil,nil end
  if n and m.clip and s.weapon_icon == m.icon then
    if n < m.clip then m.shot = now elseif n > m.clip then m.reloaded = now end
  end
  s.shot = m.shot and clamp(1-(now-m.shot)/.16,0,1) or 0
  s.reloaded = m.reloaded and clamp(1-(now-m.reloaded)/.28,0,1) or 0
  s.time = now
  m.health, m.sprint, m.armed, m.clock = s.health, s.sprint, s.armed, now
  m.clip, m.icon = n, s.weapon_icon
  return s
end
function H.ratio(value, empty, full, fallback)
  if value ~= value or empty ~= empty or full ~= full or full <= empty then return fallback or 0 end
  return clamp((value - empty) / (full - empty), 0, 1)
end

-- Keep the game's own ammo rules. Melee has no line; thrown weapons use a
-- single total; guns use clip/reserve; infinite ammo is a native image tag.
function H.ammo(text)
  if not text or text == "" then return nil, nil end
  local clip, reserve = text:match("^%s*(.-)%s*/%s*(.-)%s*$")
  clip = clip or text:match("^%s*(.-)%s*$")
  local function line(s)
    if not s or s == "" then return nil end
    if s:find("ui_hud_infinity", 1, true) then return { infinite = true } end
    if not s:match("^%d+$") then return nil end
    return { text = #s < 2 and ("0" .. s) or s }
  end
  return line(clip), line(reserve)
end
function H.weapon_data(player)
  local item=r32(player+G.P.EQUIPPED)
  if not G.pointer_ok(item) then return {} end
  local ammo=r32(item+16)
  if not G.pointer_ok(ammo) then return {} end
  local info=r32(ammo+8)
  if not G.pointer_ok(info) then return {} end
  local nameptr=r32(info);local chars={}
  if G.pointer_ok(nameptr) then for i=0,47 do
    local n=wml.read_u8(nameptr+i);if n==0 then break end
    if n<32 or n>126 then break end;chars[#chars+1]=string.char(n)
  end end
  local name=table.concat(chars)
  return {capacity=r16(info+104),maximum=r16(info+106),
    single=r32(info+100)==2 or name=="rpg_launcher" or name=="rpg_laser"}
end
function H.ammo_warning(s)
  local clip,reserve=H.ammo(s.ammo_text)
  if not clip or clip.infinite then return false,false end
  local n=tonumber(clip.text);local spare=reserve and tonumber(reserve.text)
  if not n then return false,false end
  local info=s.weapon_data or {}
  if info.single or not reserve then return n+(spare or 0)<=1,false end
  local mag=info.capacity or 0
  local low=n==0 or (mag>1 and n<=math.max(1,math.floor(mag*.25)))
  local most=info.maximum or 0
  local low_total=spare~=nil and (spare==0 or (most>0 and n+spare<=math.max(1,math.floor(most*.1))))
  return low or low_total,low_total
end
local function native_text(ptr)
  if not G.pointer_ok(ptr) then return nil end
  local chars = {}
  for i = 0, 95 do
    local c = r16(ptr + i * 2)
    if c == 0 then return table.concat(chars) end
    -- The native ammo and respect formatters emit ASCII numbers/image tags.
    if c < 32 or c > 126 then return nil end
    chars[#chars + 1] = string.char(c)
  end
end
for n=0,9 do H.ASSETS[#H.ASSETS+1]="srt_reserve_"..n;H.ASSETS[#H.ASSETS+1]="srt_ammo_"..n end
for n=0,3 do H.ASSETS[#H.ASSETS+1]="srt_respect_"..n end
function H.ready(ctx)
  if not UI.ready() then return false end
  for _, name in ipairs(H.ASSETS) do
    if not UI.bitmap_ready(UI.bitmap(ctx, name)) then return false end
  end
  return true
end

-- Pure drawing list, in the same 1280 x 720 units as the native interface.
-- Bars fill continuously within each segment, preserving fractional health.
function H.build(ctx, state)
  local L, ops = H.LAYOUT, {}
  local x, y, alpha = 0, 0, clamp(state.alpha or 1, 0, 1)
  local function col(rgb, a) return { rgb[1], rgb[2], rgb[3], math.floor((a or 255) * alpha + 0.5) } end
  local painted, white = { 128, 128, 128 }, { 128, 128, 128 }
  local function image(name, px, py, w, h, colour, extra)
    local op = { image = name, x = px, y = py, w = w, h = h, colour = col(colour or painted) }
    if extra then for k, v in pairs(extra) do op[k] = v end end
    ops[#ops + 1] = op
    return op
  end
  local function panel(px, py, w, h, rgb, opacity, skew)
    return image("px_swatch_color", px, py, w, h, rgb, {
      part = { 10, 8, 26, 14 }, colour = col(rgb, opacity),
      points = { { px + (skew or 0), py }, { px + w, py }, { px, py + h }, { px + w - (skew or 0), py + h } },
    })
  end
  -- Feather alpha at every outside edge instead of placing a hard rectangle
  -- behind each segment. The centre stays faint, including at the pulse peak.
  local function soft_rect(px,py,w,h,rgb,opacity,feather,tag)
    local xs,ys={px-feather,px,px+w,px+w+feather},{py-feather,py,py+h,py+h+feather}
    local function corner(i,j) return col(rgb,(i==1 or i==4 or j==1 or j==4) and 0 or opacity) end
    for j=1,3 do for i=1,3 do
      image("px_swatch_color",xs[i],ys[j],xs[i+1]-xs[i],ys[j+1]-ys[j],rgb,{
        part={10,8,26,14},tag=tag,colour=col(rgb,opacity),
        colours={corner(i,j),corner(i+1,j),corner(i,j+1),corner(i+1,j+1)} })
    end end
  end
  local reserve_colours
  local function text(s, px, py, height, rgb, center, max_width, tag, warning, opacity, paint_ink)
    opacity=opacity or 1
    local small=tag=="reserve_digit" or tag=="respect_digit" or tag=="respect_previous"
    local metrics=small and RESERVE_FONT or FONT
    local atlas=small and (paint_ink and "srt_ammo_" or "srt_reserve_") or "srt_slate_digits"
    local width,top,bottom=0,32,0
    for i=1,#s do
      local b=metrics[tonumber(s:sub(i,i))]
      if b then width=width+b[3]-b[1];top=math.min(top,b[2]);bottom=math.max(bottom,b[4]) end
    end
    local scale=height/math.max(1,bottom-top)
    local gap=2
    local span=width*scale+math.max(0,#s-1)*gap
    if max_width and span>max_width then
      scale=scale*max_width/span;gap=gap*max_width/span;span=max_width
    end
    local left=center and px-span/2 or px
    local start=left
    if warning then
      local pulse=.5+.5*math.cos((state.time or 0)*math.pi*3)
      soft_rect(left,py-height/2,span,height,{128,5,8},(38+48*pulse)*opacity,5,"ammo_warning")
      if not paint_ink then rgb={128,math.floor(24+12*pulse),math.floor(24+12*pulse)} end
    end
    for i = 1, #s do
      local n = tonumber(s:sub(i,i))
      if n then
        local b=metrics[n]
        local gx,gy,gw,gh=left-b[1]*scale,py-(top+bottom)/2*scale,24*scale,32*scale
        image(small and (atlas..n) or atlas,gx,gy,gw,gh,rgb or painted,
          {colour=col(rgb or painted,255*opacity),colours=paint_ink and reserve_colours(gx,gy,gw,gh,opacity) or nil,part={small and 0 or n%5*24,small and 0 or math.floor(n/5)*32,24,32},tag=tag or "number",number=i==1 and s or nil,
           ink={left,py-(bottom-top)*scale/2,(b[3]-b[1])*scale,(bottom-top)*scale}})
        left=left+(b[3]-b[1])*scale+gap
      end
    end
    return start,span
  end
  local function bar(value, py, first, last, id, warning)
    local bx, total, gap = x + 25, 268, 3
    local sw = (total - gap * (L.segments - 1)) / L.segments
    local t = clamp(value or 0, 0, 1) * L.segments
    soft_rect(bx+.7,py+1.8,total,8,{0,0,0},38,2.8,id.."_shadow")
    local light=H.glow(state,id)
    local pulse=warning and light.pulse or 0
    if warning then
      soft_rect(bx,py,total,9,first,light.opacity*.35,8,id.."_warning")
      soft_rect(bx,py,math.max(16,total*clamp(value or 0,0,1)),9,first,light.opacity,8,id.."_warning")
    end
    for i = 0, L.segments - 1 do
      local xx = bx + i * (sw + gap)
      -- Thin black edge sits above the soft shadow, beneath the actual meter.
      panel(xx-.55,py-.55,sw+1.1,10.1,{0,0,0},190,2)
      ops[#ops].tag=id.."_stroke"
      image("hud_act_bar_bg", xx, py, sw, 9, painted, { tag = id .. "_empty", points = {
        { xx + 2, py }, { xx + sw, py }, { xx, py + 9 }, { xx + sw - 2, py + 9 } } })
      local filled = clamp(t - i, 0, 1)
      if filled > 0 then
        local a, b = (i / L.segments), ((i + filled) / L.segments)
        local function mix(k) return { first[1] + (last[1] - first[1]) * k,
          first[2] + (last[2] - first[2]) * k, first[3] + (last[3] - first[3]) * k } end
        local ca, cb = col(mix(a)), col(mix(b))
        for k=1,3 do ca[k]=math.min(128,ca[k]+pulse*12); cb[k]=math.min(128,cb[k]+pulse*12) end
        for k = 1, 3 do ca[k], cb[k] = math.floor(ca[k] + 0.5), math.floor(cb[k] + 0.5) end
        local da, db = {ca[1]*.62,ca[2]*.62,ca[3]*.62,ca[4]}, {cb[1]*.62,cb[2]*.62,cb[3]*.62,cb[4]}
        for k=1,3 do da[k],db[k]=math.floor(da[k]),math.floor(db[k]) end
        image("hud_act_bar_fill", xx, py, sw * filled, 9, painted, { tag = id .. "_fill", fraction = filled,
          part = { 0, 0, 205 * filled, 6 }, colours = { ca, cb, da, db }, points = {
            { xx + 2, py }, { xx + 2 + (sw - 2) * filled, py },
            { xx, py + 9 }, { xx + (sw - 2) * filled, py + 9 } } })
        image("px_swatch_color",xx+2,py+.15,(sw-2)*filled,3.7,painted,{
          part={10,8,26,14},tag=id.."_highlight",colours={col(painted,112),col(painted,112),col(painted,0),col(painted,0)},
          points={{xx+2,py+.15},{xx+2+(sw-2)*filled,py+.15},
            {xx+1.15,py+3.85},{xx+1.15+(sw-2)*filled,py+3.85}} })
        -- Crisp reflected rim and a restrained lower reflection leave colour
        -- visible through the wider upper gloss gradient.
        panel(xx+2,py+.35,(sw-2)*filled,.5,painted,105,.1).tag=id.."_gloss_rim"
        panel(xx+.6,py+6.8,(sw-2)*filled,.65,painted,23,.15).tag=id.."_gloss_lower"
      end
    end
  end

  image("hud_act_ornate_top", x + 27, y, 264, 25,painted,{colour=col(painted,235),tag="tribal"})
  bar(state.sprint, y + 22, { 128, 78, 0 }, { 128, 117, 31 }, "sprint", state.sprint_warning)
  local red = state.health_tint or { 105, 0, 0 } -- native health draw: RGB 210,0,0
  bar(state.health, y + 37, {math.min(128,red[1]+20),red[2]+7,red[3]+7}, red, "health", state.health_warning)
  image("hud_health_ico_health", x + 3, y + 32, 19, 21)

  -- Dark weapon panel with Saints purple on the ammo side. Its slight lean
  -- follows the reference; the ornaments/corners are the game's activity HUD.
  -- More visible tribal silhouette beneath the panel, with transparent tips.
  image("hud_act_ornate_bottom_left",x-1,y+102,173,34,painted,{colour=col(painted,235),tag="tribal"})
  image("hud_act_ornate_bottom_right",x+167,y+102,134,34,painted,{colour=col(painted,235),tag="tribal"})
  panel(x + 3, y + 53, 292, 58, { 5, 5, 5 }, 228, 10)
  local paint_layers={}
  local function brush(px,py,w,h,rgb,opacity)
    paint_layers[#paint_layers+1]={px,py,w,h,rgb,opacity}
    for i,name in ipairs({"srt_brush_left","srt_brush_right"}) do
      image(name,px+(i-1)*w/2-(i==2 and .6 or 0),py,w/2+.6,h,rgb,{part={.5,.5,63,63},colour=col(rgb,opacity),tag="brush"})
    end
  end
  -- Follow the real paint coverage, including the light bristles and the
  -- empty/reload overlay. Tint the ink in that hue instead of fading white.
  reserve_colours=function(px,py,w,h,opacity)
    local function tint(xx,yy)
      local rgb={5,5,5}
      for _,layer in ipairs(paint_layers) do
        local lx,ly,lw,lh,c,a=table.unpack(layer)
        for i=1,2 do
          local bx=lx+(i-1)*lw/2-(i==2 and .6 or 0)
          local u,v=(xx-bx)/(lw/2+.6),(yy-ly)/lh
          local coverage=paint_alpha(i,u,v)*a/255
          for k=1,3 do rgb[k]=rgb[k]*(1-coverage)+c[k]*coverage end
        end
      end
      -- Keep the sampled hue, with enough coloured ink to read on dark paint.
      local gain=math.min(1.75,128/math.max(1,table.unpack(rgb)))
      for k=1,3 do rgb[k]=math.floor(rgb[k]*gain+.5) end
      return col(rgb,255*opacity)
    end
    return {tint(px,py),tint(px+w,py),tint(px,py+h),tint(px+w,py+h)}
  end
  -- Every purple pixel comes from the supplied ABR alpha silhouette.
  -- Offset lighter paint remains exposed around the dark stroke's bristles.
  local clip,reserve=H.ammo(state.ammo_text)
  if clip then
    brush(x+144,y+52,155,65,{85,51,110},242)
    brush(x+145,y+51,149,63,{42,16,64},255)
  end
  -- Four atlas tiles share real neighbouring texels in their gutters, so
  -- the tiny chrome emblem has no seams. Only its internal shine animates.
  local ix,iy,size=x+14,y+71,22
  for row=0,1 do for column=0,1 do
    image("srt_respect_"..(row*2+column),ix+column*size/2,iy+row*size/2,size/2,size/2,painted,{tag="respect_symbol"})
  end end
  local shine=state.respect_shine
  if C.values.motion and shine and shine>=0 and shine<1 then
    local cycle=(shine*2)%1
    local centre=-.25+cycle*1.5
    local envelope=1-ease((shine-.7)/.3)
    -- White over a white emblem barely changes its body. A travelling silver
    -- reflection beside the bright core supplies contrast within the alpha.
    for _,band in ipairs({{offset=.15,width=.24,opacity=205,rgb={38,44,54}},
                         {offset=0,width=.18,opacity=250,rgb={255,255,255}}}) do
      local function light(u,v)
        local coordinate=(1-v)*.8+u*.2
        return band.opacity*envelope*clamp(1-math.abs(coordinate-centre-band.offset)/band.width,0,1)^1.5
      end
      for row=0,7 do for column=0,7 do
        local a,b,c,d=light(column/8,row/8),light((column+1)/8,row/8),light(column/8,(row+1)/8),light((column+1)/8,(row+1)/8)
        if math.max(a,b,c,d)>.5 then
          image("srt_respect_"..(math.floor(row/4)*2+math.floor(column/4)),ix+column*size/8,iy+row*size/8,size/8,size/8,white,{
            part={(column%4)*8,(row%4)*8,8,8},tag="respect_symbol_shine",
            colours={col(band.rgb,a),col(band.rgb,b),col(band.rgb,c),col(band.rgb,d)} })
        end
      end end
    end
  end

  if state.respect_text and state.respect_text:match("^%d+$") then
    local t=state.respect_progress
    if C.values.motion and t and state.respect_from then
      local mix=ease(t/.55)
      local settle=1-(1-t)^3
      if mix<1 then text(state.respect_from,x+40,y+83-t*5,13,white,false,32,"respect_previous",false,1-mix) end
      text(state.respect_text,x+40,y+83+(1-settle)*6,13*(1+.14*math.sin(t*math.pi)),white,false,32,"respect_digit",false,mix)
    else text(state.respect_text,x+40,y+83,13,white,false,32,"respect_digit") end
  end
  if state.weapon_icon and UI.bitmap_ready(state.weapon_icon) then
    ops[#ops + 1] = { bitmap = state.weapon_icon, x = x + (clip and 75 or 112), y = y + 55, w = 72, h = 55, colour = col(painted), tag = "weapon" }
  end
  local low_clip,low_reserve=H.ammo_warning(state)
  local function ammo_line(line, px,py,height,tag,center,warning)
    if not line then return end
    local paint_ink=tag=="reserve_digit" and not (state.weapon_data and state.weapon_data.single)
    local opacity=paint_ink and .6 or 1
    if line.infinite then
      image("ui_hud_infinity",px-height*.615,py-height/2,height*1.23,height,painted,{colour=col(painted,255*opacity),colours=paint_ink and reserve_colours(px-height*.615,py-height/2,height*1.23,height,opacity) or nil,tag=tag.."_infinity"})
      return px-height*.615
    end
    return text(line.text,px,py,height,painted,center,86,tag,warning,opacity,paint_ink)
  end
  if clip and clip.text=="00" then
    local empty = reserve and reserve.text=="00"
    local pulse=.5+.5*math.sin((state.time or 0)*math.pi*3)
    brush(x+145,y+51,149,63,empty and {101,8,16} or {72,29,94},70+65*pulse)
  elseif clip and (state.reloaded or 0)>0 then
    brush(x+145,y+51,149,63,{104,76,127},80*state.reloaded)
  end
  if reserve then
    local left=ammo_line(clip,x+222,y+72,22,"clip_digit",true,low_clip)
    ammo_line(reserve,left or x+205,y+97,11,"reserve_digit",false,low_reserve)
  else ammo_line(clip,x+222,y+82,23,"clip_digit",true,low_clip) end
  -- One transform for the whole HUD. No part has its own depth/recoil
  -- translation: bars, art, weapon, Saints icon and digits remain attached.
  local moving=C.values.motion
  local sensitivity=C.values.camera/100
  local hx=moving and clamp(state.camera_x or 0,-1,1)*sensitivity or 0
  local hy=moving and clamp(state.camera_y or 0,-1,1)*sensitivity or 0
  local k=1+hy*.006
  local dx=moving and (state.impact_x or 0) or 0
  local dy=moving and (state.impact_y or 0) or 0
  local function position(px,py)
    return L.x+((px-148)*k+148-hx*3+dx)*L.scale,
      L.y+((py-70)*k+70-hy*2+dy)*L.scale
  end
  for _,op in ipairs(ops) do
    op.x,op.y=position(op.x,op.y)
    op.w,op.h=op.w*k*L.scale,op.h*k*L.scale
    if op.points then for _,p in ipairs(op.points) do p[1],p[2]=position(p[1],p[2]) end end
  end
  return ops
end

local R,D=require('hud_reactions'),require('hud_death')
local death={}
local current, scope
local function enabled()
  if H.unavailable then return false end
  return H.enabled() and not H.failed and UI.ok and G.player() ~= 0
    and not G.in_front_end() and not G.in_cutscene() and not G.screen_up()
end
R.enabled=enabled
G.hud_blast_reveal=function() H.note_combat(G.player()) end
function H.tick()
  local now=os.clock()
  C.flush(now)
  if not enabled() then M.reset();R.reset();death={};return end
  R.tick(now)
  M.tick(G.player(),now)
end
function H.note_impact(victim,attacker,damage)
  if enabled() then
    M.car_hit(victim,attacker,damage,os.clock());M.combat_hit(victim,attacker,damage,os.clock())
  end
end
function H.sample(state)
  local p=state.player
  state.handle=r32(p+68)
  state.health = H.ratio(rf(p + G.P.HEALTH), 0, r32(p + G.P.HEALTH_MAX))
  state.sprint = H.ratio(rf(G.SPRINT_METER), rf(0x8370E3F0), rf(G.SPRINT_METER_MAX), 1)
  -- Empty native text calls must never override the actual banked levels.
  local full=r32(p+G.P.RESPECT_BAR)
  state.respect_text=tostring(full>0 and math.max(0,math.floor(r32(p+G.P.RESPECT)/full)) or 0)
  state.exhausted=(wml.read_u8(p+3592)&2)~=0
  state.weapon_data=H.weapon_data(p)
  local pad=H.input() or {}
  state.armed=G.pointer_ok(r32(p+G.P.EQUIPPED))
  state.x,state.z=rf(p+G.P.POS),rf(p+G.P.POS+8)
  state.on_foot=not G.vehicle_object(p)
  state.attacking=(pad.rt or 0)>40
  state.sprinting=state.sprint<.999
  local now=os.clock()
  state.camera_x,state.camera_y=H.camera_pose(p,now,rf(G.CAMERA+104),rf(G.CAMERA+108),rf(G.CAMERA+112))
  state.impact_x,state.impact_y=M.offset(now)
  local rx,ry,active=R.offset(now)
  state.impact_x=clamp(state.impact_x+rx,-22,22)
  state.impact_y=clamp(state.impact_y+ry,-22,32)
  state.impact_active=M.active() or active
  H.update(state,now)
  return state
end
local function flush(ctx)
  if not current or current.drawn then return end
  local dead=rf(current.player+G.P.HEALTH)<=0
  if not current.health_seen and not (dead and C.values.death) then return end
  current.drawn = true
  local p = current.player
  if p ~= G.player() then return end
  if N.active() then return end
  H.sample(current)
  local now=os.clock()
  current.alpha=current.alpha*current.visibility
  if current.alpha <= 0 and not dead then return end
  -- 8263E7D8 stores RGBA/255 at +52..64 of the current draw context.
  -- Restore that colour so the following native HUD pieces inherit it.
  local dc = G.call(ctx, 0x8263D818, {})
  local c
  if G.pointer_ok(dc) then
    c = {}
    for i = 1, 4 do c[i] = math.floor(clamp(rf(dc + 48 + i * 4), 0, 1) * 255 + .5) end
  end
  local ok, why = pcall(function()
    local build=function(s) return H.build(ctx,s) end
    local ops
    if C.values.death then ops=D.update(death,current,now,build)
    else death={};ops=build(current) end
    UI.draw(ctx,ops)
  end)
  if c then G.call(ctx, G.DRAW_COLOR, c) end
  if not ok then
    H.failed = true
    wml.log("Tribal HUD: drawing failed; native HUD restored on the next frame: " .. tostring(why))
  end
end
G.hook(H.ADDR.pass, function(ctx)
  UI.draw_overlay(ctx)
  current, scope = nil, nil
  -- Switching off restores the native path immediately, including after a
  -- rendering failure. Missing assets also leave the native circle intact.
  if not H.enabled() then H.failed = false;require("hud_layout").failed=false end
  if not enabled() then H.motion,H.activity,H.camera=nil,nil,nil;M.reset() end
  if enabled() then
    local ok, ready = pcall(function() return N.active() and UI.ready() or (not N.active() and H.ready(ctx)) end)
    if ok and ready and (C.values.death or rf(G.player()+G.P.HEALTH)>0) then
      current = { player = G.player(), alpha = 1 }
      if N.active() then H.sample(current);N.frame={} end
    end
  end
  ctx:call_original()
  -- Native health drawing can stop as soon as death begins. Finish the
  -- latched presentation here even when no health-cluster call occurred.
  if current and rf(current.player+G.P.HEALTH)<=0 and C.values.death then flush(ctx) end
  if current and N.active() then
    local ok,err=pcall(N.finish,ctx,current)
    if not ok then H.failed=true;wml.log("Default HUD death: "..tostring(err)) end
  end
  current, scope = nil, nil
end)
for _, name in ipairs({ "health", "respect", "sprint", "icons", "weapon" }) do
  G.hook(H.ADDR[name], function(ctx)
    if not current then ctx:call_original(); return end
    if name == "health" and ctx:r(3) ~= current.player then
      -- Native spectator/remote-control HUDs may draw a different actor.
      -- Leave those paths entirely native rather than hiding their meters.
      current, scope = nil, nil
      ctx:call_original()
      return
    end
    local previous = scope
    scope = name
    if name == "health" then
      current.health_seen = true
      current.alpha = clamp(ctx:f(1), 0, 1)
      current.player = ctx:r(3)
    end
    if N.active() and current.health<=0 and C.values.death then
      -- Shared death fade draws the latched native background after the pass.
    elseif N.active() then
      local alpha=ctx:f(1);ctx:set_f(1,alpha*(current.visibility or 1))
      local ok,err=pcall(N.scope,ctx,current,function() ctx:call_original() end)
      ctx:set_f(1,alpha)
      if not ok then H.failed=true;wml.log("Default HUD: "..tostring(err)) end
    else ctx:call_original() end
    scope = previous
  end)
end
G.hook(H.ADDR.bitmap, function(ctx)
  if W.bitmap(ctx) then return end
  if current and scope and N.active() then N.capture(ctx,"bitmap",scope,current) end
  if current and scope and not N.active() then
    if scope == "weapon" then current.weapon_icon = ctx:r(3) & 0xFFFF end
    return
  end
  ctx:call_original()
end)
G.hook(H.ADDR.arc, function(ctx)
  if W.arc(ctx) then return end
  if current and scope and N.active() then N.capture(ctx,"arc",scope,current);N.glow(ctx,scope,current) end
  if current and scope and not N.active() then return end
  ctx:call_original()
end)
G.hook(H.ADDR.respect_arc, function(ctx)
  if current and scope and not N.active() then return end
  ctx:call_original()
end)
G.hook(H.ADDR.respect_text, function(ctx)
  if current and scope == "respect" and not N.active() then
    current.respect_text = native_text(ctx:r(3))
    current.respect_seen = current.respect_text ~= nil
    return
  end
  ctx:call_original()
end)
G.hook(H.ADDR.text, function(ctx)
  if current and N.active() and scope=="weapon" then
    current.ammo_text=native_text(ctx:r(5))
    N.ammo(ctx,current,function() ctx:call_original() end);return
  end
  if current and not N.active() and (scope == "weapon" or scope == "respect") then
    local s = native_text(ctx:r(5))
    if scope == "weapon" then current.ammo_text = s else current.respect_text = s end
    return
  end
  ctx:call_original()
end)
G.hook(H.ADDR.after_cluster, function(ctx)
  -- This is the next native call after the five cluster pieces. Draw before
  -- it so notifications, followers, prompts and the tweak menu remain above.
  flush(ctx)
  ctx:call_original()
end)
require("hud_layout").enabled=function() return current~=nil and enabled() end
-- The hooks the HUD can't work without: with one refused (which ones depends
-- on the build of saintsrow.exe) it would hide the game's HUD and draw
-- nothing, so it stays off and the game's own HUD stays up.
for _,a in pairs(H.ADDR) do
  if G.broken[a] then H.unavailable=string.format("%08X",a) end
end
if H.unavailable then wml.log("HUD styles off: the game refused the hook at "..H.unavailable) end
return H
