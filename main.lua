-- main.lua
-- Dev harness: runs the sequencer engine + player and pipes MIDI events
-- to bridge.py via the line protocol.
--
-- Usage:
--   lua main.lua | python3 bridge.py
--
-- In Ableton: Preferences → MIDI → enable "Sequencer" as MIDI input.
-- Route MIDI channel 1 to a bass/lead instrument, channel 2 to a pad/chord.
--
-- Sequence layout:
--   Track 1 (ch 1) — C minor pentatonic bass line, 2 patterns × 8 steps
--   Track 2 (ch 2) — chord stabs, 2 patterns × 4 steps, half-speed (clockDiv=2)

local uv     = require("luv")
local Engine = require("sequencer/engine")
local Player = require("player/player")
local Track  = require("sequencer/track")
local Step   = require("sequencer/step")
-- @dev
local Tui    = require("tui")
-- @end

-- ── Constants ─────────────────────────────────────────────────────────────────

local BPM             = 120
local PULSES_PER_BEAT = 4   -- 4 pulses per beat → 16th-note grid
-- @dev
local ENABLE_TICK_TRACE = true
-- @end

-- ── Engine (data / sequencer) ──────────────────────────────────────────────────

local engine      = Engine.new(BPM, PULSES_PER_BEAT, 2, 0)
local trackBass   = Engine.getTrack(engine, 1)
local trackChords = Engine.getTrack(engine, 2)

Track.setMidiChannel(trackBass, 1)
Track.setMidiChannel(trackChords, 2)

-- ── Track 1 — bass line ───────────────────────────────────────────────────────
-- C minor pentatonic: C3=48  Eb3=51  F3=53  G3=55  Bb3=58
local patBassA = Track.addPattern(trackBass, 8)  -- noqa: unused var (pattern built via setStep)
local patBassB = Track.addPattern(trackBass, 8)  -- noqa

-- Pattern A — slow melodic descent
Track.setStep(trackBass,  1, Step.new(58, 100, 4, 3))
Track.setStep(trackBass,  2, Step.new(55,  90, 4, 3))
Track.setStep(trackBass,  3, Step.new(53,  95, 4, 3))
Track.setStep(trackBass,  4, Step.new(51,  85, 4, 3))
Track.setStep(trackBass,  5, Step.new(48, 100, 4, 3))
Track.setStep(trackBass,  6, Step.new(51,  80, 4, 2))
Track.setStep(trackBass,  7, Step.new(53,  90, 4, 3))
Track.setStep(trackBass,  8, Step.new(55,  70, 4, 0))

-- Pattern B — syncopated groove (flat indices 9–16)
Track.setStep(trackBass,  9, Step.new(48, 100, 2, 2))
Track.setStep(trackBass, 10, Step.new(48,  80, 2, 1, 2))
Track.setStep(trackBass, 11, Step.new(55, 100, 4, 3))
Track.setStep(trackBass, 12, Step.new(53,  90, 2, 2))
Track.setStep(trackBass, 13, Step.new(51,  85, 2, 1, 2))
Track.setStep(trackBass, 14, Step.new(53,  95, 4, 3))
Track.setStep(trackBass, 15, Step.new(48,  75, 2, 2))
Track.setStep(trackBass, 16, Step.new(48, 100, 2, 0))

Track.setLoopStart(trackBass, Track.patternStartIndex(trackBass, 2))
Track.setLoopEnd(trackBass,   Track.patternEndIndex(trackBass, 2))

-- ── Track 2 — chord stabs ─────────────────────────────────────────────────────
Track.setClockDiv(trackChords, 2)
Track.setDirection(trackChords, "pingpong")

local patChordsA = Track.addPattern(trackChords, 4)  -- noqa
local patChordsB = Track.addPattern(trackChords, 4)  -- noqa

Track.setStep(trackChords, 1, Step.new(60, 80, 4, 3))
Track.setStep(trackChords, 2, Step.new(60, 75, 4, 3))
Track.setStep(trackChords, 3, Step.new(67, 80, 4, 3))
Track.setStep(trackChords, 4, Step.new(63, 70, 4, 2))

Track.setStep(trackChords, 5, Step.new(60, 90, 2, 2))
Track.setStep(trackChords, 6, Step.new(63, 85, 2, 1))
Track.setStep(trackChords, 7, Step.new(67, 90, 4, 3))
Track.setStep(trackChords, 8, Step.new(70, 80, 4, 0))

-- ── Player (MIDI / playback) ───────────────────────────────────────────────────

local player = Player.new(engine, BPM, uv.now)
Player.setSwing(player, 56)
Player.setScale(player, "minorPentatonic", 0)
Player.start(player)

-- ── MIDI emit helpers ─────────────────────────────────────────────────────────

local function emitNoteOn(pitch, velocity, channel)
    io.write("NOTE_ON " .. pitch .. " " .. velocity .. " " .. channel .. "\n")
end

local function emitNoteOff(pitch, channel)
    io.write("NOTE_OFF " .. pitch .. " " .. channel .. "\n")
end

local function onMidiEvent(event)
    if event.type == "NOTE_ON" then
        emitNoteOn(event.pitch, event.velocity, event.channel)
    elseif event.type == "NOTE_OFF" then
        emitNoteOff(event.pitch, event.channel)
    end
end

local function flushAllNotes()
    local offEvents = Player.allNotesOff(player)
    for _, event in ipairs(offEvents) do
        emitNoteOff(event.pitch, event.channel)
    end
    io.flush()
end

-- ── Timer ─────────────────────────────────────────────────────────────────────

local intervalMs = math.floor(player.pulseIntervalMs)
local timer      = uv.new_timer()

local sigint = uv.new_signal()
uv.signal_start(sigint, "sigint", function()
    io.stderr:write("[main] SIGINT received — flushing notes and exiting\n")
    flushAllNotes()
    uv.timer_stop(timer)
    uv.stop()
end)

uv.timer_start(timer, 0, intervalMs, function()
    -- @dev
    local pulseCount = player.pulseCount + 1  -- peek ahead for trace (tick increments it)
    -- @end

    Player.tick(player, onMidiEvent)

    -- @dev
    if ENABLE_TICK_TRACE then
        io.stderr:write(Tui.renderTickTrace(engine, pulseCount, {}) .. "\n")
    end
    if pulseCount % engine.pulsesPerBeat == 0 then
        io.stderr:write(Tui.render(engine, pulseCount, {}) .. "\n")
        io.stderr:flush()
    end
    -- @end

    io.flush()
end)

uv.run()
