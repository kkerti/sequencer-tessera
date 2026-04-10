-- tests/step.lua
-- Behavioural tests for sequencer/step.lua.
-- Run with: lua tests/step.lua

local Step = require("sequencer/step")

-- Defaults
local s = Step.stepNew()
assert(Step.stepGetPitch(s)    == 60)
assert(Step.stepGetVelocity(s) == 100)
assert(Step.stepGetDuration(s) == 4)
assert(Step.stepGetGate(s)     == 2)
assert(Step.stepGetActive(s)   == true)
assert(Step.stepIsPlayable(s)  == true)

-- Setters
Step.stepSetPitch(s, 72)
assert(Step.stepGetPitch(s) == 72)

Step.stepSetVelocity(s, 80)
assert(Step.stepGetVelocity(s) == 80)

Step.stepSetDuration(s, 8)
assert(Step.stepGetDuration(s) == 8)

Step.stepSetGate(s, 4)
assert(Step.stepGetGate(s) == 4)

-- Muted step is not playable
Step.stepSetActive(s, false)
assert(Step.stepIsPlayable(s) == false)
Step.stepSetActive(s, true)

-- Rest (gate == 0) is not playable
local rest = Step.stepNew(60, 100, 4, 0)
assert(Step.stepIsPlayable(rest) == false)

-- Skipped step (duration == 0) is not playable
local skip = Step.stepNew(60, 100, 0, 0)
assert(Step.stepIsPlayable(skip) == false)

-- Out-of-range pitch is rejected
local ok = pcall(Step.stepNew, 200, 100, 4, 2)
assert(not ok, "expected error for pitch > 127")

-- Out-of-range velocity is rejected
ok = pcall(Step.stepNew, 60, 200, 4, 2)
assert(not ok, "expected error for velocity > 127")

print("step: all tests passed")
