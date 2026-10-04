local R={}
local _host=require
local B={device_boot="seq3ui",edit="seq3l",engine="seq3e",headless="seq3h",midi_rx="seq3ui",ops="seq3x",persist="seq3p",preset="seq3l",screen="seq3s",seq_data="seq3h",source_names="seq3p"}
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
R["sources"]=(function()

local M = {}
M.OFF                 = 0
M.TRANSPORT_WHOLE     = 1
M.TRANSPORT_HALF      = 2
M.TRANSPORT_QUARTER   = 3
M.TRANSPORT_EIGHTH    = 4
M.TRANSPORT_SIXTEENTH = 5
M.TRANSPORT_INTERVAL = {
[M.TRANSPORT_WHOLE]     = 96,
[M.TRANSPORT_HALF]      = 48,
[M.TRANSPORT_QUARTER]   = 24,
[M.TRANSPORT_EIGHTH]    = 12,
[M.TRANSPORT_SIXTEENTH] = 6,
}
function M.parse(value, default)
if type(value) == "number" then return value end
local v = require("source_names").names[value]
if v == nil then return default or M.OFF end
return v
end
function M.name(src)
return require("source_names").reverse[src] or "off"
end
return M

end)()
R["scales"]=(function()

local M = {}
M.MAJOR = 0xAB5
M.MINOR = 0x5AD
function M.rotate(mask, root)
root = (root or 0) % 12
if root == 0 then return mask & 0xFFF end
return ((mask << root) | (mask >> (12 - root))) & 0xFFF
end
function M.quantize(p, mask)
if mask == 0 then return p end
local pc = p % 12
if (mask >> pc) & 1 == 1 then return p end
local base = (p // 12) * 12
for d = 1, 12 do
local dn = pc - d
if dn >= 0 then
if (mask >> dn) & 1 == 1 then return base + dn end
else
local dd = dn + 12
if (mask >> dd) & 1 == 1 then
local r = base - 12 + dd
if r < 0 then return 0 end
return r
end
end
local up = pc + d
if up < 12 then
if (mask >> up) & 1 == 1 then return base + up end
else
local u = up - 12
if (mask >> u) & 1 == 1 then return base + 12 + u end
end
end
return p
end
return M

end)()
R["transport"]=(function()

local Sources = require("sources")
local M = {}
function M.new()
return { running = false, pulse = 0 }
end
function M.start(t)
t.running = true
t.pulse = 0
end
function M.stop(t)
t.running = false
end
function M.tick(t)
if not t.running then return false end
t.pulse = t.pulse + 1
return true
end
function M.fired(t, interval)
if not t.running or interval <= 0 then return false end
return (t.pulse % interval) == 0
end
function M.tapFired(t, source)
local interval = Sources.TRANSPORT_INTERVAL[source]
if not interval then return false end
return M.fired(t, interval)
end
return M

end)()
R["lane"]=(function()

local Sources = require("sources")
local M = {}
M.CAP = 16
local DIMS = {
["16x1"] = { width = 16, height = 1 },
["8x2"]  = { width = 8,  height = 2 },
["5x3"]  = { width = 5,  height = 3 },
["4x3"]  = { width = 4,  height = 3 },
["4x4"]  = { width = 4,  height = 4 },
}
function M.new(kind)
local l = {
type = kind or "note",
dims = "16x1", width = 16, height = 1,
length = 16, division = 1, divCount = 0,
position = 1, emit = false, pendingReset = false,
channel = 1, midiNote = 60,
scaleMask = 0xAB5, rawScaleMask = 0xAB5, root = 0,
minNote = 0, maxNote = 127,
advanceSource = Sources.OFF,
xAdvanceSource = Sources.OFF,
yAdvanceSource = Sources.OFF,
resetSource = Sources.OFF,
randomSource = Sources.OFF,
previousSource = Sources.OFF,
shiftSource = Sources.OFF, shiftAmount = 1,
activeNote = nil, noteOffIn = 0,
pitch = {}, velocity = {}, stepLength = {}, gate = {},
}
for i = 1, M.CAP do
l.pitch[i] = 60
l.velocity[i] = 100
l.stepLength[i] = 6
l.gate[i] = 0
end
return l
end
function M.usedSteps(lane) return lane.width * lane.height end
function M.limit(lane)
if lane.height == 1 then return lane.length end
return lane.width * lane.height
end
function M.setPosition(lane, p)
local limit = M.limit(lane)
if p < 1 then p = 1 elseif p > limit then p = limit end
lane.position = p
lane.emit = true
end
function M.advanceForward(lane)
local limit = M.limit(lane)
local p = lane.position + 1
if p > limit then p = 1 end
lane.position = p
lane.emit = true
end
function M.advanceBackward(lane)
local limit = M.limit(lane)
local p = lane.position - 1
if p < 1 then p = limit end
lane.position = p
lane.emit = true
end
function M.advanceX(lane)
if lane.height == 1 then return M.advanceForward(lane) end
local p = lane.position - 1
local x = p % lane.width
local y = p // lane.width
x = (x + 1) % lane.width
lane.position = y * lane.width + x + 1
lane.emit = true
end
function M.advanceY(lane)
if lane.height == 1 then return end
local p = lane.position - 1
local x = p % lane.width
local y = p // lane.width
y = (y + 1) % lane.height
lane.position = y * lane.width + x + 1
lane.emit = true
end
function M.randomizePosition(lane)
lane.position = math.random(1, M.limit(lane))
lane.emit = true
end
function M.setDims(lane, name)
local d = DIMS[name]
if not d then return false end
lane.dims, lane.width, lane.height = name, d.width, d.height
local used = lane.width * lane.height
if lane.length > used then lane.length = used end
if lane.position > M.limit(lane) then lane.position = 1 end
return true
end
local scratch = {}
local function rotateOne(arr, used, amount)
for i = 1, used do scratch[i] = arr[i] end
for i = 1, used do arr[((i - 1 + amount) % used) + 1] = scratch[i] end
end
function M.rotate(lane, amount)
local used = M.limit(lane)
amount = amount % used
if amount == 0 then return end
rotateOne(lane.velocity, used, amount)
rotateOne(lane.stepLength, used, amount)
if lane.type == "note" then
rotateOne(lane.pitch, used, amount)
else
rotateOne(lane.gate, used, amount)
end
end
return M

end)()
return R
