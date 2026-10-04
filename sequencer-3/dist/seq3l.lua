local R={}
local _host=require
local B={device_boot="seq3ui",engine="seq3e",headless="seq3h",lane="seq3",midi_rx="seq3ui",ops="seq3x",persist="seq3p",scales="seq3",screen="seq3s",seq_data="seq3h",source_names="seq3p",sources="seq3",transport="seq3"}
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
R["preset"]=(function()

local Lane = require("lane")
return function(E, tool)
local lanep, clamp = tool.lanep, tool.clamp
local M = {}
function M.copy(from, to)
local src, dst = lanep(from), lanep(to)
if not src or not dst then return false end
local used = Lane.limit(dst)
for i = 1, Lane.CAP do
dst.pitch[i] = src.pitch[i]
dst.velocity[i] = src.velocity[i]
dst.stepLength[i] = src.stepLength[i]
dst.gate[i] = src.gate[i]
end
dst.type = src.type
dst.scaleMask, dst.rawScaleMask, dst.root = src.scaleMask, src.rawScaleMask, src.root
dst.minNote, dst.maxNote = src.minNote, src.maxNote
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
if p.minNote or p.maxNote then
l.minNote = clamp(p.minNote or 0, 0, 127)
l.maxNote = clamp(p.maxNote or 127, 0, 127)
end
if p.pitch then for k = 1, #p.pitch do l.pitch[k] = p.pitch[k] end end
if p.velocity then for k = 1, #p.velocity do l.velocity[k] = p.velocity[k] end end
if p.stepLength then for k = 1, #p.stepLength do l.stepLength[k] = p.stepLength[k] end end
if p.gate then for k = 1, #p.gate do l.gate[k] = p.gate[k] end end
end
end
return true
end
return M
end

end)()
return R
