local R={}
local _host=require
local B={device_boot="seq3ui",engine="seq3e",headless="seq3h",lane="seq3",midi_rx="seq3ui",persist="seq3p",preset="seq3l",scales="seq3",screen="seq3s",seq_data="seq3h",source_names="seq3p",sources="seq3",transport="seq3"}
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
R["edit"]=(function()

local Sources = require("sources")
local Scales  = require("scales")
local Lane    = require("lane")
return function(E, tool)
local lanep, clamp = tool.lanep, tool.clamp
local M = {}
function M.setType(lane, kind)
local l = lanep(lane); if not l then return false end
l.type = (kind == "trig" or kind == "gate") and "trig" or "note"
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
for name, f in pairs{ Division = { "division", 1, 16 }, Channel = { "channel", 1, 16 },
MidiNote = { "midiNote", 0, 127 } } do
local field, lo, hi = f[1], f[2], f[3]
M["set" .. name] = function(lane, v)
local l = lanep(lane); if not l then return false end
l[field] = clamp(v, lo, hi)
return true
end
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
l.minNote = clamp(min, 0, 127); l.maxNote = clamp(max, 0, 127)
return true
end
for _, name in ipairs{ "Advance", "XAdvance", "YAdvance", "Reset", "Random",
"Previous", "Shift" } do
local field = name:sub(1, 1):lower() .. name:sub(2) .. "Source"
M["set" .. name .. "Source"] = function(lane, src)
local l = lanep(lane); if not l then return false end
l[field] = Sources.parse(src)
return true
end
end
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
for name, f in pairs{ Pitch = { "pitch", 0, 127 }, Velocity = { "velocity", 1, 127 } } do
local field, lo, hi = f[1], f[2], f[3]
M["set" .. name] = function(lane, step, v)
local l = lanep(lane); if not l or step < 1 or step > Lane.CAP then return false end
l[field][step] = clamp(v, lo, hi)
return true
end
end
function M.setStepLength(lane, step, ticks)
local l = lanep(lane); if not l or step < 1 or step > Lane.CAP then return false end
l.stepLength[step] = math.max(1, ticks | 0)
return true
end
function M.setGate(lane, step, on)
local l = lanep(lane); if not l or step < 1 or step > Lane.CAP then return false end
l.gate[step] = (on == false or on == 0 or on == nil) and 0 or 1
return true
end
return M
end

end)()
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
