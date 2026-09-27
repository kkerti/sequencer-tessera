local R={}
local _host=require
local _1
local _x
local function require(n)
 local r=R[n] if r~=nil then return r end
 if not _1 then _1=_host('seq3ui') end local m=_1[n] if m then return m end
 if not _x then _x=_host('seq3x') end x=_x[n] if x then return x end
 error('seq3 module not found: '..tostring(n))
end
local _1
local _x
local x
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
R["engine"]=(function()

local Sources   = require("sources")
local Scales    = require("scales")
local Lane      = require("lane")
local Transport = require("transport")
local M = {}
local OUT_CAP = 64
local MOD_FIRE_THRESHOLD = 64
M.lanes = {}
M.out = { n = 0, typ = {}, pitch = {}, velocity = {}, channel = {} }
M.transport = Transport.new()
M.externalTrigger = {}
M.externalValue = {}
M.laneFired = {}
M.running = false
M.suppressFire = false
function M.init(opts)
opts = opts or {}
local count = opts.lanes or 4
local baseChannel = opts.channel or 1
for i = 1, count do
local kind = (opts.types and opts.types[i]) or "note"
local l = Lane.new(kind)
l.channel = baseChannel + i - 1
M.lanes[i] = l
end
M.out.n = 0
for i = 1, OUT_CAP do
M.out.typ[i] = 0
M.out.pitch[i] = 0
M.out.velocity[i] = 0
M.out.channel[i] = 0
end
for i = 1, Sources.EXTERNAL_COUNT do
M.externalTrigger[i] = false
M.externalValue[i] = nil
end
for i = 1, Sources.LANE_COUNT do M.laneFired[i] = false end
M.transport = Transport.new()
M.running = false
M.suppressFire = false
return M
end
local function addEvent(kind, pitch, velocity, channel)
local n = M.out.n + 1
if n > OUT_CAP then return end
M.out.n = n
M.out.typ[n] = kind
M.out.pitch[n] = pitch
M.out.velocity[n] = velocity
M.out.channel[n] = channel
end
local function sourceFired(src)
if src == Sources.OFF then return false end
if Sources.isTransport(src) then
return Transport.tapFired(M.transport, src)
elseif Sources.isExternal(src) then
return M.externalTrigger[src - Sources.EXTERNAL_FIRST + 1] == true
elseif Sources.isLane(src) then
return M.laneFired[src - Sources.LANE_FIRST + 1] == true
end
return false
end
local function sourceValue(src)
if Sources.isExternal(src) then
return M.externalValue[src - Sources.EXTERNAL_FIRST + 1]
elseif Sources.isLane(src) then
local l = M.lanes[src - Sources.LANE_FIRST + 1]
if not l then return nil end
if l.type == "note" then return l.pitch[l.position]
elseif l.type == "mod" then return l.value[l.position]
else return l.gate[l.position] * 127 end
end
return nil
end
local function applyAdvance(lane, kind)
if lane.pendingReset then
lane.position = 1
lane.divCount = 0
lane.pendingReset = false
lane.emit = true
return
end
lane.divCount = lane.divCount + 1
if lane.divCount < lane.division then return end
lane.divCount = 0
if kind == "x" then Lane.advanceX(lane)
elseif kind == "y" then Lane.advanceY(lane)
elseif kind == "back" then Lane.advanceBackward(lane)
else Lane.advanceForward(lane) end
end
local function applyAddress(lane, src)
local v = sourceValue(src)
if not v then return end
local used = Lane.usedSteps(lane)
local pos = (v * used) // 127 + 1
if pos > used then pos = used end
if pos < 1 then pos = 1 end
if pos ~= lane.position then
lane.position = pos
lane.emit = true
end
end
local function clamp(v, lo, hi)
if v < lo then return lo elseif v > hi then return hi else return v end
end
local Generate, Ops, Ext, Preset
local lanep
local function loadGenerate()
if not Generate then Generate = require("generate") end
return Generate
end
local function loadOps()
if not Ops then
Ops = require("ops")(M, { lanep = lanep, clamp = clamp })
end
return Ops
end
local function loadPresetMod()
if not Preset then
Preset = require("preset")(M, { lanep = lanep, clamp = clamp })
end
return Preset
end
local function loadExt()
if not Ext then Ext = require("ext")(M, { srcVal = sourceValue }) end
return Ext
end
local function applyAddressAll(l)
applyAddressAll = loadExt()
applyAddressAll(l)
end
local function emitStep(lane)
local pos = lane.position
lane.fired = false
if lane.type == "note" then
if lane.activeNote then
addEvent(0, lane.activeNote, 0, lane.channel)
lane.activeNote = nil
end
local p = Scales.quantize(lane.pitch[pos], lane.scaleMask)
p = clamp(p, lane.minNote, lane.maxNote)
addEvent(1, p, lane.velocity[pos], lane.channel)
lane.activeNote = p
lane.noteOffIn = lane.stepLength[pos]
lane.sustain = false
lane.fired = true
elseif lane.type == "mod" then
local v = clamp(lane.value[pos], lane.minValue, lane.maxValue)
addEvent(2, lane.controller or 0, v, lane.channel)
lane.fired = v >= MOD_FIRE_THRESHOLD
elseif lane.type == "trig" then
if lane.gate[pos] == 1 then
addEvent(1, lane.midiNote, 100, lane.channel)
lane.activeNote = lane.midiNote
lane.noteOffIn = 1
lane.sustain = false
lane.fired = true
end
elseif lane.type == "gate" then
if lane.gate[pos] == 1 then
if not lane.activeNote then
addEvent(1, lane.midiNote, 100, lane.channel)
lane.activeNote = lane.midiNote
lane.sustain = true
lane.fired = true
end
elseif lane.activeNote then
addEvent(0, lane.activeNote, 0, lane.channel)
lane.activeNote = nil
lane.sustain = false
end
end
lane.emit = false
end
function M.onPulse()
M.out.n = 0
local lanes = M.lanes
local n = #lanes
for i = 1, n do
local l = lanes[i]
if l.activeNote and not l.sustain then
l.noteOffIn = l.noteOffIn - 1
if l.noteOffIn <= 0 then
addEvent(0, l.activeNote, 0, l.channel)
l.activeNote = nil
end
end
end
if not M.running then return M.out end
Transport.tick(M.transport)
for i = 1, n do
local l = lanes[i]
if sourceFired(l.resetSource) then l.pendingReset = true end
if sourceFired(l.randomSource) then Lane.randomizePosition(l) end
if sourceFired(l.shiftSource) then Lane.rotate(l, l.shiftAmount) end
if sourceFired(l.previousSource) then applyAdvance(l, "back") end
if sourceFired(l.advanceSource) then applyAdvance(l, "linear") end
if sourceFired(l.xAdvanceSource) then applyAdvance(l, "x") end
if sourceFired(l.yAdvanceSource) then applyAdvance(l, "y") end
if l.addressSource ~= Sources.OFF or l.xAddressSource ~= Sources.OFF
or l.yAddressSource ~= Sources.OFF then applyAddressAll(l) end
if l.emit then
if l.generator == 1 then loadGenerate().step(l) end
emitStep(l)
end
if i <= Sources.LANE_COUNT then
M.laneFired[i] = (not M.suppressFire) and l.fired or false
end
end
M.suppressFire = false
for i = 1, Sources.EXTERNAL_COUNT do M.externalTrigger[i] = false end
return M.out
end
function M.onStart()
M.out.n = 0
M.running = true
Transport.start(M.transport)
for i = 1, #M.lanes do
local l = M.lanes[i]
l.position = 1
l.divCount = 0
l.pendingReset = false
l.emit = true
end
for i = 1, Sources.LANE_COUNT do M.laneFired[i] = false end
M.suppressFire = true
return M.out
end
function M.onStop()
M.out.n = 0
M.running = false
Transport.stop(M.transport)
for i = 1, #M.lanes do
local l = M.lanes[i]
if l.activeNote then
addEvent(0, l.activeNote, 0, l.channel)
l.activeNote = nil
end
l.emit = false
end
return M.out
end
function M.start() return M.onStart() end
function M.stop()  return M.onStop() end
function M.tick()  return M.onPulse() end
function M.reset()
M.out.n = 0
for i = 1, #M.lanes do
local l = M.lanes[i]
l.position = 1
l.divCount = 0
l.pendingReset = false
l.emit = true
end
return M.out
end
function M.triggerExternal(index)
if index >= 1 and index <= Sources.EXTERNAL_COUNT then
M.externalTrigger[index] = true
end
end
function M.setExternalValue(index, value)
if index >= 1 and index <= Sources.EXTERNAL_COUNT then
M.externalValue[index] = clamp(value, 0, 127)
end
end
lanep = function(index) return M.lanes[index] end
function M.setType(lane, kind)
local l = lanep(lane); if not l then return false end
l.type = kind or "note"
return true
end
function M.setDimensions(lane, name)
local l = lanep(lane); if not l then return false end
return Lane.setDims(l, name)
end
function M.setLength(lane, n)
local l = lanep(lane); if not l then return false end
if l.height ~= 1 then return false end
l.length = clamp(n, 1, Lane.CAP)
if l.position > l.length then l.position = 1 end
return true
end
function M.setDivision(lane, n)
local l = lanep(lane); if not l then return false end
l.division = clamp(n, 1, 16)
return true
end
function M.setChannel(lane, channel)
local l = lanep(lane); if not l then return false end
l.channel = clamp(channel, 1, 16)
return true
end
function M.setController(lane, cc)
local l = lanep(lane); if not l then return false end
l.controller = clamp(cc, 0, 127)
return true
end
function M.setMidiNote(lane, note)
local l = lanep(lane); if not l then return false end
l.midiNote = clamp(note, 0, 127)
return true
end
function M.setScale(lane, mask, root)
local l = lanep(lane); if not l then return false end
l.rawScaleMask = mask or 0
l.root = (root or 0) % 12
l.scaleMask = Scales.rotate(l.rawScaleMask, l.root)
return true
end
function M.setRange(lane, min, max)
local l = lanep(lane); if not l then return false end
if l.type == "mod" then
l.minValue = clamp(min, 0, 127); l.maxValue = clamp(max, 0, 127)
else
l.minNote = clamp(min, 0, 127); l.maxNote = clamp(max, 0, 127)
end
return true
end
local function setSource(lane, field, value)
local l = lanep(lane); if not l then return false end
l[field] = Sources.parse(value)
return true
end
function M.setAdvanceSource(lane, src) return setSource(lane, "advanceSource", src) end
function M.setXAdvanceSource(lane, src) return setSource(lane, "xAdvanceSource", src) end
function M.setYAdvanceSource(lane, src) return setSource(lane, "yAdvanceSource", src) end
function M.setResetSource(lane, src) return setSource(lane, "resetSource", src) end
function M.setRandomSource(lane, src) return setSource(lane, "randomSource", src) end
function M.setPreviousSource(lane, src) return setSource(lane, "previousSource", src) end
function M.setShiftSource(lane, src) return setSource(lane, "shiftSource", src) end
function M.setAddressSource(lane, src) return setSource(lane, "addressSource", src) end
function M.setXAddressSource(lane, src) return setSource(lane, "xAddressSource", src) end
function M.setYAddressSource(lane, src) return setSource(lane, "yAddressSource", src) end
function M.setShiftAmount(lane, steps)
local l = lanep(lane); if not l then return false end
l.shiftAmount = steps | 0
return true
end
function M.setPosition(lane, step)
local l = lanep(lane); if not l then return false end
Lane.setPosition(l, step)
return true
end
function M.setPitch(lane, step, note)
local l = lanep(lane); if not l or step < 1 or step > Lane.CAP then return false end
l.pitch[step] = clamp(note, 0, 127)
return true
end
function M.setVelocity(lane, step, v)
local l = lanep(lane); if not l or step < 1 or step > Lane.CAP then return false end
l.velocity[step] = clamp(v, 1, 127)
return true
end
function M.setStepLength(lane, step, ticks)
local l = lanep(lane); if not l or step < 1 or step > Lane.CAP then return false end
l.stepLength[step] = math.max(1, ticks | 0)
return true
end
function M.setValue(lane, step, v)
local l = lanep(lane); if not l or step < 1 or step > Lane.CAP then return false end
l.value[step] = clamp(v, 0, 127)
return true
end
function M.setGate(lane, step, on)
local l = lanep(lane); if not l or step < 1 or step > Lane.CAP then return false end
l.gate[step] = (on == false or on == 0 or on == nil) and 0 or 1
return true
end
function M.generate(lane, opts)
local l = lanep(lane); if not l then return false end
opts = opts or {}
local G = loadGenerate()
local kind = opts.kind or "gamut"
if kind == "euclid" or kind == "rhythm" then
return G.euclidean(l, opts)
end
G.configure(l, opts)
if opts.fill ~= false then G.fill(l) end
l.generator = opts.live and 1 or 0
return true
end
setmetatable(M, {
__index = function(t, k)
local fn
if k == "shred" or k == "zero" or k == "rotate" then
fn = loadOps()[k]
elseif k == "copy" or k == "loadPreset" then
fn = loadPresetMod()[k]
end
if fn then t[k] = fn end
return fn
end,
})
function M.get(lane, field)
local l = lanep(lane); if not l then return nil end
return l[field]
end
function M.set(lane, field, value)
local l = lanep(lane); if not l then return false end
l[field] = value
return true
end
function M.state(lane) return lanep(lane) end
function M.dump() return M.lanes, M.out end
return M

end)()
return R
