local Track = require("sequencer/track")
local Step = require("sequencer/step")
local Engine = require("sequencer/engine")

local Scenario = {}

Scenario.name = "05_scale_quantizer"
Scenario.description = "Chromatic source phrase quantized to C major"
Scenario.defaultPulses = 12

function Scenario.build(helpers)
    local engine = helpers.newEngine(1, 120, 4)
    local track = engine.tracks[1]

    Track.addPattern(track, 6)
    Track.setStep(track, 1, Step.new(61, 100, 1, 1)) -- C# -> C
    Track.setStep(track, 2, Step.new(63, 95, 1, 1)) -- D# -> D
    Track.setStep(track, 3, Step.new(66, 95, 1, 1)) -- F# -> F
    Track.setStep(track, 4, Step.new(68, 90, 1, 1)) -- G# -> G
    Track.setStep(track, 5, Step.new(70, 90, 1, 1)) -- A# -> A
    Track.setStep(track, 6, Step.new(73, 85, 1, 1)) -- C# -> C

    Engine.setScale(engine, "major", 0)
    return engine
end

function Scenario.assert(helpers, result)
    assert(result.noteOnPitches[1] == 60, "61 should quantize to 60 in C major")
    assert(result.noteOnPitches[2] == 62, "63 should quantize to 62 in C major")
    assert(result.noteOnPitches[3] == 65, "66 should quantize to 65 in C major")
end

return Scenario
