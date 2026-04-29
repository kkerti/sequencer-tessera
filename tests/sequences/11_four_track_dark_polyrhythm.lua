local Track = require("sequencer/track")
local Step = require("sequencer/step")
local MathOps = require("sequencer/mathops")

local Scenario = {}

Scenario.name = "11_four_track_dark_polyrhythm"
Scenario.description = "4-track dark scene: minor harmony, sparse-heavy contrast"
Scenario.defaultPulses = 64

function Scenario.build(helpers)
    local engine = helpers.newEngine(4, 102, 4)

    local t1 = engine.tracks[1] -- sub bass drone pulse
    local t2 = engine.tracks[2] -- ominous lead fragments
    local t3 = engine.tracks[3] -- slow reversed harmonic anchor
    local t4 = engine.tracks[4] -- metallic/percussive accents

    Track.setMidiChannel(t1, 1)
    Track.setMidiChannel(t2, 2)
    Track.setMidiChannel(t3, 3)
    Track.setMidiChannel(t4, 10)

    -- ---------------------------------------------------------------------
    -- T1: deep bass with looped low-end motif
    -- C harm. minor in octave 1: C1=24 D1=26 Eb1=27 F1=29 G1=31 Ab1=32 B1=35
    -- ---------------------------------------------------------------------
    Track.addPattern(t1, 8)
    Track.setStep(t1, 1, Step.new(31, 118, 2, 1, false))  -- G1
    Track.setStep(t1, 2, Step.new(31, 114, 2, 1, false))  -- G1
    Track.setStep(t1, 3, Step.new(32, 110, 2, 1, false))  -- Ab1
    Track.setStep(t1, 4, Step.new(35, 108, 2, 1, false))  -- B1
    Track.setStep(t1, 5, Step.new(31, 120, 2, 1, false))  -- G1
    Track.setStep(t1, 6, Step.new(29, 112, 2, 1, false))  -- F1
    Track.setStep(t1, 7, Step.new(31, 116, 2, 1, false))  -- G1
    Track.setStep(t1, 8, Step.new(32, 100, 2, 0, false))  -- Ab1 rest
    Track.setLoopStart(t1, 3)
    Track.setLoopEnd(t1, 8)

    -- ---------------------------------------------------------------------
    -- T2: sparse lead with ratchet stabs and pingpong motion
    -- C harm. minor in octave 3-4: G3=55 B3=59 C4=60 Eb3=51 F4=65
    -- ---------------------------------------------------------------------
    Track.addPattern(t2, 8)
    Track.setDirection(t2, "pingpong")

    Track.setStep(t2, 1, Step.new(55, 88, 2, 1, false))   -- G3
    Track.setStep(t2, 2, Step.new(59, 86, 2, 1, true))   -- B3
    Track.setStep(t2, 3, Step.new(60, 82, 2, 1, false))   -- C4
    Track.setStep(t2, 4, Step.new(65, 84, 2, 1, true))   -- F4
    Track.setStep(t2, 5, Step.new(60, 82, 2, 1, false))   -- C4
    Track.setStep(t2, 6, Step.new(59, 86, 2, 1, true))   -- B3
    Track.setStep(t2, 7, Step.new(55, 88, 2, 1, false))   -- G3
    Track.setStep(t2, 8, Step.new(51, 76, 2, 0, false))   -- Eb3 rest

    -- ---------------------------------------------------------------------
    -- T3: very slow reverse progression, gives dark bed
    -- C harm. minor in octave 2-3: G2=43 B2=47 C3=48 F3=53
    -- ---------------------------------------------------------------------
    Track.addPattern(t3, 6)
    Track.setClockDiv(t3, 4)
    Track.setDirection(t3, "reverse")

    Track.setStep(t3, 1, Step.new(43, 78, 6, 3, false))   -- G2
    Track.setStep(t3, 2, Step.new(47, 76, 6, 3, false))   -- B2
    Track.setStep(t3, 3, Step.new(48, 74, 6, 3, false))   -- C3
    Track.setStep(t3, 4, Step.new(53, 72, 6, 3, false))   -- F3
    Track.setStep(t3, 5, Step.new(48, 74, 6, 3, false))   -- C3
    Track.setStep(t3, 6, Step.new(47, 76, 6, 3, false))   -- B2

    -- ---------------------------------------------------------------------
    -- T4: off-grid metallic lane, fast and jittery
    -- C harm. minor in octave 4-5: Eb4=63 F4=65 G4=67 B4=71 C5=72
    -- ---------------------------------------------------------------------
    Track.addPattern(t4, 8)
    Track.setClockMult(t4, 2)
    Track.setDirection(t4, "forward")

    Track.setStep(t4, 1, Step.new(72, 72, 1, 1, false))   -- C5
    Track.setStep(t4, 2, Step.new(71, 68, 1, 1, false))   -- B4
    Track.setStep(t4, 3, Step.new(67, 70, 1, 1, false))   -- G4
    Track.setStep(t4, 4, Step.new(65, 66, 1, 1, false))   -- F4
    Track.setStep(t4, 5, Step.new(63, 70, 1, 1, false))   -- Eb4
    Track.setStep(t4, 6, Step.new(65, 66, 1, 1, false))   -- F4
    Track.setStep(t4, 7, Step.new(67, 70, 1, 1, false))   -- G4
    Track.setStep(t4, 8, Step.new(71, 62, 1, 0, false))   -- B4 rest

    math.randomseed(1111)
    -- Boolean ratchet: enable a single step's ratch flag for stab accent.
    Track.setStep(t4, 3, Step.setRatch(Track.getStep(t4, 3), true))
    MathOps.jitter(t4, "velocity", 6)

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

    assert(noteOnByChannel[1] > 8, "dark bass lane should be active")
    assert(noteOnByChannel[2] > 10, "dark lead lane should be active")
    assert(noteOnByChannel[3] >= 2, "slow harmonic lane should still appear")
    assert(noteOnByChannel[10] > noteOnByChannel[1], "accent lane should stay denser than bass")
end

return Scenario
