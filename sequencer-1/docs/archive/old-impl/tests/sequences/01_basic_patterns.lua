require("authoring")
local Track = require("sequencer").Track
local Step = require("sequencer").Step

local Scenario = {}

Scenario.name = "01_basic_patterns"
Scenario.description = "Intro pattern then looping groove pattern"
Scenario.defaultPulses = 24

function Scenario.build(helpers)
    local engine = helpers.newEngine(1, 120, 4)
    local track = engine.tracks[1]

    Track.addPattern(track, 4) -- intro
    Track.addPattern(track, 4) -- groove

    -- Intro phrase (C minor feel)
    Track.setStep(track, 1, Step.new(48, 100, 2, 1))
    Track.setStep(track, 2, Step.new(51, 95, 2, 1))
    Track.setStep(track, 3, Step.new(55, 90, 2, 1))
    Track.setStep(track, 4, Step.new(58, 90, 2, 1))

    -- Groove phrase that loops
    Track.setStep(track, 5, Step.new(48, 100, 1, 1))
    Track.setStep(track, 6, Step.new(55, 90, 1, 1))
    Track.setStep(track, 7, Step.new(58, 95, 1, 1))
    Track.setStep(track, 8, Step.new(55, 85, 1, 0))

    Track.setLoopStart(track, 5)
    Track.setLoopEnd(track, 8)

    return engine
end

function Scenario.assert(helpers, result)
    assert(#result.noteOnPitches >= 10, "expected many NOTE_ON events")
    assert(result.noteOnPitches[1] == 48, "first note should come from intro pattern")
    assert(result.noteOnPitches[2] == 48, "second note should jump to groove loop start")
    assert(result.noteOnPitches[3] == 55 and result.noteOnPitches[4] == 58,
        "groove pattern should continue musically")
end

return Scenario
