-- tests/step.lua
-- Behavioural tests for sequencer/step.lua.
-- Run with: lua tests/step.lua

local Step = require("sequencer/step")

-- Defaults
local s = Step.new()
assert(Step.getPitch(s)       == 60)
assert(Step.getVelocity(s)    == 100)
assert(Step.getDuration(s)    == 4)
assert(Step.getGate(s)        == 2)
assert(Step.getRatch(s)       == false)
assert(Step.getProbability(s) == 100)
assert(Step.getActive(s)      == true)
assert(Step.isPlayable(s)     == true)

-- Setters return a new packed integer; rebind to verify.
s = Step.setPitch(s, 72)
assert(Step.getPitch(s) == 72)

s = Step.setVelocity(s, 80)
assert(Step.getVelocity(s) == 80)

s = Step.setDuration(s, 8)
assert(Step.getDuration(s) == 8)

s = Step.setGate(s, 4)
assert(Step.getGate(s) == 4)

s = Step.setRatch(s, true)
assert(Step.getRatch(s) == true)

s = Step.setProbability(s, 50)
assert(Step.getProbability(s) == 50)

-- Setters are PURE: discarding the return value leaves the original untouched.
local before = s
local _ = Step.setPitch(s, 33)
assert(Step.getPitch(before) == 72, "setters must not mutate; got " .. Step.getPitch(before))

-- Muted step is not playable
s = Step.setActive(s, false)
assert(Step.isPlayable(s) == false)
s = Step.setActive(s, true)

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

-- Ratchet sample-gate (boolean: gate cycles HIGH for `gate` pulses,
-- LOW for `gate` pulses, repeated until duration ends — ER-101 model).
local r = Step.new(60, 100, 4, 1, true)
assert(Step.sampleGate(r, 0) == true)
assert(Step.sampleGate(r, 1) == false)
assert(Step.sampleGate(r, 2) == true)
assert(Step.sampleGate(r, 3) == false)

-- ER-101 manual example: dur=8 gate=2 ratch=true → HIGH HIGH LOW LOW HIGH HIGH LOW LOW
local m = Step.new(60, 100, 8, 2, true)
local expected = { true, true, false, false, true, true, false, false }
for i = 1, 8 do
    assert(Step.sampleGate(m, i - 1) == expected[i],
        string.format("ER-101 ratchet example: pulse %d should be %s",
            i - 1, tostring(expected[i])))
end

-- Non-ratch: gate is HIGH on [0, gate), LOW after.
local n = Step.new(60, 100, 4, 2)
assert(Step.sampleGate(n, 0) == true)
assert(Step.sampleGate(n, 1) == true)
assert(Step.sampleGate(n, 2) == false)
assert(Step.sampleGate(n, 3) == false)

-- Legato (gate >= duration) stays high through the whole step.
local leg = Step.new(60, 100, 4, 4)
for i = 0, 3 do
    assert(Step.sampleGate(leg, i) == true)
end
local legBig = Step.new(60, 100, 4, 8)
for i = 0, 3 do
    assert(Step.sampleGate(legBig, i) == true)
end

-- Rest (gate == 0): always low.
for i = 0, 3 do
    assert(Step.sampleGate(rest, i) == false)
end

-- Skipped (duration == 0): always low.
for i = 0, 3 do
    assert(Step.sampleGate(skip, i) == false)
end

-- Muted (active == false): always low.
local muted = Step.setActive(Step.new(60, 100, 4, 2), false)
for i = 0, 3 do
    assert(Step.sampleGate(muted, i) == false)
end

-- sampleCv returns held pitch and velocity.
local cv = Step.new(64, 90, 4, 2)
local cvA, cvB = Step.sampleCv(cv)
assert(cvA == 64)
assert(cvB == 90)

-- Step is now an integer.
assert(type(Step.new()) == "number", "Step.new must return an integer (was " .. type(Step.new()) .. ")")

print("step: all tests passed")
