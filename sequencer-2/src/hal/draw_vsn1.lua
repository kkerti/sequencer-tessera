-- draw_vsn1.lua — the on-device VSN1 screen (UI bundle). Two modes:
--   PLAY  — split: piano roll + playhead (top), selected param value (bottom).
--   SETUP — full 320x240 focused param grid (Hermod-style), for dialing in a
--           pattern. Selected row highlighted.
--
-- Real Grid draw API is `scr:draw_*`; ends with scr:draw_swap(). Called as
-- SEQ.draw(self, ENGINE, CTL) from the screen element's draw event. Reads only.

local Pattern = require("pattern")

local M = {}

local BG   = {12, 12, 16}
local DIM  = {60, 60, 60}
local GREY = {130, 130, 130}
local WHITE= {235, 235, 235}
local BLACK= {0, 0, 0}
local ORANGE = {249, 150, 0}
local DIMOR  = {150, 95, 20}
local CYAN   = {0, 200, 220}
local PLO, PHI = 40, 84

local function roll(scr, tr, y0h)
    local pat = tr.pattern
    local ev  = pat.events
    local loop = Pattern.loopTicks(pat)
    local ph  = (tr._gt or 0) % loop
    local rowH = (y0h - 4) / (PHI - PLO)
    local on = 0
    for i = 1, ev.n do
        local s, l, p = ev.start[i], ev.len[i], ev.pitch[i]
        local x1 = 2 + s / loop * 316
        local x2 = 2 + (s + l) / loop * 316
        if x2 - x1 < 2 then x2 = x1 + 2 end
        local y = (y0h - 2) - (p - PLO) * rowH
        local act = (ph >= s and ph < s + l)
        if act then on = on + 1 end
        scr:draw_rectangle_filled(x1, y - rowH / 2, x2, y + rowH / 2, act and ORANGE or DIMOR)
    end
    scr:draw_line(2 + ph / loop * 316, 0, 2 + ph / loop * 316, y0h - 1, CYAN)
    return on, ph, loop
end

local function drawPlay(scr, eng, ctl)
    local t = ctl and ctl.track or 1
    local tr = eng.tracks[t]
    tr._gt = (eng.gt < 0 and 0 or eng.gt)
    scr:draw_rectangle_filled(0, 0, 319, 239, BG)
    local on, ph, loop = roll(scr, tr, 120)

    scr:draw_line(0, 120, 319, 120, DIM)
    scr:draw_text_fast("T" .. t, 8, 128, 16, WHITE)
    scr:draw_text_fast(eng.playing and "PLAY" or "STOP", 232, 128, 16, eng.playing and ORANGE or DIM)
    local p = ctl and ctl.params and ctl.params[ctl.sel]
    if p then
        scr:draw_text_fast(p.label, 8, 156, 16, GREY)
        scr:draw_text_fast(p.show(), 8, 178, 24, ORANGE)
    end
    scr:draw_text_fast("KS0-5 PICK   KS6 TRACK   KS7 SETUP", 8, 224, 8, DIM)
    scr:draw_swap()
end

local function drawSetup(scr, eng, ctl)
    scr:draw_rectangle_filled(0, 0, 319, 239, BG)
    scr:draw_text_fast("PATTERN SETUP", 8, 6, 16, ORANGE)
    scr:draw_text_fast("T" .. ctl.track, 284, 6, 16, WHITE)
    scr:draw_line(0, 26, 319, 26, DIM)

    local rows = #ctl.params
    local leftN = math.ceil(rows / 2)
    for i = 1, rows do
        local left = (i <= leftN)
        local x = left and 16 or 176
        local row = left and (i - 1) or (i - leftN - 1)
        local y = 32 + row * 26
        local sel = (i == ctl.sel)
        -- selection = colour only (no fill box that hides the value)
        if sel then scr:draw_text_fast(">", x - 12, y, 16, WHITE) end
        scr:draw_text_fast(ctl.params[i].label, x, y, 16, sel and WHITE or GREY)
        scr:draw_text_fast(ctl.params[i].show(), x + 84, y, 16, sel and WHITE or ORANGE)
    end

    scr:draw_line(0, 214, 319, 214, DIM)
    scr:draw_text_fast("ENC edit   KS0/1 nav   KS5 reroll   KS6 track   KS7 exit", 6, 224, 8, GREY)
    scr:draw_swap()
end

function M.draw(scr, eng, ctl)
    if ctl and ctl.mode == "SETUP" then drawSetup(scr, eng, ctl)
    else drawPlay(scr, eng, ctl) end
end

return M
