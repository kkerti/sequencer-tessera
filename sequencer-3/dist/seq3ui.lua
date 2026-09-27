local R={}
local _host=require
local B={engine="seq3",ext="seq3x",generate="seq3x",lane="seq3",ops="seq3x",persist="seq3p",preset="seq3p",scales="seq3",sources="seq3",transport="seq3"}
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
local M = {}
function M.pulse()
Engine.onPulse()
end
function M.demo()
Engine.init{ lanes = 2, channel = 1 }
local melody = { 60, 62, 64, 67, 69, 67, 64, 62, 60, 64, 67, 72, 71, 67, 64, 60 }
for i = 1, 16 do
Engine.setPitch(1, i, melody[i])
Engine.setVelocity(1, i, 70 + (i % 4) * 15)
Engine.setStepLength(1, i, 6)
end
local QUARTER = 3
Engine.setAdvanceSource(1, QUARTER)
Engine.setType(2, "trig"); Engine.setDimensions(2, "4x4"); Engine.setDivision(2, 4)
Engine.setAdvanceSource(2, QUARTER)
for i = 1, 16 do Engine.setGate(2, i, (i * 7) % 3 ~= 0 and 1 or 0) end
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
function M.status(lcd)
if not Engine then
lcd:draw_rectangle_filled(0, 0, 319, 239, { 12, 12, 16 })
lcd:draw_text_fast("seq3: press a key to load", 8, 110, 16, { 120, 220, 255 })
lcd:draw_swap()
return
end
lcd:draw_rectangle_filled(0, 0, 319, 239, { 12, 12, 16 })
for i = 1, #Engine.lanes do
local l = Engine.lanes[i]
lcd:draw_text_fast(i .. " " .. l.type .. " " .. l.position,
8, 8 + (i - 1) * 24, 16, { 120, 220, 255 })
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
R["screen"]=(function()

local RX     = require("midi_rx")
RX.ensure()
local Engine = require("engine")
local S = {}
local lastPos = { 0, 0, 0, 0 }
S.screen = "overview"
S.selLane = 1
S.selStep = 1
S.param = 1
S.cursor = 1
S.editing = false
S.dirtyFlag = true
local NOTE_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local TYPE_COLORS = { note = { 90, 170, 255 }, mod = { 90, 220, 120 },
trig = { 255, 180, 90 }, gate = { 255, 110, 110 } }
local BG = { 12, 12, 16 }
local DIM = { 64, 64, 74 }
local WHITE = { 235, 235, 235 }
local BAR = { 255, 255, 255 }
local GREY = { 150, 150, 160 }
local Menu
local function used(l)
if l.height == 1 then return l.length end
return l.width * l.height
end
local function clamp(v, lo, hi)
if v < lo then return lo elseif v > hi then return hi end return v
end
local function stripValue(l, s)
if l.type == "note" then return l.pitch[s] end
if l.type == "mod" then return l.value[s] end
return l.gate[s]
end
function S.touch() S.dirtyFlag = true end
local function cell(lcd, x, y, w, h, l, step, selStep)
local color = TYPE_COLORS[l.type]
lcd:draw_rectangle_filled(x, y, x + w, y + h, DIM)
local v = stripValue(l, step)
if l.type == "note" or l.type == "mod" then
local fh = math.floor(v / 127 * h)
if fh > 0 then lcd:draw_rectangle_filled(x, y + h - fh, x + w, y + h, color) end
elseif v == 1 then
lcd:draw_rectangle_filled(x, y, x + w, y + h, color)
end
if step == l.position then lcd:draw_rectangle_filled(x, y + h - 2, x + w, y + h, BAR) end
if step == selStep then lcd:draw_rectangle_filled(x, y, x + w, y + 2, BAR) end
end
local function drawOverview(lcd)
lcd:draw_rectangle_filled(0, 0, 319, 239, BG)
for lane = 1, #Engine.lanes do
local l = Engine.state(lane)
local y = (lane - 1) * 60
lcd:draw_text_fast(lane .. " " .. string.upper(string.sub(l.type, 1, 3)),
6, y + 22, 16, (lane == S.selLane) and WHITE or TYPE_COLORS[l.type])
for s = 1, 16 do
local sel = (lane == S.selLane) and S.selStep or 0
cell(lcd, 92 + (s - 1) * 14, y + 8, 12, 44, l, s, sel)
end
end
lcd:draw_swap()
end
local function paramLabel()
local l = Engine.state(S.selLane)
if l.type ~= "note" then return "VAL" end
if S.param == 1 then return "PIT" elseif S.param == 2 then return "VEL" end
return "LEN"
end
local function readout(l)
local s = S.selStep
if l.type == "note" then
if S.param == 1 then
local p = l.pitch[s]
return NOTE_NAMES[(p % 12) + 1] .. (math.floor(p / 12) - 1)
elseif S.param == 2 then return "V" .. l.velocity[s]
else return l.stepLength[s] .. "t" end
elseif l.type == "mod" then return tostring(l.value[s])
else return (l.gate[s] == 1) and "ON" or "OFF" end
end
local function drawFocus(lcd)
lcd:draw_rectangle_filled(0, 0, 319, 239, BG)
local l = Engine.state(S.selLane)
for row = 1, 4 do
for col = 1, 4 do
local s = (row - 1) * 4 + col
cell(lcd, (col - 1) * 70, (row - 1) * 58 + 6, 66, 52, l, s, S.selStep)
end
end
lcd:draw_rectangle_filled(282, 6, 318, 122, DIM)
lcd:draw_text_fast(paramLabel(), 286, 20, 8, GREY)
lcd:draw_text_fast(readout(l), 286, 40, 16, WHITE)
lcd:draw_swap()
end
function S.draw(lcd)
for lane = 1, #Engine.lanes do
local p = Engine.state(lane).position
if lastPos[lane] ~= p then lastPos[lane] = p; S.dirtyFlag = true end
end
if not S.dirtyFlag then return end
S.dirtyFlag = false
if S.screen == "focus" then drawFocus(lcd)
elseif S.screen == "config" then Menu.draw(lcd)
else drawOverview(lcd) end
end
local function move(d)
S.selStep = ((S.selStep - 1 + d) % used(Engine.state(S.selLane))) + 1
S.touch()
end
local function editFocused(d)
local lane, step = S.selLane, S.selStep
local l = Engine.state(lane)
if l.type == "note" then
if S.param == 1 then Engine.setPitch(lane, step, l.pitch[step] + d)
elseif S.param == 2 then Engine.setVelocity(lane, step, l.velocity[step] + d * 2)
else Engine.setStepLength(lane, step, l.stepLength[step] + d * 6) end
elseif l.type == "mod" then
Engine.setValue(lane, step, l.value[step] + d * 2)
else
Engine.setGate(lane, step, (l.gate[step] + 1) % 2)
end
S.touch()
end
function S.key(i)
if S.screen == "config" then
if i == 0 or i == 1 then
S.screen = S.cfgReturn or "overview"
S.touch()
end
return
end
if i == 0 then
if not Menu then
Menu = require("menu")
Menu.init(S, Engine)
Menu.page = (S.screen == "focus") and "lane" or "globals"
else
Menu.page = (S.screen == "focus") and "lane" or "globals"
end
S.cfgReturn = S.screen
S.cursor = 1; S.editing = false
S.screen = "config"; S.touch()
elseif i == 1 then
S.screen = (S.screen == "overview") and "focus" or "overview"; S.touch()
elseif i == 4 then move(-1)
elseif i == 5 then move(1)
elseif i == 6 then Engine.zero(S.selLane); S.touch()
elseif i == 7 then Engine.shred(S.selLane); S.touch() end
end
function S.btn(i)
if i >= 9 and i <= 12 then
local lanes = #Engine.lanes
if i - 8 <= lanes then
S.selLane = i - 8
S.selStep = clamp(S.selStep, 1, used(Engine.state(S.selLane)))
S.param = 1
S.touch()
end
end
end
function S.turn(d)
if S.screen == "config" then
Menu.turn(d)
elseif S.screen == "focus" then
editFocused(d)
else
move(d)
end
end
function S.press()
if S.screen == "config" then
S.editing = not S.editing; S.touch()
elseif S.screen == "focus" then
local n = (Engine.state(S.selLane).type == "note") and 3 or 1
S.param = (S.param % n) + 1
S.touch()
else
S.screen = "focus"; S.touch()
end
end
return S

end)()
R["menu"]=(function()

local S
local Engine
local M = {}
M.page = "globals"
local NOTE_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local TYPES = { "note", "mod", "trig", "gate" }
local DIMS  = { "16x1", "8x2", "5x3", "4x3", "4x4" }
local WHITE = { 235, 235, 235 }
local GREY  = { 150, 150, 160 }
local BG    = { 12, 12, 16 }
local PAGES = {
lane = {
title = "LANE",
items = {
{ label = "type",     field = "type",     choices = TYPES },
{ label = "dims",     field = "dims",     choices = DIMS },
{ label = "division", field = "division", lo = 1, hi = 16 },
{ label = "channel",  field = "channel",  lo = 1, hi = 16 },
},
},
globals = {
title = "GLOBALS",
items = {
{ label = "run",   field = "running", bool = true },
{ label = "reset", field = "_reset" },
{ label = "slot",  field = "_slot", lo = 1, hi = 24 },
{ label = "save",  field = "_save" },
{ label = "load",  field = "_load" },
},
},
}
M.slot = 1
M.status = "-"
local Persist
local function persist()
if not Persist then
Persist = require("persist")
Persist.prefix = "s"
end
return Persist
end
function M.init(screenState, engine)
S = screenState
Engine = engine
end
local function used(l)
if l.height == 1 then return l.length end
return l.width * l.height
end
local function clamp(v, lo, hi)
if v < lo then return lo elseif v > hi then return hi end return v
end
function M.itemValue(it)
if it.field == "_reset" then return "-" end
if it.field == "_slot" then return tostring(M.slot) end
if it.field == "_save" or it.field == "_load" then return M.status end
if it.bool then return Engine.running and "on" or "off" end
return tostring(Engine.state(S.selLane)[it.field])
end
function M.applyItem(it, d)
if it.field == "_reset" then
Engine.reset()
elseif it.field == "_slot" then
M.slot = clamp(M.slot + d, it.lo, it.hi)
elseif it.field == "_save" then
M.status = persist().saveSlot(M.slot) and "ok" or "err"
elseif it.field == "_load" then
M.status = persist().loadSlot(M.slot) and "ok" or "err"
elseif it.bool then
if Engine.running then Engine.onStop() else Engine.onStart() end
else
local lane = S.selLane
local v = Engine.state(lane)[it.field]
if it.choices then
local idx = 1
for i, c in ipairs(it.choices) do if c == v then idx = i end end
v = it.choices[((idx - 1 + d) % #it.choices) + 1]
if it.field == "type" then Engine.setType(lane, v)
else Engine.setDimensions(lane, v) end
else
v = clamp(v + d, it.lo, it.hi)
if it.field == "division" then Engine.setDivision(lane, v)
else Engine.setChannel(lane, v) end
end
S.selStep = clamp(S.selStep, 1, used(Engine.state(lane)))
end
S.touch()
end
function M.cursorCount()
local page = PAGES[M.page]
return page and #page.items or 1
end
function M.turn(d)
local page = PAGES[M.page]
if S.editing then
M.applyItem(page.items[S.cursor], d)
else
S.cursor = ((S.cursor - 1 + d) % #page.items) + 1
S.touch()
end
end
function M.draw(lcd)
lcd:draw_rectangle_filled(0, 0, 319, 239, BG)
local page = PAGES[M.page]
lcd:draw_text_fast(page.title .. " " .. S.selLane, 8, 8, 16, WHITE)
for i, it in ipairs(page.items) do
local y = 40 + (i - 1) * 28
local sel = (i == S.cursor)
local col = sel and WHITE or GREY
lcd:draw_text_fast((sel and (S.editing and ">" or "-") or " ") .. " " .. it.label,
8, y, 16, col)
lcd:draw_text_fast(M.itemValue(it), 170, y, 16, col)
end
lcd:draw_swap()
end
return M

end)()
return R
