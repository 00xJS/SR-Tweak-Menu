-- Enhanced original HUD: native art, text formatters and font arguments stay native.
local G,C=require('game'),require('hud_settings')
local N={}
local r32,rf,w32,wf=wml.read_u32,wml.read_f32,wml.write_u32,wml.write_f32
local function signed(n) return n>=0x80000000 and n-0x100000000 or n end
function N.active() return (C.preview or C.values.design)==2 end
function N.ammo(ctx,s,draw)
 local low=require('tribal_hud').ammo_warning(s)
 if not low then draw();return end
 local dc=G.call(ctx,0x8263D818,{})
 if not G.pointer_ok(dc) then draw();return end
 local colour={};for i=1,4 do colour[i]=math.floor(math.max(0,math.min(1,rf(dc+48+i*4)))*255+.5) end
 local ok,err=pcall(function() G.call(ctx,G.DRAW_COLOR,{240,55,55,colour[4]});draw() end)
 G.call(ctx,G.DRAW_COLOR,colour)
 if not ok then error(err) end
end
function N.capture(ctx,kind,scope,s)
 if N.replaying or s.health<=0 then return end
 local id=ctx:r(3)&0xFFFF
 local keep=kind=='bitmap' and scope=='health' or kind=='arc' and
  ((scope=='health' and id==(r32(0x827AF1D4)&0xFFFF)) or (scope=='sprint' and id==(r32(0x827AF1F4)&0xFFFF)))
 if not keep then return end
 local command={kind=kind,args={},floats={},stack={}}
 for i=3,10 do command.args[#command.args+1]=ctx:r(i) end
 for i=1,4 do command.floats[i]=ctx:f(i) end
 for i=84,128,4 do command.stack[#command.stack+1]={i,4,r32(ctx:r(1)+i)} end
 N.frame=N.frame or {};if #N.frame<16 then N.frame[#N.frame+1]=command end
end
function N.finish(ctx,s)
 if not C.values.death then N.dead_at=nil;return end
 local now=os.clock()
 if s.health>0 then
  N.dead_at=nil;N.owner=s.handle
  N.last={commands=N.frame or {},state=s};return
 end
 if not N.last or N.owner~=s.handle then return end
 N.dead_at=N.dead_at or now
 local age=now-N.dead_at;local t=math.max(0,math.min(1,(age-.3)/.9))
 local alpha=1-t*t*(3-2*t)
 if alpha<=0 then return end
 local dc=G.call(ctx,0x8263D818,{})
 if not G.pointer_ok(dc) then return end
 local colour={};for i=1,4 do colour[i]=math.floor(math.max(0,math.min(1,rf(dc+48+i*4)))*255+.5) end
 local H=require('tribal_hud')
 local ok,err=pcall(N.scope,ctx,N.last.state,function()
  N.replaying=true
  G.call(ctx,G.DRAW_COLOR,{0,0,0,math.floor(255*alpha*(N.last.state.alpha or 1))})
  for _,c in ipairs(N.last.commands) do G.call(ctx,H.ADDR[c.kind],c.args,c.floats,c.stack) end
 end)
 N.replaying=nil;G.call(ctx,G.DRAW_COLOR,colour)
 if not ok then error(err) end
end
function N.transform(s)
 -- Reactions only: Default+ has no camera depth (the weapon wheel keeps its own).
 if not C.values.motion then return 0,0,1 end
 return s.impact_x or 0,s.impact_y or 0,1
end
function N.scope(ctx,s,draw)
 local saved={}
 for _,a in ipairs({0x82FFB4E8,0x82FFB4EC,0x82FFB4F0,0x82FFB4F4}) do saved[a]=r32(a) end
 local dx,dy,k=N.transform(s);local scale=math.max(rf(0x82FFB4E8),rf(0x82FFB4EC))
 if scale>.1 and scale<20 then
  wf(0x82FFB4E8,rf(0x82FFB4E8)*k);wf(0x82FFB4EC,rf(0x82FFB4EC)*k)
  for _,v in ipairs({{0x82FFB4F4,0x8370E28C,dx},{0x82FFB4F0,0x8370E390,dy}}) do
   w32(v[1],math.floor(signed(r32(v[1]))+((1-k)*signed(r32(v[2]))+v[3])*scale+.5)&0xFFFFFFFF)
  end
 end
 local ok,err=pcall(draw)
 for a,v in pairs(saved) do w32(a,v) end
 if not ok then error(err) end
end
function N.glow(ctx,scope,s)
 if N.replaying or (scope~='health' and scope~='sprint') then return end
 local id=r32(scope=='health' and 0x827AF1DC or 0x827AF1FC)&0xFFFF
 if (ctx:r(3)&0xFFFF)~=id or not s[scope..'_warning'] then return end
 local H=require('tribal_hud');local g=H.glow(s,scope)
 local dc=G.call(ctx,0x8263D818,{})
 if not G.pointer_ok(dc) then return end
 local colour={};for i=1,4 do colour[i]=math.floor(math.max(0,math.min(1,rf(dc+48+i*4)))*255+.5) end
 local args={};for i=3,10 do args[#args+1]=ctx:r(i) end
 local floats={ctx:f(1),ctx:f(2),ctx:f(3),ctx:f(4)}
 local stack={{92,4,r32(ctx:r(1)+92)},{100,4,r32(ctx:r(1)+100)}}
 local ok,err=pcall(function()
  N.replaying=true
  for i=3,1,-1 do
   local alpha=math.floor(g.opacity*(s.alpha or 1)*(.12+(3-i)*.06))
   G.call(ctx,G.DRAW_COLOR,scope=='health' and {230,30,45,alpha} or {175,70,230,alpha})
   local f={floats[1],floats[2],math.max(floats[3],.015),floats[4]*(1+i*.025)}
   G.call(ctx,H.ADDR.arc,args,f,stack)
  end
 end)
 N.replaying=nil;G.call(ctx,G.DRAW_COLOR,colour)
 if not ok then error(err) end
end
return N
