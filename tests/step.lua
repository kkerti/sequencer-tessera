-- tests/step.lua
-- Behavioural tests for sequencer/step.lua.
-- Run with: lua tests/step.lua

local Step = require("sequencer/step")

-- Defaults
local s = Step.new()
assert(Step.getPitch(s)    == 60)
assert(Step.getVelocity(s) == 100)
assert(Step.getDuration(s) == 4)
assert(Step.getGate(s)     == 2)
assert(Step.getRatchet(s)  == 1)
assert(Step.getActive(s)   == true)
assert(Step.isPlayable(s)  == true)

-- Setters
Step.setPitch(s, 72)
assert(Step.getPitch(s) == 72)

Step.setVelocity(s, 80)
assert(Step.getVelocity(s) == 80)

Step.setDuration(s, 8)
assert(Step.getDuration(s) == 8)

Step.setGate(s, 4)
assert(Step.getGate(s) == 4)

Step.setRatchet(s, 3)
assert(Step.getRatchet(s) == 3)

-- Muted step is not playable
Step.setActive(s, false)
assert(Step.isPlayable(s) == false)
Step.setActive(s, true)

-- Rest (gate == 0) is not playable
local rest = Step.new(60, 100, 4, 0)
assert(Step.isPlayable(rest) == false)

-- Skipped step (duration == 0) is not playable
local skip = Step.new(60, 100, 0, 0)
assert(Step.isPlayable(skip) == false)

-- Out-of-range pitch is rejected
local ok = pcall(Step.new, 200, 100, 4, 2)
assert(not ok, "expected error for pitch > 127")

-- Out-of-range velocity is rejected
ok = pcall(Step.new, 60, 200, 4, 2)
assert(not ok, "expected error for velocity > 127")

-- Ratchet pulse events
local r = Step.new(60, 100, 4, 1, 2)
assert(Step.getPulseEvent(r, 0) == "NOTE_ON")
assert(Step.getPulseEvent(r, 2) == "NOTE_ON")

-- Scale resolution passthrough / quantized
assert(Step.resolvePitch(r, nil, 0) == 60)
local Utils = require("utils")
assert(Step.resolvePitch(Step.new(61, 100, 4, 2), Utils.SCALES.major, 0) == 60)

print("step: all tests passed")
