-- tests/pattern.lua
-- Behavioural tests for sequencer/pattern.lua

local Pattern = require("sequencer/pattern")
local Step    = require("sequencer/step")

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

-- Default construction: zero steps, empty name.
do
    local pat = Pattern.new()
    assert(Pattern.getStepCount(pat) == 0, "default stepCount should be 0")
    assert(Pattern.getName(pat) == "", "default name should be empty string")
end

-- Construction with stepCount: pre-populated with default Steps.
do
    local pat = Pattern.new(4)
    assert(Pattern.getStepCount(pat) == 4, "stepCount should be 4")
    local s = Pattern.getStep(pat, 1)
    assert(s ~= nil, "step 1 should exist")
    assert(Step.getPitch(s)       == 60,   "default pitch should be 60")
    assert(Step.getVelocity(s)    == 100,  "default velocity should be 100")
    assert(Step.getDuration(s)    == 4,    "default duration should be 4")
    assert(Step.getGate(s)        == 2,    "default gate should be 2")
    assert(Step.getActive(s)      == true, "default active should be true")
end

-- Construction with stepCount and name.
do
    local pat = Pattern.new(2, "Intro")
    assert(Pattern.getStepCount(pat) == 2, "stepCount should be 2")
    assert(Pattern.getName(pat) == "Intro", "name should be 'Intro'")
end

-- ---------------------------------------------------------------------------
-- Name get/set
-- ---------------------------------------------------------------------------

do
    local pat = Pattern.new(0, "A")
    assert(Pattern.getName(pat) == "A", "getName should return 'A'")
    Pattern.setName(pat, "B")
    assert(Pattern.getName(pat) == "B", "getName should return 'B' after setName")
end

-- ---------------------------------------------------------------------------
-- Step get/set
-- ---------------------------------------------------------------------------

do
    local pat = Pattern.new(3)

    -- getStep returns the correct step (steps are packed integers — equal-by-value
    -- when defaults match, so identity is no longer meaningful; just verify both
    -- decode to the expected default pitch).
    local s1 = Pattern.getStep(pat, 1)
    local s3 = Pattern.getStep(pat, 3)
    assert(Step.getPitch(s1) == 60, "default pitch at index 1")
    assert(Step.getPitch(s3) == 60, "default pitch at index 3")

    -- setStep replaces a step.
    local newStep = Step.new(72, 90, 8, 4)
    Pattern.setStep(pat, 2, newStep)
    local retrieved = Pattern.getStep(pat, 2)
    assert(Step.getPitch(retrieved) == 72, "replaced step pitch should be 72")
    assert(Step.getVelocity(retrieved) == 90, "replaced step velocity should be 90")
end

-- ---------------------------------------------------------------------------
-- Out-of-range guards
-- ---------------------------------------------------------------------------

-- stepCount must be non-negative integer.
do
    local ok, err = pcall(Pattern.new, -1)
    assert(not ok, "negative stepCount should error")
end

do
    local ok, err = pcall(Pattern.new, 1.5)
    assert(not ok, "fractional stepCount should error")
end

-- getStep out of range.
do
    local pat      = Pattern.new(2)
    local ok, err  = pcall(Pattern.getStep, pat, 3)
    assert(not ok, "getStep beyond stepCount should error")
end

do
    local pat      = Pattern.new(2)
    local ok, err  = pcall(Pattern.getStep, pat, 0)
    assert(not ok, "getStep at 0 should error")
end

-- setStep out of range.
do
    local pat     = Pattern.new(2)
    local ok, err = pcall(Pattern.setStep, pat, 3, Step.new())
    assert(not ok, "setStep beyond stepCount should error")
end

-- setName too long.
do
    local pat     = Pattern.new()
    local longStr = string.rep("x", 33)
    local ok, err = pcall(Pattern.setName, pat, longStr)
    assert(not ok, "setName with >32 chars should error")
end

print("tests/pattern.lua OK")
