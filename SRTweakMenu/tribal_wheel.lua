-- Rendering replacement only: native radial input, dead zone, selection,
-- inventory checks and equip-on-release continue to run without modification.
local G,UI=require("game"),require("gameui")
local W={enabled=function() return false end, failed=false}
local r32,rf=wml.read_u32,wml.read_f32
W.ADDR={draw=0x8229E600,slot=0x8229CAB8,close=0x8229DD58,arrow=0x8227E720,
  selected=0x8370DE98,stick_x=0x8370DE90,stick_y=0x8370DE94,
  drug_mode=0x82FFE654,drug_selected=0x8370DE9C,items=0x82FFE658}
local active,slot
local function clamp(n,a,b) return math.max(a,math.min(b,n==n and n or a)) end
local function signed(n) n=n&0xFFFFFFFF; return n>=0x80000000 and n-0x100000000 or n end
G.hud_radial_tick=function()
  if not W.playing_tick then W.native_ticks=(W.native_ticks or 0)+1 end
end
function W.selection_sound(ctx,key)
  local serial=W.native_ticks or 0
  if W.last_sound_key and W.last_sound_key~=key and serial==(W.sound_baseline or 0) then
    local id=r32(0x827B01F0) -- SYS_RADIAL_SELECT, initialized by the game.
    if id~=0xFFFFFFFF and id>0 then
      W.playing_tick=true
      pcall(G.call,ctx,0x82287FC0,{id,0,0})
      W.playing_tick=nil
    else UI.sound(ctx,"scroll") end
  end
  W.last_sound_key,W.sound_baseline=key,serial
end

