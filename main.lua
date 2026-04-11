-- main.lua
-- Dev harness: runs the sequencer engine and pipes MIDI events to bridge.py.
--
-- Usage:
--   lua main.lua | python3 bridge.py
--
-- In Ableton: Preferences → MIDI → enable "Sequencer" as MIDI input.
-- Route MIDI channel 1 to a bass/lead instrument, channel 2 to a pad/chord instrument.
--
-- Sequence layout:
--   Track 1 (ch 1) — C minor pentatonic bass line, 2 patterns × 8 steps
--                    loop points set to pattern 2 after the intro plays once
--   Track 2 (ch 2) — chord stabs, 2 patterns × 4 steps, half-speed (clockDiv=2)

local uv     = require("luv")
local Engine = require("sequencer/engine")
local Track  = require("sequencer/track")
local Step   = require("sequencer/step")
local Tui    = require("tui")

-- ── Engine ────────────────────────────────────────────────────────────────────

local BPM             = 120
local PULSES_PER_BEAT = 4   -- 4 pulses per beat → 16th-note grid
local ENABLE_TICK_TRACE = true
local SHORT_GATE_MS = 45     -- set to 0 to use engine NOTE_OFF timing
local TRACK_1_CHANNEL = 1
local TRACK_2_CHANNEL = 2

-- Engine.new creates tracks with one default pattern each (stepCount used below).
-- We want zero-pattern tracks here so we add patterns manually — pass stepCount=0
-- and then call Track.addPattern explicitly.
local engine          = Engine.new(BPM, PULSES_PER_BEAT, 2, 0)
local trackBass       = Engine.getTrack(engine, 1)
local trackChords     = Engine.getTrack(engine, 2)

Track.setMidiChannel(trackBass, TRACK_1_CHANNEL)
Track.setMidiChannel(trackChords, TRACK_2_CHANNEL)

Engine.setSwing(engine, 56)
Engine.setScale(engine, "minorPentatonic", 0)

-- ── Track 1 — bass line ───────────────────────────────────────────────────────
-- C minor pentatonic: C3=48  Eb3=51  F3=53  G3=55  Bb3=58
-- Pattern A: descending intro phrase (8 steps, each 1 beat = 4 pulses)
local patBassA = Track.addPattern(trackBass, 8)
-- Pattern B: tight repeating groove (8 steps, mix of 8th and 16th note lengths)
local patBassB = Track.addPattern(trackBass, 8)

-- Pattern A — slow melodic descent
Track.setStep(trackBass,  1, Step.new(58, 100, 4, 3))  -- Bb3
Track.setStep(trackBass,  2, Step.new(55,  90, 4, 3))  -- G3
Track.setStep(trackBass,  3, Step.new(53,  95, 4, 3))  -- F3
Track.setStep(trackBass,  4, Step.new(51,  85, 4, 3))  -- Eb3
Track.setStep(trackBass,  5, Step.new(48, 100, 4, 3))  -- C3
Track.setStep(trackBass,  6, Step.new(51,  80, 4, 2))  -- Eb3
Track.setStep(trackBass,  7, Step.new(53,  90, 4, 3))  -- F3
Track.setStep(trackBass,  8, Step.new(55,  70, 4, 0))  -- G3 rest

-- Pattern B — syncopated groove (flat indices 9–16)
Track.setStep(trackBass,  9, Step.new(48, 100, 2, 2))  -- C3  eighth
Track.setStep(trackBass, 10, Step.new(48,  80, 2, 1, 2))  -- C3  eighth staccato ratchet
Track.setStep(trackBass, 11, Step.new(55, 100, 4, 3))  -- G3  quarter
Track.setStep(trackBass, 12, Step.new(53,  90, 2, 2))  -- F3  eighth
Track.setStep(trackBass, 13, Step.new(51,  85, 2, 1, 2))  -- Eb3 eighth staccato ratchet
Track.setStep(trackBass, 14, Step.new(53,  95, 4, 3))  -- F3  quarter
Track.setStep(trackBass, 15, Step.new(48,  75, 2, 2))  -- C3  eighth
Track.setStep(trackBass, 16, Step.new(48, 100, 2, 0))  -- C3  rest / ghost

-- Loop: after pattern A plays once, loop over pattern B only.
local bassLoopStart = Track.patternStartIndex(trackBass, 2)  -- flat index 9
local bassLoopEnd   = Track.patternEndIndex(trackBass, 2)    -- flat index 16
Track.setLoopStart(trackBass, bassLoopStart)
Track.setLoopEnd(trackBass, bassLoopEnd)

