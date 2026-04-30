-- controls.lua
-- Grid VSN1 UI -- single-track 16-column contour view.
-- Reads engine.tracks tables; calls engine setters. Core knows nothing.
--
-- Hardware:
--   - 320x240 LCD
--   - 4 small buttons under screen
--   - 8 keyswitches (modes 1-7 + SHIFT on slot 8)
--   - Endless jog wheel (relative: 65 = up, 63 = down) with click
--
-- Control model:
--   * Keyswitches 1..7 select a per-step parameter MODE that the encoder
--     and EN16 edit:  NOTE  VEL  DUR  GATE  MUTE  RATCH  PROB
--   * Keyswitch 8 is SHIFT (momentary; press = on, release = off).
--   * VSN1 endless turn edits the SELECTED step in the current mode.
--   * VSN1 endless click toggles selected step's MUTE.
--   * VSN1 small buttons (no SHIFT) select track 1..4.
--   * VSN1 small buttons + SHIFT queue region 1..4.
--   * EN16 encoder turn/push selects step (and edits/toggles).
--
-- Layout (320x240, 16 columns 20 px wide):
--
--   y   0..14   header strip: "T1  NOTE   01 02 .. 16"  (selected step bold)
--   y  15..89   pitch contour band  (75 px; col fill height = pitch/127 * 75)
--   y  90..164  velocity contour band (75 px)
--   y 165..194  gate-in-dur ribbon (30 px; dur bar above, gate bar below)
--   y 195..209  ratchet glyph row (15 px; "R" if ratch, blank otherwise)
--   y 210..224  mute glyph row (15 px; "M" if muted, "." if audible)
--   y 225..239  clock-progress bar (15 px; fills L->R as stepAcc counts down)
--
--   The selected column gets vertical accent lines on its left+right edges
--   spanning the full screen height. The active MODE outlines its band
--   across the selected column.
--   The playhead column draws contours with brighter fill.

local Engine = require("engine")
local Track  = require("track")
local Step   = require("step")

local M = {}

-- ---- selection state (UI only; not in Core) ----
M.selT  = 1
M.selS  = 1
M.focus = 1   -- 1=NOTE 2=VEL 3=DUR 4=GATE 5=MUTE 6=RATCH 7=PROB
M.shift = false

local CELLS = { "NOTE","VEL","DUR","GATE","MUTE","RATCH","PROB","SHIFT" }
M.CELLS = CELLS
local FIELD = { "pitch","vel","dur","gate","mute","ratch","prob" }
M.FIELD = FIELD

-- ---- shared param mutator (used by EN16 + endless) ----
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

-- ---- dirty tracking ----
-- One bit per column. Track-wide repaints set all 16. Header is repainted
-- whenever ANY column is dirty (cheap: one draw_text per column number).
-- Clock-progress bar repaints every frame the engine is running.
local dirtyCol = {}
for i = 1, 16 do dirtyCol[i] = true end
local headerDirty = true
local lastPhCol = 0   -- last drawn playhead column (0 = none)

local function dirtyAll()
    for i = 1, 16 do dirtyCol[i] = true end
    headerDirty = true
    lastPhCol = 0
end
M.dirtyAll = dirtyAll

-- Mark the selected column dirty (param changed, or selection moved).
function M.dirtyValueCells()
    local lo = Track.regionLo(Engine.tracks[M.selT].curRegion)
    local c = M.selS - lo + 1
    if c >= 1 and c <= 16 then dirtyCol[c] = true end
    headerDirty = true
end

-- ---- selection helpers ----

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
    -- mark old + new selected columns dirty
    local lo = Track.regionLo(Engine.tracks[M.selT].curRegion)
    local oldC = M.selS - lo + 1
    local newC = s - lo + 1
    M.selS = s
    if oldC >= 1 and oldC <= 16 then dirtyCol[oldC] = true end
    if newC >= 1 and newC <= 16 then dirtyCol[newC] = true end
    headerDirty = true
end

-- ---- input handlers ----

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
    dirtyAll()    -- mode-band outline moves; cheapest to repaint all
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

-- ---- drawing ----

-- Palette
--   1 BG_DEFAULT      (background)
--   2 BG_SELECTED     (selected-column accent stripe)
--   3 BG_PLAYHEAD     (playhead column wash)
--   4 FG_TEXT         (header text + glyphs)
--   5 FG_DIM          (idle column fill)
--   6 BAR_FILL        (active column fill)
--   7 COL_HIGHLIGHT   (mode band outline)
--   8 PROG_FILL       (clock-progress bar)
local P = {
    {  20,  20,  20 },
    { 160,  30,  30 },
    {  40,  60, 110 },
    { 230, 230, 230 },
    {  80,  80,  80 },
    { 180, 180, 180 },
    { 200, 160,  60 },
    { 110, 170, 110 },
}

-- Column geometry: 16 cols, each 20 px wide, total 320.
local COL_W = 20

-- Band y-ranges (inclusive top, exclusive bottom = top + h)
local Y_HEAD     = 0
local H_HEAD     = 15
local Y_PITCH    = 15
local H_PITCH    = 75
local Y_VEL      = 90
local H_VEL      = 75
local Y_GATEDUR  = 165
local H_GATEDUR  = 30   -- two stacked 14-px bars + 2 px gap
local Y_RATCH    = 195
local H_RATCH    = 15
local Y_MUTE     = 210
local H_MUTE     = 15
local Y_PROG     = 225
local H_PROG     = 15

