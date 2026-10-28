-- SR22 presentation preferences. No executable configuration is loaded.
local C={values={},dirty=false}
C.file=(wml.mod_folder or '.')..'/hud_preferences.txt'
C.schema={
 {key='design',label='HUD Style',default=2,min=1,max=2,step=1,choices={"SR '22",'Default+'},help='Change only the HUD artwork. The reactive weapon wheel stays unchanged.'},
 {key='homies_placement',label='Homie placement',default=1,min=1,max=3,step=1,choices={'Left of default HUD','Bottom right','Custom position'},help='Choose a position for follower portraits. Keeps the native health and revival meters.'},
 {key='homies_layout',label='Homie Layout',default=3,min=1,max=3,step=1,choices={'Vertical column','Horizontal row','Rows of three'},help='One vertical column, one horizontal row, or rows of three.'},
 {key='motion',label='HUD motion',default=true,help='Turn off all movement of the HUD and wheel for a steady view.'},
 {key='camera',label='Camera sensitivity',default=100,min=0,max=200,step=5,help='Depth movement from camera turns. Zero keeps the HUD steady while looking around.'},
 {key='impacts',label='Reactive motions',default=true,help='Car impacts, high landings and fast vehicle exits. Money and homie meters always stay steady.'},
 {key='strength',label='Impact sensitivity',default=100,min=0,max=200,step=5,help='Strength of the whole HUD reaction. Zero removes impact movement.'},
 {key='car',label='Car Impact Shake',default=true,help='A brief horizontal reaction when a vehicle hurts you.'},
 {key='fall',label='High landing reaction',default=true,help='A downward landing followed by a short vertical settle.'},
 {key='bail',label='Fast Vehicle Exit Shake',default=true,help='A short two-axis reaction after leaving a fast moving vehicle.'},
 {key='knockdown',label='Combat knockdown reaction',default=true,help='Landing impact when melee or hand-to-hand combat knocks you to the floor.'},
 {key='car_intensity',label='Car impact intensity',default=100,min=0,max=200,step=5,help='How strong this reaction is. 0% turns it off, 100% is normal, 200% is double.'},
 {key='fall_intensity',label='High landing intensity',default=100,min=0,max=200,step=5,help='How strong this reaction is. 0% turns it off, 100% is normal, 200% is double.'},
 {key='bail_intensity',label='Fast vehicle exit intensity',default=100,min=0,max=200,step=5,help='How strong this reaction is. 0% turns it off, 100% is normal, 200% is double.'},
 {key='knockdown_intensity',label='Combat knockdown intensity',default=100,min=0,max=200,step=5,help='How strong this reaction is. 0% turns it off, 100% is normal, 200% is double.'},
 {key='heavy44_intensity',label='.44 Shepherd intensity',default=100,min=0,max=200,step=5,help='How strong this reaction is. 0% turns it off, 100% is normal, 200% is double.'},
 {key='heavy50_intensity',label='GDHC .50 intensity',default=100,min=0,max=200,step=5,help='How strong this reaction is. 0% turns it off, 100% is normal, 200% is double.'},
 {key='pump_intensity',label='Tombstone intensity',default=100,min=0,max=200,step=5,help='How strong this reaction is. 0% turns it off, 100% is normal, 200% is double.'},
 {key='auto_intensity',label='AS12 Riot intensity',default=100,min=0,max=200,step=5,help='How strong this reaction is. 0% turns it off, 100% is normal, 200% is double.'},
 {key='platinum_intensity',label='Platinum AS12 intensity',default=100,min=0,max=200,step=5,help='How strong this reaction is. 0% turns it off, 100% is normal, 200% is double.'},
 {key='double_intensity',label='12 Gauge intensity',default=100,min=0,max=200,step=5,help='How strong this reaction is. 0% turns it off, 100% is normal, 200% is double.'},
 {key='cane_intensity',label='Pimp Cane intensity',default=100,min=0,max=200,step=5,help='How strong this reaction is. 0% turns it off, 100% is normal, 200% is double.'},
 {key='ak_intensity',label='K6 Krukov intensity',default=100,min=0,max=200,step=5,help='How strong this reaction is. 0% turns it off, 100% is normal, 200% is double.'},
 {key='ar_intensity',label='AR40 Xtnd intensity',default=100,min=0,max=200,step=5,help='How strong this reaction is. 0% turns it off, 100% is normal, 200% is double.'},
 {key='rpg_intensity',label='RPG launch intensity',default=100,min=0,max=200,step=5,help='How strong this reaction is. 0% turns it off, 100% is normal, 200% is double.'},
 {key='platinum_rpg_intensity',label='Platinum RPG launch intensity',default=100,min=0,max=200,step=5,help='How strong this reaction is. 0% turns it off, 100% is normal, 200% is double.'},
 {key='grenade_intensity',label='Grenade throw intensity',default=100,min=0,max=200,step=5,help='How strong this reaction is. 0% turns it off, 100% is normal, 200% is double.'},
 {key='pipe_intensity',label='Pipe Bomb throw intensity',default=100,min=0,max=200,step=5,help='How strong this reaction is. 0% turns it off, 100% is normal, 200% is double.'},
 {key='blast_intensity',label='Nearby explosion intensity',default=100,min=0,max=200,step=5,help='How strong this reaction is. 0% turns it off, 100% is normal, 200% is double.'},
 {key='death',label='Death fade animation',default=true,help='Empty and blacken the HUD on death, then fade it away. Off restores the game death HUD.'},
 {key='dp_money_x',label='Money horizontal',default=0,min=-1100,max=150,step=5,help='Moves the money counter left or right from where the game puts it.'},
 {key='dp_money_y',label='Money vertical',default=0,min=-600,max=600,step=5,help='Moves the money counter down or up from where the game puts it.'},
 {key='money_x',label='Money horizontal',default=1235,min=1040,max=1235,step=5,help='Right edge of the compact money counter, within the right side of the screen.'},
 {key='money_y',label='Money vertical',default=565,min=65,max=565,step=5,help='Counter height. The default leaves space above the tribal artwork.'},
 {key='homies_x',label='Homies horizontal',default=1190,min=1060,max=1210,step=5,help='Rightmost homie slot. Layouts stay within the right section of the screen.'},
 {key='homies_y',label='Homies Vertical',default=105,min=65,max=365,step=5,help='Homie slot height, inset from the top edge.'},
}
function C.clean(s,v)
 if type(s.default)=='boolean' then return v=='true' or v==true end
 v=tonumber(v)
 if not v or v~=v or v==math.huge or v==-math.huge then return s.default end
 return math.max(s.min,math.min(s.max,math.floor(v/s.step+.5)*s.step))
end
function C.load(path)
 for _,s in ipairs(C.schema) do C.values[s.key]=s.default end
 local f=io.open(path or C.file,'rb')
 local legacy=f~=nil;local current=false
 if f then
  for line in f:lines() do
   if line=='layout_version=2' then current=true end
   local k,v=line:match('^([%w_]+)=([%w%.%-]+)$')
   if k then for _,s in ipairs(C.schema) do if s.key==k then C.values[k]=C.clean(s,v);break end end end
  end
  f:close()
 end
 C.dirty=legacy and not current
 if C.dirty then
  -- Positions chosen against the broken centre-offset layout never had a
  -- visible meaning. Reset those four once; retain every motion preference.
  for _,s in ipairs(C.schema) do
   if s.key=='money_x' or s.key=='money_y' or s.key=='homies_x' or s.key=='homies_y' then C.values[s.key]=s.default end
  end
  C.changed=os.clock()
 end
end
function C.set(key,v)
 for _,s in ipairs(C.schema) do if s.key==key then
  C.values[key]=C.clean(s,v);C.dirty=true;C.changed=os.clock();return C.values[key]
 end end
end
function C.flush(now,force)
 if not C.dirty or (not force and now-(C.changed or now)<.5) then return end
 -- Debounce held sliders. Preserve a pending change if a file cannot open.
 local f=io.open(C.file,'wb');if not f then return end
 local lines={'layout_version=2\n'}
 for _,s in ipairs(C.schema) do lines[#lines+1]=s.key..'='..tostring(C.values[s.key])..'\n' end
 local ok=f:write(table.concat(lines));f:close()
 if ok then C.dirty=false end
end
-- Rows each design leaves out: Default+ moves the game's own money counter
-- from its own place, and has no camera depth (its weapon wheel still has depth).
local SKIP={[1]={design=true,dp_money_x=true,dp_money_y=true},[2]={design=true,camera=true,money_x=true,money_y=true}}
local function rows_for(design)
 local rows={}
 for _,s in ipairs(C.schema) do if not SKIP[design][s.key] then
  local row={id='sr22_'..s.key..(design==2 and '_dp' or ''),label=s.label,needs='none',help=s.help,default=s.default,v=C.values[s.key],key=s.key}
  if s.key:match('_intensity$') then
   row.hidden=function() return not C.values.motion or not C.values.impacts end
  elseif s.key=='camera' or s.key=='impacts' then
   row.hidden=function() return not C.values.motion end
  elseif s.key=='strength' or s.key=='car' or s.key=='fall' or s.key=='bail' or s.key=='knockdown' then
   row.hidden=function() return not C.values.motion or not C.values.impacts end
  end
  if type(s.default)=='boolean' then row.kind='toggle'
  else
   row.kind='value';row.bar=true;row.min=s.min;row.max=s.max;row.step=s.step;row.wrap=s.choices~=nil  -- (choices cycle round)
   row.fmt=function(n) return s.choices and s.choices[n] or tostring(n)..(s.max==200 and '%' or '') end
  end
  row.change=function(_,_,_,it) it.v=C.set(s.key,it.v) end
  rows[#rows+1]=row
 end end
 rows[#rows+1]={id='sr22_layout_reset'..(design==2 and '_dp' or ''),label='Reset money and homie positions',kind='action',needs='none',
  help=design==2 and "Puts the money counter back in the game's place and the homies back in the top right." or 'Puts the money counter above the HUD and the homies back in the top right.',run=function()
  for _,s in ipairs(C.schema) do
   if (s.key=='money_x' or s.key=='money_y') and design==1 or (s.key=='dp_money_x' or s.key=='dp_money_y') and design==2
    or s.key=='homies_x' or s.key=='homies_y' then
    C.set(s.key,s.default)
    for _,r in ipairs(rows) do if r.key==s.key then r.v=s.default end end
   end
  end
  return 'Money and homie positions reset.'
 end}
 rows[#rows+1]={id='sr22_reset'..(design==2 and '_dp' or ''),label='Reset all HUD settings',kind='action',needs='none',help='Puts motion, reactions and positions back to their defaults.',run=function()
  for _,s in ipairs(C.schema) do if s.key~='design' then C.set(s.key,s.default) end end
  for _,r in ipairs(rows) do if r.key then r.v=C.values[r.key] end end
  return 'HUD settings reset.'
 end}
 return rows
end
C.rows_for=rows_for
-- Customizing a design shows that HUD (even with HUD Styles off) until you
-- leave its page; then the chosen one is back.
C.preview=nil
function C.preview_page(title,design)
 C.preview=design
 return {title=title,rows=rows_for(design),back=function() C.preview=nil end}
end
-- HUD Options: the switch, the design, a page per design, then the extra
-- screen effects (rows made in features.lua).
function C.page(enable,extras)
 local s=C.schema[1]
 local rows={enable,
  {id='sr22_design',label=s.label,kind='value',needs='none',min=1,max=2,step=1,wrap=true,default=s.default,v=C.values.design,key='design',
   help='Picks the HUD artwork. The reactive weapon wheel works with both.',
   fmt=function(n) return s.choices[n] end,change=function(_,_,_,it) it.v=C.set('design',it.v) end},
  {id='hud_default_plus',label='Default+ HUD',kind='page',needs='none',help="Motion, reactions and homie placement for the game's own HUD.",
   open=function() return C.preview_page('Default+ HUD',2) end},
  {id='hud_sr22',label="SR '22 HUD",kind='page',needs='none',help="Motion, camera depth, reactions, and money and homie placement for the Saints Row '22 HUD.",
   open=function() return C.preview_page("SR '22 HUD",1) end}}
 if extras and #extras>0 then
  rows[#rows+1]={kind='header',label='Extra Visuals'}
  for _,r in ipairs(extras) do rows[#rows+1]=r end
 end
 return {title='HUD Options',rows=rows}
end
C.load()
return C
