-- draw_text.lua — LEAN text-only VSN1 screen (UI bundle).
--
-- Device-budget rewrite: no piano roll, no per-note rectangles — every mode
-- is a handful of draw_text_fast lines + one background fill + one swap.
-- (The graphical views were cut; the screen shows state as text, seq-1
-- style. Playhead position is reported as text "pos t/n".)
--
--   PLAY  — mode/track/seq/run header, selected param + value (big),
--           playhead position + note count, flags (nap/auto/staged), hints.
--           SETUP (ENTER) = full-screen param grid, also text-only.
--   STEP  — header, step cursor, field (PITCH/LEN/VEL) + value, hints.
--   SEQ   — header, per-track slot row "T1:P1 T2:P3 ...", hints.
--
-- Real Grid draw API is scr:draw_*; ends with scr:draw_swap(). Called as
-- DRAW(self, ENGINE, CTL) from the screen element's draw event. Reads only.

local Pattern = require("pattern")

local M = {}

local BG     = {12, 12, 16}
local DIM    = {60, 60, 60}
local GREY   = {130, 130, 130}
local WHITE  = {235, 235, 235}
local ORANGE = {249, 150, 0}
local GREEN  = {90, 220, 120}

local NOTE = { "C","C#","D","D#","E","F","F#","G","G#","A","A#","B" }
local function noteName(m) return NOTE[m % 12 + 1] .. (m // 12 - 1) end

local function localTickOf(pat, gt)
    if gt < 0 then return 0 end
    local s0, loopLen = Pattern.loopWindow(pat)
    if gt < s0 then return 0 end
    return s0 + (gt - s0) % loopLen
end

local function head(scr, mode, t, eng)
    scr:draw_text_fast(mode, 8, 6, 16, ORANGE)
    scr:draw_text_fast("T" .. t, 70, 6, 16, WHITE)
    scr:draw_text_fast("SEQ" .. eng.currentSeq .. "/" .. #eng.sequences, 120, 8, 12, GREY)
    scr:draw_text_fast(eng.playing and "RUN" or "STOP", 270, 6, 16,
                       eng.playing and ORANGE or DIM)
    scr:draw_line(0, 26, 319, 26, DIM)
end

-- ---- PLAY (compact) ----------------------------------------------------
local function drawPlay(scr, eng, ctl)
    local t = ctl.track
    local tr = eng.tracks[t]
    scr:draw_rectangle_filled(0, 0, 319, 239, BG)
    head(scr, "PLAY", t, eng)

    local i = ctl.sel
    local val = ctl.show(i)
    if tr.dirty then val = val .. " *" end
    scr:draw_text_fast(ctl.params[i][1], 8, 40, 16, GREY)
    scr:draw_text_fast(val, 8, 64, 24, tr.dirty and ORANGE or WHITE)

    local pat = tr.pattern
    local full = Pattern.loopTicks(pat)
    scr:draw_text_fast("pos " .. localTickOf(pat, eng.gt) .. "/" .. full
                       .. "  notes " .. pat.events.n, 8, 108, 12, GREY)

    local flags = ""
    if tr.nap.armed then flags = flags .. (tr.nap.muted and "NAP!" or "nap") .. " " end
    if tr.auto.armed then flags = flags .. "auto " end
    if tr.dirty then flags = flags .. "staged " end
    if flags ~= "" then scr:draw_text_fast(flags, 8, 200, 12, GREEN) end

    scr:draw_text_fast("0-4 PAR  5 AUTO  6 TRK  7 MODE", 6, 224, 8, DIM)
    scr:draw_text_fast("9 BACK  10 SETUP  11 NAP  12 OK", 6, 232, 8, DIM)
    scr:draw_swap()
end

-- ---- PLAY (SETUP = full param grid) ------------------------------------
local function drawSetup(scr, eng, ctl)
    scr:draw_rectangle_filled(0, 0, 319, 239, BG)
    scr:draw_text_fast("SETUP (BACK exit)", 8, 6, 16, ORANGE)
    scr:draw_text_fast("T" .. ctl.track, 284, 6, 16, WHITE)
    if eng.tracks[ctl.track].dirty then scr:draw_text_fast("*", 196, 6, 16, ORANGE) end
    scr:draw_line(0, 26, 319, 26, DIM)

    local rows = #ctl.params
    local leftN = (rows + 1) // 2
    for i = 1, rows do
        local left = (i <= leftN)
        local x = left and 16 or 172
        local row = left and (i - 1) or (i - leftN - 1)
        local y = 32 + row * 26
        local sel = (i == ctl.sel)
        if sel then scr:draw_text_fast(">", x - 12, y, 16, WHITE) end
        scr:draw_text_fast(ctl.params[i][1], x, y, 16, sel and WHITE or GREY)
        scr:draw_text_fast(ctl.show(i), x + 82, y, 16, sel and ORANGE or WHITE)
    end

    scr:draw_line(0, 214, 319, 214, DIM)
    scr:draw_text_fast("0/1 NAV  5 AUTO  6 TRK  7 MODE  12 OK", 6, 224, 8, GREY)
    scr:draw_swap()
end

-- ---- STEP ----------------------------------------------------------------
local FIELD = { "PITCH", "LEN", "VEL" }
local function drawStep(scr, eng, ctl)
    local t = ctl.track
    local tr = eng.tracks[t]
    scr:draw_rectangle_filled(0, 0, 319, 239, BG)
    head(scr, "STEP", t, eng)
    scr:draw_text_fast("st " .. (ctl.step + 1) .. "/" .. tr.pattern.length, 8, 40, 16, WHITE)

    local pat = tr.pattern
    local ev = pat.events
    local tick = ctl.step * pat.zoom
    local pitch, len, vel, found
    for i = 1, ev.n do
        if ev.start[i] == tick then
            pitch, len, vel, found = ev.pitch[i], ev.len[i], ev.vel[i], true
            break
        end
    end

    scr:draw_text_fast(FIELD[ctl.field], 8, 84, 16, GREY)
    local val = "-"
    if found then
        if ctl.field == 1 then val = noteName(pitch)
        elseif ctl.field == 2 then val = len .. "t"
        else val = tostring(vel) end
    end
    scr:draw_text_fast(val, 8, 108, 24, WHITE)

    scr:draw_text_fast("0 ADD  1 DEL  2/3 OCT  4/5 EDIT  6 TRK", 6, 224, 8, DIM)
    scr:draw_text_fast("enc STEP  click FIELD  11 NAP  12 OK", 6, 232, 8, DIM)
    scr:draw_swap()
end

-- ---- SEQ (slot picker) ----------------------------------------------------
local function drawSeq(scr, eng, ctl)
    scr:draw_rectangle_filled(0, 0, 319, 239, BG)
    head(scr, "SEQ", ctl.track, eng)

    local seq = eng.sequences[eng.currentSeq]
    local sel = ctl.seqTrack
    for k = 1, #eng.tracks do
        local label = "T" .. k .. ":P" .. seq.slot[k] .. (seq.mute[k] and "m" or "")
        scr:draw_text_fast(label, 8, 40 + (k - 1) * 24, 24,
                           k == sel and ORANGE or WHITE)
    end

    scr:draw_text_fast("0-3 TRK  5 MUTE  enc SLOT  click SEQ", 6, 224, 8, DIM)
    scr:draw_text_fast("9 BACK  11 NAP  12 OK", 6, 232, 8, DIM)
    scr:draw_swap()
end

-- ---- entry ----------------------------------------------------------------
function M.draw(scr, eng, ctl)
    if not ctl then return end
    if ctl.frame then ctl.frame() end
    if ctl.mode == "PLAY" then
        if ctl.setup then drawSetup(scr, eng, ctl) else drawPlay(scr, eng, ctl) end
    elseif ctl.mode == "STEP" then
        drawStep(scr, eng, ctl)
    else
        drawSeq(scr, eng, ctl)
    end
end

return M
