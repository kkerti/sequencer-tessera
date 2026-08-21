-- tests/test_track_laststep.lua
local Track = require("track")
local Step  = require("step")
local M = {}

local function eq(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end end

function M.test_default_last_step_is_16()
    local tr = Track.new()
    eq(tr.lastStep, 16)
end

function M.test_track_wraps_at_last_step()
    local tr = Track.new()
    Track.setLastStep(tr, 4)
    -- Distinct pitches so we can spot the wrap.
    for i = 1, tr.cap do
        tr.steps[i] = Step.pack({ pitch=59 + i, vel=100, dur=1, gate=1 })
    end
    Track.reset(tr)

    local seen = {}
    for _ = 1, 10 do
        local out = {}
        Track.advance(tr, out)
        for _, e in ipairs(out) do
            if e.type == Track.EV_ON then seen[#seen+1] = e.pitch end
        end
    end
    -- With dur=1 and lastStep=4, we expect: 60,61,62,63,60,61,62,63,60,61
    eq(seen[1], 60)
    eq(seen[2], 61)
    eq(seen[3], 62)
    eq(seen[4], 63)
    eq(seen[5], 60, "wrapped back to step 1")
    eq(seen[6], 61)
end

function M.test_set_last_step_clamps()
    local tr = Track.new()
    Track.setLastStep(tr, 0);   eq(tr.lastStep, 1)
    Track.setLastStep(tr, 999); eq(tr.lastStep, tr.cap)
    Track.setLastStep(tr, 32);  eq(tr.lastStep, 32)
end

function M.test_polyrhythm_two_tracks_drift()
    -- Track A wraps at 4, track B wraps at 3, both dur=1.
    -- After 12 pulses both must be aligned again (LCM=12).
    local a = Track.new(); Track.setLastStep(a, 4)
    local b = Track.new(); Track.setLastStep(b, 3)
    for i = 1, a.cap do
        a.steps[i] = Step.pack({ pitch=60+i-1, vel=100, dur=1, gate=1 })
        b.steps[i] = Step.pack({ pitch=70+i-1, vel=100, dur=1, gate=1 })
    end
    Track.reset(a); Track.reset(b)

    for _ = 1, 12 do
        local oa, ob = {}, {}
        Track.advance(a, oa); Track.advance(b, ob)
    end
    -- Next pulse, both should be at their step 1.
    eq(a.pos % a.lastStep + 1, 1)
    eq(b.pos % b.lastStep + 1, 1)
end

return M
