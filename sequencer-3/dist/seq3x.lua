local R={}
local _host=require
local B={device_boot="seq3ui",edit="seq3l",engine="seq3e",headless="seq3h",lane="seq3",midi_rx="seq3ui",persist="seq3p",preset="seq3l",scales="seq3",screen="seq3s",seq_data="seq3h",source_names="seq3p",sources="seq3",transport="seq3"}
local C={}
local function require(n)
 local r=R[n] if r~=nil then return r end
 local b=B[n]
 if b then
  local m=C[b] if not m then m=_host(b) C[b]=m end
  local v=m[n] if v~=nil then return v end
 end
 error('seq3 module not found: '..tostring(n))
end
R["ops"]=(function()

local Lane = require("lane")
return function(E, tool)
local lanep = tool.lanep
local M = {}
local function shredAt(l, pos)
if l.type == "note" then
l.pitch[pos] = tool.clamp(math.random(l.minNote, l.maxNote), 0, 127)
l.velocity[pos] = math.random(1, 127)
else
l.gate[pos] = math.random(0, 1)
end
end
function M.shred(lane)
local l = lanep(lane); if not l then return false end
shredAt(l, l.position)
return true
end
function M.randomize(lane)
local l = lanep(lane); if not l then return false end
for pos = 1, Lane.limit(l) do shredAt(l, pos) end
return true
end
function M.zero(lane)
local l = lanep(lane); if not l then return false end
local pos = l.position
if l.type == "note" then l.pitch[pos] = l.minNote
else l.gate[pos] = 0 end
return true
end
function M.rotate(lane, steps)
local l = lanep(lane); if not l then return false end
Lane.rotate(l, steps | 0)
return true
end
return M
end

end)()
return R
