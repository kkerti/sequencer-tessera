-- tests/mathops.lua
-- Behavioural tests for sequencer/mathops.lua.

local Track = require("sequencer/track")
local Step = require("sequencer/step")
local MathOps = require("sequencer/mathops")

do
    local t = Track.new()
    Track.addPattern(t, 4)
    Track.setStep(t, 1, Step.new(60, 100, 4, 2))
    Track.setStep(t, 2, Step.new(61, 100, 4, 2))
    Track.setStep(t, 3, Step.new(62, 100, 4, 2))
    Track.setStep(t, 4, Step.new(63, 100, 4, 2))

    MathOps.transpose(t, 12, 2, 3)
    assert(Step.getPitch(Track.getStep(t, 1)) == 60)
    assert(Step.getPitch(Track.getStep(t, 2)) == 73)
    assert(Step.getPitch(Track.getStep(t, 3)) == 74)
    assert(Step.getPitch(Track.getStep(t, 4)) == 63)
end

do
    local t = Track.new()
    Track.addPattern(t, 2)
    Track.setStep(t, 1, Step.new(60, 100, 4, 2))
    Track.setStep(t, 2, Step.new(60, 100, 4, 2))

    math.randomseed(22)
    MathOps.jitter(t, "pitch", 2)
    for i = 1, 2 do
        local p = Step.getPitch(Track.getStep(t, i))
        assert(p >= 58 and p <= 62)
    end
end

print("tests/mathops.lua OK")
