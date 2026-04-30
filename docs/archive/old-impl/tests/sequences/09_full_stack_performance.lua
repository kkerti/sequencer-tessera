require("authoring")
local Track = require("sequencer").Track
local Step = require("sequencer").Step
local MathOps = require("mathops")

local Scenario = {}

Scenario.name = "09_full_stack_performance"
Scenario.description = "Multi-track performance blend of direction, ratchet, clock division"
Scenario.defaultPulses = 32

function Scenario.build(helpers)
    local engine = helpers.newEngine(2, 120, 4)
    local t1 = engine.tracks[1]
    local t2 = engine.tracks[2]

    Track.addPattern(t1, 8)
    Track.setStep(t1, 1, Step.new(60, 100, 2, 1, true))
    Track.setStep(t1, 2, Step.new(63, 95, 2, 1, false))
    Track.setStep(t1, 3, Step.new(67, 100, 2, 1, true))
    Track.setStep(t1, 4, Step.new(70, 90, 2, 1, false))
    Track.setStep(t1, 5, Step.new(67, 95, 2, 1, false))
    Track.setStep(t1, 6, Step.new(63, 90, 2, 1, true))
    Track.setStep(t1, 7, Step.new(60, 100, 2, 1, false))
    Track.setStep(t1, 8, Step.new(58, 85, 2, 0, false))
    Track.setDirection(t1, "pingpong")

    Track.addPattern(t2, 8)
    Track.setStep(t2, 1, Step.new(48, 95, 2, 1, false))
    Track.setStep(t2, 2, Step.new(50, 90, 2, 1, false))
    Track.setStep(t2, 3, Step.new(52, 85, 2, 1, false))
    Track.setStep(t2, 4, Step.new(53, 80, 2, 0, false))
    Track.setStep(t2, 5, Step.new(55, 90, 2, 1, false))
    Track.setStep(t2, 6, Step.new(53, 85, 2, 1, false))
    Track.setStep(t2, 7, Step.new(52, 80, 2, 1, false))
    Track.setStep(t2, 8, Step.new(50, 75, 2, 0, false))
    Track.setClockDiv(t2, 2)
    Track.setDirection(t2, "reverse")
    Track.setMidiChannel(t1, 1)
    Track.setMidiChannel(t2, 2)

    MathOps.transpose(t2, 12)

    return engine
end

function Scenario.assert(helpers, result)
    assert(result.noteOnCount > 20, "full stack should emit many NOTE_ON events")
    -- NOTE_OFFs are wall-clock driven; skip count assertion in synchronous test loops.
    local hasTrack2 = false
    for pulse = 1, #result.eventsPerPulse do
        local events = result.eventsPerPulse[pulse]
        for i = 1, #events do
            if events[i].channel == 2 then
                hasTrack2 = true
            end
        end
    end
    assert(hasTrack2, "expected track 2 events in full stack scenario")
end

return Scenario
