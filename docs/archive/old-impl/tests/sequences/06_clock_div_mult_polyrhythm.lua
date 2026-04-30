require("authoring")
local Track = require("sequencer").Track
local Step = require("sequencer").Step

local Scenario = {}

Scenario.name = "06_clock_div_mult_polyrhythm"
Scenario.description = "Bass at base clock + melody at x2 for clear polyrhythm"
Scenario.defaultPulses = 24

function Scenario.build(helpers)
    local engine = helpers.newEngine(2, 120, 4)
    local t1 = engine.tracks[1]
    local t2 = engine.tracks[2]

    -- Bass pulse (channel 1)
    Track.addPattern(t1, 4)
    Track.setStep(t1, 1, Step.new(48, 110, 2, 1))
    Track.setStep(t1, 2, Step.new(55, 100, 2, 1))
    Track.setStep(t1, 3, Step.new(48, 110, 2, 1))
    Track.setStep(t1, 4, Step.new(58, 95, 2, 1))

    -- Counter melody (channel 2), twice as fast
    Track.addPattern(t2, 3)
    Track.setStep(t2, 1, Step.new(72, 90, 1, 1))
    Track.setStep(t2, 2, Step.new(74, 85, 1, 1))
    Track.setStep(t2, 3, Step.new(77, 80, 1, 1))
    Track.setClockMult(t2, 2)

    Track.setMidiChannel(t1, 1)
    Track.setMidiChannel(t2, 2)

    return engine
end

function Scenario.assert(helpers, result)
    local t1On = 0
    local t2On = 0
    for pulse = 1, #result.eventsPerPulse do
        local events = result.eventsPerPulse[pulse]
        for i = 1, #events do
            local event = events[i]
            if event.type == "NOTE_ON" and event.channel == 1 then t1On = t1On + 1 end
            if event.type == "NOTE_ON" and event.channel == 2 then t2On = t2On + 1 end
        end
    end
    assert(t2On > t1On, "multiplied track should emit more NOTE_ON events")
end

return Scenario