-- Native layout records, including their slot order, determine the angles.
-- An input-sector guess would disagree with the native dead zone and pads
-- configured to use the right stick; read the actual selection instead.
function W.build(s)
  local ops={}
  local sx,sy=clamp(s.sx or 0,-1,1),clamp(s.sy or 0,-1,1)
  local moving=require("hud_settings").values.motion
  if not moving then sx,sy=0,0 end
  local yaw,pitch=sx*.11,sy*.085
  local cyaw,syaw,cp,sp=math.cos(yaw),math.sin(yaw),math.cos(pitch),math.sin(pitch)
  -- Rotate the rigid wheel in XYZ, then perspective-divide its centres.
  -- Native circular sprites face the camera, like 3D billboards: every
  -- component gets one uniform depth scale, never a shear or separate X/Y scale.
  local function project(x,y,z)
    local xx,zz=x*cyaw+z*syaw,-x*syaw+z*cyaw
    local yy=y*cp-zz*sp
    zz=y*sp+zz*cp
    local k=700/(700-zz)
    return 640+xx*k,360+yy*k,k,zz
  end
  local function image(h,px,py,size,a,tag,rgb)
    if not h then return end
    rgb=rgb or {128,128,128}
    local op={bitmap=h,x=px-size/2,y=py-size/2,w=size,h=size,
      colour={rgb[1],rgb[2],rgb[3],math.floor(a or 255)},tag=tag}
    ops[#ops+1]=op
    return op
  end
  local function ammo_fill(v,px,py,k,alpha)
    local f=clamp(v.ammo_fraction or 0,0,1)
    if f<=0 or not s.ammo_fill then return end
    local start,finish=v.arc_start or -1.56204355,v.arc_end or -3.15026641
    finish=start+(finish-start)*f
    local slices=math.max(1,math.ceil(8*f))
    for j=0,slices-1 do
      local a0,a1=start+(finish-start)*j/slices,start+(finish-start)*(j+1)/slices
      local u0,v0=.5+.5*math.cos(a0),.5-.5*math.sin(a0)
      local u1,v1=.5+.5*math.cos(a1),.5-.5*math.sin(a1)
      ops[#ops+1]={bitmap=s.ammo_fill,x=px,y=py,w=1,h=1,tag="wheel_ammo_fill",fraction=f,
        colour={128,128,128,math.floor(alpha)},
        points={{px,py},{px,py},{px+(u0-.5)*68*k,py+(v0-.5)*68*k},{px+(u1-.5)*68*k,py+(v1-.5)*68*k}},
        uv_points={{.5,.5},{.5,.5},{u0,v0},{u1,v1}}}
    end
  end
  local discs={}
  for i=0,7 do
    local v=s.slots[i] or {}
    local angle=v.angle or (-math.pi/2+i*math.pi/4)
    local hover=clamp((s.hover and s.hover[i]) or 0,0,1)
    local h=moving and hover or 0
    local px,py,k,z=project(math.cos(angle)*(132+h*9),math.sin(angle)*(132+h*9),h*28)
    discs[#discs+1]={v=v,px=px,py=py,k=k,z=z,hover=hover,index=i}
  end
  table.sort(discs,function(a,b) return a.z==b.z and a.index<b.index or a.z<b.z end)
  for _,d in ipairs(discs) do
    local v,px,py,k,hover=d.v,d.px,d.py,d.k,d.hover
    local alpha=clamp(v.alpha or 1,0,1)*255
    image(s.circle,px+.5,py+2*k,66*k,alpha*.22,"wheel_shadow",{0,0,0})
    if hover>.01 then image(s.glow,px,py,96*k,alpha*hover*.85,"wheel_highlight") end
    local circle=image(s.circle,px,py,64*k,alpha,"wheel_circle")
    if circle then circle.slot=d.index end
    if v.icon and UI.bitmap_ready(v.icon) then
      image(v.icon,px,py,64*k,v.disabled and alpha*.38 or alpha,"wheel_weapon").slot=d.index
    end
    if v.has_ammo then
      image(s.ammo_empty,px,py,68*k,alpha,"wheel_ammo_empty")
      ammo_fill(v,px,py,k,alpha)
    end
  end
  if s.stick and UI.bitmap_ready(s.stick) then image(s.stick,640+sx*7,360+sy*7,44,210,"wheel_stick") end
  -- Consumables keep their original inventory and D-pad selection, alongside
  -- the centred weapon wheel rather than over the bottom-right HUD.
  for i=0,3 do
    local v=s.drugs[i] or {}
    local a=-math.pi/2+i*math.pi/2
    local px,py=930+math.cos(a)*55,360+math.sin(a)*55
    if s.drug_mode and s.drug_selected==i then image(s.drug_glow,px,py,72,230,"drug_highlight") end
    image(s.drug_circle,px,py,48,150,"drug_slot")
    if v.icon then image(v.icon,px,py,48,255,"drug_icon") end
  end
  if s.dpad then image(s.dpad,930,360,30,190,"drug_dpad") end
  return ops
end

function W.bitmap(ctx)
  if not active then return false end
  local h=ctx:r(3)&0xFFFF
  if slot then
    if h==r32(0x827B0214) then slot.has_ammo=true
    elseif not slot.icon then slot.icon=h end
  elseif h==r32(0x827B0208) or h==r32(0x827B020C) then active.stick=h
  elseif h~=r32(0x827B01FC) and h~=r32(0x827B0200) and h~=r32(0x827B0204)
    and h~=active.drug_circle and h~=active.drug_glow and h~=active.dpad then
    local x,y=signed(ctx:r(6)),signed(ctx:r(7))
    local best,dist
    for i=0,3 do
      local p=0x827B02E8+i*20
      local scale=rf(p+12)
      local d=(x-signed(r32(p))*scale)^2+(y-signed(r32(p+4))*scale)^2
      if not dist or d<dist then best,dist=i,d end
    end
    active.drugs[best]={icon=h}
  end
  return true
end
function W.arc(ctx)
  if not active then return false end
  if slot then
    slot.has_ammo=true; slot.ammo_fraction=clamp(ctx:f(3),0,1)
    slot.arc_start,slot.arc_end=ctx:f(1),ctx:f(2)
  end
  return true
end
G.hook(W.ADDR.slot,function(ctx)
  if not active then ctx:call_original(); return end
  local i=ctx:r(3)&0xFFFFFFFF
  if i>7 then ctx:call_original(); return end
  local prev=slot
  slot=active.slots[i]
  ctx:call_original()
  slot=prev
end)
-- Shared with the existing follower-arrow hook at the same native draw call.
G.radial_bitmap_hidden=function() return active~=nil end
G.hook(W.ADDR.close,function(ctx)
  local p=W.open_player
  W.open_player=nil
  ctx:call_original()
  -- The native close callback covers button release and cancel. A render
  -- timeout would mistake a pause or a dropped frame for an exit.
  if p and p==G.player() and W.enabled() and rf(p+G.P.HEALTH)>0
    and not G.in_cutscene() and not G.in_front_end() and not G.screen_up() then
    UI.sound(ctx,"back")
  end
  W.hover,W.clock,W.pose,W.last_sound_key=nil,nil,nil,nil
end)
G.hook(W.ADDR.draw,function(ctx)
  if not W.enabled() then W.failed=false; W.hover=nil; W.pose=nil; W.open_player=nil; W.last_sound_key=nil end
  if not W.enabled() or W.failed or not UI.ready() or G.player()==0
    or G.in_cutscene() or G.screen_up() or G.in_front_end()
    or not UI.bitmap_ready(UI.bitmap(ctx,"radial_circle"))
    or not UI.bitmap_ready(UI.bitmap(ctx,"radial_circle_glow")) then ctx:call_original(); return end
  local now=os.clock()
  W.open_player=G.player()
  local dt=W.clock and clamp(now-W.clock,0,.1) or .05
  if W.clock and now-W.clock>.25 then W.hover=nil; W.pose=nil end
  W.clock=now
  W.hover=W.hover or {}
  W.pose=W.pose or {x=0,y=0}
  local blend=1-math.exp(-dt*12)
  W.pose.x=W.pose.x+(clamp(rf(W.ADDR.stick_x),-1,1)-W.pose.x)*blend
  W.pose.y=W.pose.y+(clamp(rf(W.ADDR.stick_y),-1,1)-W.pose.y)*blend
  local selected=r32(W.ADDR.selected)
  local weapon_mode=r32(W.ADDR.drug_mode)==0
  local drug_selected=r32(W.ADDR.drug_selected)
  local key=weapon_mode and (selected<8 and "w"..selected or nil) or (drug_selected<4 and "d"..drug_selected or nil)
  if key then W.selection_sound(ctx,key) end
  local s={slots={},drugs={},sx=W.pose.x,sy=W.pose.y,hover=W.hover,
    circle=UI.bitmap(ctx,"radial_circle"),glow=UI.bitmap(ctx,"radial_circle_glow"),
    ammo_empty=r32(0x827B0214),ammo_fill=r32(0x827B0218),
    drug_mode=not weapon_mode,drug_selected=drug_selected,
    drug_circle=r32(0x827B022C),drug_glow=r32(0x827B0230),dpad=r32(0x827B0234)}
  for i=0,7 do
    local p=0x827B0248+i*20
    local x,y=signed(r32(p)),signed(r32(p+4))
    s.slots[i]={angle=(x~=0 or y~=0) and math.atan(y,x) or nil,
      alpha=rf(p+8),disabled=wml.read_u8(p+16)~=0}
    local target=weapon_mode and selected==i and 1 or 0
    W.hover[i]=(W.hover[i] or 0)+(target-(W.hover[i] or 0))*(1-math.exp(-dt*18))
  end
  active=s
  local ok,why=pcall(function() ctx:call_original() end)
  active,slot=nil,nil
  if not ok then W.failed=true; wml.log("Tribal wheel: native draw failed: "..tostring(why)); return end
  local dc=G.call(ctx,0x8263D818,{})
  local colour
  if G.pointer_ok(dc) then
    colour={}
    for i=1,4 do colour[i]=math.floor(clamp(rf(dc+48+i*4),0,1)*255+.5) end
  end
  ok,why=pcall(function() UI.draw(ctx,W.build(s)) end)
  if colour then G.call(ctx,G.DRAW_COLOR,colour) end
  if not ok then W.failed=true; wml.log("Tribal wheel: native layout restored next frame: "..tostring(why)) end
end)
return W
