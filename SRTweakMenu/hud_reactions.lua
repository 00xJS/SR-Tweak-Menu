-- Presentation events only. Native shots, projectile releases and explosion
-- audio remain responsible for ammunition, damage, timing and sound.
local G,C,P=require('game'),require('hud_settings'),require('hud_reaction_curves')
local R={events={},pending={},enabled=function() return false end,sequence=0}
R.ADDR={projectile=0x8241FCB0,explosion=0x82138AE8,audio_update=0x820FFD28}
local r32,rf=wml.read_u32,wml.read_f32
local function clamp(n,a,b) return math.max(a,math.min(b,n)) end
local function valid(n) return type(n)=='number' and n==n and math.abs(n)<1e7 end
local function name(info)
 if not G.pointer_ok(info) then return '' end
 local ptr=r32(info);if not G.pointer_ok(ptr) then return '' end
 local t={};for i=0,63 do local b=wml.read_u8(ptr+i);if b==0 then break end
  if b<32 or b>126 then return '' end;t[#t+1]=string.char(b)
 end;return table.concat(t):lower()
end
R.names={magnum='heavy44',['desert eagle']='heavy50',desert_eagle_gold='heavy50',
 pump_action_shotgun='pump',spas12='auto',spas12b='platinum',twelve_gauge='double',pimpcane='cane',
 ak47='ak',ak47l='ak',m16='ar',rpg_launcher='rpg',rpg_laser='platinum_rpg',pipe_bomb='pipe',grenade='grenade'}
function R.reset()
 R.events={};R.pending={};R.owner=nil;R.handle=nil;R.clock=nil
end
local function running()
 local p=G.player()
 return R.enabled() and p~=0 and rf(p+G.P.HEALTH)>0 and C.values.motion and C.values.impacts
end
function R.emit(kind,now,event)
 if not running() or (C.values[kind..'_intensity'] or 0)<=0 then return false end
 local p=G.player();local handle=r32(p+68)
 if R.owner and (R.owner~=p or R.handle~=handle) then R.reset() end
 R.owner,R.handle=p,handle
 if #R.events>=32 then table.remove(R.events,1) end
 R.sequence=R.sequence+1
 event=event or {};event.kind=kind;event.at=now;event.index=R.sequence
 R.events[#R.events+1]=event
 if kind=='blast' and G.hud_blast_reveal then G.hud_blast_reveal() end
 return true
end
function R.tick(now)
 local p=G.player();local handle=p~=0 and r32(p+68) or 0
 if not running() then R.reset();return end
 if (R.owner and (R.owner~=p or R.handle~=handle)) or (R.clock and (now<R.clock or now-R.clock>.5)) then R.reset() end
 R.owner,R.handle,R.clock=p,handle,now
 for i=#R.pending,1,-1 do if now-R.pending[i].at>.35 then table.remove(R.pending,i) end end
end
function R.offset(now)
 if not running() then R.reset();return 0,0,false end
 local x,y=0,0
 for i=#R.events,1,-1 do
  local e=R.events[i];local age=now-e.at;local gain=(C.values[e.kind..'_intensity'] or 0)/100
  if age<0 or age>1.4 or gain<=0 then table.remove(R.events,i)
  else
   local dx,dy
   if e.kind=='blast' then dx,dy=P.blast({},e,now)
   elseif e.kind=='rpg' or e.kind=='platinum_rpg' then dx,dy=P.launch(e.kind,age)
   elseif e.kind=='pipe' or e.kind=='grenade' then dx,dy=P.throw(e.kind,age)
   else dx,dy=P.shot(e.kind,age,e.index) end
   x,y=x+dx*gain,y+dy*gain
  end
 end
 return clamp(x,-22,22),clamp(y,-22,32),#R.events>0
end
-- Existing rocket-ammo hook delegates its original call here; no second
-- hook competes for G.FIRE. A dry trigger/cooldown/reload has no round loss.
G.hud_fire=function(ctx)
 local p=G.player();local actor=ctx:r(3)&0xFFFFFFFF
 local item=actor==p and p~=0 and r32(p+G.P.EQUIPPED) or 0
 local ammo=G.pointer_ok(item) and r32(item+16) or 0
 local info=G.pointer_ok(ammo) and r32(ammo+8) or 0
 local before=G.pointer_ok(ammo) and r32(ammo+16) or 0
 local kind=R.names[name(info)]
 local bullet=G.pointer_ok(info) and r32(info+100)==0
 ctx:call_original()
 if bullet and kind and before>0 and r32(ammo+16)<before then R.emit(kind,os.clock()) end
end
G.hook(R.ADDR.projectile,function(ctx)
 local owner,info=ctx:r(3)&0xFFFFFFFF,ctx:r(4)&0xFFFFFFFF
 local kind=R.names[name(info)];local p=G.player()
 local match=p~=0 and owner==r32(p+68)
 ctx:call_original()
 local made=ctx:r(3)&0xFFFFFFFF
 if G.on_projectile then pcall(G.on_projectile,owner,name(info),made) end
 if match and kind and G.pointer_ok(made) and r32(made+228)==owner and r32(made+208)==info then
  R.emit(kind,os.clock())
 end
end)
G.hook(R.ADDR.explosion,function(ctx)
 local definition,pos=ctx:r(3)&0xFFFFFFFF,ctx:r(7)&0xFFFFFFFF
 local event
 if running() and G.pointer_ok(definition) and G.pointer_ok(pos) then
  local x,y,z=G.vec(pos);local p=G.player();local px,py,pz=G.vec(p+G.P.POS)
  if valid(x) and valid(y) and valid(z) and (x-px)^2+(y-py)^2+(z-pz)^2<=30^2 then
   local effect=r32(definition+68)
   if effect<4096 then
    event={x=x,y=y,z=z,at=os.clock(),cue=r32(0x829CE4E8+effect*52+16),
     listener={x=px,y=py,z=pz,right_x=rf(G.CAMERA+80),right_z=rf(G.CAMERA+88)}}
    -- Queue before original: its effect can submit sound synchronously.
    if #R.pending>=32 then table.remove(R.pending,1) end
    R.pending[#R.pending+1]=event
   end
  end
 end
 ctx:call_original()
 -- Refused/native co-op forwarding events have no local explosion sound;
 -- they expire without creating a fake reaction.
end)
G.hud_sound=function(req,out)
 if not running() or not G.pointer_ok(req) or not G.pointer_ok(out) then return end
 local cue=r32(req+4);local now=os.clock()
 local x,y,z=G.vec(req+32)
 for _,e in ipairs(R.pending) do
  if not e.voice and e.cue==cue and now-e.at>=0 and now-e.at<.35
   and (e.x-x)^2+(e.y-y)^2+(e.z-z)^2<4 then
   local handle=r32(out+8);local slot=handle&255
   if slot<128 then e.voice=0x82911AE8+slot*416;e.generation=handle>>8 end
   break
  end
 end
end
function R.audio_updated(now)
 if not running() then R.reset();return end
 for i=#R.pending,1,-1 do
  local e=R.pending[i]
  if now-e.at<0 or now-e.at>.35 then table.remove(R.pending,i)
  elseif e.voice then
   local v=e.voice
   if r32(v+172)~=e.generation then table.remove(R.pending,i)
   elseif G.pointer_ok(r32(v+8)) then
    -- Native 820FFD28 has now evaluated obstruction into +36 and spatial
    -- gain into +40. 820FFAE8 multiplies these with +28/+32 before user
    -- volume/mixer attenuation; use that same pre-mixer perceived gain.
    local gain=rf(v+28)*rf(v+32)*rf(v+36)*rf(v+40)
    e.audibility=valid(gain) and clamp(gain,0,1) or 0
    local captured=P.capture(e.listener,e)
    captured.at=now
    if captured.gain>.015 then R.emit('blast',now,captured) end
    table.remove(R.pending,i)
   end
  end
 end
end
G.hook(R.ADDR.audio_update,function(ctx)
 ctx:call_original();R.audio_updated(os.clock())
end)
return R
