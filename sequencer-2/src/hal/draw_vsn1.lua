-- draw_vsn1.lua — the on-device VSN1 screen (UI bundle). Three M4 modes:
--   PLAY  — piano roll + playhead (top); staged param + status (bottom).
--           SETUP (SHIFT+KS4) = full-screen param grid within PLAY.
--   STEP  — piano roll + playhead + step cursor (top); note editor (bottom).
--   SEQ   — piano roll + playhead (top); sequence/song builder (bottom).
-- Real Grid draw API is scr:draw_*; ends with scr:draw_swap(). Called as
-- SEQ.draw(self, ENGINE, CTL) from the screen element's draw event. Reads only.

local Pattern = require("pattern")

local M = {}

local BG     = {12, 12, 16}
local DIM    = {60, 60, 60}
local GREY   = {130, 130, 130}
local WHITE  = {235, 235, 235}
local ORANGE = {249, 150, 0}
local DIMOR  = {150, 95, 20}
local CYAN   = {0, 200, 220}
local GREEN  = {90, 220, 120}

local PLO, PHI = 40, 84
local NOTE = { "C","C#","D","D#","E","F","F#","G","G#","A","A#","B" }
local function noteName(m) return NOTE[m % 12 + 1] .. (m // 12 - 1) end

-- Playhead position within the (possibly loop-regioned) window.
local function localTickOf(pat, gt)
    if gt < 0 then return 0 end
    local s0, loopLen = Pattern.loopWindow(pat)
    if gt < s0 then return 0 end
    return s0 + (gt - s0) % loopLen
end

-- Piano roll + playhead; loop-region markers if active; step cursor in STEP.
local function roll(scr, tr, gt, cursorStep)
    local pat = tr.pattern
    local ev  = pat.events
    local full = Pattern.loopTicks(pat)
    local lt = localTickOf(pat, gt)
    local rowH = 116 / (PHI - PLO)
    for i = 1, ev.n do
        local s, l, p = ev.start[i], ev.len[i], ev.pitch[i]
        local x1 = 2 + s / full * 316
        local x2 = 2 + (s + l) / full * 316
        if x2 - x1 < 2 then x2 = x1 + 2 end
        local y = 118 - (p - PLO) * rowH
        local act = (lt >= s and lt < s + l)
        scr:draw_rectangle_filled(x1, y - rowH / 2, x2, y + rowH / 2, act and ORANGE or DIMOR)
    end
    local px = 2 + lt / full * 316
    scr:draw_line(px, 0, px, 119, CYAN)
    local le = pat.loopEnd or pat.length
    if le < pat.length then
        local xa = 2 + (pat.loopStart or 0) * pat.zoom / full * 316
        local xb = 2 + le * pat.zoom / full * 316
        scr:draw_line(xa, 0, xa, 119, GREY)
        scr:draw_line(xb, 0, xb, 119, GREY)
    end
    if cursorStep then
        local cx = 2 + cursorStep / pat.length * 316
        scr:draw_line(cx, 0, cx, 119, WHITE)
    end
    return lt
end

-- ---- PLAY (compact) ----------------------------------------------------
local function drawPlay(scr, eng, ctl)
    local t = ctl.track
    local tr = eng.tracks[t]
    scr:draw_rectangle_filled(0, 0, 319, 239, BG)
    roll(scr, tr, eng.gt)
    scr:draw_line(0, 120, 319, 120, DIM)

    scr:draw_text_fast("PLAY", 8, 126, 16, ORANGE)
    scr:draw_text_fast("T" .. t, 62, 126, 16, WHITE)
    scr:draw_text_fast("SEQ" .. eng.currentSeq .. "/" .. #eng.sequences, 98, 130, 12, GREY)
    scr:draw_text_fast(eng.playing and "RUN" or "STOP", 260, 126, 16, eng.playing and ORANGE or DIM)

    local p = ctl.params[ctl.sel]
    if p then
        local val = p.show()
        if tr.dirty then val = val .. " *" end
        scr:draw_text_fast(p.label, 8, 150, 16, GREY)
        scr:draw_text_fast(val, 8, 174, 24, tr.dirty and ORANGE or WHITE)
    end

    local flags = ""
    if tr.nap.armed then flags = flags .. (tr.nap.muted and "NAP!" or "nap") .. " " end
    if tr.auto.armed then flags = flags .. "auto " end
    if ctl.shift then flags = flags .. "SHIFT" end
    if flags ~= "" then scr:draw_text_fast(flags, 8, 214, 8, GREEN) end

    scr:draw_text_fast("S+1 COMMIT  S+2 NAP  S+3 AUTO  S+4 SETUP  KS7 MODE", 6, 228, 8, DIM)
    scr:draw_swap()
end

-- ---- PLAY (SETUP = full param grid) ------------------------------------
local function drawSetup(scr, eng, ctl)
    scr:draw_rectangle_filled(0, 0, 319, 239, BG)
    scr:draw_text_fast("SETUP (S+4 exit)", 8, 6, 16, ORANGE)
    scr:draw_text_fast("T" .. ctl.track, 284, 6, 16, WHITE)
    if eng.tracks[ctl.track].dirty then scr:draw_text_fast("*", 196, 6, 16, ORANGE) end
    scr:draw_line(0, 26, 319, 26, DIM)

    local rows = #ctl.params
    local leftN = math.ceil(rows / 2)
    for i = 1, rows do
        local left = (i <= leftN)
        local x = left and 16 or 172
        local row = left and (i - 1) or (i - leftN - 1)
        local y = 32 + row * 26
        local sel = (i == ctl.sel)
        if sel then scr:draw_text_fast(">", x - 12, y, 16, WHITE) end
        scr:draw_text_fast(ctl.params[i].label, x, y, 16, sel and WHITE or GREY)
        scr:draw_text_fast(ctl.params[i].show(), x + 82, y, 16, sel and ORANGE or WHITE)
    end

    scr:draw_line(0, 214, 319, 214, DIM)
    scr:draw_text_fast("S+1 COMMIT  KS1/2 NAV  KS6 TRK  KS7 MODE", 6, 224, 8, GREY)
    scr:draw_swap()
end

-- ---- STEP ----------------------------------------------------------------
local FIELD = { "PITCH", "LEN", "VEL" }
local function drawStep(scr, eng, ctl)
    local t = ctl.track
    local tr = eng.tracks[t]
    scr:draw_rectangle_filled(0, 0, 319, 239, BG)
    roll(scr, tr, eng.gt, ctl.step)
    scr:draw_line(0, 120, 319, 120, DIM)

    scr:draw_text_fast("STEP", 8, 126, 16, ORANGE)
    scr:draw_text_fast("T" .. t, 60, 126, 16, WHITE)
    scr:draw_text_fast("st " .. (ctl.step + 1), 98, 130, 12, GREY)

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

    scr:draw_text_fast(FIELD[ctl.field], 8, 150, 16, GREY)
    local val = "-"
    if found then
        if ctl.field == 1 then val = noteName(pitch)
        elseif ctl.field == 2 then val = len .. "t"
        else val = tostring(vel) end
    end
    scr:draw_text_fast(val, 8, 174, 24, WHITE)

    scr:draw_text_fast("KS1 ADD  S+1 DEL  KS2/3 OCT  KS4/5 EDIT  KS6 TRK", 6, 228, 8, DIM)
    scr:draw_swap()
end

-- ---- SEQ -----------------------------------------------------------------
local function drawSeqSlot(scr, eng, ctl)
    local t = ctl.track
    scr:draw_rectangle_filled(0, 0, 319, 239, BG)
    roll(scr, eng.tracks[t], eng.gt)
    scr:draw_line(0, 120, 319, 120, DIM)

    scr:draw_text_fast("SEQ", 8, 126, 16, ORANGE)
    scr:draw_text_fast("SLOT", 52, 130, 12, GREY)
    scr:draw_text_fast(eng.currentSeq .. "/" .. #eng.sequences, 100, 126, 16, WHITE)

    local seq = eng.sequences[eng.currentSeq]
    for k = 1, #eng.tracks do
        local x = 8 + (k - 1) * 78
        local sel = (k == ctl.seqTrack)
        local label = "T" .. k .. ":P" .. seq.slot[k] .. (seq.mute[k] and "m" or "")
        scr:draw_text_fast(label, x, 156, 16, sel and ORANGE or WHITE)
    end

    scr:draw_text_fast("KS1-4 TRK  KS5 SONG  KS6 MUTE", 6, 190, 8, DIM)
    scr:draw_text_fast("enc SLOT  click NEXT SEQ  KS7 MODE", 6, 202, 8, DIM)
    scr:draw_swap()
end

local function drawSeqSong(scr, eng, ctl)
    local t = ctl.track
    scr:draw_rectangle_filled(0, 0, 319, 239, BG)
    roll(scr, eng.tracks[t], eng.gt)
    scr:draw_line(0, 120, 319, 120, DIM)

    scr:draw_text_fast("SEQ", 8, 126, 16, ORANGE)
    scr:draw_text_fast("SONG", 52, 130, 12, GREY)
    scr:draw_text_fast("sync " .. eng.song.syncBars .. " bar", 102, 130, 12, GREY)

    local steps = eng.song.steps
    if #steps == 0 then
        scr:draw_text_fast("(empty)", 8, 156, 16, DIM)
    else
        local s = ""
        for i = 1, #steps do
            if i == ctl.songCur then s = s .. "[" .. steps[i] .. "] " else s = s .. steps[i] .. " " end
        end
        scr:draw_text_fast(s, 8, 156, 16, WHITE)
    end

    scr:draw_text_fast("KS1 ADD  KS2 DEL  KS6 CLEAR", 6, 190, 8, DIM)
    scr:draw_text_fast("enc CURSOR  click JUMP  KS5 SLOT  KS7 MODE", 6, 202, 8, DIM)
    scr:draw_swap()
end

-- ---- entry ----------------------------------------------------------------
function M.draw(scr, eng, ctl)
    if not ctl then return end
    if ctl.frame then ctl.frame() end      -- service auto-reroll (off hot path)
    if ctl.mode == "PLAY" then
        if ctl.setup then drawSetup(scr, eng, ctl) else drawPlay(scr, eng, ctl) end
    elseif ctl.mode == "STEP" then
        drawStep(scr, eng, ctl)
    else
        if ctl.seqPage == "SLOT" then drawSeqSlot(scr, eng, ctl) else drawSeqSong(scr, eng, ctl) end
    end
end

return M
