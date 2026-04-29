-- driver/driver.lua
-- Drives an Engine in real time and routes the resulting (cvA, cvB, gate)
-- stream through MidiTranslate to produce NOTE_ON / NOTE_OFF events.
--
-- This is a *driver* (not a player): it does not own the music. The Engine
-- is the music. The Driver just decides *when* to advance the engine and
-- routes its outputs to MIDI.
--
-- Two clock modes (mutually exclusive):
--   1. Internal (software) clock — call Driver.tick(d, emit) on a timer;
--      derives elapsed pulses from clockFn() and fires that many engine pulses.
--   2. External clock (e.g. MIDI 0xF8 → divided down to engine.pulsesPerBeat) —
--      call Driver.externalPulse(d, emit) once per engine pulse.
--
-- Per pulse, for each track:
--   1. Sample the track:    cvA, cvB, gate = Engine.sampleTrack(eng, i)
--   2. Translate to MIDI:   MidiTranslate.step(state, cvA, cvB, gate, ch, emit)
--   3. Advance the engine:  Engine.advanceTrack(eng, i)
--
-- Sample-then-advance keeps the present pulse readable to the translator
-- (matches Track.sample / Track.advance contract).
--
-- Emit callback signature: emit(kind, pitch, velocity, channel)
--   kind: "NOTE_ON" | "NOTE_OFF"
--   velocity: nil for NOTE_OFF
--
-- Runtime knobs:
--   Driver.setBpm(d, bpm)      -- internal-clock mode only

local Engine        = require("sequencer/engine")
local MidiTranslate = require("sequencer/midi_translate")

local Driver = {}

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

-- engine   : Engine instance (already loaded with patches)
-- clockFn  : function() returning monotonic milliseconds (internal clock only)
-- bpm      : optional BPM override (defaults to engine.bpm)
function Driver.new(engine, clockFn, bpm)
    bpm = bpm or engine.bpm
    local translators = {}
    for i = 1, engine.trackCount do
        translators[i] = MidiTranslate.new()
    end
    return {
        engine      = engine,
        clockFn     = clockFn,
        bpm         = bpm,
        pulseMs     = Engine.bpmToMs(bpm, engine.pulsesPerBeat),
        translators = translators,
        startMs     = 0,
        pulseCount  = 0,
        running     = false,
    }
end

-- ---------------------------------------------------------------------------
-- Transport
-- ---------------------------------------------------------------------------

function Driver.start(d)
    if d.clockFn then d.startMs = d.clockFn() end
    d.pulseCount = 0
    d.running    = true
end

function Driver.stop(d)
    d.running = false
end

-- Sets BPM at runtime, preserving current pulse position so playback doesn't
-- jump. Only meaningful for internal-clock mode (Driver.tick).
function Driver.setBpm(d, bpm)
    d.bpm     = bpm
    d.pulseMs = Engine.bpmToMs(bpm, d.engine.pulsesPerBeat)
    if d.clockFn then
        d.startMs = d.clockFn() - d.pulseCount * d.pulseMs
    end
end

-- Emits NOTE_OFF for every track that currently holds a note. Call on stop.
function Driver.allNotesOff(d, emit)
    local engine = d.engine
    for i = 1, engine.trackCount do
        local track   = engine.tracks[i]
        local channel = track.midiChannel or 1
        MidiTranslate.panic(d.translators[i], channel, emit)
    end
end

-- ---------------------------------------------------------------------------
-- External-clock entry point
-- ---------------------------------------------------------------------------

-- Advances every track by the appropriate number of engine pulses for one
-- driver pulse. Per-track clock division/multiplication is applied here
-- (the driver pulse is the master clock; each track may consume more or
-- fewer engine pulses per master pulse).
function Driver.externalPulse(d, emit)
    if not d.running then return end
    d.pulseCount = d.pulseCount + 1

    local engine = d.engine
    for i = 1, engine.trackCount do
        local track   = engine.tracks[i]
        local channel = track.midiChannel or 1

        -- Per-track clock div/mult: integer-ratio accumulator.
        track.clockAccum = track.clockAccum + track.clockMult
        local advanceCount = math.floor(track.clockAccum / track.clockDiv)
        track.clockAccum = track.clockAccum % track.clockDiv

        for _ = 1, advanceCount do
            local cvA, cvB, gate = Engine.sampleTrack(engine, i)
            MidiTranslate.step(d.translators[i], cvA, cvB, gate, channel, emit)
            Engine.advanceTrack(engine, i)
        end
    end

    -- Engine-level per-pulse hook (scene chains in full engine, no-op in lite).
    Engine.onPulse(engine, d.pulseCount)
end

-- ---------------------------------------------------------------------------
-- Internal-clock entry point
-- ---------------------------------------------------------------------------

-- Called once per firmware timer callback in software-clock mode.
-- Derives the target pulse from clockFn() and fires pulses up to it.
function Driver.tick(d, emit)
    if not d.running then return end
    local target = math.floor((d.clockFn() - d.startMs) / d.pulseMs)
    while d.pulseCount < target do
        Driver.externalPulse(d, emit)
        if not d.running then return end
    end
end

return Driver
