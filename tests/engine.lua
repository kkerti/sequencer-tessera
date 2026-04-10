-- tests/engine.lua
-- Behavioural tests for sequencer/engine.lua.
-- Run with: lua tests/engine.lua

local Engine = require("sequencer/engine")
local Track  = require("sequencer/track")
local Step   = require("sequencer/step")

-- BPM to pulse interval conversion
assert(Engine.engineBpmToMs(120, 4) == 125)
assert(Engine.engineBpmToMs(60,  4) == 250)
assert(Engine.engineBpmToMs(120, 8) == 62.5)

-- Engine construction
local e = Engine.engineNew(120, 4, 1, 4)
assert(e.bpm            == 120)
assert(e.trackCount     == 1)
assert(e.pulseIntervalMs == 125)

-- Load a C major arpeggio into track 1
local t = Engine.engineGetTrack(e, 1)
Track.trackSetStep(t, 1, Step.stepNew(60, 100, 4, 2))
Track.trackSetStep(t, 2, Step.stepNew(64, 100, 4, 2))
Track.trackSetStep(t, 3, Step.stepNew(67, 100, 4, 2))
Track.trackSetStep(t, 4, Step.stepNew(72, 100, 4, 2))

-- Pulse 0 → NOTE_ON C4
local evs = Engine.engineTick(e)
assert(#evs == 1,                  "expected 1 event")
assert(evs[1].type    == "NOTE_ON","expected NOTE_ON")
assert(evs[1].pitch   == 60,       "expected pitch 60")
assert(evs[1].channel == 1,        "expected channel 1")

-- Pulse 1 → no events
evs = Engine.engineTick(e)
assert(#evs == 0, "expected no events on pulse 1")

-- Pulse 2 → NOTE_OFF C4
evs = Engine.engineTick(e)
assert(#evs == 1 and evs[1].type == "NOTE_OFF" and evs[1].pitch == 60,
    "expected NOTE_OFF C4 at gate boundary")

-- Pulse 3 → no events, then step 2 starts
Engine.engineTick(e)
evs = Engine.engineTick(e) -- pulse 0 of step 2 → NOTE_ON E4
assert(#evs == 1 and evs[1].type == "NOTE_ON" and evs[1].pitch == 64,
    "expected NOTE_ON E4 on step 2")

-- BPM change recalculates pulse interval
Engine.engineSetBpm(e, 60)
assert(e.bpm            == 60)
assert(e.pulseIntervalMs == 250)

-- Reset returns all tracks to start
Engine.engineReset(e)
assert(t.cursor == 1 and t.pulseCounter == 0, "expected reset to step 1 pulse 0")

-- After reset, next tick should again fire NOTE_ON C4
evs = Engine.engineTick(e)
assert(#evs == 1 and evs[1].type == "NOTE_ON" and evs[1].pitch == 60,
    "expected NOTE_ON C4 after reset")

print("engine: all tests passed")
