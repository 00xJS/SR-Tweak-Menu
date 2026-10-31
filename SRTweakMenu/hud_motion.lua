-- Read-only native collision/ground sampling. One translation moves the HUD.
local G,C=require('game'),require('hud_settings')
local M={events={},enabled=function() return false end}
M.ADDR={car=0x82451C98,ragdoll_contact=0x82266680}
local rf,r32=wml.read_f32,wml.read_u32
local function clamp(n,a,b) return math.max(a,math.min(b,n)) end
local function ease(t) t=clamp(t,0,1);return t*t*(3-2*t) end
local function object(handle)
 local i=handle&0xFFFF;if handle==0 or i>=4096 then return nil end
 local p=r32(G.OBJECTS+12+i*16)
 if G.pointer_ok(p) and r32(p+68)==handle then return p end
end
function M.reset()
 M.previous=nil;M.events={};M.last={};M.bail=nil;M.knockdown=nil;M.attack=nil;M.contact=nil
end
function M.trigger(kind,now,strength)
 local c=C.values
 if not c.motion or not c.impacts or not c[kind] or c.strength==0 then return end
 M.last=M.last or {}
 if M.last[kind] and now-M.last[kind]<.65 then return end
 M.last[kind]=now
 if #M.events>=4 then table.remove(M.events,1) end
 M.events[#M.events+1]={kind=kind,at=now,strength=clamp(strength or 1,.75,1.35)}
end
function M.active() return #M.events>0 end
function M.offset(now)
 local c=C.values
 if not c.motion or not c.impacts or c.strength==0 then M.events={};return 0,0 end
 local x,y=0,0
 for i=#M.events,1,-1 do
  local e=M.events[i];local t=now-e.at
  if t<0 or t>.8 or not c[e.kind] then table.remove(M.events,i)
  else
   local envelope=(1-math.exp(-t/.018))*math.exp(-t*5)*(1-ease((t-.45)/.35))
   local a=e.strength*c.strength/100*(c[e.kind.."_intensity"] or 100)/100
   if e.kind=='fall' or e.kind=='knockdown' then
    local function hit(age) return age>0 and (age/.065)*math.exp(1-age/.065) or 0 end
    y=y+a*(20*hit(t)-12*hit(t-.12)+4*envelope*math.sin(t*48))
   elseif e.kind=='car' then x=x+a*20*envelope*math.sin(t*42)
   else
    x=x+a*15*envelope*math.sin(t*37)
    y=y+a*(12*envelope*math.sin(t*43)+5*(t/.07)*math.exp(1-t/.07))
   end
  end
 end
 -- Bound the complete cluster, including its bottom ornament, to the screen.
 return clamp(x,-22,22),clamp(y,-22,32)
end
function M.note_contact(player,now)
 M.contact={player=player,at=now}
end
function M.ragdoll_contact(record,now)
 local p=G.player()
 if p==0 or not G.pointer_ok(record) or r32(record)~=r32(p+68) or r32(p+780)==0 then return end
 local count=r32(record+8)
 if count==0 or count>64 then return end
 -- Native ragdoll-world contact, rather than the animation's exit event.
 -- Reject the car/human collision that caused the fall in the first place.
 local other=object(r32(record+4))
 if other and (r32(other+72)==1 or r32(other+72)==5) then return end
 -- Contact layout is decoded by native 8225DFF0: points +12/16/20,
 -- normals +24/28/32, 72-byte stride. A world contact must support the
 -- player from below; side walls and ceilings must not count as landing.
 for i=0,count-1 do
  local at=record+i*72
  local nx,ny,nz=rf(at+24),rf(at+28),rf(at+32)
  local norm=nx*nx+ny*ny+nz*nz
  if norm>.25 and norm<4 and ny*ny>=norm*.30 and rf(at+16)<=rf(p+24)+.6 then
   M.note_contact(p,now);return
  end
 end
end
function M.combat_hit(victim,attacker,damage,now)
 if victim~=G.player() or damage<=0 or not G.pointer_ok(attacker) or r32(attacker+72)~=1 then return end
 local dx,dz=rf(victim+20)-rf(attacker+20),rf(victim+28)-rf(attacker+28)
 if dx*dx+dz*dz>16 then return end
 local item=r32(attacker+G.P.EQUIPPED)
 if G.pointer_ok(item) then
  local ammo=r32(item+16)
  if G.pointer_ok(ammo) then
   local info=r32(ammo+8)
   if G.pointer_ok(info) and r32(info+100)~=3 then return end
  end
 end
 M.attack={player=victim,at=now,strength=clamp(damage/15,.9,1.35)}
end
function M.sample(s,now)
 local p=M.previous
 if not s or not p or p.player~=s.player or now-p.at>.25 or now<=p.at or s.health<=0
  or (s.x-p.x)^2+(s.y-p.y)^2+(s.z-p.z)^2>225 then
  M.reset();if not s or s.health<=0 then return end
 else
  if p.vehicle and not s.vehicle and p.speed>=12 then
   M.bail={at=p.at,strength=p.speed/24,saw_air=s.grounded==false or s.ragdoll}
  end
  if M.attack and M.attack.player==s.player and now-M.attack.at<=1.25 and s.ragdoll and not p.ragdoll then
   M.knockdown={at=M.attack.at,strength=M.attack.strength};M.attack=nil
  end
  local contact=M.contact and M.contact.player==s.player and M.contact.at or -1
  local function touched(pending)
   return (contact>=pending.at and now-contact<.15)
    or (s.grounded==true and pending.saw_air and now-pending.at>=.06)
    or (s.grounded==nil and (not M.contact_available or not s.ragdoll) and now-pending.at>=.2)
  end
  local landed=false
  if M.bail then
   if s.vehicle or now-M.bail.at>4 then M.bail=nil
   elseif touched(M.bail) then
    M.trigger('bail',now,M.bail.strength);M.bail=nil;M.knockdown=nil;landed=true
   else M.bail.saw_air=M.bail.saw_air or s.grounded==false or s.ragdoll end
  elseif M.knockdown then
   if now-M.knockdown.at>3 then M.knockdown=nil
   elseif touched(M.knockdown) then
    M.trigger('knockdown',now,M.knockdown.strength);M.knockdown=nil;landed=true
   else M.knockdown.saw_air=M.knockdown.saw_air or s.ragdoll or s.grounded==false end
  end
  if not s.vehicle and not p.vehicle then
   s.peak=math.max(s.y,p.peak or p.y)
   local dt=now-p.at
   -- The ragdoll no longer follows the upright controller velocity. Track
   -- actual body position too, so high-fall impact still registers.
   local vy=s.ragdoll and (s.y-p.y)/dt or s.vy
   local before=p.vertical or p.vy
   s.vertical=vy;s.min_vy=math.min(vy,p.min_vy or 0)
   local stopped=(before<-3 and vy>-1.5) or (s.grounded==true and p.grounded==false)
    or (contact>=p.at and (p.min_vy or before)<-3)
   if not landed and not M.bail and not M.knockdown and (p.min_vy or before)<-7 and stopped and s.peak-s.y>=3.5 then
    M.trigger('fall',now,(s.peak-s.y)/7);landed=true
   end
   if landed or (vy>-.5 and math.abs(s.y-p.y)<.03 and not M.bail and not M.knockdown) then s.peak=s.y;s.min_vy=0 end
  end
 end
 s.at=now;M.previous=s
end
function M.car_hit(victim,attacker,damage,now)
 if victim~=G.player() or damage<=0 then return end
 local context=M.car_context
 if context and context.player==victim and context.speed>=4 then
  M.trigger('car',now,math.max(1,context.speed/12));return
 end
 if G.pointer_ok(attacker) and r32(attacker+72)==5 then M.trigger('car',now,math.max(1,damage/15)) end
end
function M.tick(player,now)
 if not player or player==0 then M.sample(nil,now);return end
 local vx,vy,vz,grounded=0,0,0,nil
 local ragdoll=r32(player+780)~=0
 local ctrl=r32(player+G.P.CONTROLLER)
 if G.pointer_ok(ctrl) then
  local body=r32(ctrl+8)
  if G.pointer_ok(body) then
   vx,vy,vz=rf(body+16),rf(body+20),rf(body+24)
   -- The native support/state check used by 82461F58/82436658. Its
   -- upright controller is stale during ragdoll; use world contacts then.
   if not ragdoll then grounded=r32(body+256)==0 end
  end
 end
 local v=G.vehicle_object(player);local speed=0
 if v then
  local body=r32(v+244)
  if G.pointer_ok(body) then
   local motion=r32(body+88)
   if G.pointer_ok(motion) then local x,z=rf(motion+208),rf(motion+216);speed=math.sqrt(x*x+z*z) end
  end
 end
 M.sample({player=player,health=rf(player+G.P.HEALTH),x=rf(player+20),y=rf(player+24),z=rf(player+28),
  vy=vy,vehicle=v,speed=speed,grounded=grounded,ragdoll=ragdoll},now)
end
G.hook(M.ADDR.car,function(ctx)
 local p=G.player();local previous=M.car_context
 local match=p~=0 and r32(p+68)==(ctx:r(3)&0xFFFFFFFF) and M.enabled()
 local before,ragdoll
 if match then
  before,ragdoll=rf(p+G.P.HEALTH),r32(p+780)
  M.car_context={player=p,speed=math.abs(ctx:f(1))}
 end
 local speed=match and M.car_context.speed or 0
 local ok,err=pcall(function() ctx:call_original() end)
 M.car_context=previous
 if not ok then error(err) end
 if match and speed>=4 and (rf(p+G.P.HEALTH)<before or (ragdoll==0 and r32(p+780)~=0)) then
  M.trigger('car',os.clock(),math.max(1,speed/12))
 end
end)
local ok,registered=pcall(wml.hook,M.ADDR.ragdoll_contact,function(ctx)
 if M.enabled() then M.ragdoll_contact(ctx:r(3)&0xFFFFFFFF,os.clock()) end
 ctx:call_original()
end)
M.contact_available=ok and registered~=false
return M
