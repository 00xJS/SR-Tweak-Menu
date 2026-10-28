-- Shared, deterministic presentation curves. No game state writes.
local P={}
local function finite(x) return type(x)=="number" and x==x and math.abs(x)<1e8 end
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function smooth(t) t=clamp(t,0,1);return t*t*(3-2*t) end
local function bell(t,a,d)
 if t<0 then return 0 end
 local peak=a*math.log(1+d/a)
 return (1-math.exp(-t/a))*math.exp(-t/d)/((1-math.exp(-peak/a))*math.exp(-peak/d))
end
function P.proximity(distance,range)
 if not finite(distance) or distance<0 then return 0 end
 range=range or 30
 return (1-smooth((distance-4)/math.max(1,range-4)))^1.15
end
function P.strength(listener,event)
 if event.captured then return event.gain,event.distance,event.side end
 for _,p in ipairs({listener,event}) do
  for _,axis in ipairs({"x","y","z"}) do if not finite(p[axis]) then return 0,0,0 end end
 end
 local dx,dy,dz=listener.x-event.x,listener.y-event.y,listener.z-event.z
 local distance=math.sqrt(dx*dx+dy*dy+dz*dz)
 local audible=event.audibility==nil and 1 or event.audibility
 if not finite(audible) or audible<=.015 then return 0,distance,0 end
 -- Audibility is the spatial cue's perceived gain before user volume.
 -- Use the limiting cue, rather than attenuating distance twice.
 local gain=math.min(P.proximity(distance,event.range),clamp(audible,0,1)^.7)
 local horizontal=math.sqrt(dx*dx+dz*dz)
 local side=horizontal>.01 and (dx*(listener.right_x or 1)+dz*(listener.right_z or 0))/horizontal or 0
 return gain,distance,clamp(side,-1,1)
end
function P.capture(listener,event)
 local out={}
 for k,v in pairs(event) do out[k]=v end
 out.gain,out.distance,out.side=P.strength(listener,event)
 out.captured=true
 return out
end
function P.blast(listener,event,now)
 local age=now-event.at
 local gain,distance,side=P.strength(listener,event)
 if age<0 or age>1.25 or gain<=0 then return 0,0,gain,distance end
 local hit=bell(age,.010,.11)
 local tail=bell(age,.018,.28)*(1-smooth((age-.55)/.7))
 local horizontal=math.abs(side)>.05 and side or .25
 local x=gain*horizontal*(11*hit+3.2*tail*math.sin(age*math.pi*15.2))
 local y=gain*(-7.8*hit+4.1*bell(age-.11,.025,.10)+2.4*tail*math.sin(age*math.pi*20.6+.6))
 return x,y,gain,distance
end
function P.launch(kind,t)
 if t<0 or t>1.4 then return 0,0 end
 local guided=kind=="platinum_rpg"
 local hit=bell(t,.012,guided and .13 or .17)
 local rebound=bell(t-.16,.028,.13)
 local tail=bell(t,.015,guided and .29 or .36)*(1-smooth((t-.65)/.75))
 local rumble=math.sin(t*math.pi*14)+.45*math.sin(t*math.pi*23+.6)
 return (guided and -3.5 or -6)*hit+2*rebound+(guided and 2.4 or 3.2)*tail*rumble,
  -9*hit+3.8*rebound+2.4*tail*(math.sin(t*math.pi*17)+.35*math.sin(t*math.pi*29))
end
function P.throw(kind,t)
 if t<0 or t>1 then return 0,0 end
 local pipe=kind=="pipe"
 local hit=bell(t,.030,pipe and .11 or .085)
 local rebound=bell(t-.11,.025,.085)
 return (pipe and 2.5 or 1.7)*hit-.8*rebound,
  -(pipe and 3 or 2.1)*hit+1.1*rebound
end
function P.offset(listener,events,now,enabled)
 if enabled==false then return 0,0 end
 local x,y=0,0
 for _,e in ipairs(events) do local dx,dy=P.blast(listener,e,now);x,y=x+dx,y+dy end
 return clamp(x,-22,22),clamp(y,-22,32)
end
function P.visibility(listener,events,now,armed)
 if armed then return 1 end
 local alpha=0
 for _,e in ipairs(events) do
  local gain=P.strength(listener,e);local age=now-e.at
  if gain>.02 and age>=0 then alpha=math.max(alpha,1-smooth((age-1.7)/.5)) end
 end
 return alpha
end
function P.shot(kind,t,index)
 if t<0 or t>1.2 then return 0,0 end
 local side=(index or 0)%2==0 and 1 or -1
 if kind=='heavy44' then
  local p,r=bell(t,.009,.11),bell(t-.12,.022,.09)
  return -2.8*p+1.2*r,-10*p+3.2*r
 elseif kind=='heavy50' then
  local p,r=bell(t,.006,.075),bell(t-.09,.012,.08)
  return 7.2*p-3.4*r,-7.2*p+2*r+math.sin(t*54)*math.exp(-t*14)*.65
 elseif kind=='pump' then
  local p,r=bell(t,.011,.14),bell(t-.18,.025,.12)
  return -3.5*p+1.8*r,-12.5*p+4.6*r
 elseif kind=='auto' or kind=='platinum' then
  local p,r=bell(t,.006,kind=='platinum' and .064 or .075),bell(t-.075,.014,.065)
  return side*2.5*p-side*.7*r,-7.6*p+2.5*r
 elseif kind=='double' then
  local p,r=bell(t,.012,.16),bell(t-.21,.028,.15)
  return -8.5*p+3.1*r,-10.2*p+4.9*r
 elseif kind=='cane' then
  local p,r=bell(t,.015,.19),bell(t-.24,.03,.16)
  return -10.5*p+3.7*r,-12.8*p+6.4*r
 elseif kind=='ak' then
  local p,r=bell(t,.004,.045),bell(t-.05,.008,.045)
  return (3.4+side*1.7)*p-2*r,-5.6*p+2.8*r
 elseif kind=='ar' then
  local p,r=bell(t,.003,.03),bell(t-.04,.007,.033)
  return side*1.25*p-side*.4*r,-3.8*p+1.35*r
 end
 return 0,0
end
return P
