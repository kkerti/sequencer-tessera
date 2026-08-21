local Engine = require("sequencer").Engine

local Helpers = {}

function Helpers.newEngine(trackCount, bpm, pulsesPerBeat)
    trackCount = trackCount or 1
    bpm = bpm or 120
    pulsesPerBeat = pulsesPerBeat or 4
    return Engine.new(bpm, pulsesPerBeat, trackCount, 0)
end

function Helpers.noteOnPitches(events, channel)
    local pitches = {}
    for i = 1, #events do
        local event = events[i]
        if event.type == "NOTE_ON" and (channel == nil or event.channel == channel) then
            pitches[#pitches + 1] = event.pitch
        end
    end
    return pitches
end

function Helpers.countType(eventsPerPulse, eventType, channel)
    local count = 0
    for pulse = 1, #eventsPerPulse do
        local events = eventsPerPulse[pulse]
        for i = 1, #events do
            local event = events[i]
            if event.type == eventType and (channel == nil or event.channel == channel) then
                count = count + 1
            end
        end
    end
    return count
end

return Helpers
