local G,C=require('game'),require('hud_settings')
local L={enabled=function() return false end,failed=false,money=false}
local r32,rf,w32=wml.read_u32,wml.read_f32,wml.write_u32
L.ADDR={money=0x822DE200,money_text=0x822E2848,homies=0x822DEA08}
local function scale()
 local sx,sy=rf(0x82FFB4EC),rf(0x82FFB4E8)
 local n=math.max(sx,sy)
 return n>.1 and n<20 and n or 1
end
local function signed(n) return n>=0x80000000 and n-0x100000000 or n end
function L.money_position(width,sx,sy)
 -- Native F4/F0 are screen CENTRES, not a top-left origin. This helper
 -- receives final pixel coordinates, so no centre may be added here.
 local s=math.max(sx,sy)
 return math.floor((C.values.money_x-width*.65)*s+.5),math.floor(C.values.money_y*s+.5)
end
function L.homie_anchor(index,count)
 count=math.max(1,math.min(12,count or L.count or 3))
 local mode=C.values.homies_layout or 3
 local x,y=C.values.homies_x,C.values.homies_y
 if C.values.homies_placement==1 then x,y=1035,100
 elseif C.values.homies_placement==2 then x,y=1190,625-(mode==1 and count-1 or (mode==2 and 0 or math.ceil(count/3)-1))*54 end
 local col,row,step,size
 if mode==1 then col,row,step,size=0,index,42,.60
 elseif mode==2 then
  step=math.min(54,380/math.max(1,count-1));size=math.min(.8,step/64*.88)
  col,row=index,0
 else col,row,step,size=index%3,math.floor(index/3),54,.8 end
 local columns=mode==1 and 1 or (mode==2 and count or math.min(count,3))
 local lines=mode==1 and count or (mode==2 and 1 or math.ceil(count/3))
 x=math.max(820+(columns-1)*step,math.min(1235-32*size,x))
 y=math.max(55+32*size,math.min(670-32*size-(lines-1)*step,y))
 return x-col*step,y+row*step,size
end
function L.homie_position(i,pass)
 local x,y=L.homie_anchor((pass or 0)*3+i)
 local s=scale()
 return math.floor(x-signed(r32(0x82FFB4F4))/s+.5),math.floor(y-signed(r32(0x82FFB4F0))/s+.5)
