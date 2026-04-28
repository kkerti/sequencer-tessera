-- tests/engine.lua
-- Behavioural tests for sequencer/engine.lua.
-- The engine is now a pure data/cursor layer. It owns tracks, patterns,
-- steps, loop points, direction modes, and scene chains.
-- MIDI emission, active note tracking, and BPM are player concerns.
-- Run with: lua tests/engine.lua

local Engine = require("sequencer/engine")
local Track  = require("sequencer/track")
local Step   = require("sequencer/step")
local Scene  = require("sequencer/scene")

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

-- ── Engine.advanceTrack — basic cursor advancement ───────────────────────────

local eAdv = Engine.new(120, 4, 1, 4)
local tAdv = Engine.getTrack(eAdv, 1)
Track.setStep(tAdv, 1, Step.new(60, 100, 4, 2))
Track.setStep(tAdv, 2, Step.new(64, 100, 4, 2))
Track.setStep(tAdv, 3, Step.new(67, 100, 4, 2))
Track.setStep(tAdv, 4, Step.new(72, 100, 4, 2))

-- Pulse 0 of step 1 → NOTE_ON pitch 60
local step, event = Engine.advanceTrack(eAdv, 1)
assert(event == "NOTE_ON",          "pulse 0 should be NOTE_ON")
assert(Step.getPitch(step) == 60,   "step pitch should be 60")

-- Pulse 1 → nil
step, event = Engine.advanceTrack(eAdv, 1)
assert(event == nil, "pulse 1 should produce no event")

-- Pulse 2 (gate boundary) → NOTE_OFF
step, event = Engine.advanceTrack(eAdv, 1)
assert(event == "NOTE_OFF",         "pulse 2 (gate) should be NOTE_OFF")
assert(Step.getPitch(step) == 60,   "step pitch for NOTE_OFF should still be 60")

-- Pulse 3 → nil, then step 2 starts
Engine.advanceTrack(eAdv, 1)
step, event = Engine.advanceTrack(eAdv, 1) -- pulse 0 of step 2
assert(event == "NOTE_ON" and Step.getPitch(step) == 64,
    "step 2 pulse 0 should be NOTE_ON pitch 64")

-- ── Engine.advanceTrack — direction modes ─────────────────────────────────────

-- Reverse: starts at step 1, then jumps to last step.
local eRev = Engine.new(120, 4, 1, 4)
local tRev = Engine.getTrack(eRev, 1)
Track.setStep(tRev, 1, Step.new(60, 100, 1, 1))
Track.setStep(tRev, 2, Step.new(62, 100, 1, 1))
Track.setStep(tRev, 3, Step.new(64, 100, 1, 1))
Track.setStep(tRev, 4, Step.new(65, 100, 1, 1))
Track.setDirection(tRev, "reverse")

local _, ev1 = Engine.advanceTrack(eRev, 1)
assert(ev1 == "NOTE_ON", "reverse: step 1 NOTE_ON")
local s2, ev2 = Engine.advanceTrack(eRev, 1)
assert(ev2 == "NOTE_ON" and Step.getPitch(s2) == 65,
    "reverse: after step 1 should jump to step 4 (pitch 65)")

-- ── Engine.reset ─────────────────────────────────────────────────────────────

-- Reset moves all cursors back to step 1.
local eReset = Engine.new(120, 4, 1, 4)
local tReset = Engine.getTrack(eReset, 1)
Track.setStep(tReset, 1, Step.new(60, 100, 1, 1))
Track.setStep(tReset, 2, Step.new(62, 100, 1, 1))
Track.setStep(tReset, 3, Step.new(64, 100, 1, 1))
Track.setStep(tReset, 4, Step.new(65, 100, 1, 1))

Engine.advanceTrack(eReset, 1) -- step 1 → step 2
Engine.advanceTrack(eReset, 1) -- step 2 → step 3
assert(tReset.cursor == 3, "cursor should be on step 3 before reset")

Engine.reset(eReset)
assert(tReset.cursor == 1 and tReset.pulseCounter == 0,
    "reset should return cursor to step 1")

-- After reset, advanceTrack should replay from step 1.
local _, firstEv = Engine.advanceTrack(eReset, 1)
assert(firstEv == "NOTE_ON", "after reset, first advance should be NOTE_ON")

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
