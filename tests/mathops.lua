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
    assert(Track.getStep(t, 1).pitch == 60)
    assert(Track.getStep(t, 2).pitch == 73)
    assert(Track.getStep(t, 3).pitch == 74)
    assert(Track.getStep(t, 4).pitch == 63)
end

do
    local t = Track.new()
    Track.addPattern(t, 4)
    for i = 1, 4 do
        Track.setStep(t, i, Step.new(60, 100, 4, 2))
    end

    math.randomseed(11)
    MathOps.randomize(t, "ratchet", 2, 4)
    for i = 1, 4 do
        local r = Track.getStep(t, i).ratchet
        assert(r >= 2 and r <= 4)
    end
end

do
    local t = Track.new()
    Track.addPattern(t, 2)
    Track.setStep(t, 1, Step.new(60, 100, 4, 2))
    Track.setStep(t, 2, Step.new(60, 100, 4, 2))

    math.randomseed(22)
    MathOps.jitter(t, "pitch", 2)
    for i = 1, 2 do
        local p = Track.getStep(t, i).pitch
        assert(p >= 58 and p <= 62)
    end
end

print("tests/mathops.lua OK")
