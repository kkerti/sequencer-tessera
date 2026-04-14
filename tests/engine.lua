-- tests/engine.lua
-- Behavioural tests for sequencer/engine.lua.
-- Run with: lua tests/engine.lua

local Engine = require("sequencer/engine")
local Track  = require("sequencer/track")
local Step   = require("sequencer/step")

-- BPM to pulse interval conversion
assert(Engine.bpmToMs(120, 4) == 125)
assert(Engine.bpmToMs(60,  4) == 250)
assert(Engine.bpmToMs(120, 8) == 62.5)

-- Engine construction
local e = Engine.new(120, 4, 1, 4)
assert(e.bpm            == 120)
assert(e.trackCount     == 1)
assert(e.pulseIntervalMs == 125)

-- Load a C major arpeggio into track 1
local t = Engine.getTrack(e, 1)
Track.setStep(t, 1, Step.new(60, 100, 4, 2))
Track.setStep(t, 2, Step.new(64, 100, 4, 2))
Track.setStep(t, 3, Step.new(67, 100, 4, 2))
Track.setStep(t, 4, Step.new(72, 100, 4, 2))

-- Pulse 0 → NOTE_ON C4
local evs = Engine.tick(e)
assert(#evs == 1,                  "expected 1 event")
assert(evs[1].type    == "NOTE_ON","expected NOTE_ON")
assert(evs[1].pitch   == 60,       "expected pitch 60")
assert(evs[1].channel == 1,        "expected channel 1")

-- Pulse 1 → no events
evs = Engine.tick(e)
assert(#evs == 0, "expected no events on pulse 1")

-- Pulse 2 → NOTE_OFF C4
evs = Engine.tick(e)
assert(#evs == 1 and evs[1].type == "NOTE_OFF" and evs[1].pitch == 60,
    "expected NOTE_OFF C4 at gate boundary")

-- Pulse 3 → no events, then step 2 starts
Engine.tick(e)
evs = Engine.tick(e) -- pulse 0 of step 2 → NOTE_ON E4
assert(#evs == 1 and evs[1].type == "NOTE_ON" and evs[1].pitch == 64,
    "expected NOTE_ON E4 on step 2")

-- BPM change recalculates pulse interval
Engine.setBpm(e, 60)
assert(e.bpm            == 60)
assert(e.pulseIntervalMs == 250)

-- Reset returns all tracks to start
Engine.reset(e)
assert(t.cursor == 1 and t.pulseCounter == 0, "expected reset to step 1 pulse 0")

-- After reset, next tick should again fire NOTE_ON C4
evs = Engine.tick(e)
assert(#evs == 1 and evs[1].type == "NOTE_ON" and evs[1].pitch == 60,
    "expected NOTE_ON C4 after reset")

-- Clock division: div=2 advances every second engine pulse
local eDiv = Engine.new(120, 4, 1, 2)
local tDiv = Engine.getTrack(eDiv, 1)
Track.setStep(tDiv, 1, Step.new(60, 100, 1, 1))
Track.setStep(tDiv, 2, Step.new(62, 100, 1, 1))
Track.setClockDiv(tDiv, 2)
Track.setClockMult(tDiv, 1)

local d1 = Engine.tick(eDiv)
assert(#d1 == 0, "expected no event on first divided pulse")
local d2 = Engine.tick(eDiv)
assert(#d2 == 1 and d2[1].type == "NOTE_ON" and d2[1].pitch == 60,
    "expected NOTE_ON on second pulse with div=2")

-- Clock multiplication: mult=2 advances twice per engine pulse
local eMul = Engine.new(120, 4, 1, 2)
local tMul = Engine.getTrack(eMul, 1)
Track.setStep(tMul, 1, Step.new(60, 100, 1, 1))
Track.setStep(tMul, 2, Step.new(62, 100, 1, 1))
Track.setClockDiv(tMul, 1)
Track.setClockMult(tMul, 2)

local m1 = Engine.tick(eMul)
assert(#m1 == 2, "expected two NOTE_ON events in one engine pulse with mult=2")
assert(m1[1].pitch == 60 and m1[2].pitch == 62,
    "expected rapid advancement across two steps with mult=2")

-- Direction mode integration at engine level: reverse
local eRev = Engine.new(120, 4, 1, 4)
local tRev = Engine.getTrack(eRev, 1)
Track.setStep(tRev, 1, Step.new(60, 100, 1, 1))
Track.setStep(tRev, 2, Step.new(62, 100, 1, 1))
Track.setStep(tRev, 3, Step.new(64, 100, 1, 1))
Track.setStep(tRev, 4, Step.new(65, 100, 1, 1))
Track.setDirection(tRev, "reverse")

local r1 = Engine.tick(eRev)
assert(#r1 == 1 and r1[1].pitch == 60, "reverse first event should still come from step 1")
local r2 = Engine.tick(eRev)
assert(#r2 == 1 and r2[1].pitch == 65, "reverse should then move to last step")

-- Per-track MIDI channel override
local eCh = Engine.new(120, 4, 1, 1)
local tCh = Engine.getTrack(eCh, 1)
Track.setStep(tCh, 1, Step.new(60, 100, 1, 1))
Track.setMidiChannel(tCh, 10)
local ch1 = Engine.tick(eCh)
assert(#ch1 == 1 and ch1[1].channel == 10, "engine should use track midiChannel override")

-- Scale quantizer in engine event output
local eScale = Engine.new(120, 4, 1, 1)
local tScale = Engine.getTrack(eScale, 1)
Track.setStep(tScale, 1, Step.new(61, 100, 1, 1))
Engine.setScale(eScale, "major", 0)
local q1 = Engine.tick(eScale)
assert(#q1 == 1 and q1[1].pitch == 60, "major scale should quantize 61 to 60")

-- Swing delays odd pulses when set high
local eSwing = Engine.new(120, 4, 1, 1)
local tSwing = Engine.getTrack(eSwing, 1)
Track.setStep(tSwing, 1, Step.new(60, 100, 1, 1))
Engine.setSwing(eSwing, 72)
local s1 = Engine.tick(eSwing)
assert(#s1 == 1 and s1[1].pitch == 60, "first pulse should pass through")
local s2 = Engine.tick(eSwing)
assert(#s2 == 0, "high swing should hold first off-beat pulse")

-- ── Active note tracking ────────────────────────────────────────────────────

-- activeNotes table starts empty
local eTrack = Engine.new(120, 4, 1, 2)
assert(next(eTrack.activeNotes) == nil, "activeNotes should start empty")

-- After a NOTE_ON tick, activeNotes should contain that note
local tTrack = Engine.getTrack(eTrack, 1)
Track.setStep(tTrack, 1, Step.new(60, 100, 4, 2))
Track.setStep(tTrack, 2, Step.new(64, 100, 4, 2))
Engine.tick(eTrack) -- NOTE_ON pitch 60
assert(eTrack.activeNotes["60:1"] == true, "activeNotes should track NOTE_ON")

-- After NOTE_OFF, note should be removed from activeNotes
Engine.tick(eTrack) -- pulse 1, no event
Engine.tick(eTrack) -- pulse 2 → NOTE_OFF pitch 60
assert(eTrack.activeNotes["60:1"] == nil, "activeNotes should clear on NOTE_OFF")

-- ── allNotesOff ─────────────────────────────────────────────────────────────

-- allNotesOff returns NOTE_OFF events for all sounding notes
local eOff = Engine.new(120, 4, 1, 2)
local tOff = Engine.getTrack(eOff, 1)
Track.setStep(tOff, 1, Step.new(60, 100, 4, 2))
Track.setStep(tOff, 2, Step.new(64, 100, 4, 2))
Engine.tick(eOff) -- NOTE_ON pitch 60
local offEvs = Engine.allNotesOff(eOff)
assert(#offEvs == 1, "allNotesOff should return one event")
assert(offEvs[1].type == "NOTE_OFF", "allNotesOff event should be NOTE_OFF")
assert(offEvs[1].pitch == 60, "allNotesOff should flush pitch 60")
assert(offEvs[1].channel == 1, "allNotesOff should preserve channel")
assert(next(eOff.activeNotes) == nil, "activeNotes should be empty after allNotesOff")

-- allNotesOff on empty activeNotes returns empty list
local offEvs2 = Engine.allNotesOff(eOff)
assert(#offEvs2 == 0, "allNotesOff on empty activeNotes should return nothing")

-- ── reset flushes hanging notes ─────────────────────────────────────────────

-- Reset mid-note returns NOTE_OFF events
local eReset = Engine.new(120, 4, 1, 2)
local tReset = Engine.getTrack(eReset, 1)
Track.setStep(tReset, 1, Step.new(60, 100, 4, 2))
Track.setStep(tReset, 2, Step.new(64, 100, 4, 2))
Engine.tick(eReset) -- NOTE_ON pitch 60
local resetEvs = Engine.reset(eReset)
assert(#resetEvs == 1, "reset should return NOTE_OFF for sounding note")
assert(resetEvs[1].type == "NOTE_OFF" and resetEvs[1].pitch == 60,
    "reset should flush pitch 60")
assert(next(eReset.activeNotes) == nil, "activeNotes empty after reset")
assert(tReset.cursor == 1, "cursor should be at 1 after reset")

-- After reset, engine should play normally again
local postReset = Engine.tick(eReset)
assert(#postReset == 1 and postReset[1].type == "NOTE_ON" and postReset[1].pitch == 60,
    "engine should play normally after reset")

-- ── stop / start ────────────────────────────────────────────────────────────

-- Stop flushes sounding notes and halts playback
local eStop = Engine.new(120, 4, 1, 2)
local tStop = Engine.getTrack(eStop, 1)
Track.setStep(tStop, 1, Step.new(60, 100, 4, 2))
Track.setStep(tStop, 2, Step.new(64, 100, 4, 2))
Engine.tick(eStop) -- NOTE_ON pitch 60
local stopEvs = Engine.stop(eStop)
assert(#stopEvs == 1, "stop should return NOTE_OFF for sounding note")
assert(stopEvs[1].type == "NOTE_OFF" and stopEvs[1].pitch == 60,
    "stop should flush pitch 60")
assert(eStop.running == false, "engine should not be running after stop")

-- tick is a no-op after stop
local noEvs = Engine.tick(eStop)
assert(#noEvs == 0, "tick should return nothing after stop")

-- start resumes playback from where it left off
Engine.start(eStop)
assert(eStop.running == true, "engine should be running after start")
local resumed = Engine.tick(eStop)
-- We're mid-step (pulse 1 of step 1, duration=4, gate=2) — no event expected yet
assert(#resumed == 0, "mid-step pulse should produce no events")
-- Next tick should produce NOTE_OFF at gate boundary (pulse 2)
local resumed2 = Engine.tick(eStop)
assert(#resumed2 == 1 and resumed2[1].type == "NOTE_OFF",
    "start should resume normal playback — NOTE_OFF at gate boundary")

-- ── Multi-track active note tracking ────────────────────────────────────────

-- Two tracks with different channels tracked independently
local eMulti = Engine.new(120, 4, 2, 1)
local t1 = Engine.getTrack(eMulti, 1)
local t2 = Engine.getTrack(eMulti, 2)
Track.setStep(t1, 1, Step.new(60, 100, 4, 2))
Track.setStep(t2, 1, Step.new(72, 100, 4, 2))
Track.setMidiChannel(t1, 1)
Track.setMidiChannel(t2, 2)
Engine.tick(eMulti) -- both tracks NOTE_ON
assert(eMulti.activeNotes["60:1"] == true, "track 1 note should be tracked")
assert(eMulti.activeNotes["72:2"] == true, "track 2 note should be tracked")
local multiOff = Engine.allNotesOff(eMulti)
assert(#multiOff == 2, "allNotesOff should return 2 events for 2 sounding notes")

-- ── Scene chain integration ─────────────────────────────────────────────────

local Scene = require("sequencer/scene")

-- Scene chain changes loop points after the scene's beats elapse.
do
    local e = Engine.new(120, 4, 1, 0)
    local trk = Engine.getTrack(e, 1)
    Track.addPattern(trk, 4)  -- pattern 1: steps 1-4
    Track.addPattern(trk, 4)  -- pattern 2: steps 5-8
    for i = 1, 8 do
        Track.setStep(trk, i, Step.new(60 + i - 1, 100, 1, 1))
    end

    -- Scene A: loop over pattern 1 (steps 1-4) for 2 beats.
    local sceneA = Scene.new(1, 2, "A")
    Scene.setTrackLoop(sceneA, 1, 1, 4)

    -- Scene B: loop over pattern 2 (steps 5-8) for 2 beats.
    local sceneB = Scene.new(1, 2, "B")
    Scene.setTrackLoop(sceneB, 1, 5, 8)

    local chain = Scene.newChain()
    Scene.chainAppend(chain, sceneA)
    Scene.chainAppend(chain, sceneB)

    Engine.setSceneChain(e, chain)
    Engine.activateSceneChain(e)

    -- Verify scene A's loop points are applied.
    assert(Track.getLoopStart(trk) == 1, "scene A should set loopStart to 1")
    assert(Track.getLoopEnd(trk) == 4, "scene A should set loopEnd to 4")

    -- Tick through 2 beats (8 pulses at 4 ppb).
    for _ = 1, 8 do
        Engine.tick(e)
    end

    -- After 2 beats, scene should advance to B.
    assert(Track.getLoopStart(trk) == 5, "scene B should set loopStart to 5")
    assert(Track.getLoopEnd(trk) == 8, "scene B should set loopEnd to 8")

    -- Tick through 2 more beats.
    for _ = 1, 8 do
        Engine.tick(e)
    end

    -- Should wrap back to scene A.
    assert(Track.getLoopStart(trk) == 1, "scene A (wrapped) should set loopStart to 1")
    assert(Track.getLoopEnd(trk) == 4, "scene A (wrapped) should set loopEnd to 4")
end

-- Engine.reset with active scene chain resets to scene 1.
do
    local e = Engine.new(120, 4, 1, 0)
    local trk = Engine.getTrack(e, 1)
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
    Engine.setSceneChain(e, chain)
    Engine.activateSceneChain(e)

    -- Advance to scene B.
    for _ = 1, 8 do Engine.tick(e) end
    assert(chain.cursor == 2, "should be on scene B")

    -- Reset should go back to scene A.
    Engine.reset(e)
    assert(chain.cursor == 1, "reset should return to scene A")
    assert(Track.getLoopStart(trk) == 1, "reset should re-apply scene A loop points")
end

print("engine: all tests passed")
