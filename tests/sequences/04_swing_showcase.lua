local Track = require("sequencer/track")
local Step = require("sequencer/step")
local Engine = require("sequencer/engine")

local Scenario = {}

Scenario.name = "04_swing_showcase"
Scenario.description = "Groove phrase with noticeable swing push/pull"
Scenario.defaultPulses = 32

function Scenario.build(helpers)
    local engine = helpers.newEngine(1, 120, 4)
    local track = engine.tracks[1]

    Track.addPattern(track, 8)

    -- Straight 16th-grid phrase first, then global swing delays off-beat pulses.
    -- We keep gates short so the timing feel is easy to hear.
    Track.setStep(track, 1, Step.new(48, 100, 1, 1))
    Track.setStep(track, 2, Step.new(55, 95, 1, 1))
    Track.setStep(track, 3, Step.new(58, 90, 1, 1))
    Track.setStep(track, 4, Step.new(55, 85, 1, 1))
    Track.setStep(track, 5, Step.new(48, 100, 1, 1))
    Track.setStep(track, 6, Step.new(53, 90, 1, 1))
    Track.setStep(track, 7, Step.new(55, 95, 1, 1))
    Track.setStep(track, 8, Step.new(53, 80, 1, 1))

    -- 62% gives audible swing without becoming half-time hold behavior.
    engine.swingPercent = 62

    return engine
end

function Scenario.assert(helpers, result)
    local heldEvenAfterOdd = 0

    for pulse = 1, #result.eventsPerPulse - 1 do
        if pulse % 2 == 1 then
            local oddEvents = result.eventsPerPulse[pulse]
            local evenEvents = result.eventsPerPulse[pulse + 1]
            if #oddEvents > 0 and #evenEvents == 0 then
                heldEvenAfterOdd = heldEvenAfterOdd + 1
            end
        end
    end

    assert(heldEvenAfterOdd >= 2,
        "swing should create at least two delayed off-beat pulses")

    local unique = {}
    for i = 1, #result.noteOnPitches do
        unique[result.noteOnPitches[i]] = true
    end
    local uniqueCount = 0
    for _ in pairs(unique) do
        uniqueCount = uniqueCount + 1
    end

    assert(uniqueCount >= 4, "swing showcase should contain a melodic phrase, not a single repeated note")
end

return Scenario
