-- SR Tweak Menu - add-ons: other authors' mods, bundled with their permission
-- and switched from the menu.
--
--   Precise Aim    by Eazzy (Eazeepz)  addons/precise_aim   (Lua)
--   Fine Aim       by car123609!       addons/fine_aim      (Lua)
--   Weapon Switch  by Eazzy (Eazeepz)  weapon_switch.dll, settings in addons/weapon_switch
--
-- Each Lua add-on runs its own main.lua, as the mod loader would run it, but
-- with a stand-in `wml` table: settings come from the add-on's settings.ini,
-- files go to its folder, keys read as "not pressed" while this menu is open,
-- and keys it takes or holds are given back when it is switched off. A
-- `srtm` table in that stand-in is how the add-on and the menu talk.
--
-- Precise Aim has no on/off of its own: while it is off its hooks only run the
-- game's code, and its release() (in its file) first undoes what it changed.
-- Fine Aim has its own on/off (enabled), which the menu drives through
-- srtm.live(). Weapon Switch reads the menu's flags from the mailbox.

local AD = { loaded = {} }

local MAILBOX = 0x00F00000
local FLAGS, FLAGS_MAGIC = MAILBOX + 0x30, MAILBOX + 0x34
local MAGIC = 0x53524144   -- 'SRAD'

-- [settings] of an ini file: lower-case name -> value text.
local function read_settings(path)
  local out, section = {}, nil
  local f = io.open(path, "r")
  if not f then return out end
  for line in f:lines() do
    line = line:gsub("\r$", "")
    local s = line:match("^%s*%[(.-)%]%s*$")
    if s then section = s:lower()
    elseif section == "settings" and not line:match("^%s*[;#]") then
      local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
      if k then out[k:lower()] = v end
    end
  end
  f:close()
  return out
end

-- wml.setting as the loader does it: converted to the default's type.
local function setting_reader(values)
  return function(name, default)
    local v = values[tostring(name):lower()]
    if v == nil then return default end
    if type(default) == "number" then
      local n = tonumber(v:match("^%s*([-+]?[%d%.]+[eE]?[-+]?%d*)"))
      if n then return n end
      return default
    end
    if type(default) == "boolean" then
      v = v:lower()
      return v == "true" or v == "1" or v == "yes" or v == "on"
    end
    return v
  end
end

-- Runs folder/main.lua with a stand-in wml. opts: live() -> bool, quiet() ->
-- bool (keys read as up), gate = true to pass the hooks straight through while
-- off, release() run once when it goes off.
function AD.load(name, folder, opts)
  local srtm = { live = opts.live }
  local values = read_settings(folder .. "/settings.ini")
  local taken, forced = {}, {}
  local proxy = setmetatable({}, { __index = wml })
  proxy.mod_name, proxy.mod_folder = name, folder
  proxy.settings = values
  proxy.setting = setting_reader(values)
  -- Not offered: reloading would reload the whole menu, and the menu owns the text overlay.
  proxy.reload_lua_mod, proxy.on_settings_changed, proxy.overlay_text = false, false, false
  proxy.srtm = srtm
  proxy.key_down = function(k) if opts.quiet() then return false end return wml.key_down(k) end
  proxy.key_pressed = function(k) if opts.quiet() then return false end return wml.key_pressed(k) end
  proxy.take_key = function(k, on)
    taken[k] = (on ~= false) or nil
    return wml.take_key(k, on)
  end
  proxy.force_key = function(k, down)
    forced[k] = down and true or nil
    return wml.force_key(k, down)
  end

  local was_live = false
  local function release()
    if srtm.release then
      local ok, err = pcall(srtm.release)
      if not ok then wml.log(name .. ": release failed: " .. tostring(err)) end
    end
    for k in pairs(taken) do pcall(wml.take_key, k, false) end
    for k in pairs(forced) do pcall(wml.force_key, k, false) end
    taken, forced = {}, {}
  end
  local function live_now()
    local on = opts.live()
    if on ~= was_live then
      was_live = on
      if not on then release() end
      wml.log(name .. (on and " on" or " off"))
    end
    return on
  end

  if opts.gate then
    proxy.hook = function(addr, fn)
      return wml.hook(addr, function(ctx)
        if live_now() or (srtm.must and srtm.must(addr)) then return fn(ctx) end
        ctx:call_original()
      end)
    end
    proxy.on_frame = function(fn)
      return wml.on_frame(function(...)
        if live_now() then return fn(...) end
      end)
    end
  end

  local env = setmetatable({ wml = proxy }, { __index = _G })
  local chunk, err = loadfile(folder .. "/main.lua", "t", env)
  if not chunk then
    wml.log(name .. ": could not load: " .. tostring(err))
    return nil
  end
  local ok, run_err = pcall(chunk)
  if not ok then
    wml.log(name .. ": stopped while starting: " .. tostring(run_err))
    return nil
  end
  AD.loaded[name] = srtm
  return srtm
end

-- The flags Weapon Switch reads: bit0 on, bit1 menu open, bit2 free camera,
-- bit3 the D-pad is the game's again, bit4 a tap of the wheel button does not
-- switch, bit5 a menu combo is being pressed (so it is never a tap).
local flags = 0
local function put_flags(v)
  flags = v
  if wml.read_u32(FLAGS) ~= v then wml.write_u32(FLAGS, v) end
  if wml.read_u32(FLAGS_MAGIC) ~= MAGIC then wml.write_u32(FLAGS_MAGIC, MAGIC) end
end
function AD.write_flags(on, menu_open, freecam, no_dpad, no_tap)
  put_flags((on and 1 or 0) | (menu_open and 2 or 0) | (freecam and 4 or 0) | (no_dpad and 8 or 0)
    | (no_tap and 16 or 0) | (flags & 32))
end
-- From the controller hook, which runs just before Weapon Switch looks at the pad.
function AD.set_combo(down)
  local v = down and (flags | 32) or (flags & ~32)
  if v ~= flags then put_flags(v) end
end

return AD
