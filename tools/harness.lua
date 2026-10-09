-- Offline test harness: fakes the wml table over extracted tables.
local src, out, ini = arg[1], arg[2], arg[3]
local settings = {}
for line in io.lines(ini) do
  local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
  if k and not line:match("^%s*;") then settings[k] = v end
end
local function read(p) local f = io.open(p, "rb"); if not f then return nil end local d = f:read("a"); f:close(); return d end
wml = {
  mod_name = "test", mod_folder = ".",
  log = function(...) print("[log]", ...) end,
  setting = function(name, default)
    local v = settings[name]
    if v == nil then return default end
    if type(default) == "number" then return tonumber(v) end
    if type(default) == "boolean" then return v == "true" or v == "1" end
    return v
  end,
  packfile_read = function(pack, name) return read(src .. "/" .. pack .. "/" .. name) end,
  packfile_write = function(pack, name, data)
    os.execute("mkdir -p '" .. out .. "/" .. pack .. "'")
    local f = assert(io.open(out .. "/" .. pack .. "/" .. name, "wb")); f:write(data); f:close()
  end,
}
dofile(arg[4])
