-- controls.lua
-- Grid VSN1 UI -- single-screen EDIT view.
-- Reads engine.tracks tables; calls engine setters. Core knows nothing.
--
-- Modes (selected via keyswitches 1..7):
--   1 = NOTE      cyan      per-step pitch
--   2 = VEL       orange    per-step velocity
--   3 = GATE      yellow    per-step note-on length
--   4 = MUTE      red       per-step mute toggle
--   5 = DUR       magenta   per-step pulse length (advanced)
--   6 = RATCH     green     per-step ratchet toggle (advanced)
--   7 = LASTSTEP  white     per-track loop end (1..64; default 16)
--
-- Viewport: 4 logical "regions" of 16 steps each (1..16, 17..32, ...).
-- The viewport is purely UI -- the engine has no concept of regions.
-- Switched by small button press (no SHIFT).
--
-- Polyrhythm awareness: each track has its own lastStep. The selected
-- track's playhead may be outside the viewport; an indicator shows
-- where it actually is.

local Engine = require("engine")
local Track  = require("track")
local Step   = require("step")

local M = {}

-- ---- mode table (single source of truth for naming + RGB) ----
-- Color values are exposed via M.modeColor(idx) so EN16 LEDs match.
local MODES = {
    { name="NOTE",     r= 30, g=200, b=220 },  -- cyan
    { name="VEL",      r=255, g=140, b= 30 },  -- orange
    { name="GATE",     r=240, g=210, b= 40 },  -- yellow
    { name="MUTE",     r=220, g= 50, b= 50 },  -- red
    { name="DUR",      r=200, g= 60, b=200 },  -- magenta
    { name="RATCH",    r= 60, g=200, b=100 },  -- green
    { name="LASTSTEP", r=230, g=230, b=230 },  -- white
}
M.MODES = MODES
M.MODE_NOTE     = 1
M.MODE_VEL      = 2
M.MODE_GATE     = 3
M.MODE_MUTE     = 4
M.MODE_DUR      = 5
M.MODE_RATCH    = 6
M.MODE_LASTSTEP = 7

function M.modeColor(i)
    local m = MODES[i] or MODES[1]
    return m.r, m.g, m.b
end

-- ---- selection state (UI only; not in Core) ----
M.selT     = 1
M.selS     = 1
M.viewport = 1   -- 1..4: which 16-step window we're looking at
M.focus    = 1   -- 1..7 mode index
M.shift    = false

local function viewportLo(v) return (v - 1) * 16 + 1 end
M.viewportLo = viewportLo

