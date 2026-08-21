-- tests/engine.lua
-- Behavioural tests for sequencer/engine.lua.
-- The engine is now a pure data/cursor layer. It owns tracks, patterns,
-- steps, loop points, direction modes, and scene chains.
-- MIDI emission, active note tracking, and BPM are player concerns.
-- Run with: lua tests/engine.lua

require("authoring")
local Engine = require("sequencer").Engine
local Track  = require("sequencer").Track
local Step   = require("sequencer").Step
local Scene  = require("sequencer").Scene

-- ── Construction ─────────────────────────────────────────────────────────────

local e = Engine.new(120, 4, 1, 4)
assert(e.bpm            == 120)
assert(e.trackCount     == 1)
assert(e.pulsesPerBeat  == 4)
assert(e.pulseIntervalMs == 125)
assert(e.sceneChain     == nil)

-- ── Engine.bpmToMs ────────────────────────────────────────────────────────────

assert(Engine.bpmToMs(120, 4) == 125)
assert(Engine.bpmToMs(60,  4) == 250)
assert(Engine.bpmToMs(120, 8) == 62.5)

-- ── Engine.getTrack ───────────────────────────────────────────────────────────

local t = Engine.getTrack(e, 1)
assert(type(t) == "table" and t.patterns ~= nil, "getTrack should return a track table")

-- Out-of-range access raises an error.
local ok = pcall(Engine.getTrack, e, 0)
assert(not ok, "getTrack with index 0 should error")
local ok2 = pcall(Engine.getTrack, e, 2)
assert(not ok2, "getTrack with index > trackCount should error")

-- ── Engine.advanceTrack / Engine.sampleTrack — basic playback ────────────────

local eAdv = Engine.new(120, 4, 1, 4)
local tAdv = Engine.getTrack(eAdv, 1)
Track.setStep(tAdv, 1, Step.new(60, 100, 4, 2))
Track.setStep(tAdv, 2, Step.new(64, 100, 4, 2))
Track.setStep(tAdv, 3, Step.new(67, 100, 4, 2))
Track.setStep(tAdv, 4, Step.new(72, 100, 4, 2))

-- Pulse 0 of step 1: gate HIGH at pitch 60, velocity 100.
local cvA, cvB, gate = Engine.sampleTrack(eAdv, 1)
assert(cvA == 60 and cvB == 100 and gate == true,
    "pulse 0 of step 1 should sample (60, 100, true)")
Engine.advanceTrack(eAdv, 1)

-- Pulse 1: still HIGH (gate=2 → HIGH on pulses 0,1).
_, _, gate = Engine.sampleTrack(eAdv, 1)
assert(gate == true, "pulse 1 should still be gate HIGH")
Engine.advanceTrack(eAdv, 1)

-- Pulse 2: gate LOW (gate boundary).
_, _, gate = Engine.sampleTrack(eAdv, 1)
assert(gate == false, "pulse 2 should be gate LOW")
Engine.advanceTrack(eAdv, 1)

-- Pulse 3: still LOW.
_, _, gate = Engine.sampleTrack(eAdv, 1)
assert(gate == false, "pulse 3 should be gate LOW")
Engine.advanceTrack(eAdv, 1)

-- Pulse 0 of step 2: gate HIGH at pitch 64.
cvA, _, gate = Engine.sampleTrack(eAdv, 1)
assert(cvA == 64 and gate == true, "step 2 pulse 0 should sample (64, _, true)")

-- ── Engine.advanceTrack — direction modes ─────────────────────────────────────

-- Reverse: starts at step 1, then jumps to last step.
local eRev = Engine.new(120, 4, 1, 4)
local tRev = Engine.getTrack(eRev, 1)
Track.setStep(tRev, 1, Step.new(60, 100, 1, 1))
Track.setStep(tRev, 2, Step.new(62, 100, 1, 1))
Track.setStep(tRev, 3, Step.new(64, 100, 1, 1))
Track.setStep(tRev, 4, Step.new(65, 100, 1, 1))
Track.setDirection(tRev, "reverse")

cvA, _, gate = Engine.sampleTrack(eRev, 1)
assert(cvA == 60 and gate == true, "reverse: step 1 sample is pitch 60 HIGH")
Engine.advanceTrack(eRev, 1) -- after 1 pulse, dur=1 elapsed → cursor moves
cvA, _, gate = Engine.sampleTrack(eRev, 1)
assert(cvA == 65 and gate == true,
    "reverse: after step 1 should jump to step 4 (pitch 65)")