-- Mode -> band index for the outline highlight.
--   1=NOTE -> pitch band
--   2=VEL  -> vel band
--   3=DUR  -> dur half of gate-dur band
--   4=GATE -> gate half of gate-dur band
--   5=MUTE -> mute glyph row
--   6=RATCH-> ratch glyph row
--   7=PROB -> (no band; falls through; PROB shown as a number in header)
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
    -- Clear strip
    scr:draw_rectangle_filled(0, Y_HEAD, 319, Y_HEAD + H_HEAD - 1, P[1])
    -- "T1 NOTE  PROB:127" style left-side legend (kept short)
    local tr = Engine.tracks[M.selT]
    local stp = tr.steps[M.selS]
    local prob = Step.prob(stp)
    local txt = "T" .. M.selT .. " " .. CELLS[M.focus] .. " R" .. tr.curRegion
                .. " S" .. string.format("%02d", M.selS)
                .. " P" .. prob
    scr:draw_text_fast(txt, 2, Y_HEAD + 3, 8, P[4])
end

-- Draw a single column from y=Y_PITCH downward through Y_PROG.
-- Does NOT touch the header (drawHeader does that).
local function drawCol(scr, c)
    local tr = Engine.tracks[M.selT]
    local lo = Track.regionLo(tr.curRegion)
    local s  = lo + c - 1
    local stp = tr.steps[s]

    local x0 = (c - 1) * COL_W
    local x1 = x0 + COL_W - 1
    local isSel = (s == M.selS)
    local isPh  = Engine.running and (tr.pos == s)

    -- Wipe the entire column (under header).
    local bg = P[1]
    if isPh then bg = P[3] end
    scr:draw_rectangle_filled(x0, Y_PITCH, x1, Y_PROG + H_PROG - 1, bg)

    -- Selected accents: vertical lines at x0 and x1.
    if isSel then
        scr:draw_rectangle_filled(x0, Y_PITCH, x0, Y_PROG + H_PROG - 1, P[2])
        scr:draw_rectangle_filled(x1, Y_PITCH, x1, Y_PROG + H_PROG - 1, P[2])
    end

    -- Inner column rect (1px in from edges so accents always show).
    local ix0, ix1 = x0 + 2, x1 - 2

    -- Pitch contour: fill height proportional to pitch/127.
    local fill = (isPh or isSel) and P[6] or P[5]
    local muted = Step.muted(stp)
    if not muted then
        local p = Step.pitch(stp)
        local h = (p * H_PITCH) // 127
        if h > 0 then
            local top = Y_PITCH + (H_PITCH - h)
            scr:draw_rectangle_filled(ix0, top, ix1, Y_PITCH + H_PITCH - 1, fill)
        end

        -- Velocity contour
        local v = Step.vel(stp)
        local hv = (v * H_VEL) // 127
        if hv > 0 then
            local topv = Y_VEL + (H_VEL - hv)
            scr:draw_rectangle_filled(ix0, topv, ix1, Y_VEL + H_VEL - 1, fill)
        end

        -- Gate-in-dur ribbon: top half = dur, bottom half = gate (capped to dur)
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

    -- Ratchet glyph
    if Step.ratch(stp) then
        scr:draw_text_fast("R", x0 + 7, Y_RATCH + 3, 8, P[4])
    end

    -- Mute glyph
    scr:draw_text_fast(muted and "M" or ".", x0 + 7, Y_MUTE + 3, 8, P[4])

    -- Per-column clock-progress: only the playhead column draws this.
    -- Other columns draw nothing (background already wiped to bg).
    if isPh and tr.stepLen and tr.stepLen > 0 then
        -- stepAcc counts DOWN from stepLen toward 0 (1 == final pulse).
        -- Filled portion = consumed fraction = (stepLen - stepAcc) / stepLen.
        local consumed = tr.stepLen - tr.stepAcc
        if consumed < 0 then consumed = 0 end
        if consumed > tr.stepLen then consumed = tr.stepLen end
        local pw = (consumed * (ix1 - ix0 + 1)) // tr.stepLen
        if pw > 0 then
            scr:draw_rectangle_filled(ix0, Y_PROG + 2, ix0 + pw - 1, Y_PROG + H_PROG - 3, P[8])
        end
    end

    -- Mode band outline (only on selected column to keep the screen quiet).
    if isSel then
        local by, bh = modeBand(M.focus)
        if bh > 0 then
            scr:draw_rectangle(x0, by, x1, by + bh - 1, P[7])
        end
    end
end

function M.draw(scr)
    -- Playhead tracking: when running, mark old + new playhead columns dirty.
    if Engine.running then
        local tr = Engine.tracks[M.selT]
        local lo = Track.regionLo(tr.curRegion)
        local c  = tr.pos - lo + 1
        if c < 1 or c > 16 then c = 0 end
        if c ~= lastPhCol then
            if lastPhCol >= 1 and lastPhCol <= 16 then dirtyCol[lastPhCol] = true end
            if c >= 1 and c <= 16 then dirtyCol[c] = true end
            lastPhCol = c
        elseif c >= 1 then
            -- Same column, but stepAcc decremented this pulse: redraw to
            -- advance the clock-progress bar.
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
