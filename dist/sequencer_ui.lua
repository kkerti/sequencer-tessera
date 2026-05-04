-- dist/sequencer_ui.lua (auto-generated; Controls layer)
local R={}
local _hostReq = require
local _seq
local function require(n)
    local r = R[n]
    if r ~= nil then return r end
    if not _seq then _seq = _hostReq("sequencer") end
    return _seq[n]
end
R["controls"]=(function()

local Engine = require("engine")
local Track = require("track")
local Step = require("step")
local M = {}
M.selT = 1
M.selS = 1
M.focus = 1
M.shift = false
local CELLS = { "NOTE","VEL","DUR","GATE","MUTE","RATCH","PROB","SHIFT" }
M.CELLS = CELLS
local FIELD = { "pitch","vel","dur","gate","mute","ratch","prob" }
M.FIELD = FIELD
local function setParam(i, t, s, d)
 local stp = Engine.tracks[t].steps[s]
 if i == 1 then
 Engine.setStepParam(t, s, "pitch", Step.pitch(stp) + d)
 elseif i == 2 then
 Engine.setStepParam(t, s, "vel", Step.vel(stp) + d)
 elseif i == 3 then
 Engine.setStepParam(t, s, "dur", Step.dur(stp) + d)
 elseif i == 4 then
 Engine.setStepParam(t, s, "gate", Step.gate(stp) + d)
 elseif i == 5 then
 Engine.setStepParam(t, s, "mute", Step.muted(stp) and 0 or 1)
 elseif i == 6 then
 Engine.setStepParam(t, s, "ratch", Step.ratch(stp) and 0 or 1)
 elseif i == 7 then
 Engine.setStepParam(t, s, "prob", Step.prob(stp) + d)
 end
end
M.setParam = setParam
local needsFullRepaint = true
local lastPhCol = 0
local function dirtyAll()
 needsFullRepaint = true
 lastPhCol = 0
end
M.dirtyAll = dirtyAll
function M.dirtyValueCells()
 needsFullRepaint = true
end
function M.setSelectedTrack(t)
 if t < 1 or t > #Engine.tracks then return end
 if t == M.selT then return end
 M.selT = t
 local cap = Engine.tracks[t].cap
 if M.selS > cap then M.selS = cap end
 dirtyAll()
end
function M.setSelectedStep(s)
 if s < 1 then return end
 local cap = Engine.tracks[M.selT].cap
 if s > cap then return end
 if s == M.selS then return end
 M.selS = s
 needsFullRepaint = true
end
function M.onEndless(dir)
 local i = M.focus
 if i < 1 or i > 7 then return end
 setParam(i, M.selT, M.selS, dir)
 needsFullRepaint = true
end
function M.onEndlessClick()
 local stp = Engine.tracks[M.selT].steps[M.selS]
 Engine.setStepParam(M.selT, M.selS, "mute", Step.muted(stp) and 0 or 1)
 needsFullRepaint = true
end
function M.onKey(idx)
 if idx < 1 or idx > 7 then return end
 if idx == M.focus then return end
 M.focus = idx
 needsFullRepaint = true
end
function M.setShift(b)
 if b == M.shift then return end
 M.shift = b and true or false
end
function M.onSmallBtn(idx)
 if idx < 1 or idx > 4 then return end
 if M.shift then
 if idx <= Track.REGION_COUNT then Engine.setQueuedRegion(idx) end
 else
 M.setSelectedTrack(idx)
 end
end
local P = {
 { 18, 18, 20 },
 { 200, 60, 40 },
 { 40, 90, 160 },
 { 240, 240, 240 },
 { 110, 110, 115 },
 { 200, 200, 200 },
 { 90, 90, 95 },
 { 60, 60, 65 },
}
local NOTE = { "C","C#","D","D#","E","F","F#","G","G#","A","A#","B" }
local function noteName(p)
 local oct = (p // 12) - 1
 return NOTE[(p % 12) + 1] .. tostring(oct)
end
local HDR_H = 22
local PARAM_Y = 30
local PARAM_H = 20
local CTX_Y = 192
local CTX_H = 48
local COL_W = 20
local PARAM_LABELS = {
 "pitch", "vel", "dur", "gate", "mute", "ratch", "prob",
}
local function drawHeader(scr)
 local stp = Engine.tracks[M.selT].steps[M.selS]
 scr:draw_rectangle_filled(0, 0, 319, HDR_H - 1, P[1])
 local left = "T" .. M.selT
 .. " S" .. string.format("%02d", M.selS)
 .. " R" .. Engine.tracks[M.selT].curRegion
 scr:draw_text_fast(left, 4, 4, 14, P[4])
 scr:draw_text_fast(CELLS[M.focus], 130, 4, 14, P[2])
 local p = Step.pitch(stp)
 scr:draw_text_fast(noteName(p) .. " (" .. p .. ")",
 210, 4, 14, P[4])
 scr:draw_rectangle_filled(0, HDR_H, 319, HDR_H, P[8])
end
local function drawParamRow(scr, i)
 local stp = Engine.tracks[M.selT].steps[M.selS]
 local y = PARAM_Y + (i - 1) * PARAM_H
 local active = (i == M.focus)
 local bg = active and P[2] or P[1]
 scr:draw_rectangle_filled(0, y, 319, y + PARAM_H - 1, bg)
 local fg = active and P[4] or P[5]
 scr:draw_text_fast(PARAM_LABELS[i], 4, y + 4, 12, fg)
 local val, max, glyph
 if i == 1 then
 val, max = Step.pitch(stp), 127
 elseif i == 2 then
 val, max = Step.vel(stp), 127
 elseif i == 3 then
 val, max = Step.dur(stp), 127
 elseif i == 4 then
 val, max = Step.gate(stp), 127
 elseif i == 5 then
 glyph = Step.muted(stp) and "MUTED" or "audible"
 elseif i == 6 then
 glyph = Step.ratch(stp) and "RATCH" or "off"
 elseif i == 7 then
 val, max = Step.prob(stp), 127
 end
 if glyph then
 scr:draw_text_fast(glyph, 80, y + 4, 12,
 active and P[4] or P[5])
 else
 scr:draw_text_fast(tostring(val), 80, y + 4, 12,
 active and P[4] or P[6])
 local bx, bw = 130, 180
 scr:draw_rectangle(bx, y + 4, bx + bw - 1, y + PARAM_H - 6,
 active and P[4] or P[8])
 local fw = (val * (bw - 2)) // max
 if fw > 0 then
 scr:draw_rectangle_filled(bx + 1, y + 5,
 bx + 1 + fw - 1, y + PARAM_H - 7,
 active and P[4] or P[6])
 end
 end
end
local function drawCtxStrip(scr)
 local tr = Engine.tracks[M.selT]
 local lo = Track.regionLo(tr.curRegion)
 scr:draw_rectangle_filled(0, CTX_Y - 8, 319, 239, P[1])
 scr:draw_rectangle_filled(0, CTX_Y - 8, 319, CTX_Y - 8, P[8])
 scr:draw_text_fast("region " .. tr.curRegion, 4, CTX_Y - 6,
 8, P[5])
 for c = 1, 16 do
 local s = lo + c - 1
 local stp = tr.steps[s]
 local x0 = (c - 1) * COL_W + 1
 local x1 = x0 + COL_W - 3
 local isSel = (s == M.selS)
 local isPh = Engine.running and (tr.pos == s)
 local bg = isPh and P[3] or P[1]
 scr:draw_rectangle_filled(x0, CTX_Y, x1,
 CTX_Y + CTX_H - 1, bg)
 if not Step.muted(stp) then
 local p = Step.pitch(stp)
 local h = (p * (CTX_H - 4)) // 127
 if h > 0 then
 local top = CTX_Y + 2 + (CTX_H - 4 - h)
 local fill = (isPh or isSel) and P[6] or P[7]
 scr:draw_rectangle_filled(x0 + 1, top, x1 - 1,
 CTX_Y + CTX_H - 3, fill)
 end
 end
 if isSel then
 scr:draw_rectangle(x0, CTX_Y, x1,
 CTX_Y + CTX_H - 1, P[2])
 end
 end
end
function M.draw(scr)
 local tr = Engine.tracks[M.selT]
 local ctxDirty = false
 if Engine.running then
 local lo = Track.regionLo(tr.curRegion)
 local c = tr.pos - lo + 1
 if c < 1 or c > 16 then c = 0 end
 if c ~= lastPhCol then
 ctxDirty = true
 lastPhCol = c
 end
 elseif lastPhCol ~= 0 then
 ctxDirty = true
 lastPhCol = 0
 end
 local any = needsFullRepaint
 if needsFullRepaint then
 scr:draw_rectangle_filled(0, 0, 319, 239, P[1])
 drawHeader(scr)
 for i = 1, 7 do drawParamRow(scr, i) end
 drawCtxStrip(scr)
 needsFullRepaint = false
 elseif ctxDirty then
 drawCtxStrip(scr)
 any = true
 end
 if any then scr:draw_swap() end
end
return M

end)()
R["controls_en16"]=(function()

local Engine = require("engine")
local Track = require("track")
local Step = require("step")
local Controls = require("controls")
local M = {}
M.NUM_ENC = 16
local function resolve(idx)
 if idx < 1 or idx > 16 then return nil, nil end
 local tr = Engine.tracks[Controls.selT]
 if not tr then return nil, nil end
 return tr, Track.regionLo(tr.curRegion) + (idx - 1)
end
function M.onEncoder(idx, delta)
 local tr, s = resolve(idx)
 if not tr then return end
 Controls.setSelectedStep(s)
 local d = delta > 0 and 1 or -1
 Controls.setParam(Controls.focus, Controls.selT, s, d)
 Controls.dirtyValueCells()
end
function M.onEncoderPress(idx)
 local tr, s = resolve(idx)
 if not tr then return end
 Controls.setSelectedStep(s)
 if Controls.focus == 5 then
 local newMute = Step.muted(tr.steps[s]) and 0 or 1
 Engine.setStepParam(Controls.selT, s, "mute", newMute)
 Controls.dirtyValueCells()
 end
end
function M.refreshLeds(emit)
 local tr = Engine.tracks[Controls.selT]; if not tr then return end
 local lo = Track.regionLo(tr.curRegion)
 local ph = 0
 if Engine.running and tr.pos >= lo and tr.pos < lo + 16 then
 ph = tr.pos - lo + 1
 end
 for i = 1, 16 do
 local b
 if i == ph then b = 255
 elseif Step.muted(tr.steps[lo + i - 1]) then b = 0
 else b = 80 end
 emit(i, b)
 end
end
return M

end)()
return {
    screen = R.controls,
    en16   = R.controls_en16,
}
