-- controls.lua
-- Grid VSN1 UI -- single-screen EDIT view.
-- Reads engine.tracks tables; calls engine setters. Core knows nothing.
--
-- Modes (selected via keyswitches 1..7):
--   1 = NOTE      cyan      per-step pitch
--   2 = VEL       orange    per-step velocity
--   3 = GATE      yellow    per-step gate;  SHIFT + endless = DUR
--   4 = MUTE      red       endless toggles mute on selS;
--                           SHIFT + endless-click toggles RATCH on selS
--   5 = STEP      blue      endless moves selected step (1..lastStep)
--   6 = (free)    --        reserved
--   7 = LASTSTEP  white     endless edits selT.lastStep (1..64)
-- Keyswitch 8     SHIFT (momentary)
--
-- Viewport: 4 logical "regions" of 16 steps each. UI-only.
-- An inline lastStep readout sits just above the 16-step bottom strip,
-- highlighted when focus == LASTSTEP.

local Engine = require("engine")
local Step   = require("step")

local M = {}

-- ---- mode table ----
local MODES = {
    { name="NOTE",     r= 30, g=200, b=220 },
    { name="VEL",      r=255, g=140, b= 30 },
    { name="GATE",     r=240, g=210, b= 40 },
    { name="MUTE",     r=220, g= 50, b= 50 },
    { name="STEP",     r= 60, g=120, b=255 },
    { name="--",       r= 70, g= 70, b= 75 },
    { name="LASTSTEP", r=230, g=230, b=230 },
}
M.MODES = MODES
M.MODE_NOTE     = 1
M.MODE_VEL      = 2
M.MODE_GATE     = 3
M.MODE_MUTE     = 4
M.MODE_STEP     = 5
M.MODE_LASTSTEP = 7

function M.modeColor(i)
    local m = MODES[i] or MODES[1]
    return m.r, m.g, m.b
end

-- ---- selection state ----
M.selT     = 1
M.selS     = 1
M.viewport = 1
M.focus    = 1
M.shift    = false

local function viewportLo(v) return (v - 1) * 16 + 1 end
M.viewportLo = viewportLo

-- ---- shared param mutator ----
-- focus i + delta d -> mutate selS on track t.
-- GATE focus + SHIFT promotes to DUR edit.
local function setParam(i, t, s, d)
    local stp = Engine.tracks[t].steps[s]
    if i == M.MODE_NOTE then
        Engine.setStepParam(t, s, "pitch", Step.pitch(stp) + d)
    elseif i == M.MODE_VEL then
        Engine.setStepParam(t, s, "vel", Step.vel(stp) + d)
    elseif i == M.MODE_GATE then
        if M.shift then
            Engine.setStepParam(t, s, "dur", Step.dur(stp) + d)
        else
            Engine.setStepParam(t, s, "gate", Step.gate(stp) + d)
        end
    elseif i == M.MODE_MUTE then
        Engine.setStepParam(t, s, "mute", Step.muted(stp) and 0 or 1)
    end
end
M.setParam = setParam

-- ---- dirty tracking ----
local needsFullRepaint = true
local lastPhCol = -1

local function dirtyAll()
    needsFullRepaint = true
    lastPhCol = -1
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
    dirtyAll()
end

