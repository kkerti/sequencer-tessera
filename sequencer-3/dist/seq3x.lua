local R={}
local _host=require
local _1
local _x
local function require(n)
 local r=R[n] if r~=nil then return r end
 if not _1 then _1=_host('seq3') end local m=_1[n] if m then return m end
 if not _x then _x=_host('seq3x') end x=_x[n] if x then return x end
 error('seq3 module not found: '..tostring(n))
end
local _1
local _x
local x
R["generate"]=(function()

local Scales = require("scales")
local M = {}
local RNG_MOD = 2147483647
function M.seed(lane, seed)
local s = (seed or 1) % RNG_MOD
if s <= 0 then s = 1 end
lane.rng = s
end
function M.configure(lane, opts)
opts = opts or {}
lane.genBase = opts.base or 60
lane.genSpread = opts.spread or 12
lane.genDownUp = opts.downUp or 64
lane.genVelSpread = opts.velSpread or 0
lane.genGateSpread = opts.gateSpread or 0
M.seed(lane, opts.seed or 1)
end
local function nextInt(lane, lo, hi)
lane.rng = (lane.rng * 1103515245 + 12345) % RNG_MOD
local span = hi - lo + 1
local v = lo + math.floor((lane.rng / RNG_MOD) * span)
if v > hi then v = hi end
return v
end
local function clamp(v, lo, hi)
if v < lo then return lo elseif v > hi then return hi else return v end
end
function M.step(lane, pos)
pos = pos or lane.position
if lane.type == "note" then
local up = math.floor(lane.genSpread * lane.genDownUp / 127 + 0.5)
local down = lane.genSpread - up
local off = nextInt(lane, -down, up)
lane.pitch[pos] = clamp(Scales.quantize(lane.genBase + off, lane.scaleMask),
lane.minNote, lane.maxNote)
if lane.genVelSpread > 0 then
lane.velocity[pos] = clamp(100 + nextInt(lane, -lane.genVelSpread, lane.genVelSpread), 1, 127)
end
if lane.genGateSpread > 0 then
lane.stepLength[pos] = math.max(1, 6 + nextInt(lane, -lane.genGateSpread, lane.genGateSpread))
end
elseif lane.type == "mod" then
local mid = (lane.minValue + lane.maxValue) // 2
lane.value[pos] = clamp(mid + nextInt(lane, -lane.genSpread, lane.genSpread), 0, 127)
else
local density = (lane.genSpread > 0 and lane.genSpread <= 100) and lane.genSpread or 50
lane.gate[pos] = (nextInt(lane, 0, 99) < density) and 1 or 0
end
end
local function usedSteps(lane)
if lane.height == 1 then return lane.length end
return lane.width * lane.height
end
function M.fill(lane)
local used = usedSteps(lane)
for i = 1, used do M.step(lane, i) end
end
function M.euclidean(lane, opts)
opts = opts or {}
local used = usedSteps(lane)
local hits = opts.hits or math.max(1, used // 4)
if hits > used then hits = used end
local rotate = opts.rotate or 0
for i = 1, used do
local idx = ((i - 1) + rotate) % used
lane.gate[i] = (((idx * hits) % used) < hits) and 1 or 0
end
return true
end
return M

end)()
R["ext"]=(function()

return function(E, tool)
local srcVal = tool.srcVal
local function applyAddress(lane, src)
local v = srcVal(src)
if not v then return end
local used = lane.width * lane.height
local pos = (v * used) // 127 + 1
if pos > used then pos = used end
if pos < 1 then pos = 1 end
if pos ~= lane.position then
lane.position = pos
lane.emit = true
end
end
local function applyXAddress(lane, src)
local v = srcVal(src)
if not v then return end
local x = (v * lane.width) // 127
if x >= lane.width then x = lane.width - 1 end
if x < 0 then x = 0 end
local y = (lane.position - 1) // lane.width
local pos = y * lane.width + x + 1
if pos ~= lane.position then
lane.position = pos
lane.emit = true
end
end
local function applyYAddress(lane, src)
local v = srcVal(src)
if not v then return end
local y = (v * lane.height) // 127
if y >= lane.height then y = lane.height - 1 end
if y < 0 then y = 0 end
local x = (lane.position - 1) % lane.width
local pos = y * lane.width + x + 1
if pos ~= lane.position then
lane.position = pos
lane.emit = true
end
end
return function(l)
if l.addressSource ~= 0 then applyAddress(l, l.addressSource) end
if l.xAddressSource ~= 0 then applyXAddress(l, l.xAddressSource) end
if l.yAddressSource ~= 0 then applyYAddress(l, l.yAddressSource) end
end
end

end)()
R["ops"]=(function()

local Lane = require("lane")
return function(E, tool)
local lanep = tool.lanep
local M = {}
function M.shred(lane)
local l = lanep(lane); if not l then return false end
local pos = l.position
if l.type == "note" then
l.pitch[pos] = tool.clamp(math.random(l.minNote, l.maxNote), 0, 127)
l.velocity[pos] = math.random(1, 127)
elseif l.type == "mod" then
l.value[pos] = math.random(l.minValue, l.maxValue)
else
l.gate[pos] = math.random(0, 1)
end
return true
end
function M.zero(lane)
local l = lanep(lane); if not l then return false end
local pos = l.position
if l.type == "note" then l.pitch[pos] = l.minNote
elseif l.type == "mod" then l.value[pos] = l.minValue
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
R["preset"]=(function()

local Lane = require("lane")
return function(E, tool)
local lanep = tool.lanep
local M = {}
function M.copy(from, to)
local src, dst = lanep(from), lanep(to)
if not src or not dst then return false end
local used = Lane.limit(dst)
for i = 1, Lane.CAP do
dst.pitch[i] = src.pitch[i]
dst.velocity[i] = src.velocity[i]
dst.stepLength[i] = src.stepLength[i]
dst.value[i] = src.value[i]
dst.gate[i] = src.gate[i]
end
dst.type = src.type
dst.scaleMask, dst.rawScaleMask, dst.root = src.scaleMask, src.rawScaleMask, src.root
dst.minNote, dst.maxNote = src.minNote, src.maxNote
dst.minValue, dst.maxValue = src.minValue, src.maxValue
dst.controller = src.controller
dst.length = src.length
dst.division = src.division
if (dst.width * dst.height) < used then dst.length = dst.width * dst.height end
return true
end
function M.loadPreset(data)
if type(data) ~= "table" or type(data.lanes) ~= "table" then return false end
for i = 1, #E.lanes do
local p = data.lanes[i]
if type(p) == "table" then
local l = E.lanes[i]
if p.type then E.setType(i, p.type) end
if p.dims then E.setDimensions(i, p.dims) end
if p.length then E.setLength(i, p.length) end
if p.division then E.setDivision(i, p.division) end
if p.channel then E.setChannel(i, p.channel) end
if p.controller then E.setController(i, p.controller) end
if p.midiNote then E.setMidiNote(i, p.midiNote) end
if p.scaleMask then E.setScale(i, p.scaleMask, p.root or 0) end
if p.advanceSource then E.setAdvanceSource(i, p.advanceSource) end
if p.xAdvanceSource then E.setXAdvanceSource(i, p.xAdvanceSource) end
if p.yAdvanceSource then E.setYAdvanceSource(i, p.yAdvanceSource) end
if p.resetSource then E.setResetSource(i, p.resetSource) end
if p.randomSource then E.setRandomSource(i, p.randomSource) end
if p.previousSource then E.setPreviousSource(i, p.previousSource) end
if p.shiftSource then E.setShiftSource(i, p.shiftSource) end
if p.shiftAmount then E.setShiftAmount(i, p.shiftAmount) end
if p.addressSource then E.setAddressSource(i, p.addressSource) end
if p.xAddressSource then E.setXAddressSource(i, p.xAddressSource) end
if p.yAddressSource then E.setYAddressSource(i, p.yAddressSource) end
if p.minNote or p.maxNote then E.setRange(i, p.minNote or 0, p.maxNote or 127) end
if p.pitch then for k = 1, #p.pitch do l.pitch[k] = p.pitch[k] end end
if p.velocity then for k = 1, #p.velocity do l.velocity[k] = p.velocity[k] end end
if p.stepLength then for k = 1, #p.stepLength do l.stepLength[k] = p.stepLength[k] end end
if p.value then for k = 1, #p.value do l.value[k] = p.value[k] end end
if p.gate then for k = 1, #p.gate do l.gate[k] = p.gate[k] end end
if p.generate then E.generate(i, p.generate) end
end
end
return true
end
return M
end

end)()
return R
