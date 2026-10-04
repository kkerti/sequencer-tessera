local R={}
local _host=require
local B={device_boot="seq3ui",edit="seq3l",engine="seq3e",lane="seq3",lane_focus="seq3f",midi_rx="seq3ui",ops="seq3x",persist="seq3p",preset="seq3l",scales="seq3",screen="seq3s",source_names="seq3p",sources="seq3",transport="seq3"}
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
R["seq_data"]=(function()

local Scales = require("scales")
local M = {}
local MELODY = { 69, 72, 76, 72, 67, 72, 76, 79,
69, 72, 76, 72, 65, 69, 72, 76 }
local BASS   = { 45, 45, 52, 45, 41, 41, 48, 41 }
local DRUM   = { 1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 0 }
local SIXTEENTH = 5
local EIGHTH    = 4
function M.apply(Engine)
Engine.init{ lanes = 3, channel = 1 }
local a, b, c = Engine.lanes[1], Engine.lanes[2], Engine.lanes[3]
a.channel = 1
a.rawScaleMask, a.root = 0x5AD, 9
a.scaleMask = Scales.rotate(0x5AD, 9)
a.advanceSource = SIXTEENTH
for i = 1, 16 do
a.pitch[i] = MELODY[i]; a.velocity[i] = 90; a.stepLength[i] = 4
end
b.channel = 2
b.length = 8
b.advanceSource = EIGHTH
for i = 1, 8 do
b.pitch[i] = BASS[i]; b.velocity[i] = 105; b.stepLength[i] = 10
end
c.type = "trig"
c.channel = 10
c.midiNote = 36
c.advanceSource = SIXTEENTH
for i = 1, 16 do c.gate[i] = DRUM[i] end
return true
end
return M

end)()
R["headless"]=(function()

local M = {}
local Engine, Data
local started = false
function M.ensure()
if started then return end
started = true
print("seq3h: engine")
Engine = require("engine")
print("seq3h: engine ok")
Data = require("seq_data")
Data.apply(Engine)
print("seq3h: sequence ok")
Engine.onStart()
print("seq3h: running")
end
local function emit(out, send)
local n = out.n
local typ, pitch, vel, ch = out.typ, out.pitch, out.velocity, out.channel
for i = 1, n do
local t = typ[i]
if t == 1 then
send(ch[i], 0x90, pitch[i], vel[i])
elseif t == 2 then
send(ch[i], 0xB0, pitch[i], vel[i])
else
send(ch[i], 0x80, pitch[i], 0)
end
end
end
function M.handle(t, send)
M.ensure()
if t == 0xF8 then
emit(Engine.onPulse(), send)
elseif t == 0xFA then
Engine.onStart()
elseif t == 0xFB then
if not Engine.running then Engine.onStart() end
elseif t == 0xFC then
emit(Engine.onStop(), send)
end
end
function M.key() M.ensure() end
local function limit(l)
if l.height == 1 then return l.length end
return l.width * l.height
end
local function playing(l)
if not l.activeNote then return "-" end
return "n" .. l.activeNote
end
function M.report()
if not Engine then
print("seq3h: idle (send clock or press a key)")
return
end
for i = 1, #Engine.lanes do
local l = Engine.lanes[i]
print("L" .. i .. " " .. l.type
.. " ch" .. l.channel
.. " step " .. l.position .. "/" .. limit(l)
.. " " .. playing(l)
.. (Engine.running and "" or " STOPPED"))
end
end
return M

end)()
return R
