-- Shared death presentation; no gameplay writes or artificial sounds.
local D={HOLD=.30,FADE=.90}
local function copy(t)
 if type(t)~="table" then return t end
 local out={} for k,v in pairs(t) do out[k]=copy(v) end return out
end
local function smooth(t) t=math.max(0,math.min(1,t));return t*t*(3-2*t) end
function D.update(tracker,state,now,build)
 local owner=state.player or 1
 if tracker.owner~=owner or tracker.handle~=(state.handle or 0) or (tracker.clock and now<tracker.clock) then
  for k in pairs(tracker) do tracker[k]=nil end
  tracker.owner=owner
  tracker.handle=state.handle or 0
 end
 tracker.clock=now
 if (state.health or 0)>0 then
  tracker.live=copy(state);tracker.dead_at=nil;tracker.skeleton=nil
  return build(state),"alive",state.alpha or 1
 end
 if not tracker.live then return {},"hidden",0 end
 if not tracker.dead_at then
  tracker.dead_at=now
  -- Freeze the last visible whole-cluster pose and its native opacity.
  -- No weapon/count/icon can linger, pulse or move separately after death.
  local s=copy(tracker.live)
  s.health,s.sprint=0,0
  s.ammo_text,s.respect_text,s.weapon_icon=nil,nil,nil
  s.health_warning,s.sprint_warning=false,false
  s.respect_shine,s.respect_progress,s.respect_from=nil,nil,nil
  s.health_glow,s.sprint_glow,s.shot,s.reloaded=0,0,0,0
  tracker.skeleton=s
 end
 local age=now-tracker.dead_at
 local fade=1-smooth((age-D.HOLD)/D.FADE)
 if fade<=0 then return {},"hidden",0 end
 local s=copy(tracker.skeleton)
 s.alpha=(s.alpha or 1)*fade
 local out={}
 for _,op in ipairs(build(s)) do
  local tag=op.tag or ""
  local keep=tag=="tribal" or tag:match("^[a-z]+_empty$") or
   tag:match("^[a-z]+_stroke$") or tag:match("^[a-z]+_shadow$") or
   (op.image=="px_swatch_color" and not op.tag)
  if keep then
   if op.colour then for i=1,3 do op.colour[i]=0 end end
   if op.colours then for _,c in ipairs(op.colours) do for i=1,3 do c[i]=0 end end end
   out[#out+1]=op
  end
 end
 return out,age<=D.HOLD and "empty" or "fading",(tracker.skeleton.alpha or 1)*fade
end
return D