-- ── Engine.reset ─────────────────────────────────────────────────────────────

-- Reset moves all cursors back to step 1.
local eReset = Engine.new(120, 4, 1, 4)
local tReset = Engine.getTrack(eReset, 1)
Track.setStep(tReset, 1, Step.new(60, 100, 1, 1))
Track.setStep(tReset, 2, Step.new(62, 100, 1, 1))
Track.setStep(tReset, 3, Step.new(64, 100, 1, 1))
Track.setStep(tReset, 4, Step.new(65, 100, 1, 1))

Engine.advanceTrack(eReset, 1) -- cursor 1 → 2
Engine.advanceTrack(eReset, 1) -- cursor 2 → 3
assert(tReset.cursor == 3, "cursor should be on step 3 before reset")

Engine.reset(eReset)
assert(tReset.cursor == 1 and tReset.pulseCounter == 0,
    "reset should return cursor to step 1")

-- After reset, sample should reflect step 1 again.
cvA, _, gate = Engine.sampleTrack(eReset, 1)
assert(cvA == 60 and gate == true, "after reset, sample should be step 1 (pitch 60 HIGH)")

-- ── Scene chain integration ───────────────────────────────────────────────────

-- Scene chain changes loop points after the scene's beats elapse.
-- onPulse drives the scene chain tick (called by the player's tick loop).
do
    local es = Engine.new(120, 4, 1, 0)
    local trk = Engine.getTrack(es, 1)
    Track.addPattern(trk, 4)  -- steps 1-4
    Track.addPattern(trk, 4)  -- steps 5-8
    for i = 1, 8 do
        Track.setStep(trk, i, Step.new(60 + i - 1, 100, 1, 1))
    end

    local sceneA = Scene.new(1, 2, "A")
    Scene.setTrackLoop(sceneA, 1, 1, 4)
    local sceneB = Scene.new(1, 2, "B")
    Scene.setTrackLoop(sceneB, 1, 5, 8)

    local chain = Scene.newChain()
    Scene.chainAppend(chain, sceneA)
    Scene.chainAppend(chain, sceneB)

    Engine.setSceneChain(es, chain)
    Engine.activateSceneChain(es)

    assert(Track.getLoopStart(trk) == 1, "scene A should set loopStart=1")
    assert(Track.getLoopEnd(trk)   == 4, "scene A should set loopEnd=4")

    -- Simulate 2 beats (8 pulses at pulsesPerBeat=4).
    for pulse = 1, 8 do
        Engine.onPulse(es, pulse)
    end

    assert(Track.getLoopStart(trk) == 5, "after 2 beats, scene B loopStart=5")
    assert(Track.getLoopEnd(trk)   == 8, "after 2 beats, scene B loopEnd=8")

    -- 2 more beats → wraps back to scene A.
    for pulse = 9, 16 do
        Engine.onPulse(es, pulse)
    end

    assert(Track.getLoopStart(trk) == 1, "wrapped scene A loopStart=1")
    assert(Track.getLoopEnd(trk)   == 4, "wrapped scene A loopEnd=4")
end

-- Engine.reset with active scene chain resets to scene 1.
do
    local es = Engine.new(120, 4, 1, 0)
    local trk = Engine.getTrack(es, 1)
    Track.addPattern(trk, 4)
    Track.addPattern(trk, 4)
    for i = 1, 8 do
        Track.setStep(trk, i, Step.new(60, 100, 1, 1))
    end

    local sceneA = Scene.new(1, 2, "A")
    Scene.setTrackLoop(sceneA, 1, 1, 4)
    local sceneB = Scene.new(1, 2, "B")
    Scene.setTrackLoop(sceneB, 1, 5, 8)

    local chain = Scene.newChain()
    Scene.chainAppend(chain, sceneA)
    Scene.chainAppend(chain, sceneB)
    Engine.setSceneChain(es, chain)
    Engine.activateSceneChain(es)

    for pulse = 1, 8 do Engine.onPulse(es, pulse) end
    assert(chain.cursor == 2, "should be on scene B after 2 beats")

    Engine.reset(es)
    assert(chain.cursor == 1, "reset should return to scene A")
    assert(Track.getLoopStart(trk) == 1, "reset should re-apply scene A loop points")
end

print("engine: all tests passed")
