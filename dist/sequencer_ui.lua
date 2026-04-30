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
local dirtyCol = {}
for i = 1, 16 do dirtyCol[i] = true end
local headerDirty = true
local lastPhCol = 0
local function dirtyAll()
 for i = 1, 16 do dirtyCol[i] = true end
 headerDirty = true
 lastPhCol = 0
end
M.dirtyAll = dirtyAll
function M.dirtyValueCells()
 local lo = Track.regionLo(Engine.tracks[M.selT].curRegion)
 local c = M.selS - lo + 1
 if c >= 1 and c <= 16 then dirtyCol[c] = true end
 headerDirty = true
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
 local lo = Track.regionLo(Engine.tracks[M.selT].curRegion)
 local oldC = M.selS - lo + 1
 local newC = s - lo + 1
 M.selS = s
 if oldC >= 1 and oldC <= 16 then dirtyCol[oldC] = true end
 if newC >= 1 and newC <= 16 then dirtyCol[newC] = true end
 headerDirty = true
end
function M.onEndless(dir)
 local i = M.focus
 if i < 1 or i > 7 then return end
 setParam(i, M.selT, M.selS, dir)
 M.dirtyValueCells()
end
function M.onEndlessClick()
 local stp = Engine.tracks[M.selT].steps[M.selS]
 Engine.setStepParam(M.selT, M.selS, "mute", Step.muted(stp) and 0 or 1)
 M.dirtyValueCells()
end
function M.onKey(idx)
 if idx < 1 or idx > 7 then return end
 if idx == M.focus then return end
 M.focus = idx
 dirtyAll()
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
 { 20, 20, 20 },
 { 160, 30, 30 },
 { 40, 60, 110 },
 { 230, 230, 230 },
 { 80, 80, 80 },
 { 180, 180, 180 },
 { 200, 160, 60 },
 { 110, 170, 110 },
}
local COL_W = 20
local Y_HEAD = 0
local H_HEAD = 15
local Y_PITCH = 15
local H_PITCH = 75
local Y_VEL = 90
local H_VEL = 75
local Y_GATEDUR = 165
local H_GATEDUR = 30
local Y_RATCH = 195
local H_RATCH = 15
local Y_MUTE = 210
local H_MUTE = 15
local Y_PROG = 225
local H_PROG = 15
local function modeBand(focus)
 if focus == 1 then return Y_PITCH, H_PITCH end
 if focus == 2 then return Y_VEL, H_VEL end
 if focus == 3 then return Y_GATEDUR, 14 end
 if focus == 4 then return Y_GATEDUR + 16, 14 end
 if focus == 5 then return Y_MUTE, H_MUTE end
 if focus == 6 then return Y_RATCH, H_RATCH end
 return 0, 0
end
local function drawHeader(scr)
 scr:draw_rectangle_filled(0, Y_HEAD, 319, Y_HEAD + H_HEAD - 1, P[1])
 local tr = Engine.tracks[M.selT]
 local stp = tr.steps[M.selS]
 local prob = Step.prob(stp)
 local txt = "T" .. M.selT .. " " .. CELLS[M.focus] .. " R" .. tr.curRegion
 .. " S" .. string.format("%02d", M.selS)
 .. " P" .. prob
 scr:draw_text_fast(txt, 2, Y_HEAD + 3, 8, P[4])
end
local function drawCol(scr, c)
 local tr = Engine.tracks[M.selT]
 local lo = Track.regionLo(tr.curRegion)
 local s = lo + c - 1
 local stp = tr.steps[s]
 local x0 = (c - 1) * COL_W
 local x1 = x0 + COL_W - 1
 local isSel = (s == M.selS)
 local isPh = Engine.running and (tr.pos == s)
 local bg = P[1]
 if isPh then bg = P[3] end
 scr:draw_rectangle_filled(x0, Y_PITCH, x1, Y_PROG + H_PROG - 1, bg)
 if isSel then
 scr:draw_rectangle_filled(x0, Y_PITCH, x0, Y_PROG + H_PROG - 1, P[2])
 scr:draw_rectangle_filled(x1, Y_PITCH, x1, Y_PROG + H_PROG - 1, P[2])
 end
 local ix0, ix1 = x0 + 2, x1 - 2
 local fill = (isPh or isSel) and P[6] or P[5]
 local muted = Step.muted(stp)
 if not muted then
 local p = Step.pitch(stp)
 local h = (p * H_PITCH) // 127
 if h > 0 then
 local top = Y_PITCH + (H_PITCH - h)
 scr:draw_rectangle_filled(ix0, top, ix1, Y_PITCH + H_PITCH - 1, fill)
 end
 local v = Step.vel(stp)
 local hv = (v * H_VEL) // 127
 if hv > 0 then
 local topv = Y_VEL + (H_VEL - hv)
 scr:draw_rectangle_filled(ix0, topv, ix1, Y_VEL + H_VEL - 1, fill)
 end
 local d = Step.dur(stp); if d < 1 then d = 1 end
 local g = Step.gate(stp); if g > d then g = d end
 local barW = ix1 - ix0 + 1
 local dw = (d * barW) // 127
 if dw < 1 then dw = 1 end
 scr:draw_rectangle_filled(ix0, Y_GATEDUR, ix0 + dw - 1, Y_GATEDUR + 13, fill)
 local gw = (g * barW) // 127
 if gw > dw then gw = dw end
 if gw > 0 then
 scr:draw_rectangle_filled(ix0, Y_GATEDUR + 16, ix0 + gw - 1, Y_GATEDUR + 29, fill)
 end
 end
 if Step.ratch(stp) then
 scr:draw_text_fast("R", x0 + 7, Y_RATCH + 3, 8, P[4])
 end
 scr:draw_text_fast(muted and "M" or ".", x0 + 7, Y_MUTE + 3, 8, P[4])
 if isPh and tr.stepLen and tr.stepLen > 0 then
 local consumed = tr.stepLen - tr.stepAcc
 if consumed < 0 then consumed = 0 end
 if consumed > tr.stepLen then consumed = tr.stepLen end
 local pw = (consumed * (ix1 - ix0 + 1)) // tr.stepLen
 if pw > 0 then
 scr:draw_rectangle_filled(ix0, Y_PROG + 2, ix0 + pw - 1, Y_PROG + H_PROG - 3, P[8])
 end
 end
 if isSel then
 local by, bh = modeBand(M.focus)
 if bh > 0 then
 scr:draw_rectangle(x0, by, x1, by + bh - 1, P[7])
 end
 end
end
function M.draw(scr)
 if Engine.running then
 local tr = Engine.tracks[M.selT]
 local lo = Track.regionLo(tr.curRegion)
 local c = tr.pos - lo + 1
 if c < 1 or c > 16 then c = 0 end
 if c ~= lastPhCol then
 if lastPhCol >= 1 and lastPhCol <= 16 then dirtyCol[lastPhCol] = true end
 if c >= 1 and c <= 16 then dirtyCol[c] = true end
 lastPhCol = c
 elseif c >= 1 then
 dirtyCol[c] = true
 end
 elseif lastPhCol ~= 0 then
 dirtyCol[lastPhCol] = true
 lastPhCol = 0
 end
 local any = false
 for c = 1, 16 do
 if dirtyCol[c] then
 drawCol(scr, c)
 dirtyCol[c] = false
 any = true
 end
 end
 if headerDirty or any then
 drawHeader(scr)
 headerDirty = false
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
