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
local Utils  = require("utils")
local Performance = require("sequencer/performance")

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
    assert(type(stepCount) == "number" and stepCount >= 0, "engineNew: stepCount must be non-negative")

    local tracks = {}
    for i = 1, trackCount do
        local track = Track.new()
        if stepCount > 0 then
            Track.addPattern(track, stepCount)
        end
        tracks[i] = track
    end

    return {
        bpm             = bpm,
        pulsesPerBeat   = pulsesPerBeat,
        pulseIntervalMs = Engine.bpmToMs(bpm, pulsesPerBeat),
        tracks          = tracks,
        trackCount      = trackCount,
        pulseCount      = 0,
        swingPercent    = 50,
        swingCarry      = 0,
        scaleName       = nil,
        scaleTable      = nil,
        rootNote        = 0,
        running         = true,
        -- Active note tracking: keyed by "pitch:channel", value = true.
        -- Used by allNotesOff() to flush sounding notes on reset/stop.
        activeNotes     = {},
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

function Engine.setSwing(engine, percent)
    assert(type(percent) == "number" and percent >= 50 and percent <= 72,
        "engineSetSwing: percent out of range 50-72")
    engine.swingPercent = percent
end

function Engine.getSwing(engine)
    return engine.swingPercent
end

function Engine.setScale(engine, scaleName, rootNote)
    assert(type(scaleName) == "string", "engineSetScale: scaleName must be a string")
    assert(Utils.SCALES[scaleName] ~= nil, "engineSetScale: unknown scale")
    rootNote = rootNote or 0
    assert(type(rootNote) == "number" and rootNote >= 0 and rootNote <= 11,
        "engineSetScale: rootNote out of range 0-11")

    engine.scaleName = scaleName
    engine.scaleTable = Utils.SCALES[scaleName]
    engine.rootNote = rootNote
end

function Engine.clearScale(engine)
    engine.scaleName = nil
    engine.scaleTable = nil
    engine.rootNote = 0
end

-- Builds a string key for the activeNotes table: "pitch:channel".
local function noteKey(pitch, channel)
    return pitch .. ":" .. channel
end

-- Returns NOTE_OFF events for every note currently tracked as sounding,
-- then clears the activeNotes table.  The caller should emit these events
-- to the MIDI output to avoid hanging notes.
function Engine.allNotesOff(engine)
    local events = {}
    for key, _ in pairs(engine.activeNotes) do
        local pitch, channel = key:match("^(%d+):(%d+)$")
        pitch   = tonumber(pitch)
        channel = tonumber(channel)
        events[#events + 1] = {
            type     = "NOTE_OFF",
            pitch    = pitch,
            velocity = 0,
            channel  = channel,
        }
    end
    engine.activeNotes = {}
    return events
end

-- Advances all tracks by one pulse.
-- Returns a list (possibly empty) of MIDI event tables.
-- Tracks active (sounding) notes so they can be flushed on reset/stop.
function Engine.tick(engine)
    if not engine.running then
        return {}
    end

    engine.pulseCount = engine.pulseCount + 1

    local shouldHoldSwing
    shouldHoldSwing, engine.swingCarry = Performance.nextSwingHold(
        engine.pulseCount,
        engine.pulsesPerBeat,
        engine.swingPercent,
        engine.swingCarry
    )

    if shouldHoldSwing then
        return {}
    end

    local events = {}

    for trackIndex = 1, engine.trackCount do
        local track = engine.tracks[trackIndex]
        track.clockAccum = track.clockAccum + track.clockMult
        local advanceCount = math.floor(track.clockAccum / track.clockDiv)
        track.clockAccum = track.clockAccum % track.clockDiv

        for _ = 1, advanceCount do
            local step = Track.getCurrentStep(track)
            local event = Track.advance(track)

            if event == "NOTE_ON" then
                local channel = track.midiChannel or trackIndex
                local pitch   = Step.resolvePitch(step, engine.scaleTable, engine.rootNote)
                local key     = noteKey(pitch, channel)
                engine.activeNotes[key] = true
                events[#events + 1] = {
                    type     = "NOTE_ON",
                    pitch    = pitch,
                    velocity = Step.getVelocity(step),
                    channel  = channel,
                }
            elseif event == "NOTE_OFF" then
                local channel = track.midiChannel or trackIndex
                local pitch   = Step.resolvePitch(step, engine.scaleTable, engine.rootNote)
                local key     = noteKey(pitch, channel)
                engine.activeNotes[key] = nil
                events[#events + 1] = {
                    type     = "NOTE_OFF",
                    pitch    = pitch,
                    velocity = 0,
                    channel  = channel,
                }
            end
        end
    end

    return events
end

-- Resets all tracks to the start.
-- Returns a list of NOTE_OFF events for any notes that were sounding,
-- so the caller can flush them to MIDI output before restarting.
function Engine.reset(engine)
    local events = Engine.allNotesOff(engine)
    engine.pulseCount = 0
    engine.swingCarry = 0
    engine.running    = true
    for i = 1, engine.trackCount do
        Track.reset(engine.tracks[i])
    end
    return events
end

-- Stops playback and returns NOTE_OFF events for all sounding notes.
-- After calling stop, Engine.tick() becomes a no-op until reset/start.
function Engine.stop(engine)
    local events = Engine.allNotesOff(engine)
    engine.running = false
    return events
end

-- Resumes playback after a stop.
-- Does not reset cursors — playback continues from where it was halted.
function Engine.start(engine)
    engine.running = true
end

return Engine