-- ── Track 2 — chord stabs ─────────────────────────────────────────────────────
-- Half-speed via clockDiv=2 (one advance per 2 engine pulses → 8th-note resolution)
Track.setClockDiv(trackChords, 2)
Track.setDirection(trackChords, "pingpong")

-- We use single MIDI notes to represent chord roots; the Ableton instrument
-- (e.g. a chord rack or a pad with a chord note effect) handles the voicing.
-- Cm chord tones: C4=60  Eb4=63  G4=67  Bb4=70
-- Pattern A: whole-note pads (4 steps × duration 4, but at half-speed = 1 beat each)
local patChordsA = Track.addPattern(trackChords, 4)
-- Pattern B: broken / arpeggiated stabs
local patChordsB = Track.addPattern(trackChords, 4)

-- Pattern A (flat indices 1–4 on trackChords)
Track.setStep(trackChords, 1, Step.new(60, 80, 4, 3))   -- Cm root
Track.setStep(trackChords, 2, Step.new(60, 75, 4, 3))   -- Cm root
Track.setStep(trackChords, 3, Step.new(67, 80, 4, 3))   -- G (5th)
Track.setStep(trackChords, 4, Step.new(63, 70, 4, 2))   -- Eb (minor 3rd)

-- Pattern B (flat indices 5–8 on trackChords) — more rhythmic
Track.setStep(trackChords, 5, Step.new(60, 90, 2, 2))   -- C  stab
Track.setStep(trackChords, 6, Step.new(63, 85, 2, 1))   -- Eb stab
Track.setStep(trackChords, 7, Step.new(67, 90, 4, 3))   -- G  held
Track.setStep(trackChords, 8, Step.new(70, 80, 4, 0))   -- Bb rest

-- ── Emit helpers ─────────────────────────────────────────────────────────────

local function emitNoteOn(pitch, velocity, channel)
    io.write("NOTE_ON " .. pitch .. " " .. velocity .. " " .. channel .. "\n")
end

local function emitNoteOff(pitch, channel)
    io.write("NOTE_OFF " .. pitch .. " " .. channel .. "\n")
end

local pendingOffTimers = {}

local function scheduleShortNoteOff(pitch, channel)
    if SHORT_GATE_MS <= 0 then
        return
    end

    local timer = uv.new_timer()
    pendingOffTimers[#pendingOffTimers + 1] = timer
    uv.timer_start(timer, SHORT_GATE_MS, 0, function()
        emitNoteOff(pitch, channel)
        io.flush()
        uv.timer_stop(timer)
        timer:close()
    end)
end

-- Cancels all pending short-gate timers and emits NOTE_OFF events for every
-- note the engine currently tracks as sounding.  Call this before reset,
-- stop, or exit to guarantee no hanging MIDI notes remain.
local function flushAllNotes()
    -- 1. Cancel any pending short-gate timers so they don't fire after cleanup
    for _, t in ipairs(pendingOffTimers) do
        if not t:is_closing() then
            uv.timer_stop(t)
            t:close()
        end
    end
    pendingOffTimers = {}

    -- 2. Ask the engine for NOTE_OFF events for all tracked active notes
    local offEvents = Engine.allNotesOff(engine)
    for _, event in ipairs(offEvents) do
        emitNoteOff(event.pitch, event.channel)
    end
    io.flush()
end

-- ── Timer ────────────────────────────────────────────────────────────────────

local intervalMs = math.floor(engine.pulseIntervalMs)
local pulseCount = 0

local timer = uv.new_timer()

-- ── Signal handling — clean shutdown ─────────────────────────────────────────
local sigint = uv.new_signal()
uv.signal_start(sigint, "sigint", function()
    io.stderr:write("[main] SIGINT received — flushing notes and exiting\n")
    flushAllNotes()
    uv.timer_stop(timer)
    uv.stop()
end)

uv.timer_start(timer, 0, intervalMs, function()
    pulseCount = pulseCount + 1
    local events = Engine.tick(engine)

    if ENABLE_TICK_TRACE then
        io.stderr:write(Tui.renderTickTrace(engine, pulseCount, events) .. "\n")
    end

    if pulseCount % engine.pulsesPerBeat == 0 then
        io.stderr:write(Tui.render(engine, pulseCount, events) .. "\n")
        io.stderr:flush()
    end

    for _, event in ipairs(events) do
        if event.type == "NOTE_ON" then
            emitNoteOn(event.pitch, event.velocity, event.channel)
            scheduleShortNoteOff(event.pitch, event.channel)
        elseif event.type == "NOTE_OFF" then
            if SHORT_GATE_MS <= 0 then
                emitNoteOff(event.pitch, event.channel)
            end
        end
    end
    io.flush()
end)

uv.run()