-- ---- shared param mutator (delta applied to selected step's mode field) ----
local function setParam(i, t, s, d)
    local stp = Engine.tracks[t].steps[s]
    if i == M.MODE_NOTE then
        Engine.setStepParam(t, s, "pitch", Step.pitch(stp) + d)
    elseif i == M.MODE_VEL then
        Engine.setStepParam(t, s, "vel", Step.vel(stp) + d)
    elseif i == M.MODE_GATE then
        Engine.setStepParam(t, s, "gate", Step.gate(stp) + d)
    elseif i == M.MODE_MUTE then
        Engine.setStepParam(t, s, "mute", Step.muted(stp) and 0 or 1)
    elseif i == M.MODE_DUR then
        Engine.setStepParam(t, s, "dur", Step.dur(stp) + d)
    elseif i == M.MODE_RATCH then
        Engine.setStepParam(t, s, "ratch", Step.ratch(stp) and 0 or 1)
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
    -- snap viewport to contain selected step
    local v = ((s - 1) // 16) + 1
    if v ~= M.viewport then M.viewport = v end
    needsFullRepaint = true
end

function M.setViewport(v)
    if v < 1 or v > 4 then return end
    if v == M.viewport then return end
    M.viewport = v
    -- keep selS within new viewport for editing convenience
    local lo = viewportLo(v)
    if M.selS < lo or M.selS > lo + 15 then M.selS = lo end
    dirtyAll()
end

-- ---- input handlers ----

function M.onEndless(dir)
    if M.focus == M.MODE_LASTSTEP then
        local tr = Engine.tracks[M.selT]
        Engine.setLastStep(M.selT, tr.lastStep + dir)
        needsFullRepaint = true
    elseif M.focus >= 1 and M.focus <= 6 then
        setParam(M.focus, M.selT, M.selS, dir)
        needsFullRepaint = true
    end
end

function M.onEndlessClick()
    if M.focus == M.MODE_LASTSTEP then return end
    local stp = Engine.tracks[M.selT].steps[M.selS]
    Engine.setStepParam(M.selT, M.selS, "mute", Step.muted(stp) and 0 or 1)
    needsFullRepaint = true
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
        M.setSelectedTrack(idx)
    else
        M.setViewport(idx)
    end
end

-- ---- drawing ----

-- Static colors
local C_BG       = {  18,  18,  20 }
local C_TEXT     = { 240, 240, 240 }
local C_DIM      = { 110, 110, 115 }
local C_GUIDE    = {  60,  60,  65 }
local C_OOR      = {  45,  45,  50 }   -- out-of-range placeholder
local C_PLAYHEAD = {  40,  90, 160 }   -- blue wash on playhead column

local HDR_H   = 22
local PARAM_Y = 30
local PARAM_H = 20
local CTX_Y   = 192
local CTX_H   = 48
local COL_W   = 20

local PARAM_LABELS = { "pitch", "vel", "gate", "mute", "dur", "ratch" }

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
        val, max = Step.gate(stp), 127
    elseif i == M.MODE_MUTE then
        glyph = Step.muted(stp) and "MUTED" or "audible"
    elseif i == M.MODE_DUR then
        val, max = Step.dur(stp), 127
    elseif i == M.MODE_RATCH then
        glyph = Step.ratch(stp) and "RATCH" or "off"
    end

    if glyph then
        scr:draw_text_fast(glyph, 80, y + 4, 12, fg)
    else
        scr:draw_text_fast(tostring(val), 80, y + 4, 12, fg)
        local bx, bw = 130, 180
        scr:draw_rectangle(bx, y + 4, bx + bw - 1, y + PARAM_H - 6,
            active and C_TEXT or C_GUIDE)
        local fw = (val * (bw - 2)) // max
        if fw > 0 then
            scr:draw_rectangle_filled(bx + 1, y + 5,
                bx + 1 + fw - 1, y + PARAM_H - 7,
                active and C_TEXT or C_DIM)
        end
    end
end

local function drawCtxStrip(scr)
    local tr = Engine.tracks[M.selT]
    local lo = viewportLo(M.viewport)
    scr:draw_rectangle_filled(0, CTX_Y - 8, 319, 239, C_BG)
    scr:draw_rectangle_filled(0, CTX_Y - 8, 319, CTX_Y - 8, C_GUIDE)

    -- info: viewport + lastStep + playhead-outside indicator
    local info = "V" .. M.viewport
        .. "  last:" .. tr.lastStep
    if Engine.running and (tr.pos < lo or tr.pos > lo + 15) then
        info = info .. "  ph:" .. tr.pos
    end
    scr:draw_text_fast(info, 4, CTX_Y - 6, 8, C_DIM)

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

-- LASTSTEP screen takeover: 64-cell mini-map of the whole track buffer,
-- big number in the middle.
local function drawLastStepScreen(scr)
    local tr = Engine.tracks[M.selT]
    scr:draw_rectangle_filled(0, 0, 319, 239, C_BG)

    -- header
    scr:draw_rectangle_filled(0, 0, 319, HDR_H - 1, C_BG)
    scr:draw_text_fast("T" .. M.selT, 4, 4, 14, C_TEXT)
    scr:draw_text_fast("LASTSTEP", 130, 4, 14, modeRGB(M.MODE_LASTSTEP))
    scr:draw_rectangle_filled(0, HDR_H, 319, HDR_H, C_GUIDE)

    -- big number, centered-ish
    scr:draw_text_fast(tostring(tr.lastStep), 110, 60, 60,
        modeRGB(M.MODE_LASTSTEP))
    scr:draw_text_fast("steps", 130, 130, 14, C_DIM)

    -- 64-cell mini-map at bottom: 64 cells × 4 px wide, 24 px tall
    local mapY = 200
    local mapH = 30
    local cellW = 5
    local x0 = (320 - 64 * cellW) // 2
    -- viewport boundaries 16/32/48 as ticks
    for i = 1, 64 do
        local cx = x0 + (i - 1) * cellW
        local active = (i <= tr.lastStep)
        local color = active
            and ((i % 16 == 1) and modeRGB(M.MODE_LASTSTEP) or C_DIM)
            or C_OOR
        scr:draw_rectangle_filled(cx, mapY, cx + cellW - 2,
            mapY + mapH - 1, color)
        if i == tr.lastStep then
            scr:draw_rectangle(cx - 1, mapY - 2, cx + cellW - 1,
                mapY + mapH + 1, modeRGB(M.MODE_LASTSTEP))
        end
        if Engine.running and tr.pos == i then
            scr:draw_rectangle_filled(cx, mapY - 6,
                cx + cellW - 2, mapY - 3, C_PLAYHEAD)
        end
    end
end

function M.draw(scr)
    if M.focus == M.MODE_LASTSTEP then
        if needsFullRepaint or Engine.running then
            drawLastStepScreen(scr)
            needsFullRepaint = false
            scr:draw_swap()
        end
        return
    end

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
        for i = 1, 6 do drawParamRow(scr, i) end
        drawCtxStrip(scr)
        needsFullRepaint = false
    elseif ctxDirty then
        drawCtxStrip(scr)
        any = true
    end

    if any then scr:draw_swap() end
end

return M