end
function L.preview(row,on)
 local UI=require('gameui');UI.preview=nil;L.show_money=false
 if not on or not row then return end
 local id=row.key and 'sr22_'..row.key or row.id or '';local p=G.player();if p==0 then return end
 local ops={}
 -- (Default+ money sliders: the real counter stays up while you move it)
 L.show_money=id=='sr22_dp_money_x' or id=='sr22_dp_money_y'
 if id=='sr22_money_x' or id=='sr22_money_y' then
  local text='$'..tostring(r32(p+3688))
  ops[1]={text=text,x=C.values.money_x-#text*10,y=C.values.money_y,size=.65,font='thin',colour={255,255,255,255}}
 elseif id=='sr22_homies_x' or id=='sr22_homies_y' or id=='sr22_homies_layout' or id=='sr22_homies_placement' then
  -- Twelve marked placeholders also make an empty party adjustable. They
  -- are only previews; no fake party entries or recruitment are created.
  for i=0,11 do
   local x,y,z=L.homie_anchor(i,12);local size=38*z
   for r=0,1 do for c=0,1 do ops[#ops+1]={image='srt_respect_'..(r*2+c),x=x-size/2+c*size/2,y=y-size/2+r*size/2,w=size/2,h=size/2,colour={128,128,128,240}} end end
   ops[#ops+1]={text=tostring(i+1),x=x-5,y=y+size/2,size=.35,font='thin',colour={255,255,255,255}}
  end
 end
 UI.preview=#ops>0 and ops or nil
end
wml.hook(L.ADDR.money,function(ctx)
 if not L.enabled() or L.failed then ctx:call_original();return end
 L.money=true;L.money_seen=false
 local ok,err=pcall(function()
  ctx:call_original()
  local H=require('tribal_hud');local p=G.player()
  -- SR '22 keeps the cash up with the HUD; Default+ lets it fade the
  -- game's way (unless you're moving it in the menu).
  local keep=not require('native_hud').active() or L.show_money
  if keep and not L.money_seen and H.motion and H.motion.alpha>.01 and p~=0 and rf(p+G.P.HEALTH)>0 then
   local colour=G.buffer(ctx,2)
   for i=0,3 do wml.write_u8(colour+i,255) end
   G.call(ctx,0x822DE010,{r32(p+3688),0,0,0,colour},{H.motion.alpha})
  end
 end)
 L.money=false
 if not ok then L.failed=true;wml.log('SR22 money layout: '..tostring(err)) end
end)
wml.hook(L.ADDR.money_text,function(ctx)
 if not L.money then ctx:call_original();return end
 L.money_seen=true
 local original={ctx:r(3),ctx:r(4),ctx:f(1),ctx:f(2)}
 local sx,sy=rf(0x82FFB4EC),rf(0x82FFB4E8)
 if sx<=0 or sy<=0 then ctx:call_original();return end
 -- Measure the native currency string, preserving rolling amounts and colour.
 local out=ctx:r(1)-0x300
 G.call(ctx,0x8264EF48,{out,out+4,ctx:r(5),0xFFFFFFFF,ctx:r(10)})
 local width=r32(out)
 if width>1000 then ctx:call_original();return end
 if require('native_hud').active() then
  -- Default+: the game's own place and size, moved by the two sliders
  -- (1280 x 720 units, up is positive).
  local s=math.max(sx,sy)
  ctx:set_r(3,math.floor(signed(original[1])+(C.values.dp_money_x or 0)*s+.5)&0xFFFFFFFF)
  ctx:set_r(4,math.floor(signed(original[2])-(C.values.dp_money_y or 0)*s+.5)&0xFFFFFFFF)
 else
  local x,y=L.money_position(width,sx,sy,r32(0x82FFB4F4),r32(0x82FFB4F0))
  ctx:set_r(3,x);ctx:set_r(4,y);ctx:set_f(1,.65)
 end
 local H=require('tribal_hud')
 local keep=not require('native_hud').active() or L.show_money
 if keep and H.motion and H.motion.alpha>.01 and rf(G.player()+G.P.HEALTH)>0 then
  ctx:set_f(2,math.max(ctx:f(2),L.show_money and 1 or H.motion.alpha))
 end
 local ok,err=pcall(function() ctx:call_original() end)
 ctx:set_r(3,original[1]);ctx:set_r(4,original[2]);ctx:set_f(1,original[3])
 ctx:set_f(2,original[4])
 if not ok then error(err) end
end)
function L.draw_homies(ctx,draw)
 if not L.enabled() or L.failed then draw();return end
 local saved={}
 L.count=math.max(1,math.min(12,r32(G.player()+2096)))
 local function replace(addr,n) saved[#saved+1]={addr,r32(addr)};w32(addr,n&0xFFFFFFFF) end
 -- Scope the native draw anchors to this call, including portrait health arcs
 -- and revival timers. Never apply camera/impact motion to follower meters.
 replace(0x8370E28C,0);replace(0x8370E390,0)
 for i=0,2 do
  local slot=0x8301AF48+i*16
  local x,y=L.homie_position(i,0)
  replace(slot,x);replace(slot+4,y)
  saved[#saved+1]={slot+8,r32(slot+8)}
  local _,_,z=L.homie_anchor(i);wml.write_f32(slot+8,z)
 end
 L.active=true
 local ok,err=pcall(draw)
 L.active=false
 for _,v in ipairs(saved) do w32(v[1],v[2]) end
 if not ok then L.failed=true;wml.log('SR22 homie layout: '..tostring(err)) end
end
function L.homie_pass(pass)
 if not L.active then return false end
 for i=0,2 do
  local x,y=L.homie_position(i,pass)
  w32(0x8301AF48+i*16,x&0xFFFFFFFF);w32(0x8301AF4C+i*16,y&0xFFFFFFFF)
 end
 return true
end
return L
