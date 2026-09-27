local R={}
local _host=require
local B={device_boot="seq3ui",engine="seq3e",ext="seq3x",generate="seq3x",lane="seq3",menu="seq3ui",midi_rx="seq3ui",ops="seq3x",persist="seq3p",preset="seq3p",scales="seq3",screen="seq3ui",sources="seq3",transport="seq3"}
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

local M = {}
local MELODY = { 69, 72, 76, 72, 67, 72, 76, 79,
69, 72, 76, 72, 65, 69, 72, 76 }
local BASS   = { 45, 45, 52, 45, 41, 41, 48, 41 }
local DRUM   = { 1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 0 }
local SIXTEENTH = 5
local EIGHTH    = 4
function M.apply(Engine)
Engine.init{ lanes = 3, channel = 1 }
Engine.setType(1, "note")
Engine.setChannel(1, 1)
Engine.setScale(1, 0x5AD, 9)
Engine.setAdvanceSource(1, SIXTEENTH)
for i = 1, 16 do
Engine.setPitch(1, i, MELODY[i])
Engine.setVelocity(1, i, 90)
Engine.setStepLength(1, i, 4)
end
Engine.setType(2, "note")
Engine.setChannel(2, 2)
Engine.setLength(2, 8)
Engine.setAdvanceSource(2, EIGHTH)
for i = 1, 8 do
Engine.setPitch(2, i, BASS[i])
Engine.setVelocity(2, i, 105)
Engine.setStepLength(2, i, 10)
end
Engine.setType(3, "trig")
Engine.setChannel(3, 10)
Engine.setMidiNote(3, 36)
Engine.setAdvanceSource(3, SIXTEENTH)
for i = 1, 16 do Engine.setGate(3, i, DRUM[i]) end
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
if l.type == "mod" then return "cc" .. l.controller .. "=" .. l.value[l.position] end
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
