-- leds.lua — dedicated LED render pass (UI bundle).
--
-- Runs OFF the pulse hot path (driven by the screen draw/frame event). Every
-- LED is derived from CTL + engine state — there is no independent LED state.
-- Blink / breathe feedback (nap armed + napping, commit-pending) is computed
-- here from a frame tick, NOT from firmware toggle/momentary element behaviour
-- (we deliberately keep every element in its plainest bst()/epva() mode).
--
-- Grid LED API (globals available in the module's event scripts, like gms):
--   led_color(element, led, r, g, b, brightness)   -- set a LED's colour
--   led_value(element, led, brightness)            -- brightness ceiling
-- LED index 2 is the primary LED on VSN1 keyswitches/buttons — the value the
-- proven seq-1 profiles (../sequencer-1/configs/*.lua) light. On a plain-Lua
-- host (tests) `led_color` is absent, so M.update() is a no-op there.
--
-- M.compute(eng, ctl, frame) -> lit[0..12] = {r,g,b}   (pure, testable)
-- M.update(eng, ctl)           -> calls led_color for each element
--
-- Element indices: 0..7 keyswitches, 8 encoder, 9..12 small buttons.

local M = {}

local frame = 0

local OFF    = { 0, 0, 0 }
local DIM    = { 36, 36, 40 }
local WHITE  = { 235, 235, 235 }
local ORANGE = { 249, 150, 0 }
local ORANGE_DIM = { 120, 70, 0 }
local GREEN  = { 90, 220, 120 }
local RED    = { 220, 60, 60 }
local RED_DIM    = { 120, 40, 40 }
local CYAN   = { 0, 200, 220 }
local PURPLE = { 160, 90, 220 }

local function blink(f) return (f % 40) < 20 end   -- ~1 Hz at 20 fps

-- NAP small-button LED: red blink while armed+awake, steady red while napping.
local function napLed(tr, b)
    if not tr.nap.armed then return DIM end
    if tr.nap.muted then return RED end
    return b and RED or RED_DIM
end

-- COMMIT small-button LED: orange blink while staged edits are pending.
local function commitLed(tr, b)
    if not tr.dirty then return DIM end
    return b and ORANGE or ORANGE_DIM
end

-- Pure LED decision table. Returns lit[0..12] (always all 13 entries).
function M.compute(eng, ctl, f)
    local lit = {}
    for el = 0, 12 do lit[el] = OFF end
    if not eng or not ctl then return lit end

    local b = blink(f)
    local mode = ctl.mode
    local tr = eng.tracks[ctl.track]

    if mode == "PLAY" then
        local PLAY_KEY = { 3, 2, 1, 6, 7 }          -- KS0..KS4 -> param index
        for k = 0, 4 do
            lit[k] = (not ctl.setup and ctl.sel == PLAY_KEY[k + 1]) and WHITE or DIM
        end
        lit[5] = tr.auto.armed and GREEN or DIM      -- KS5 = AUTO-REROLL
        lit[6] = DIM                                 -- KS6 = TRACK
        lit[7] = ORANGE                              -- KS7 = MODE (PLAY)
        lit[9] = DIM                                 -- BACK
        lit[10] = ctl.setup and WHITE or DIM         -- ENTER (SETUP active)
        lit[11] = napLed(tr, b)
        lit[12] = commitLed(tr, b)

    elseif mode == "STEP" then
        lit[0] = DIM                                 -- add
        lit[1] = DIM                                 -- delete
        lit[2] = DIM                                 -- octave down
        lit[3] = DIM                                 -- octave up
        lit[4] = DIM                                 -- field -
        lit[5] = DIM                                 -- field +
        lit[6] = DIM                                 -- track
        lit[7] = CYAN                                -- MODE (STEP)
        lit[9] = DIM
        lit[10] = DIM
        lit[11] = napLed(tr, b)
        lit[12] = commitLed(tr, b)

    else -- SEQ
        local seq = eng.sequences[eng.currentSeq]
        if ctl.seqPage == "SLOT" then
            for k = 0, 3 do
                lit[k] = (ctl.seqTrack == k + 1) and WHITE or DIM
            end
            lit[4] = OFF
            lit[5] = seq.mute[ctl.seqTrack] and RED or DIM   -- mute toggle
            lit[6] = OFF
            lit[7] = PURPLE                         -- MODE (SEQ)
            lit[10] = WHITE                         -- ENTER (-> SONG)
        else -- SONG
            lit[0] = DIM                            -- append
            lit[1] = DIM                            -- remove
            lit[2] = DIM                            -- clear
            lit[3] = OFF
            lit[4] = OFF
            lit[5] = OFF
            lit[6] = OFF
            lit[7] = PURPLE
            lit[10] = DIM
        end
        lit[9] = DIM
        lit[11] = napLed(tr, b)
        lit[12] = DIM                               -- commit not meaningful in SEQ
    end

    return lit
end

-- Render pass: push every element's LED from the computed table. No-op when
-- the Grid global is absent (tests / headless).
function M.update(eng, ctl)
    frame = frame + 1
    if not led_color then return end
    local lit = M.compute(eng, ctl, frame)
    for el = 0, 12 do
        local c = lit[el] or OFF
        led_color(el, 2, c[1], c[2], c[3], 0)
    end
end

return M
