-- controls.lua  (slim)
local Engine = require("engine")
local Step   = require("step")

local M = {}

-- mode table: parallel arrays, no name strings except a single label list
local MR = {  30, 255, 240, 220,  60,  70, 230 }
local MG = { 200, 140, 210,  50, 120,  70, 230 }
local MB = { 220,  30,  40,  50, 255,  75, 230 }
local MN = { "NOTE", "VEL", "GATE", "MUTE", "STEP", "--", "LAST" }

M.MODE_NOTE     = 1
M.MODE_VEL      = 2
M.MODE_GATE     = 3
M.MODE_MUTE     = 4
M.MODE_STEP     = 5
M.MODE_LASTSTEP = 7
M.MODES         = MN          -- shape kept for tests/UI consumers

function M.modeColor(i) return MR[i], MG[i], MB[i] end

-- selection state (UI only)
M.selT, M.selS, M.viewport, M.focus, M.shift = 1, 1, 1, 1, false

local function vplo(v) return (v - 1) * 16 + 1 end
M.viewportLo = vplo

local function setParam(i, t, s, d)
    local stp = Engine.tracks[t].steps[s]
    if i == 1 then
        Engine.setStepParam(t, s, "pitch", Step.pitch(stp) + d)
    elseif i == 2 then
        Engine.setStepParam(t, s, "vel", Step.vel(stp) + d)
    elseif i == 3 then
        if M.shift then
            Engine.setStepParam(t, s, "dur", Step.dur(stp) + d)
        else
            Engine.setStepParam(t, s, "gate", Step.gate(stp) + d)
        end
    elseif i == 4 then
        Engine.setStepParam(t, s, "mute", Step.muted(stp) and 0 or 1)
    end
end
M.setParam = setParam

-- dirty flag (single bool; ph repaints whole screen at 30 Hz cap)
local dirty = true
local function dAll() dirty = true end
M.dirtyAll        = dAll
M.dirtyValueCells = dAll

function M.setSelectedTrack(t)
    if t < 1 or t > #Engine.tracks or t == M.selT then return end
    M.selT = t; dirty = true
end

