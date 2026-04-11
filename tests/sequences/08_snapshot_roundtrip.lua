local Track = require("sequencer/track")
local Step = require("sequencer/step")
local Snapshot = require("sequencer/snapshot")

local Scenario = {}

Scenario.name = "08_snapshot_roundtrip"
Scenario.description = "Save/reload a pingpong phrase and keep musical identity"
Scenario.defaultPulses = 12

function Scenario.build(helpers)
    local engine = helpers.newEngine(1, 120, 4)
    local track = engine.tracks[1]

    Track.addPattern(track, 5)
    Track.setStep(track, 1, Step.new(60, 100, 1, 1))
    Track.setStep(track, 2, Step.new(63, 95, 1, 1))
    Track.setStep(track, 3, Step.new(67, 100, 1, 1))
    Track.setStep(track, 4, Step.new(70, 90, 1, 1))
    Track.setStep(track, 5, Step.new(67, 85, 1, 1))
    Track.setDirection(track, "pingpong")

    local path = "/tmp/sequencer_sequence_runner_snapshot.lua"
    Snapshot.saveToFile(engine, path)
    local loaded = Snapshot.loadFromFile(path)
    os.remove(path)

    return loaded
end

function Scenario.assert(helpers, result)
    assert(result.noteOnPitches[1] == 60, "loaded sequence should start on C4")
    assert(result.noteOnPitches[2] == 63, "loaded sequence should continue to Eb4")
    assert(result.noteOnPitches[3] == 67, "loaded sequence should continue to G4")
end

return Scenario
