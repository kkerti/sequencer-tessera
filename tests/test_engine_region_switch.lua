-- tests/test_engine_region_switch.lua
-- Engine-level region coordination:
--   - all tracks must finish current region before activeRegion updates
--   - tracks at different div finish at different pulse counts;
--     activeRegion only updates after all have flipped

local Engine = require("engine")
local Track  = require("track")
local Step   = require("step")
local M = {}

local function eq(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end end

local function seedAll(tr)
    for i = 1, 64 do
        tr.steps[i] = Step.pack({ pitch=i % 128, vel=100, dur=1, gate=1 })
    end
end

function M.test_global_flip_completes_after_all_tracks()
    Engine.init({ trackCount = 4, stepsPerTrack = 64 })
    for t = 1, 4 do seedAll(Engine.tracks[t]) end
    Engine.onStart()
    Engine.setQueuedRegion(2)
    eq(Engine.activeRegion, 1)
    eq(Engine.queuedRegion, 2)

    -- 16 pulses: each track plays steps 1..16 of region 1, then on pulse
    -- 17 they all jump to step 17 (region 2's lo).
    for _ = 1, 16 do Engine.onPulse() end
    -- After 16 pulses every track is at pos=16 (still in region 1 — boundary
    -- is detected on the next advance).
    for t = 1, 4 do eq(Engine.tracks[t].pos, 16, "track " .. t .. " pos") end
    eq(Engine.activeRegion, 1, "still region 1")
    eq(Engine.queuedRegion, 2)

    Engine.onPulse()  -- pulse 17: each track flips into region 2
    for t = 1, 4 do
        eq(Engine.tracks[t].pos, 17, "track " .. t .. " jumped to 17")
        eq(Engine.tracks[t].curRegion, 2)
    end
    eq(Engine.activeRegion, 2, "engine flipped activeRegion")
    eq(Engine.queuedRegion, 0, "queue cleared")
end

function M.test_div_2_track_holds_flip()
    -- Same intent as before, now achieved via per-step `dur=2` on track 2:
    -- each step occupies 2 pulses, so track 2 advances at half the rate
    -- of track 1 (which uses dur=1 from seedAll).
    Engine.init({ trackCount = 2, stepsPerTrack = 64 })
    for t = 1, 2 do seedAll(Engine.tracks[t]) end
    -- override track 2 with dur=2 per step
    for i = 1, 64 do
        Engine.tracks[2].steps[i] = Step.pack({ pitch=i % 128, vel=100, dur=2, gate=1 })
    end
    Engine.onStart()
    Engine.setQueuedRegion(3)

    -- 16 pulses: track 1 plays all of region 1; track 2 plays 8 steps
    -- (each step occupies 2 pulses).
    for _ = 1, 16 do Engine.onPulse() end
    eq(Engine.tracks[1].pos, 16)
    eq(Engine.tracks[2].pos, 8)
    eq(Engine.activeRegion, 1, "activeRegion can't flip yet, track 2 mid-region")

    -- pulse 17: track 1 flips (boundary), track 2 still mid-region.
    Engine.onPulse()
    eq(Engine.tracks[1].pos, 33, "track 1 in region 3")
    eq(Engine.tracks[1].curRegion, 3)
    eq(Engine.tracks[1].regionDone, true)
    eq(Engine.tracks[2].curRegion, 1, "track 2 still in region 1")
    eq(Engine.activeRegion, 1)
    eq(Engine.queuedRegion, 3)

    -- track 2 needs to advance 8 more steps to reach pos 16. With dur=2
    -- that's 16 more pulses; we already did pulse 17. Need 15 more to
    -- bring track 2 to step 16.
    for _ = 1, 15 do Engine.onPulse() end
    eq(Engine.tracks[2].pos, 16)
    eq(Engine.activeRegion, 1)

    -- next pulse: track 2 boundary -> flip into region 3.
    Engine.onPulse()
    eq(Engine.tracks[2].pos, 33)
    eq(Engine.tracks[2].curRegion, 3)
    eq(Engine.activeRegion, 3, "now flipped because both tracks done")
    eq(Engine.queuedRegion, 0)
end

function M.test_setQueuedRegion_clears_on_self()
    Engine.init({ trackCount = 1 })
    Engine.activeRegion = 2
    Engine.setQueuedRegion(2)
    eq(Engine.queuedRegion, 0, "queueing the active region clears the queue")
end

function M.test_setQueuedRegion_clamps_invalid()
    Engine.init({})
    Engine.setQueuedRegion(99)
    eq(Engine.queuedRegion, 0)
    Engine.setQueuedRegion(-1)
    eq(Engine.queuedRegion, 0)
    Engine.setQueuedRegion(nil)
    eq(Engine.queuedRegion, 0)
end

return M
