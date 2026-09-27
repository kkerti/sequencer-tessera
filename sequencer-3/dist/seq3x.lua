local R={}
local _host=require
local B={device_boot="seq3ui",engine="seq3",lane="seq3",menu="seq3ui",midi_rx="seq3ui",persist="seq3p",preset="seq3p",scales="seq3",screen="seq3ui",sources="seq3",transport="seq3"}
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
return R
