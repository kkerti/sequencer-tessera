-- sequencer/engine.lua
-- The sequencer engine. Owns one or more tracks and a global clock.
--
-- engineTick() is called once per clock pulse by the host timer (main.lua).
-- It advances all tracks and returns a list of MIDI events to emit.
-- The engine has no knowledge of timers, MIDI libraries, or UI.
--
-- A MIDI event table:
--   { type = "NOTE_ON",  pitch = 60, velocity = 100, channel = 1 }
--   { type = "NOTE_OFF", pitch = 60, velocity = 0,   channel = 1 }

local Track  = require("sequencer/track")
local Step   = require("sequencer/step")

local Engine = {}

-- BPM to pulse interval in milliseconds.
-- pulsesPerBeat is how many clock pulses fit in one beat (default 4).
function Engine.bpmToMs(bpm, pulsesPerBeat)
    pulsesPerBeat = pulsesPerBeat or 4
    assert(type(bpm) == "number" and bpm > 0, "engineBpmToMs: bpm must be positive")
    assert(type(pulsesPerBeat) == "number" and pulsesPerBeat > 0, "engineBpmToMs: pulsesPerBeat must be positive")
    return (60000 / bpm) / pulsesPerBeat
end

-- Creates a new engine.
-- `bpm`           : tempo in beats per minute (default 120)
-- `pulsesPerBeat` : clock resolution (default 4)
-- `trackCount`    : number of tracks (default 1)
-- `stepCount`     : steps per track (default 8)
function Engine.new(bpm, pulsesPerBeat, trackCount, stepCount)
    bpm           = bpm or 120
    pulsesPerBeat = pulsesPerBeat or 4
    trackCount    = trackCount or 1
    stepCount     = stepCount or 8

    assert(type(bpm) == "number" and bpm > 0, "engineNew: bpm must be positive")
    assert(type(pulsesPerBeat) == "number" and pulsesPerBeat > 0, "engineNew: pulsesPerBeat must be positive")
    assert(type(trackCount) == "number" and trackCount > 0, "engineNew: trackCount must be positive")
    assert(type(stepCount) == "number" and stepCount > 0, "engineNew: stepCount must be positive")

    local tracks = {}
    for i = 1, trackCount do
        tracks[i] = Track.new(stepCount)
    end

    return {
        bpm             = bpm,
        pulsesPerBeat   = pulsesPerBeat,
        pulseIntervalMs = Engine.bpmToMs(bpm, pulsesPerBeat),
        tracks          = tracks,
        trackCount      = trackCount,
    }
end

-- Returns the track at 1-based `index`.
function Engine.getTrack(engine, index)
    assert(type(index) == "number" and index >= 1 and index <= engine.trackCount,
        "engineGetTrack: index out of range")
    return engine.tracks[index]
end

-- Sets the BPM and recalculates the pulse interval.
function Engine.setBpm(engine, bpm)
    assert(type(bpm) == "number" and bpm > 0, "engineSetBpm: bpm must be positive")
    engine.bpm = bpm
    engine.pulseIntervalMs = Engine.bpmToMs(bpm, engine.pulsesPerBeat)
end

-- Advances all tracks by one pulse.
-- Returns a list (possibly empty) of MIDI event tables.
function Engine.tick(engine)
    local events = {}

    for trackIndex = 1, engine.trackCount do
        local track = engine.tracks[trackIndex]
        local step  = Track.getCurrentStep(track)
        local event = Track.advance(track)

        if event == "NOTE_ON" then
            events[#events + 1] = {
                type     = "NOTE_ON",
                pitch    = Step.getPitch(step),
                velocity = Step.getVelocity(step),
                channel  = trackIndex,
            }
        elseif event == "NOTE_OFF" then
            events[#events + 1] = {
                type     = "NOTE_OFF",
                pitch    = Step.getPitch(step),
                velocity = 0,
                channel  = trackIndex,
            }
        end
    end

    return events
end

-- Resets all tracks to the start.
function Engine.reset(engine)
    for i = 1, engine.trackCount do
        Track.reset(engine.tracks[i])
    end
end

return Engine
