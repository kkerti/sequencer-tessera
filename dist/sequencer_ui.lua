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
M.focus = 3
local CELLS = { "TRACK","STEP","NOTE","VEL","DUR","GATE","RATCH","PROB" }
M.CELLS = CELLS
local function getParam(i, t, s)
 local stp = Engine.tracks[t].steps[s]
 if i == 1 then return t
 elseif i == 2 then return s
 elseif i == 3 then return stp and Step.pitch(stp) or 0
 elseif i == 4 then return Step.vel(stp)
 elseif i == 5 then return Step.dur(stp)
 elseif i == 6 then return Step.gate(stp)
 elseif i == 7 then return Step.ratch(stp) and 1 or 0
 elseif i == 8 then return Step.prob(stp)
 end
 return 0
end
local function setParam(i, t, s, d)
 if i == 1 then
 M.selT = ((t - 1 + d) % 4) + 1
 elseif i == 2 then
 local n = (s - 1 + d) % Engine.tracks[t].cap
 M.selS = n + 1
 elseif i == 3 then
 Engine.setStepParam(t, s, "pitch", Step.pitch(Engine.tracks[t].steps[s]) + d)
 elseif i == 4 then
 Engine.setStepParam(t, s, "vel", Step.vel(Engine.tracks[t].steps[s]) + d)
 elseif i == 5 then
 Engine.setStepParam(t, s, "dur", Step.dur(Engine.tracks[t].steps[s]) + d)
 elseif i == 6 then
 Engine.setStepParam(t, s, "gate", Step.gate(Engine.tracks[t].steps[s]) + d)
 elseif i == 7 then
 local cur = Step.ratch(Engine.tracks[t].steps[s]) and 1 or 0
 Engine.setStepParam(t, s, "ratch", (cur + d) % 2)
 elseif i == 8 then
 Engine.setStepParam(t, s, "prob", Step.prob(Engine.tracks[t].steps[s]) + d)
 end
end
local dirtyCells = { true, true, true, true, true, true, true, true }
local function dirtyAll()
 for i = 1, 8 do dirtyCells[i] = true end
end
M.dirtyAll = dirtyAll
function M.dirtyTopCell(i) dirtyCells[i] = true end
function M.dirtyValueCells()
 for i = 3, 8 do dirtyCells[i] = true end
end
function M.onEndless(dir)
 setParam(M.focus, M.selT, M.selS, dir)
 dirtyCells[M.focus] = true
 if M.focus == 1 or M.focus == 2 then dirtyAll() end
end
function M.onKey(idx)
 if idx < 1 or idx > 8 then return end
 dirtyCells[M.focus] = true
 M.focus = idx
 dirtyCells[idx] = true
end
function M.onSmallBtn(idx)
 if idx < 1 or idx > Track.REGION_COUNT then return end
 Engine.setQueuedRegion(idx)
end
local P = {
 { 200, 30, 30 },
 { 40, 40, 40 },
 { 230, 230, 230 },
}
local CELL_W, CELL_H = 80, 60
local function drawCell(scr, i)
 local col = (i - 1) % 4
 local row = (i - 1) >= 4 and 1 or 0
 local x = col * CELL_W
 local y = row * CELL_H
 local val = getParam(i, M.selT, M.selS)
 local bg = (i == M.focus) and P[1] or P[2]
 scr:draw_rectangle_filled(x, y, x + CELL_W - 1, y + CELL_H - 1, bg)
 scr:draw_text_fast(CELLS[i], x + 4, y + 4, 8, P[3])
 scr:draw_text_fast(tostring(val), x + 4, y + 18, 16, P[3])
end
function M.draw(scr)
 local any = false
 for i = 1, 8 do
 if dirtyCells[i] then
 drawCell(scr, i)
 dirtyCells[i] = false
 any = true
 end
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
 local d = delta > 0 and 1 or -1
 Engine.setStepParam(Controls.selT, s, "pitch", Step.pitch(tr.steps[s]) + d)
 if s == Controls.selS then Controls.dirtyValueCells() end
end
function M.onEncoderPress(idx)
 local tr, s = resolve(idx)
 if not tr then return end
 local cur = Step.active(tr.steps[s]) and 1 or 0
 Engine.setStepParam(Controls.selT, s, "active", cur == 0 and 1 or 0)
 if s == Controls.selS then Controls.dirtyValueCells() end
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
 elseif Step.active(tr.steps[lo + i - 1]) then b = 80
 else b = 0 end
 emit(i, b)
 end
end
return M

end)()
return {
    screen = R.controls,
    en16   = R.controls_en16,
}