function M.setSelectedStep(s)
    if s < 1 or s > Engine.tracks[M.selT].cap then return end
    if s == M.selS then return end
    M.selS = s
    local v = ((s - 1) // 16) + 1
    if v ~= M.viewport then M.viewport = v end
    needsFullRepaint = true
end

function M.setViewport(v)
    if v < 1 or v > 4 then return end
    if v == M.viewport then return end
    M.viewport = v
    local lo = viewportLo(v)
    if M.selS < lo or M.selS > lo + 15 then M.selS = lo end
    dirtyAll()
end

-- ---- input handlers ----

function M.onEndless(dir)
    local f = M.focus
    if f == M.MODE_LASTSTEP then
        local tr = Engine.tracks[M.selT]
        Engine.setLastStep(M.selT, tr.lastStep + dir)
        needsFullRepaint = true
    elseif f == M.MODE_STEP then
        local tr = Engine.tracks[M.selT]
        local s = M.selS + dir
        if s < 1 then s = tr.lastStep end
        if s > tr.lastStep then s = 1 end
        M.setSelectedStep(s)
    elseif f == M.MODE_NOTE or f == M.MODE_VEL
        or f == M.MODE_GATE or f == M.MODE_MUTE then
        setParam(f, M.selT, M.selS, dir)
        needsFullRepaint = true
    end
end

function M.onEndlessClick()
    local f = M.focus
    if f == M.MODE_LASTSTEP or f == M.MODE_STEP then return end
    if f == M.MODE_MUTE and M.shift then
        -- SHIFT + click in MUTE focus = toggle RATCH on selected step
        local stp = Engine.tracks[M.selT].steps[M.selS]
        Engine.setStepParam(M.selT, M.selS, "ratch",
            Step.ratch(stp) and 0 or 1)
    else
        local stp = Engine.tracks[M.selT].steps[M.selS]
        Engine.setStepParam(M.selT, M.selS, "mute",
            Step.muted(stp) and 0 or 1)
    end
    needsFullRepaint = true
end

function M.onKey(idx)
    if idx < 1 or idx > 7 then return end
    if idx == 6 then return end          -- reserved slot
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
        M.setSelectedTrack(idx)
    else
        M.setViewport(idx)
    end
end

-- ---- drawing ----

local C_BG       = {  18,  18,  20 }
local C_TEXT     = { 240, 240, 240 }
local C_DIM      = { 110, 110, 115 }
local C_GUIDE    = {  60,  60,  65 }
local C_OOR      = {  45,  45,  50 }
local C_PLAYHEAD = {  40,  90, 160 }

local HDR_H    = 22
local PARAM_Y  = 30
local PARAM_H  = 20
local PARAMS_N = 5                       -- rows shown above lastStep row
local LS_Y     = PARAM_Y + PARAMS_N * PARAM_H + 2  -- 2 px gap above
local LS_H     = 18
local CTX_Y    = LS_Y + LS_H + 4         -- 4 px below lastStep row
local CTX_H    = 240 - CTX_Y - 1
local COL_W    = 20

local PARAM_LABELS = { "pitch", "vel", "gate", "mute", "step" }

local function modeRGB(i) return { M.modeColor(i) } end

local function drawHeader(scr)
    local stp = Engine.tracks[M.selT].steps[M.selS]
    scr:draw_rectangle_filled(0, 0, 319, HDR_H - 1, C_BG)
    local left = "T" .. M.selT
        .. " S" .. string.format("%02d", M.selS)
        .. " V" .. M.viewport
    scr:draw_text_fast(left, 4, 4, 14, C_TEXT)
    scr:draw_text_fast(MODES[M.focus].name, 130, 4, 14, modeRGB(M.focus))
    local p = Step.pitch(stp)
    scr:draw_text_fast(Step.noteName(p) .. " (" .. p .. ")",
        210, 4, 14, C_TEXT)
    scr:draw_rectangle_filled(0, HDR_H, 319, HDR_H, C_GUIDE)
end

-- One param row. Different render per mode kind.
local function drawParamRow(scr, i)
    local stp = Engine.tracks[M.selT].steps[M.selS]
    local y = PARAM_Y + (i - 1) * PARAM_H
    local active = (i == M.focus)
    local mc = MODES[i]
    local bg = active and { mc.r, mc.g, mc.b } or C_BG
    scr:draw_rectangle_filled(0, y, 319, y + PARAM_H - 1, bg)
    local fg = active and C_TEXT or C_DIM
    scr:draw_text_fast(PARAM_LABELS[i], 4, y + 4, 12, fg)

    local val, max, glyph
    if i == M.MODE_NOTE then
        val, max = Step.pitch(stp), 127
    elseif i == M.MODE_VEL then
        val, max = Step.vel(stp), 127
    elseif i == M.MODE_GATE then
        if M.shift then
            -- show DUR while SHIFT held in GATE focus
            val, max = Step.dur(stp), 127
            glyph = nil
            scr:draw_text_fast("dur", 4, y + 4, 12, fg)
        else
            val, max = Step.gate(stp), 127
        end
    elseif i == M.MODE_MUTE then
        glyph = Step.muted(stp) and "MUTED" or "audible"
        if Step.ratch(stp) then glyph = glyph .. "  R" end
    elseif i == M.MODE_STEP then
        val, max = M.selS, Engine.tracks[M.selT].lastStep
    end

    if glyph then
        scr:draw_text_fast(glyph, 80, y + 4, 12, fg)
    elseif val then
        scr:draw_text_fast(tostring(val), 80, y + 4, 12, fg)
        local bx, bw = 130, 180
        scr:draw_rectangle(bx, y + 4, bx + bw - 1, y + PARAM_H - 6,
            active and C_TEXT or C_GUIDE)
        local fw = (val * (bw - 2)) // (max > 0 and max or 1)
        if fw > 0 then
            scr:draw_rectangle_filled(bx + 1, y + 5,
                bx + 1 + fw - 1, y + PARAM_H - 7,
                active and C_TEXT or C_DIM)
        end
    end
end

-- Inline lastStep row, sits between params and step strip.
local function drawLastStepRow(scr)
    local tr = Engine.tracks[M.selT]
    local active = (M.focus == M.MODE_LASTSTEP)
    local mc = MODES[M.MODE_LASTSTEP]
    local bg = active and { mc.r, mc.g, mc.b } or C_BG
    scr:draw_rectangle_filled(0, LS_Y, 319, LS_Y + LS_H - 1, bg)
    -- separator above
    scr:draw_rectangle_filled(0, LS_Y - 2, 319, LS_Y - 1, C_GUIDE)
    local fg = active and C_TEXT or C_DIM
    scr:draw_text_fast("lastStep", 4, LS_Y + 3, 12, fg)
    scr:draw_text_fast(tostring(tr.lastStep), 80, LS_Y + 3, 12, fg)
    -- inline mini-bar 130..310 representing 1..64
    local bx, bw = 130, 180
    scr:draw_rectangle(bx, LS_Y + 3, bx + bw - 1, LS_Y + LS_H - 5,
        active and C_TEXT or C_GUIDE)
    local fw = (tr.lastStep * (bw - 2)) // 64
    if fw > 0 then
        scr:draw_rectangle_filled(bx + 1, LS_Y + 4,
            bx + 1 + fw - 1, LS_Y + LS_H - 6,
            active and C_TEXT or C_DIM)
    end
end

local function drawCtxStrip(scr)
    local tr = Engine.tracks[M.selT]
    local lo = viewportLo(M.viewport)
    scr:draw_rectangle_filled(0, CTX_Y, 319, 239, C_BG)

    local selRGB = modeRGB(M.focus)

    for c = 1, 16 do
        local s    = lo + c - 1
        local stp  = tr.steps[s]
        local oor  = (s > tr.lastStep)
        local x0   = (c - 1) * COL_W + 1
        local x1   = x0 + COL_W - 3
        local isSel = (s == M.selS)
        local isPh  = Engine.running and (tr.pos == s)
        local bg = isPh and C_PLAYHEAD or (oor and C_OOR or C_BG)
        scr:draw_rectangle_filled(x0, CTX_Y, x1,
            CTX_Y + CTX_H - 1, bg)

        if not oor and not Step.muted(stp) then
            local p = Step.pitch(stp)
            local h = (p * (CTX_H - 4)) // 127
            if h > 0 then
                local top = CTX_Y + 2 + (CTX_H - 4 - h)
                local fill = (isPh or isSel) and C_TEXT or C_DIM
                scr:draw_rectangle_filled(x0 + 1, top, x1 - 1,
                    CTX_Y + CTX_H - 3, fill)
            end
        end

        if isSel then
            scr:draw_rectangle(x0, CTX_Y, x1,
                CTX_Y + CTX_H - 1, selRGB)
        end
    end
end

function M.draw(scr)
    local tr = Engine.tracks[M.selT]
    local ctxDirty = false
    local lo = viewportLo(M.viewport)
    if Engine.running then
        local c = tr.pos - lo + 1
        if c < 1 or c > 16 then c = 0 end
        if c ~= lastPhCol then ctxDirty = true; lastPhCol = c end
    elseif lastPhCol ~= -1 then
        ctxDirty = true; lastPhCol = -1
    end

    local any = needsFullRepaint
    if needsFullRepaint then
        scr:draw_rectangle_filled(0, 0, 319, 239, C_BG)
        drawHeader(scr)
        for i = 1, PARAMS_N do drawParamRow(scr, i) end
        drawLastStepRow(scr)
        drawCtxStrip(scr)
        needsFullRepaint = false
    elseif ctxDirty then
        drawCtxStrip(scr)
        any = true
    end

    if any then scr:draw_swap() end
end

return M
