local R={}
local _host=require
local B={device_boot="seq3ui",engine="seq3e",ext="seq3x",generate="seq3x",headless="seq3h",menu="seq3ui",midi_rx="seq3ui",ops="seq3x",persist="seq3p",preset="seq3p",screen="seq3ui",seq_data="seq3h"}
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
M.EXTERNAL_FIRST      = 6
M.EXTERNAL_LAST       = 13
M.EXTERNAL_COUNT      = 8
M.LANE_FIRST          = 14
M.LANE_LAST           = 17
M.LANE_COUNT          = 4
M.TRANSPORT_INTERVAL = {
[M.TRANSPORT_WHOLE]     = 96,
[M.TRANSPORT_HALF]      = 48,
[M.TRANSPORT_QUARTER]   = 24,
[M.TRANSPORT_EIGHTH]    = 12,
[M.TRANSPORT_SIXTEENTH] = 6,
}
local NAMES = {
["off"]                 = M.OFF,
["transport.whole"]     = M.TRANSPORT_WHOLE,
["transport.half"]      = M.TRANSPORT_HALF,
["transport.quarter"]   = M.TRANSPORT_QUARTER,
["transport.eighth"]    = M.TRANSPORT_EIGHTH,
["transport.sixteenth"] = M.TRANSPORT_SIXTEENTH,
}
for i = 0, M.EXTERNAL_COUNT - 1 do
NAMES["external." .. i] = M.EXTERNAL_FIRST + i
end
for i = 0, M.LANE_COUNT - 1 do
NAMES["lane." .. (i + 1)] = M.LANE_FIRST + i
end
function M.parse(value, default)
if type(value) == "number" then return value end
local v = NAMES[value]
if v == nil then return default or M.OFF end
return v
end
local REVERSE
function M.name(src)
if not REVERSE then
REVERSE = {}
for k, v in pairs(NAMES) do REVERSE[v] = k end
end
return REVERSE[src] or "off"
end
function M.isTransport(src)
return src >= M.TRANSPORT_WHOLE and src <= M.TRANSPORT_SIXTEENTH
end
function M.isExternal(src)
return src >= M.EXTERNAL_FIRST and src <= M.EXTERNAL_LAST
end
function M.isLane(src)
return src >= M.LANE_FIRST and src <= M.LANE_LAST
end
return M

end)()
R["scales"]=(function()

local M = {}
M.SCALES = {
{ name = "off",        mask = 0x000 },
{ name = "major",      mask = 0xAB5 },
{ name = "minor",      mask = 0x5AD },
{ name = "harm min",   mask = 0x9AD },
{ name = "dorian",     mask = 0x6AD },
{ name = "phrygian",   mask = 0x5AB },
{ name = "mixolydian", mask = 0x6B5 },
{ name = "min pent",   mask = 0x4A9 },
}
M.MAJOR = 0xAB5
M.MINOR = 0x5AD
function M.rotate(mask, root)
root = (root or 0) % 12
if root == 0 then return mask & 0xFFF end
return ((mask << root) | (mask >> (12 - root))) & 0xFFF
end
function M.step(pitch, mask, d)
if mask == 0 then
local r = pitch + d
if r < 0 then return 0 elseif r > 127 then return 127 else return r end
end
local p = M.quantize(pitch, mask)
local dir = (d >= 0) and 1 or -1
for _ = 1, (d >= 0 and d or -d) do
local q = p + dir
while q >= 0 and q <= 127 and ((mask >> (q % 12)) & 1) == 0 do
q = q + dir
end
if q < 0 then return 0 elseif q > 127 then return 127 else p = q end
end
return p
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
M.PPQN = 24
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
M.DIMS = DIMS
function M.isValidDims(name) return DIMS[name] ~= nil end
function M.new(kind)
local l = {
type = kind or "note",
dims = "16x1", width = 16, height = 1,
length = 16, division = 1, divCount = 0,
position = 1, emit = false, pendingReset = false, fired = false,
channel = 1, controller = 1, midiNote = 60,
scaleMask = 0xAB5, rawScaleMask = 0xAB5, root = 0,
minNote = 0, maxNote = 127,
minValue = 0, maxValue = 127,
advanceSource = Sources.OFF,
xAdvanceSource = Sources.OFF,
yAdvanceSource = Sources.OFF,
resetSource = Sources.OFF,
randomSource = Sources.OFF,
previousSource = Sources.OFF,
shiftSource = Sources.OFF, shiftAmount = 1,
addressSource = Sources.OFF,
xAddressSource = Sources.OFF,
yAddressSource = Sources.OFF,
activeNote = nil, noteOffIn = 0, sustain = false,
generator = 0,
genBase = 60, genSpread = 12, genDownUp = 64,
genVelSpread = 0, genGateSpread = 0, rng = 1,
pitch = {}, velocity = {}, stepLength = {}, value = {}, gate = {},
}
for i = 1, M.CAP do
l.pitch[i] = 60
l.velocity[i] = 100
l.stepLength[i] = 6
l.value[i] = 0
l.gate[i] = 0
end
return l
end
function M.usedSteps(lane) return lane.width * lane.height end
function M.limit(lane)
if lane.height == 1 then return lane.length end
return lane.width * lane.height
end
function M.index(lane, x, y)
return y * lane.width + x + 1
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
if lane.type == "note" then
rotateOne(lane.pitch, used, amount)
rotateOne(lane.velocity, used, amount)
rotateOne(lane.stepLength, used, amount)
elseif lane.type == "mod" then
rotateOne(lane.value, used, amount)
else
rotateOne(lane.gate, used, amount)
end
end
return M

end)()
return R
