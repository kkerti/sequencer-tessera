-- tests/track.lua
-- Behavioural tests for sequencer/track.lua.
-- Run with: lua tests/track.lua

local Track = require("sequencer/track")
local Step  = require("sequencer/step")

-- Construction
local t = Track.trackNew(4)
assert(t.stepCount    == 4)
assert(t.cursor       == 1)
assert(t.pulseCounter == 0)

-- Load a known sequence: C4, E4, G4, rest
Track.trackSetStep(t, 1, Step.stepNew(60, 100, 4, 2))
Track.trackSetStep(t, 2, Step.stepNew(64, 100, 4, 2))
Track.trackSetStep(t, 3, Step.stepNew(67, 100, 4, 2))
Track.trackSetStep(t, 4, Step.stepNew(60, 100, 4, 0)) -- rest

-- Pulse 0 of step 1 → NOTE_ON
local ev = Track.trackAdvance(t)
assert(ev == "NOTE_ON",  "expected NOTE_ON at pulse 0")
assert(t.cursor == 1,    "cursor should still be on step 1")

-- Pulse 1 → no event
ev = Track.trackAdvance(t)
assert(ev == nil, "expected no event on pulse 1")

-- Pulse 2 → NOTE_OFF (gate == 2)
ev = Track.trackAdvance(t)
assert(ev == "NOTE_OFF", "expected NOTE_OFF at gate boundary")

-- Pulse 3 → no event, cursor advances to step 2
ev = Track.trackAdvance(t)
assert(ev == nil)
assert(t.cursor == 2, "expected cursor to advance to step 2")

-- Pulse 0 of step 2 → NOTE_ON E4
ev = Track.trackAdvance(t)
assert(ev == "NOTE_ON", "expected NOTE_ON for step 2")
assert(Track.trackGetCurrentStep(t).pitch == 64)

-- Rest step: NOTE_ON should not fire
Track.trackReset(t)
t.cursor = 4
ev = Track.trackAdvance(t)
assert(ev == nil, "expected no event for rest step")

-- Reset returns cursor and pulse to start
Track.trackReset(t)
assert(t.cursor == 1 and t.pulseCounter == 0, "expected reset to step 1 pulse 0")

-- Zero-duration step is skipped
local t2 = Track.trackNew(2)
Track.trackSetStep(t2, 1, Step.stepNew(60, 100, 0, 0)) -- skip
Track.trackSetStep(t2, 2, Step.stepNew(64, 100, 4, 2))
ev = Track.trackAdvance(t2)
assert(ev == "NOTE_ON" and t2.cursor == 2,
    "expected zero-duration step to be skipped")

print("track: all tests passed")
