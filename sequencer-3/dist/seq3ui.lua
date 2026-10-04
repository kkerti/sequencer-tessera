local R={}
local _host=require
local B={edit="seq3x",engine="seq3e",headless="seq3h",lane="seq3",ops="seq3x",persist="seq3p",preset="seq3l",scales="seq3",screen="seq3s",seq_data="seq3h",source_names="seq3p",sources="seq3",transport="seq3"}
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
R["device_boot"]=(function()

local Engine = require("engine")
local Lane   = require("lane")
local M = {}
function M.demo()
Engine.init{ lanes = 2, channel = 1 }
local QUARTER = 3
local melody = { 60, 62, 64, 67, 69, 67, 64, 62, 60, 64, 67, 72, 71, 67, 64, 60 }
local a, b = Engine.lanes[1], Engine.lanes[2]
for i = 1, 16 do
a.pitch[i] = melody[i]
a.velocity[i] = 70 + (i % 4) * 15
b.gate[i] = (i * 7) % 3 ~= 0 and 1 or 0
end
a.advanceSource = QUARTER
b.type = "trig"; b.division = 4; b.advanceSource = QUARTER
Lane.setDims(b, "4x4")
Engine.onStart()
end
return M

end)()
R["midi_rx"]=(function()

local M = {}
local Engine, Boot
function M.ensure()
if not Engine then
print("seq3: loading engine")
Engine = require("engine")
print("seq3: engine ok")
Boot   = require("device_boot")
Boot.demo()
print("seq3: demo ok")
end
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
if not Engine then return end
if t == 0xF8 then
Engine.onPulse()
emit(Engine.out, send)
elseif t == 0xFA or t == 0xFB then
if not Engine.running then Engine.onStart() end
elseif t == 0xFC then
emit(Engine.onStop(), send)
end
end
local sig = -1
function M.status(lcd)
local s = 0
if Engine then
s = Engine.running and 1 or 2
for i = 1, #Engine.lanes do s = s * 17 + Engine.lanes[i].position end
end
if s == sig then return end
sig = s
lcd:draw_rectangle_filled(0, 0, 319, 239, { 12, 12, 16 })
if not Engine then
lcd:draw_text_fast("seq3: press a key to load", 8, 110, 16, { 120, 220, 255 })
else
for i = 1, #Engine.lanes do
local l = Engine.lanes[i]
lcd:draw_text_fast(i .. " " .. l.type .. " " .. l.position,
8, 8 + (i - 1) * 24, 16, { 120, 220, 255 })
end
lcd:draw_text_fast("press a key for the screen", 8, 200, 16, { 120, 120, 140 })
end
lcd:draw_swap()
end
local SCR
local function loadSCR()
if SCR then return SCR end
M.ensure()
print("seq3: loading screen")
SCR = require("screen")
print("seq3: screen ok")
return SCR
end
function M.key(i)    local s = loadSCR(); s.key(i) end
function M.btn(i)    local s = loadSCR(); s.btn(i) end
function M.press()   local s = loadSCR(); s.press() end
function M.turn(d)
if d ~= 0 then
local s = loadSCR(); s.turn(d)
end
end
function M.ui(lcd)
if SCR then
SCR.draw(lcd)
else
M.status(lcd)
end
end
return M

end)()
return R
