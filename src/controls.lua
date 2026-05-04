-- controls.lua
-- Grid VSN1 UI -- single-screen EDIT view.
-- Reads engine.tracks tables; calls engine setters. Core knows nothing.
--
-- Hardware:
--   - 320x240 LCD
--   - 4 small buttons under screen
--   - 8 keyswitches (modes 1-7 + SHIFT on slot 8)
--   - Endless jog wheel (relative: 65 = up, 63 = down) with click
--
-- Control model:
--   * Keyswitches 1..7   : select MODE NOTE/VEL/DUR/GATE/MUTE/RATCH/PROB
--   * Keyswitch 8        : SHIFT (momentary)
--   * Small btn 1..4     : (no SHIFT) select TRACK 1..4
--                          (+ SHIFT)  queue REGION 1..4
--   * Endless turn       : edit selected step in current mode
--   * Endless click      : toggle selected step's mute
--   * EN16 turn/push     : per-step edit / mute toggle
--
-- EDIT screen layout (320x240):
--   y   0..21   header:  T1 S05 R1   NOTE   C4 (60)
--   y  22       1-px separator
--   y  30..169  7 param rows (20 px each): label | value | bar
--                 active mode row gets HOT background.
--   y 184       1-px separator (above context strip)
--   y 192..239  bottom context strip: 16 mini pitch contours,
--                 selected = red outline, playhead = blue wash.

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
-- needsFullRepaint: header + all 7 param rows + ctx strip.
-- ctxDirty: only redraw the bottom context strip (playhead chase).
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
    M.selS = s
    needsFullRepaint = true
end

-- ---- input handlers ----

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

-- ---- drawing ----

-- Palette
--   1 BG          dark background
--   2 ACCENT_HOT  red-orange (selected, active mode wash)
--   3 ACCENT_COOL blue (playhead wash)
--   4 TEXT        bright white
--   5 TEXT_DIM    grey
--   6 FILL        bright bar fill
--   7 FILL_DIM    quiet bar fill
--   8 GUIDE       thin separator
local P = {
    {  18,  18,  20 },
    { 200,  60,  40 },
    {  40,  90, 160 },
    { 240, 240, 240 },
    { 110, 110, 115 },
    { 200, 200, 200 },
    {  90,  90,  95 },
    {  60,  60,  65 },
}

local NOTE = { "C","C#","D","D#","E","F","F#","G","G#","A","A#","B" }
local function noteName(p)
    local oct = (p // 12) - 1
    return NOTE[(p % 12) + 1] .. tostring(oct)
end

local HDR_H   = 22
local PARAM_Y = 30
local PARAM_H = 20
local CTX_Y   = 192
local CTX_H   = 48
local COL_W   = 20

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
        local s   = lo + c - 1
        local stp = tr.steps[s]
        local x0  = (c - 1) * COL_W + 1
        local x1  = x0 + COL_W - 3
        local isSel = (s == M.selS)
        local isPh  = Engine.running and (tr.pos == s)
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
        local c  = tr.pos - lo + 1
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
