-- tests/test_no_alloc.lua
-- Locks the "zero allocations per pulse" invariant.
-- If this test fails, someone added a per-pulse allocation in the engine
-- or a track. Revert and find the offending closure / table literal.

local Engine = require("engine")
local Step   = require("step")

local M = {}

local function gc_kb()
    collectgarbage("collect")
    collectgarbage("collect")
    return collectgarbage("count")
end

function M.test_onPulse_does_not_allocate()
    Engine.init({ trackCount = 4, stepsPerTrack = 64 })
    -- seed each track with a firing step so events are produced
    for t = 1, 4 do
        Engine.tracks[t].steps[1] = Step.pack({ pitch=60+t, vel=100, dur=2, gate=1 })
    end
    Engine.onStart()
    -- prime: let any one-time allocations settle
    for _ = 1, 200 do Engine.onPulse() end

    local pre = gc_kb()
    local N = 5000
    for _ = 1, N do Engine.onPulse() end
    local post = gc_kb()

    local delta_bytes = (post - pre) * 1024
    -- Allow a tiny slack for GC noise (sub-allocator rounding). 64 bytes
    -- across 5000 pulses is comfortably below any real per-pulse leak.
    if delta_bytes > 64 then
        error(string.format(
            "engine.onPulse allocated %.1f bytes over %d pulses (%.4f B/pulse) - expected ~0",
            delta_bytes, N, delta_bytes / N))
    end
end

function M.test_onPulse_when_stopped_does_not_allocate()
    Engine.init({ trackCount = 4, stepsPerTrack = 64 })
    -- not started; onPulse should early-return nil with zero work
    local pre = gc_kb()
    for _ = 1, 5000 do Engine.onPulse() end
    local post = gc_kb()
    local delta_bytes = (post - pre) * 1024
    if delta_bytes > 32 then
        error(string.format(
            "stopped engine.onPulse allocated %.1f bytes - should be 0",
            delta_bytes))
    end
end

return M
