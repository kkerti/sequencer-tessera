-- tests/test_controls_random.lua
-- RANDOM hold (keyswitch 7): while M.random is engaged, param-mode presses
-- randomize across all steps 1..lastStep of the selected track instead of
-- switching focus. GATE+shift randomizes dur (from the ladder).

local Engine   = require("engine")
local Controls = require("controls")
local Step     = require("step")
local Track    = require("track")
local M = {}

local function eq(a, b, msg)
    if a ~= b then
        error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2)
    end
end

local function setup()
    Engine.init({ trackCount = 4, stepsPerTrack = 64 })
    Track.setLastStep(Engine.tracks[1], 64)   -- keep the full buffer in play
    Controls.selT, Controls.selS = 1, 1
    Controls.viewport = 1
    Controls.focus = Controls.MODE_NOTE
    Controls.shift = false
    Controls.random = false
end

local function step(i) return Engine.tracks[1].steps[i] end

-- prepopulate the first 64 steps so pitch/vel are all the SAME prior value,
-- so a full-range randomization is detectable as a change.
local function fill(vals)
    local V = vals or { pitch = 60, vel = 100 }
    for i = 1, Engine.tracks[1].lastStep do
        Engine.tracks[1].steps[i] =
            Step.pack({ pitch = V.pitch, vel = V.vel, dur = 6, gate = 3 })
    end
end

-- ---- flag + header ----

function M.test_random_flag_roundtrip()
    setup()
    Controls.setRandom(true)
    eq(Controls.random, true, "setRandom(true) engages")
    Controls.setRandom(true)
    eq(Controls.random, true, "idempotent")
    Controls.setRandom(false)
    eq(Controls.random, false, "setRandom(false) disengages")
end

function M.test_header_shows_rndm_flag()
    setup()
    Controls.setRandom(true)
    local seen = {}
    local scr = { draw_rectangle_filled = function() end,
                  draw_rectangle = function() end,
                  draw_text_fast = function(self, s) seen[#seen + 1] = s end,
                  draw_swap = function() end }
    Controls.dirtyAll()
    Controls.draw(scr)
    local found = false
    for _, s in ipairs(seen) do if s:find("RNDM") then found = true end end
    if not found then error("header should show RNDM flag when random engaged") end
end

-- ---- randomization ----

function M.test_random_notes_fills_all_steps_and_changes_pitch()
    setup()
    fill({ pitch = 60, vel = 100 })
    Controls.setRandom(true)
    Controls.randomizeParam(Controls.MODE_NOTE)
    local changed = 0
    for i = 1, Engine.tracks[1].lastStep do
        local p = Step.pitch(step(i))
        if p ~= 60 then changed = changed + 1 end
    end
    if changed == 0 then
        error("NOTE randomize should change at least one pitch")
    end
end

function M.test_random_respects_laststep_not_full_buffer()
    setup()
    fill({ vel = 100 })
    Engine.tracks[1].lastStep = 8
    Controls.setRandom(true)
    Controls.randomizeParam(Controls.MODE_VEL)
    local changedInRange = 0
    for i = 1, 8 do if Step.vel(step(i)) ~= 100 then changedInRange = changedInRange + 1 end end
    if changedInRange == 0 then
        error("VEL randomize should touch in-range steps")
    end
    for i = 64, 9, -1 do
        if Step.vel(step(i)) ~= 100 then
            error("VEL randomize must not touch steps beyond lastStep")
        end
    end
end

function M.test_random_gate_bounded_by_dur()
    setup()
    for i = 1, Engine.tracks[1].lastStep do
        Engine.tracks[1].steps[i] = Step.pack({ pitch = 60, vel = 100, dur = 12, gate = 3 })
    end
    Controls.setRandom(true)
    Controls.randomizeParam(Controls.MODE_GATE)
    for i = 1, Engine.tracks[1].lastStep do
        local g = Step.gate(step(i))
        if g < 1 or g > 12 then
            error("gate outside 1..dur after randomization: " .. g)
        end
    end
end

function M.test_random_gate_with_shift_randomizes_dur_from_ladder()
    setup()
    for i = 1, Engine.tracks[1].lastStep do
        Engine.tracks[1].steps[i] = Step.pack({ pitch = 60, vel = 100, dur = 6, gate = 3 })
    end
    Controls.setRandom(true)
    Controls.shift = true
    Controls.randomizeParam(Controls.MODE_GATE)
    local ladder = { 3, 6, 12, 18, 24, 30 }
    local touched = false
    for i = 1, Engine.tracks[1].lastStep do
        local d = Step.dur(step(i))
        local onLadder = false
        for _, d2 in ipairs(ladder) do if d == d2 then onLadder = true end end
        if not onLadder then
            error("dur randomized off the musical ladder: " .. d)
        end
        if d ~= 6 then touched = true end
    end
    if not touched then error("dur randomize should vary at least one step") end
end

function M.test_random_mute_toggles_in_range()
    setup()
    for i = 1, Engine.tracks[1].lastStep do
        Engine.tracks[1].steps[i] = Step.pack({ pitch = 60, vel = 100, dur = 6, gate = 3 })
    end
    Controls.setRandom(true)
    Controls.randomizeParam(Controls.MODE_MUTE)
    for i = 1, Engine.tracks[1].lastStep do
        if Step.muted(step(i)) == nil then error("mute should be 0/1") end
    end
end

return M

-- vim: set ts=4 sts=4 sw=4 et: