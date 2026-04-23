local Track = require("sequencer/track")
local Step = require("sequencer/step")

local Scenario = {}

Scenario.name = "03_ratchet_showcase"
Scenario.description = "Ratchet groove with mixed repeat counts (1-4)"
Scenario.defaultPulses = 32

function Scenario.build(helpers)
    local engine = helpers.newEngine(1, 120, 4)
    local track = engine.tracks[1]

    Track.addPattern(track, 8)

    -- Straight hit
    Track.setStep(track, 1, Step.new(60, 100, 4, 1, 1))
    -- 2-hit ratchet
    Track.setStep(track, 2, Step.new(67, 100, 4, 1, 2))
    -- 3-hit ratchet
    Track.setStep(track, 3, Step.new(70, 95, 4, 1, 3))
    -- 4-hit ratchet (fastest burst)
    Track.setStep(track, 4, Step.new(72, 95, 4, 1, 4))
    -- Back to straight notes so contrast is obvious
    Track.setStep(track, 5, Step.new(67, 90, 4, 1, 1))
    -- Ratcheted lower note accent
    Track.setStep(track, 6, Step.new(55, 100, 4, 1, 2))
    -- Rest for breathing room
    Track.setStep(track, 7, Step.new(60, 100, 4, 0, 1))
    -- Final burst
    Track.setStep(track, 8, Step.new(72, 100, 4, 1, 4))

    return engine
end

function Scenario.assert(helpers, result)
    local onCount = result.noteOnCount

    -- NOTE_ONs are still synchronous pulse-driven events.
    assert(onCount >= 14, "ratchet groove should produce dense NOTE_ON bursts")

    -- NOTE_OFFs are wall-clock driven (os.clock) and will not appear in a
    -- synchronous test loop because gate durations have not elapsed in real time.
    -- Validate NOTE_ON burst density instead of NOTE_OFF count.

    local hasConsecutiveBurst = false
    for pulse = 2, #result.eventsPerPulse do
        local prev = result.eventsPerPulse[pulse - 1]
        local cur = result.eventsPerPulse[pulse]
        if #prev > 0 and #cur > 0 then
            local pPitch = nil
            local cPitch = nil
            for i = 1, #prev do
                if prev[i].type == "NOTE_ON" then pPitch = prev[i].pitch break end
            end
            for i = 1, #cur do
                if cur[i].type == "NOTE_ON" then cPitch = cur[i].pitch break end
            end
            if pPitch ~= nil and cPitch ~= nil and pPitch == cPitch then
                hasConsecutiveBurst = true
            end
        end
    end

    assert(hasConsecutiveBurst, "ratchet should create consecutive-pulse repeats of same pitch")
end

return Scenario
