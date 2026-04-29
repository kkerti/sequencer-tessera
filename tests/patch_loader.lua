-- tests/patch_loader.lua
-- Behavioural tests for sequencer/patch_loader.lua.
-- Run with: lua tests/patch_loader.lua

local PatchLoader = require("sequencer/patch_loader")
local Engine      = require("sequencer/engine")
local Track       = require("sequencer/track")
local Pattern     = require("sequencer/pattern")
local Step        = require("sequencer/step")

-- ---------------------------------------------------------------------------
-- Minimal descriptor builds the right shape
-- ---------------------------------------------------------------------------

do
    local descriptor = {
        bpm = 120, ppb = 4,
        tracks = {
            { channel = 1, direction = "forward", clockDiv = 1, clockMult = 1,
              patterns = {
                { name = "A", steps = {
                    {60, 100, 4, 2},
                    {62, 100, 4, 2},
                }},
              },
            },
        },
    }

    local engine = PatchLoader.build(descriptor)
    assert(engine.bpm == 120, "bpm")
    assert(engine.pulsesPerBeat == 4, "pulsesPerBeat")
    assert(engine.trackCount == 1, "trackCount")

    local track = Engine.getTrack(engine, 1)
    assert(Track.getMidiChannel(track) == 1, "channel")
    assert(Track.getDirection(track) == "forward", "direction")
    assert(Track.getClockDiv(track) == 1, "clockDiv")
    assert(Track.getPatternCount(track) == 1, "patternCount")
    assert(Track.getStepCount(track) == 2, "stepCount")

    local pattern = Track.getPattern(track, 1)
    assert(Pattern.getName(pattern) == "A", "pattern name")

    local step1 = Track.getStep(track, 1)
    assert(Step.getPitch(step1)    == 60,  "step 1 pitch")
    assert(Step.getVelocity(step1) == 100, "step 1 velocity")
    assert(Step.getDuration(step1) == 4,   "step 1 duration")
    assert(Step.getGate(step1)     == 2,   "step 1 gate")

    local step2 = Track.getStep(track, 2)
    assert(Step.getPitch(step2) == 62, "step 2 pitch")
end

-- ---------------------------------------------------------------------------
-- Optional ratch + probability flags propagate
-- ---------------------------------------------------------------------------

do
    local descriptor = {
        bpm = 120, ppb = 4,
        tracks = {
            { channel = 2, direction = "forward", clockDiv = 1, clockMult = 1,
              patterns = {
                { name = "R", steps = {
                    {60, 100, 4, 1, true},        -- ratchet, no prob
                    {62, 100, 4, 2, false, 50},   -- explicit ratch=false, prob 50
                }},
              },
            },
        },
    }
    local engine = PatchLoader.build(descriptor)
    local track  = Engine.getTrack(engine, 1)
    local s1     = Track.getStep(track, 1)
    local s2     = Track.getStep(track, 2)

    assert(Step.getRatch(s1) == true,  "step 1 ratch should be true")
    assert(Step.getRatch(s2) == false, "step 2 ratch should be false")
    assert(Step.getProbability(s2) == 50, "step 2 probability should be 50")
end

-- ---------------------------------------------------------------------------
-- Loop points apply against final flat indices
-- ---------------------------------------------------------------------------

do
    local descriptor = {
        bpm = 120, ppb = 4,
        tracks = {
            { channel = 1, direction = "forward", clockDiv = 1, clockMult = 1,
              loopStart = 5, loopEnd = 8,
              patterns = {
                { name = "A", steps = {
                    {60,100,4,2},{60,100,4,2},{60,100,4,2},{60,100,4,2},
                }},
                { name = "B", steps = {
                    {62,100,4,2},{62,100,4,2},{62,100,4,2},{62,100,4,2},
                }},
              },
            },
        },
    }
    local engine = PatchLoader.build(descriptor)
    local track  = Engine.getTrack(engine, 1)

    assert(Track.getStepCount(track) == 8, "stepCount across both patterns")
    assert(Track.getLoopStart(track) == 5, "loopStart=5 (pattern 2 start)")
    assert(Track.getLoopEnd(track)   == 8, "loopEnd=8 (pattern 2 end)")
end

-- ---------------------------------------------------------------------------
-- Multi-track descriptor builds correct per-track config
-- ---------------------------------------------------------------------------

do
    local descriptor = {
        bpm = 100, ppb = 4,
        tracks = {
            { channel = 1, direction = "forward",  clockDiv = 1, clockMult = 1,
              patterns = { { name = "A", steps = { {60,100,4,2} } } } },
            { channel = 3, direction = "pingpong", clockDiv = 2, clockMult = 1,
              patterns = { { name = "B", steps = { {64,100,4,2} } } } },
            { channel = 10, direction = "reverse", clockDiv = 1, clockMult = 2,
              patterns = { { name = "C", steps = { {36,110,2,1} } } } },
        },
    }
    local engine = PatchLoader.build(descriptor)
    assert(engine.trackCount == 3)

    local t1, t2, t3 = Engine.getTrack(engine, 1), Engine.getTrack(engine, 2), Engine.getTrack(engine, 3)
    assert(Track.getMidiChannel(t1) == 1)
    assert(Track.getMidiChannel(t2) == 3 and Track.getDirection(t2) == "pingpong" and Track.getClockDiv(t2) == 2)
    assert(Track.getMidiChannel(t3) == 10 and Track.getDirection(t3) == "reverse" and Track.getClockMult(t3) == 2)
end

-- ---------------------------------------------------------------------------
-- Loads existing patches from disk via PatchLoader.load
-- ---------------------------------------------------------------------------

do
    local engine = PatchLoader.load("patches/dark_groove")
    assert(engine.trackCount == 4, "dark_groove should have 4 tracks")
    assert(engine.bpm == 118)
    -- Track 1: loop 5..12 across patterns A(4) + B(8)
    local t1 = Engine.getTrack(engine, 1)
    assert(Track.getStepCount(t1) == 12, "track 1 should have 12 steps")
    assert(Track.getLoopStart(t1) == 5)
    assert(Track.getLoopEnd(t1)   == 12)
    -- Track 1 step 7 is the ratchet step from the descriptor: {48,75,2,1,true}
    local s7 = Track.getStep(t1, 7)  -- pattern A is steps 1..4, B starts at 5; step 7 = B[3]?
    -- Better: index from pattern B: dark_groove pattern B has the ratchet at index 7 of B (steps 5-12 flat),
    -- so flat index = 4 + 7 = 11.
    local s11 = Track.getStep(t1, 11)
    assert(Step.getRatch(s11) == true, "dark_groove flat step 11 should be ratchet=true")
end

do
    local engine = PatchLoader.load("patches/four_on_floor")
    assert(engine.trackCount == 1)
    local t = Engine.getTrack(engine, 1)
    assert(Track.getStepCount(t) == 4)
    assert(Track.getMidiChannel(t) == 10)
end

-- ---------------------------------------------------------------------------
-- Input guards
-- ---------------------------------------------------------------------------

do
    local ok = pcall(PatchLoader.build, nil)
    assert(not ok, "nil descriptor should error")

    local ok2 = pcall(PatchLoader.build, { ppb = 4, tracks = { {} } })
    assert(not ok2, "missing bpm should error")

    local ok3 = pcall(PatchLoader.build, { bpm = 120, ppb = 4, tracks = {} })
    assert(not ok3, "empty tracks should error")
end

print("patch_loader: all tests passed")
