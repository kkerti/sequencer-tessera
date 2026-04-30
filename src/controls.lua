-- controls.lua
-- Grid VSN1 UI -- TOP HALF ONLY.
-- Reads engine.tracks tables; calls engine setters. Core knows nothing.
--
-- Hardware:
--   - 320x240 LCD
--   - 4 small buttons under screen -> queue region 1..4
--   - 8 keyswitches -> select which parameter the endless controls
--   - Endless jog wheel (relative: 65 = up, 63 = down) with click
--
-- Layout:
--   Top half (y=0..119): 4x2 parameter cells, 80x60 each
--     TRACK | STEP  | NOTE  | VEL
--     DUR   | GATE  | RATCH | PROB
--   Bottom half (y=120..239): unused for now; not painted.
--
-- Memory-trimmed:
--   * CELLS holds only label strings.
--   * getParam/setParam are flat if/elseif over the cell index.
--   * Colors live in a single shared palette indexed by integer constants.

local Engine = require("engine")
local Track  = require("track")
local Step   = require("step")

local M = {}

-- ---- selection state (UI only; not in Core) ----
M.selT  = 1   -- selected track 1..4
M.selS  = 1   -- selected step 1..64
M.focus = 3   -- index into CELLS below; default = NOTE

-- Cell labels only. Indices map to:
--   1=TRACK 2=STEP 3=NOTE 4=VEL 5=DUR 6=GATE 7=RATCH 8=PROB
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

-- dirty flags (top-half cells only)
local dirtyCells = { true, true, true, true, true, true, true, true }

local function dirtyAll()
    for i = 1, 8 do dirtyCells[i] = true end
end
M.dirtyAll = dirtyAll

function M.dirtyTopCell(i) dirtyCells[i] = true end

-- Mark every cell that depends on (selT, selS) as dirty. Called by EN16
-- and the endless-click handler when a step's content changes.
function M.dirtyValueCells()
    -- All cells except TRACK (1) and STEP (2) display per-step values.
    for i = 3, 8 do dirtyCells[i] = true end
end

-- ---- input handlers ----

function M.onEndless(dir)
    setParam(M.focus, M.selT, M.selS, dir)
    dirtyCells[M.focus] = true
    -- track or step change cascades: every value cell now reflects a
    -- different step, redraw them all.
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

-- ---- screen drawing ----

-- Single shared palette. One table header instead of many.
-- 1 BG_ACTIVE  2 BG_INACTIVE  3 FG
local P = {
    { 200,  30,  30 },
    {  40,  40,  40 },
    { 230, 230, 230 },
}

local CELL_W, CELL_H = 80, 60

local function drawCell(scr, i)
    local col = (i - 1) % 4
    local row = (i - 1) >= 4 and 1 or 0
    local x = col * CELL_W
    local y = row * CELL_H
    local val = getParam(i, M.selT, M.selS)
    local bg  = (i == M.focus) and P[1] or P[2]
    scr:draw_rectangle_filled(x, y, x + CELL_W - 1, y + CELL_H - 1, bg)
    scr:draw_text_fast(CELLS[i],      x + 4, y + 4,  8,  P[3])
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
