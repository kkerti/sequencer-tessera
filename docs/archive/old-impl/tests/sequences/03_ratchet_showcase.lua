require("authoring")
local Track = require("sequencer").Track
local Step = require("sequencer").Step

local Scenario = {}

Scenario.name = "03_ratchet_showcase"
Scenario.description = "Ratchet groove with boolean per-step ratchet flag (ER-101 style)"
Scenario.defaultPulses = 32

function Scenario.build(helpers)
    local engine = helpers.newEngine(1, 120, 4)
    local track = engine.tracks[1]

    Track.addPattern(track, 8)

    -- Straight hit (ratch=false): single ON at pulse 0 of the step.
    Track.setStep(track, 1, Step.new(60, 100, 4, 1, false))
    -- Ratcheted (ratch=true, dur=4, gate=1): ON,OFF,ON,OFF inside the step.
    Track.setStep(track, 2, Step.new(67, 100, 4, 1, true))
    -- Ratcheted with gate=1, dur=4 — same period.
    Track.setStep(track, 3, Step.new(70, 95, 4, 1, true))
    -- Ratcheted accent.
    Track.setStep(track, 4, Step.new(72, 95, 4, 1, true))
    -- Straight notes for contrast.
    Track.setStep(track, 5, Step.new(67, 90, 4, 1, false))
    -- Ratcheted lower note accent.
    Track.setStep(track, 6, Step.new(55, 100, 4, 1, true))
    -- Rest for breathing room.
    Track.setStep(track, 7, Step.new(60, 100, 4, 0, false))
    -- Final ratchet burst.
    Track.setStep(track, 8, Step.new(72, 100, 4, 1, true))

    return engine
end

function Scenario.assert(helpers, result)
    local onCount = result.noteOnCount

    -- Each ratcheted step (steps 2,3,4,6,8 = 5 steps) emits 2 NOTE_ONs (at
    -- pulses 0 and 2 within the step's 4-pulse duration). The 3 non-rest
    -- straight steps emit 1 NOTE_ON each. Step 7 is a rest. Across 32 pulses
    -- = 8 steps, expect 5*2 + 3*1 = 13 NOTE_ONs.
    assert(onCount >= 12,
        "ratchet groove should produce dense NOTE_ONs, got " .. onCount)

    -- Find a same-pitch NOTE_ON pair separated by exactly 2 pulses (the
    -- ratchet period when gate=1: ON at pulse N, OFF at N+1, ON at N+2).
    local hasRatchetPair = false
    for pulse = 1, #result.eventsPerPulse - 2 do
        local cur = result.eventsPerPulse[pulse]
        local nxt = result.eventsPerPulse[pulse + 2]
        local cPitch, nPitch = nil, nil
        for i = 1, #cur do
            if cur[i].type == "NOTE_ON" then cPitch = cur[i].pitch break end
        end
        for i = 1, #nxt do
            if nxt[i].type == "NOTE_ON" then nPitch = nxt[i].pitch break end
        end
        if cPitch ~= nil and cPitch == nPitch then
            hasRatchetPair = true
            break
        end
    end

    assert(hasRatchetPair,
        "ratchet should create same-pitch NOTE_ON pairs 2 pulses apart")
end

return Scenario
