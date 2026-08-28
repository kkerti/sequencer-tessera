-- leds.lua — dedicated LED render pass (UI bundle).
--
-- Runs OFF the pulse hot path (driven by the screen draw/frame event). Every
-- LED is derived from CTL + engine state — no independent LED state. Blink /
-- breathe feedback (nap armed + napping, commit-pending) is computed here from
-- a frame tick, NOT from firmware toggle/momentary element behaviour (every
-- element stays in its plainest bst()/epva() mode).
--
-- Grid LED API (globals in the module's event scripts, like gms):
--   led_color(element, led, r, g, b, brightness)   -- set a LED's colour
-- LED index 2 is the primary LED on VSN1 keyswitches/buttons (the value seq-1
-- profiles light in ../sequencer-1/configs/*.lua). On a plain-Lua host (tests)
-- `led_color` is absent, so M.update() is a no-op there.
--
-- M.compute(eng, ctl, frame) -> lit[0..12] = palette index (0..9, testable)
-- M.update(eng, ctl)           -> calls led_color for each element
--
-- Element indices: 0..7 keyswitches, 8 encoder, 9..12 small buttons.
-- Palette is ONE flat array (3 numbers per colour); compute() returns indices,
-- update() dereferences them — no per-frame tables, no named colour tables.

local M = {}

local frame = 0

-- flat palette: 0 off, 1 dim, 2 white, 3 orange, 4 orange-dim, 5 green,
--               6 red, 7 red-dim, 8 cyan, 9 purple
local C = { 0,0,0, 36,36,40, 235,235,235, 249,150,0, 120,70,0,
            90,220,120, 220,60,60, 120,40,40, 0,200,220, 160,90,220 }

local OFF, DIM, WHITE, ORANGE, ORANGE_DIM, GREEN, RED, RED_DIM, CYAN, PURPLE =
      0, 1, 2, 3, 4, 5, 6, 7, 8, 9

local function blink(f) return (f % 40) < 20 end   -- ~1 Hz at 20 fps

local function napLed(tr, b)
    if not tr.nap.armed then return DIM end
    if tr.nap.muted then return RED end
    return b and RED or RED_DIM
end

local function commitLed(tr, b)
    if not tr.dirty then return DIM end
    return b and ORANGE or ORANGE_DIM
end

function M.compute(eng, ctl, f)
    local lit = {}
    for el = 0, 12 do lit[el] = OFF end
    if not eng or not ctl then return lit end

    local b = blink(f)
    local mode = ctl.mode
    local tr = eng.tracks[ctl.track]

    if mode == "PLAY" then
        local PLAY_KEY = { 3, 2, 1, 6, 7 }
        for k = 0, 4 do
            lit[k] = (not ctl.setup and ctl.sel == PLAY_KEY[k + 1]) and WHITE or DIM
        end
        lit[5] = tr.auto.armed and GREEN or DIM
        lit[6] = DIM
        lit[7] = ORANGE
        lit[9] = DIM
        lit[10] = ctl.setup and WHITE or DIM
        lit[11] = napLed(tr, b)
        lit[12] = commitLed(tr, b)

    elseif mode == "STEP" then
        for k = 0, 6 do lit[k] = DIM end
        lit[7] = CYAN
        lit[9] = DIM
        lit[10] = DIM
        lit[11] = napLed(tr, b)
        lit[12] = commitLed(tr, b)

    else -- SEQ
        local seq = eng.sequences[eng.currentSeq]
        if ctl.seqPage == "SLOT" then
            for k = 0, 3 do lit[k] = (ctl.seqTrack == k + 1) and WHITE or DIM end
            lit[4] = OFF
            lit[5] = seq.mute[ctl.seqTrack] and RED or DIM
            lit[6] = OFF
            lit[7] = PURPLE
            lit[10] = WHITE
        else
            lit[0] = DIM
            lit[1] = DIM
            lit[2] = DIM
            for k = 3, 6 do lit[k] = OFF end
            lit[7] = PURPLE
            lit[10] = DIM
        end
        lit[9] = DIM
        lit[11] = napLed(tr, b)
        lit[12] = DIM
    end

    return lit
end

function M.update(eng, ctl)
    frame = frame + 1
    if not led_color then return end
    local lit = M.compute(eng, ctl, frame)
    for el = 0, 12 do
        local i = (lit[el] or 0) * 3
        led_color(el, 2, C[i + 1], C[i + 2], C[i + 3], 0)
    end
end

return M