function M.setSelectedStep(s)
    if s < 1 or s > Engine.tracks[M.selT].cap or s == M.selS then return end
    M.selS = s
    M.viewport = ((s - 1) // 16) + 1
    dirty = true
end

function M.setViewport(v)
    if v < 1 or v > 4 or v == M.viewport then return end
    M.viewport = v
    local lo = vplo(v)
    if M.selS < lo or M.selS > lo + 15 then M.selS = lo end
    dirty = true
end

function M.onEndless(dir)
    local f = M.focus
    if f == 7 then
        local tr = Engine.tracks[M.selT]
        Engine.setLastStep(M.selT, tr.lastStep + dir)
    elseif f == 5 then
        local tr = Engine.tracks[M.selT]
        local s = M.selS + dir
        if s < 1 then s = tr.lastStep end
        if s > tr.lastStep then s = 1 end
        M.setSelectedStep(s); return
    elseif f >= 1 and f <= 4 then
        setParam(f, M.selT, M.selS, dir)
    end
    dirty = true
end

function M.onEndlessClick()
    local f = M.focus
    if f == 7 or f == 5 then return end
    local stp = Engine.tracks[M.selT].steps[M.selS]
    if f == 4 and M.shift then
        Engine.setStepParam(M.selT, M.selS, "ratch",
            Step.ratch(stp) and 0 or 1)
    else
        Engine.setStepParam(M.selT, M.selS, "mute",
            Step.muted(stp) and 0 or 1)
    end
    dirty = true
end

function M.onKey(idx)
    if idx < 1 or idx > 7 or idx == 6 or idx == M.focus then return end
    M.focus = idx; dirty = true
end

function M.setShift(b)
    b = b and true or false
    if b == M.shift then return end
    M.shift = b
end

function M.onSmallBtn(idx)
    if idx < 1 or idx > 4 then return end
    if M.shift then M.setSelectedTrack(idx) else M.setViewport(idx) end
end

-- ---- drawing ----
local C_BG   = {  18,  18,  20 }
local C_FG   = { 240, 240, 240 }
local C_DIM  = { 110, 110, 115 }
local C_LINE = {  60,  60,  65 }
local C_OOR  = {  35,  35,  40 }
local C_PH   = {  40,  90, 160 }

-- Layout (320x240)
local ROW_H  = 22                 -- header & each value row
local PARAMS = 5
local LS_Y   = ROW_H * (1 + PARAMS) + 2     -- separator above lastStep
local LS_H   = ROW_H
local STR_Y  = LS_Y + LS_H + 4
local STR_H  = 240 - STR_Y - 1
local COL_W  = 20

local function valueOf(stp, i)
    if i == 1 then return Step.pitch(stp), 127 end
    if i == 2 then return Step.vel(stp),   127 end
    if i == 3 then
        if M.shift then return Step.dur(stp), 127 end
        return Step.gate(stp), 127
    end
    if i == 4 then return Step.muted(stp) and 0 or 1, 1 end
    if i == 5 then return M.selS, Engine.tracks[M.selT].lastStep end
    return 0, 1
end

local function rgb(i) return { MR[i], MG[i], MB[i] } end

function M.draw(scr)
    if not dirty and not Engine.running then return end
    dirty = false

    local tr  = Engine.tracks[M.selT]
    local stp = tr.steps[M.selS]
    local f   = M.focus

    scr:draw_rectangle_filled(0, 0, 319, 239, C_BG)

    -- header
    local p = Step.pitch(stp)
    scr:draw_text_fast(
        "T" .. M.selT .. " S" .. M.selS .. " V" .. M.viewport
            .. "  " .. MN[f] .. "  " .. Step.noteName(p),
        4, 4, 14, rgb(f))

    -- param rows
    for i = 1, PARAMS do
        local y = ROW_H * i
        local active = (i == f)
        if active then
            scr:draw_rectangle_filled(0, y, 319, y + ROW_H - 1, rgb(i))
        end
        local fg = active and C_FG or C_DIM
        local v, _ = valueOf(stp, i)
        local txt
        if i == 4 then
            txt = (v == 1) and "audible" or "MUTED"
            if Step.ratch(stp) then txt = txt .. "  R" end
        elseif i == 3 and M.shift then
            txt = "dur  " .. v
        else
            txt = MN[i]:lower() .. "  " .. v
        end
        scr:draw_text_fast(txt, 6, y + 4, 14, fg)
    end

    -- separator + lastStep row
    scr:draw_rectangle_filled(0, LS_Y - 2, 319, LS_Y - 1, C_LINE)
    if f == 7 then
        scr:draw_rectangle_filled(0, LS_Y, 319, LS_Y + LS_H - 1, rgb(7))
    end
    scr:draw_text_fast("last  " .. tr.lastStep, 6, LS_Y + 4, 14,
        f == 7 and C_FG or C_DIM)

    -- 16-cell step strip
    local lo = vplo(M.viewport)
    local mr_, mg_, mb_ = MR[f], MG[f], MB[f]
    for c = 1, 16 do
        local s = lo + c - 1
        local x0 = (c - 1) * COL_W + 1
        local x1 = x0 + COL_W - 3
        local oor = (s > tr.lastStep)
        local cs = tr.steps[s]
        local muted = (not oor) and Step.muted(cs)

        -- base cell color: mode color × value (NOTE/VEL/GATE/STEP),
        -- mute red wash (MUTE focus), or neutral
        local cr, cg, cb = C_OOR[1], C_OOR[2], C_OOR[3]
        if not oor then
            if muted then
                cr, cg, cb = 30, 10, 10
            elseif f == 4 then
                cr, cg, cb = 30, 30, 32
            else
                local v = valueOf(cs, f) or 0
                if f == 5 then v = 127 end
                local k = 40 + (160 * v) // 127
                cr = (mr_ * k) // 255
                cg = (mg_ * k) // 255
                cb = (mb_ * k) // 255
            end
        end
        scr:draw_rectangle_filled(x0, STR_Y, x1, STR_Y + STR_H - 1,
            { cr, cg, cb })

        -- selected outline
        if s == M.selS then
            scr:draw_rectangle(x0, STR_Y, x1, STR_Y + STR_H - 1, rgb(f))
        end
        -- playhead inner rectangle (small, centered)
        if Engine.running and tr.pos == s then
            scr:draw_rectangle_filled(
                x0 + 4, STR_Y + 4, x1 - 4, STR_Y + STR_H - 5, C_PH)
        end
    end

    scr:draw_swap()
end

return M
