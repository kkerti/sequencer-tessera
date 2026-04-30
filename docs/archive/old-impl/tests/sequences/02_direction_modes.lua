require("authoring")
local Track = require("sequencer").Track
local Step = require("sequencer").Step

local Scenario = {}

Scenario.name = "02_direction_modes"
Scenario.description = "Reverse + pingpong direction phrase"
Scenario.defaultPulses = 18

function Scenario.build(helpers)
    local engine = helpers.newEngine(1, 120, 4)
    local track = engine.tracks[1]

    Track.addPattern(track, 6)
    Track.setStep(track, 1, Step.new(48, 100, 1, 1))
    Track.setStep(track, 2, Step.new(51, 95, 1, 1))
    Track.setStep(track, 3, Step.new(55, 95, 1, 1))
    Track.setStep(track, 4, Step.new(58, 90, 1, 1))
    Track.setStep(track, 5, Step.new(60, 90, 1, 1))
    Track.setStep(track, 6, Step.new(63, 85, 1, 1))
    Track.setDirection(track, "reverse")

    return engine
end

function Scenario.assert(helpers, result)
    assert(result.noteOnPitches[1] == 48, "reverse still starts from step 1 on reset")
    assert(result.noteOnPitches[2] == 63, "second note should be last step in reverse")
    assert(result.noteOnPitches[3] == 60, "reverse should continue backwards")
    assert(result.noteOnPitches[4] == 58, "reverse should continue backwards")
end

return Scenario
