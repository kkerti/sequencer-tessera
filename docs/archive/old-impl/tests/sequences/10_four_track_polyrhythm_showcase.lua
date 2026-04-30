require("authoring")
local Track = require("sequencer").Track
local Step = require("sequencer").Step
local MathOps = require("mathops")

local Scenario = {}

Scenario.name = "10_four_track_polyrhythm_showcase"
Scenario.description = "4-track performance demo: polyrhythm + direction + ratchet"
Scenario.defaultPulses = 48

function Scenario.build(helpers)
    local engine = helpers.newEngine(4, 118, 4)

    local t1 = engine.tracks[1] -- bass
    local t2 = engine.tracks[2] -- lead
    local t3 = engine.tracks[3] -- arp/chords
    local t4 = engine.tracks[4] -- percussion-like accents

    -- Track channels (so Ableton can route each track separately)
    Track.setMidiChannel(t1, 1)
    Track.setMidiChannel(t2, 2)
    Track.setMidiChannel(t3, 3)
    Track.setMidiChannel(t4, 10)

    -- ---------------------------------------------------------------------
    -- T1: bass loop, forward, medium density, loop points on pattern 2
    -- ---------------------------------------------------------------------
    Track.addPattern(t1, 4)
    Track.addPattern(t1, 4)

    -- intro
    Track.setStep(t1, 1, Step.new(36, 115, 2, 1, false))
    Track.setStep(t1, 2, Step.new(39, 105, 2, 1, false))
    Track.setStep(t1, 3, Step.new(43, 105, 2, 1, false))
    Track.setStep(t1, 4, Step.new(46, 100, 2, 1, false))
    -- groove
    Track.setStep(t1, 5, Step.new(36, 120, 1, 1, false))
    Track.setStep(t1, 6, Step.new(43, 110, 1, 1, false))
    Track.setStep(t1, 7, Step.new(46, 110, 1, 1, false))
    Track.setStep(t1, 8, Step.new(43, 95, 1, 0, false))

    Track.setLoopStart(t1, 5)
    Track.setLoopEnd(t1, 8)

    -- ---------------------------------------------------------------------
    -- T2: lead, pingpong direction, ratchet accents
    -- ---------------------------------------------------------------------
    Track.addPattern(t2, 8)
    Track.setDirection(t2, "pingpong")

    Track.setStep(t2, 1, Step.new(60, 95, 2, 1, false))
    Track.setStep(t2, 2, Step.new(63, 90, 2, 1, true))
    Track.setStep(t2, 3, Step.new(67, 95, 2, 1, false))
    Track.setStep(t2, 4, Step.new(70, 90, 2, 1, true))
    Track.setStep(t2, 5, Step.new(67, 92, 2, 1, false))
    Track.setStep(t2, 6, Step.new(63, 88, 2, 1, true))
    Track.setStep(t2, 7, Step.new(60, 95, 2, 1, false))
    Track.setStep(t2, 8, Step.new(58, 80, 2, 0, false))

    -- ---------------------------------------------------------------------
    -- T3: slower harmonic movement (clockDiv=3), reverse direction
    -- ---------------------------------------------------------------------
    Track.addPattern(t3, 6)
    Track.setClockDiv(t3, 3)
    Track.setDirection(t3, "reverse")

    Track.setStep(t3, 1, Step.new(48, 88, 4, 2, false))
    Track.setStep(t3, 2, Step.new(55, 86, 4, 2, false))
    Track.setStep(t3, 3, Step.new(58, 84, 4, 2, false))
    Track.setStep(t3, 4, Step.new(60, 82, 4, 2, false))
    Track.setStep(t3, 5, Step.new(58, 84, 4, 2, false))
    Track.setStep(t3, 6, Step.new(55, 86, 4, 2, false))

    -- ---------------------------------------------------------------------
    -- T4: fast accents/percussion-like lane (clockMult=2 + random ratchets)
    -- ---------------------------------------------------------------------
    Track.addPattern(t4, 8)
    Track.setClockMult(t4, 2)
    Track.setDirection(t4, "forward")

    Track.setStep(t4, 1, Step.new(72, 80, 1, 1, false))
    Track.setStep(t4, 2, Step.new(74, 75, 1, 1, false))
    Track.setStep(t4, 3, Step.new(77, 70, 1, 1, false))
    Track.setStep(t4, 4, Step.new(79, 68, 1, 1, false))
    Track.setStep(t4, 5, Step.new(77, 72, 1, 1, false))
    Track.setStep(t4, 6, Step.new(74, 76, 1, 1, false))
    Track.setStep(t4, 7, Step.new(72, 82, 1, 1, false))
    Track.setStep(t4, 8, Step.new(70, 66, 1, 0, false))

    math.randomseed(4242)
    -- Ratchet is now a boolean ER-101-style flag; toggle a couple of steps on
    -- to add fast accents on track 4.
    Track.setStep(t4, 2, Step.setRatch(Track.getStep(t4, 2), true))
    Track.setStep(t4, 5, Step.setRatch(Track.getStep(t4, 5), true))

    return engine
end

function Scenario.assert(helpers, result)
    local noteOnByChannel = { [1] = 0, [2] = 0, [3] = 0, [10] = 0 }

    for pulse = 1, #result.eventsPerPulse do
        local events = result.eventsPerPulse[pulse]
        for i = 1, #events do
            local event = events[i]
            if event.type == "NOTE_ON" and noteOnByChannel[event.channel] ~= nil then
                noteOnByChannel[event.channel] = noteOnByChannel[event.channel] + 1
            end
        end
    end

    assert(noteOnByChannel[1] > 6, "track 1 should be active")
    assert(noteOnByChannel[2] > 8, "track 2 should be active with ratchet accents")
    assert(noteOnByChannel[3] > 2, "track 3 should be active at slower clock")
    assert(noteOnByChannel[10] > noteOnByChannel[1], "track 4 should be densest due clockMult=2")
end

return Scenario
