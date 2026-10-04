local R={}
local _host=require
local B={device_boot="seq3ui",edit="seq3l",engine="seq3e",headless="seq3h",lane="seq3",lane_focus="seq3f",midi_rx="seq3ui",ops="seq3x",persist="seq3p",preset="seq3l",scales="seq3",seq_data="seq3h",source_names="seq3p",sources="seq3",transport="seq3"}
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
local S = { focus = false, selLane = 1, selStep = 1, cursor = 1, editing = false,
gcur = 1, gedit = false, slot = 1, status = "-", dirtyFlag = true, partial = true }
local lastPos = { 0, 0, 0, 0 }
local Persist
local GEN   = { "run", "slot", "save", "load", "draw" }
local BG, WELL = { 0, 0, 0 }, { 40, 40, 48 }
local WHITE, GREY = { 235, 235, 235 }, { 120, 120, 130 }
local COLOR = { note = { 90, 170, 255 }, trig = { 255, 170, 70 } }
local function lane() return Engine.lanes[S.selLane] end
local function used(l)
if l.height == 1 then return l.length end
return l.width * l.height
end
local function clamp(v, lo, hi)
if v < lo then return lo elseif v > hi then return hi end return v
end
local F
local function focus()
if not F then F = require("lane_focus")(S, { lane = lane, used = used, clamp = clamp }) end
return F
end
local function reclamp()
if F then F.build() end
S.selStep = clamp(S.selStep, 1, used(lane()))
S.dirtyFlag = true
end
local function gvalue(k)
if k == "run" then return Engine.running and "on" or "off" end
if k == "slot" then return S.slot end
if k == "draw" then return S.partial and "P" or "F" end
return S.status
end
local function persist()
if not Persist then
Persist = require("persist")
Persist.prefix = "s"
end
return Persist
end
local function gapply(k, d)
if k == "run" then
if Engine.running then Engine.onStop() else Engine.onStart() end
elseif k == "slot" then S.slot = clamp(S.slot + d, 1, 24)
elseif k == "save" then S.status = persist().saveSlot(S.slot) and "ok" or "er"
elseif k == "load" then S.status = persist().loadSlot(S.slot) and "ok" or "er"
elseif k == "draw" then S.partial = not S.partial
end
reclamp()
end
function S.touch() S.dirtyFlag = true end
local function cellRect(i, l, s)
if not S.focus then
local x0, y0 = 64 + (s - 1) * 16, (i - 1) * 48 + 3
return x0, y0, x0 + 13, y0 + 40
end
local w, h = l.width, l.height
local cw, ch = 320 // w, 114 // h
local x0 = ((s - 1) % w) * cw + 1
local y0 = 2 + ((s - 1) // w) * ch
return x0, y0, x0 + cw - 3, y0 + ch - 3
end
local function span(l)
local lo, hi = 127, 0
for s = 1, used(l) do
local p = l.pitch[s]
if p < lo then lo = p end
if p > hi then hi = p end
end
return lo, (hi > lo) and (hi - lo) or 1
end
local function cell(lcd, i, l, s, clear)
if s > used(l) then return end
local x0, y0, x1, y1 = cellRect(i, l, s)
if clear then lcd:draw_rectangle_filled(x0, y0, x1, y1, WELL) end
if l.type == "note" then
local lo, range = span(l)
local fh = 2 + (y1 - y0 - 2) * (l.pitch[s] - lo) // range
lcd:draw_rectangle_filled(x0, y1 - fh, x1, y1, COLOR.note)
elseif l.gate[s] == 1 then
lcd:draw_rectangle_filled(x0, y0, x1, y1, COLOR.trig)
end
if s == l.position then lcd:draw_rectangle_filled(x0, y1 - 3, x1, y1, WHITE) end
if i == S.selLane and s == S.selStep then lcd:draw_rectangle(x0, y0, x1, y1, WHITE) end
end
local function drawOverview(lcd)
for i = 1, #Engine.lanes do
local l = Engine.lanes[i]
local y = (i - 1) * 48 + 3
local c = (i == S.selLane) and WHITE or GREY
lcd:draw_text_fast(i .. (l.type == "note" and " N" or " T"), 4, y, 16, c)
lcd:draw_text_fast("/" .. l.division, 4, y + 20, 16, c)
local u = used(l)
if u > 16 then u = 16 end
lcd:draw_rectangle_filled(63, y - 1, 64 + (u - 1) * 16 + 14, y + 41, WELL)
for s = 1, u do cell(lcd, i, l, s) end
end
for g = 1, #GEN do
local c = (g ~= S.gcur) and GREY or (S.gedit and COLOR.trig or WHITE)
lcd:draw_text_fast(GEN[g] .. " " .. gvalue(GEN[g]),
4 + ((g - 1) % 3) * 106, 198 + ((g - 1) // 3) * 21, 16, c)
end
end
local function drawFocus(lcd)
local l = lane()
for s = 1, l.width * l.height do cell(lcd, S.selLane, l, s, true) end
focus().rows(lcd, WHITE, GREY)
end
function S.draw(lcd)
local lanes = Engine.lanes
local moved = false
for i = 1, #lanes do
local p = lanes[i].position
if lastPos[i] ~= p then
if S.partial and not S.dirtyFlag and (not S.focus or i == S.selLane) then
local l, old = lanes[i], lastPos[i]
if old >= 1 and old <= 16 then cell(lcd, i, l, old, true) end
cell(lcd, i, l, p, true)
moved = true
elseif not S.partial then
S.dirtyFlag = true
end
lastPos[i] = p
end
end
if S.dirtyFlag then
S.dirtyFlag = false
lcd:draw_rectangle_filled(0, 0, 319, 239, BG)
if S.focus then drawFocus(lcd) else drawOverview(lcd) end
moved = true
end
if moved then lcd:draw_swap() end
end
function S.turn(d)
if not S.focus then
if S.gedit then gapply(GEN[S.gcur], d); return end
S.selLane = ((S.selLane - 1 + d) % #Engine.lanes) + 1
reclamp()
else
focus().turn(d)
end
end
function S.press()
if S.focus then S.editing = not S.editing; S.dirtyFlag = true; return end
local k = GEN[S.gcur]
if k == "slot" then S.gedit = not S.gedit; S.dirtyFlag = true
else gapply(k, 1) end
end
local function prevNext(d)
if S.focus then focus().edit("step", d); return end
S.gcur = ((S.gcur - 1 + d) % #GEN) + 1
S.gedit = false
S.dirtyFlag = true
end
function S.key(i)
if i == 0 then gapply("run", 1)
elseif i == 1 then
S.focus = not S.focus; S.editing = false; S.gedit = false
if S.focus then focus() end
reclamp()
elseif i == 4 then prevNext(-1)
elseif i == 5 then prevNext(1)
elseif i == 3 then Engine.randomize(S.selLane); S.dirtyFlag = true
elseif i == 6 then Engine.zero(S.selLane); S.dirtyFlag = true
elseif i == 7 then Engine.shred(S.selLane); S.dirtyFlag = true end
end
function S.btn(i)
if i >= 9 and i - 8 <= #Engine.lanes then
S.selLane = i - 8
reclamp()
end
end
return S

end)()
return R
