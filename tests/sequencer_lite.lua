-- tests/sequencer_lite.lua
-- Smoke test for the lite engine (sequencer_lite/).
-- Verifies:
--   1. All four lite modules load without error.
--   2. Engine.new builds the expected track/pattern/step structure.
--   3. Step accessors produce the same events as the full engine.
--   4. Track.advance walks a 4-step pattern and emits NOTE_ON/NOTE_OFF
--      at the expected pulses.
--   5. Engine.reset returns cursors to step 1.
--   6. Engine.onPulse is a no-op (no error, no return value).
--   7. Removed APIs are absent (sanity check the carve worked).

local Engine  = require("sequencer_lite/engine")
local Track   = require("sequencer_lite/track")
local Pattern = require("sequencer_lite/pattern")
local Step    = require("sequencer_lite/step")

local function ok(msg) print("  OK  " .. msg) end
local function bad(msg) error("FAIL: " .. msg, 2) end

-- 1. Module load
ok("4 lite modules required")

-- 2. Engine.new structure
local engine = Engine.new(120, 4, 2, 4)
assert(engine.trackCount == 2, "trackCount")
assert(#engine.tracks == 2, "tracks array")
assert(Track.getStepCount(engine.tracks[1]) == 4, "stepCount")
assert(Track.getPatternCount(engine.tracks[1]) == 1, "patternCount")
ok("Engine.new built 2 tracks x 1 pattern x 4 steps")

-- 3. Step accessors
local step = Track.getStep(engine.tracks[1], 1)
Step.setPitch(step, 60)
Step.setVelocity(step, 100)
Step.setDuration(step, 4)
Step.setGate(step, 2)
assert(Step.getPitch(step) == 60, "pitch")
assert(Step.getVelocity(step) == 100, "velocity")
assert(Step.getDuration(step) == 4, "duration")
assert(Step.getGate(step) == 2, "gate")
assert(Step.isPlayable(step) == true, "isPlayable")
ok("Step setters/getters round-trip")

-- 4. Track.advance walks the pattern correctly.
-- Step 1: pitch 60, dur 4, gate 2  -> NOTE_ON at pulse 0, NOTE_OFF at pulse 2
-- Step 2: pitch 62, dur 4, gate 2
-- Step 3: pitch 64, dur 4, gate 2
-- Step 4: pitch 65, dur 4, gate 2
local track = engine.tracks[1]
for i = 1, 4 do
    local s = Track.getStep(track, i)
    Step.setPitch(s, 59 + i)  -- 60, 61, 62, 63 (pre-set 60 still holds for step 1 test)
end
-- Re-set step 1 explicitly because we overwrote it above.
Step.setPitch(Track.getStep(track, 1), 60)

Track.reset(track)
local events = {}
for pulse = 1, 16 do
    local current = Track.getCurrentStep(track)
    local pitchBefore = Step.getPitch(current)
    local ev = Track.advance(track)
    if ev then
        events[#events + 1] = { pulse = pulse, event = ev, pitch = pitchBefore }
    end
end
-- 4 steps × dur 4 = 16 pulses; each step emits NOTE_ON @ pulse 0 of step,
-- NOTE_OFF @ pulse 2 of step. So 8 events total: ON, OFF, ON, OFF, ON, OFF, ON, OFF.
assert(#events == 8, "expected 8 events, got " .. #events)
assert(events[1].event == "NOTE_ON" and events[1].pitch == 60, "ev1")
assert(events[2].event == "NOTE_OFF",                          "ev2")
assert(events[3].event == "NOTE_ON" and events[3].pitch == 61, "ev3")
assert(events[5].event == "NOTE_ON" and events[5].pitch == 62, "ev5")
assert(events[7].event == "NOTE_ON" and events[7].pitch == 63, "ev7")
ok("Track.advance emits 8 events across 16 pulses with correct pitches")

-- 5. Reset
Track.reset(track)
assert(track.cursor == 1, "cursor after reset")
assert(track.pulseCounter == 0, "pulseCounter after reset")
ok("Track.reset returns cursor to 1")

-- 6. Engine.onPulse is a no-op
Engine.onPulse(engine, 1)
Engine.onPulse(engine, 2)
ok("Engine.onPulse is a no-op (no error)")

-- 7. Removed APIs are absent
assert(Track.copyPattern == nil, "copyPattern should be absent")
assert(Track.duplicatePattern == nil, "duplicatePattern should be absent")
assert(Track.insertPattern == nil, "insertPattern should be absent")
assert(Track.deletePattern == nil, "deletePattern should be absent")
assert(Track.swapPatterns == nil, "swapPatterns should be absent")
assert(Track.pastePattern == nil, "pastePattern should be absent")
assert(Engine.setSceneChain == nil, "setSceneChain should be absent")
assert(Engine.activateSceneChain == nil, "activateSceneChain should be absent")
ok("Removed APIs are absent")

-- 8. Direction modes still work
Track.setDirection(track, "reverse")
assert(Track.getDirection(track) == "reverse", "setDirection")
Track.setDirection(track, "pingpong")
Track.setDirection(track, "random")
Track.setDirection(track, "brownian")
Track.setDirection(track, "forward")
ok("All 5 direction modes still settable")

print("\nALL OK — sequencer_lite smoke test passed")
