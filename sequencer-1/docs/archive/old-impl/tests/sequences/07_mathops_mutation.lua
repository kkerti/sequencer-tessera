require("authoring")
local Track = require("sequencer").Track
local Step = require("sequencer").Step
local MathOps = require("mathops")

local Scenario = {}

Scenario.name = "07_mathops_mutation"
Scenario.description = "Mutation pass: transpose + velocity randomization"
Scenario.defaultPulses = 16

function Scenario.build(helpers)
    local engine = helpers.newEngine(1, 120, 4)
    local track = engine.tracks[1]

    Track.addPattern(track, 8)
    Track.setStep(track, 1, Step.new(48, 100, 1, 1))
    Track.setStep(track, 2, Step.new(50, 100, 1, 1))
    Track.setStep(track, 3, Step.new(52, 100, 1, 1))
    Track.setStep(track, 4, Step.new(53, 100, 1, 1))
    Track.setStep(track, 5, Step.new(55, 100, 1, 1))
    Track.setStep(track, 6, Step.new(53, 100, 1, 1))
    Track.setStep(track, 7, Step.new(52, 100, 1, 1))
    Track.setStep(track, 8, Step.new(50, 100, 1, 1))

    MathOps.transpose(track, 12)
    math.randomseed(1337)
    MathOps.randomize(track, "velocity", 70, 90)

    return engine
end

function Scenario.assert(helpers, result)
    assert(result.noteOnPitches[1] == 60, "first transposed note should be 60")
    assert(result.noteOnPitches[2] == 62, "second transposed note should be 62")
    assert(result.noteOnPitches[5] == 67, "fifth note should reflect transposed extension")
end

return Scenario
