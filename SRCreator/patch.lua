-- The always-loaded chunk with the creator pieces in it (build_chunk.py makes it from
-- the game's own, so it is game data: it stays in this folder, out of any repo).
local f = io.open(wml.mod_folder .. "/sr_alwaysload01.bbchunk_xbox2", "rb")
if not f then
  wml.log("sr_alwaysload01.bbchunk_xbox2 is missing")
  return
end
local data = f:read("a")
f:close()
wml.packfile_write("misc2.vpp_xbox2", "sr_alwaysload01.bbchunk_xbox2", data)
wml.log(string.format("chunk written, %d bytes", #data))
