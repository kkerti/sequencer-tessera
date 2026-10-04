local R={}
local _host=require
local B={device_boot="seq3ui",edit="seq3x",engine="seq3e",headless="seq3h",lane="seq3",midi_rx="seq3ui",ops="seq3x",persist="seq3p",preset="seq3l",scales="seq3",seq_data="seq3h",source_names="seq3p",sources="seq3",transport="seq3"}
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
R["screen"]=(function()

local RX     = require("midi_rx")
RX.ensure()
local Engine = require("engine")
local S = { selLane = 1, selStep = 1, cursor = 1, editing = false,
slot = 1, status = "-", dirtyFlag = true }
local lastPos = { 0, 0, 0, 0 }
local Persist
local NOTE_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local TYPES = { "note", "trig" }
local DIMS  = { "16x1", "8x2", "5x3", "4x3", "4x4" }
local HEAD, TAIL = 5, 4
local STEP_ROWS = { note = { "pitch", "vel", "len" }, trig = { "gate", "vel", "len" } }
local FIRST = { "type", "dims", "div", "ch", "step" }
local LAST  = { "run", "slot", "save", "load" }
local WHITE, GREY, BG = { 235, 235, 235 }, { 130, 130, 140 }, { 0, 0, 0 }
local function lane() return Engine.state(S.selLane) end
local function used(l)
if l.height == 1 then return l.length end
return l.width * l.height
end
local function clamp(v, lo, hi)
if v < lo then return lo elseif v > hi then return hi end return v
end
local function rowKey(i)
local steps = STEP_ROWS[lane().type]
if i <= HEAD then return FIRST[i] end
i = i - HEAD
if i <= #steps then return steps[i] end
return LAST[i - #steps]
end
local function rowCount() return HEAD + #STEP_ROWS[lane().type] + TAIL end
local function cycle(list, v, d)
local idx = 1
for i = 1, #list do if list[i] == v then idx = i end end
return list[((idx - 1 + d) % #list) + 1]
end
local function value(k)
local l, s = lane(), S.selStep
if k == "type" or k == "dims" then return l[k] end
if k == "div" then return l.division end
if k == "ch" then return l.channel end
if k == "step" then return s .. "/" .. used(l) end
if k == "pitch" then
local p = l.pitch[s]
return NOTE_NAMES[(p % 12) + 1] .. (p // 12 - 1) .. " (" .. p .. ")"
end
if k == "vel" then return l.velocity[s] end
if k == "len" then return l.stepLength[s] .. "t" end
if k == "gate" then return l.gate[s] == 1 and "on" or "off" end
if k == "run" then return Engine.running and "on" or "off" end
if k == "slot" then return S.slot end
return S.status
end
local function persist()
if not Persist then
Persist = require("persist")
Persist.prefix = "s"
end
return Persist
end
local function apply(k, d)
local n, l, s = S.selLane, lane(), S.selStep
if k == "type" then Engine.setType(n, cycle(TYPES, l.type, d))
elseif k == "dims" then Engine.setDimensions(n, cycle(DIMS, l.dims, d))
elseif k == "div" then Engine.setDivision(n, l.division + d)
elseif k == "ch" then Engine.setChannel(n, l.channel + d)
elseif k == "step" then S.selStep = ((s - 1 + d) % used(l)) + 1
elseif k == "pitch" then Engine.setPitch(n, s, l.pitch[s] + d)
elseif k == "vel" then Engine.setVelocity(n, s, l.velocity[s] + d * 2)
elseif k == "len" then Engine.setStepLength(n, s, l.stepLength[s] + d)
elseif k == "gate" then Engine.setGate(n, s, (l.gate[s] + 1) % 2)
elseif k == "run" then
if Engine.running then Engine.onStop() else Engine.onStart() end
elseif k == "slot" then S.slot = clamp(S.slot + d, 1, 24)
elseif k == "save" then S.status = persist().saveSlot(S.slot) and "saved" or "err"
elseif k == "load" then S.status = persist().loadSlot(S.slot) and "loaded" or "err"
end
S.selStep = clamp(S.selStep, 1, used(lane()))
S.cursor = clamp(S.cursor, 1, rowCount())
S.dirtyFlag = true
end
function S.touch() S.dirtyFlag = true end
function S.draw(lcd)
local lanes = Engine.lanes
for i = 1, #lanes do
local p = lanes[i].position
if lastPos[i] ~= p then lastPos[i] = p; S.dirtyFlag = true end
end
if not S.dirtyFlag then return end
S.dirtyFlag = false
lcd:draw_rectangle_filled(0, 0, 319, 239, BG)
local line = ""
for i = 1, #lanes do
line = line .. (i == S.selLane and "*" or " ") .. i .. ":" .. lanes[i].position .. " "
end
lcd:draw_text_fast(line, 4, 2, 16, WHITE)
for i = 1, rowCount() do
local sel = i == S.cursor
local y = 4 + i * 18
lcd:draw_text_fast((sel and (S.editing and ">" or "-") or " ") .. rowKey(i),
4, y, 16, sel and WHITE or GREY)
lcd:draw_text_fast(tostring(value(rowKey(i))), 120, y, 16, sel and WHITE or GREY)
end
lcd:draw_swap()
end
function S.turn(d)
if S.editing then
apply(rowKey(S.cursor), d)
else
S.cursor = ((S.cursor - 1 + d) % rowCount()) + 1
S.dirtyFlag = true
end
end
function S.press()
local k = rowKey(S.cursor)
if k == "save" or k == "load" or k == "run" then apply(k, 1)
else S.editing = not S.editing; S.dirtyFlag = true end
end
function S.key(i)
if i == 0 then apply("run", 1)
elseif i == 4 then apply("step", -1)
elseif i == 5 then apply("step", 1)
elseif i == 3 then Engine.randomize(S.selLane); S.dirtyFlag = true
elseif i == 6 then Engine.zero(S.selLane); S.dirtyFlag = true
elseif i == 7 then Engine.shred(S.selLane); S.dirtyFlag = true end
end
function S.btn(i)
if i >= 9 and i - 8 <= #Engine.lanes then
S.selLane = i - 8
apply("", 0)
end
end
return S

end)()
return R
