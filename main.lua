-- main.lua
-- Dev harness: runs the sequencer engine and pipes MIDI events to bridge.py.
--
-- Usage:
--   lua main.lua | python3 bridge.py
--
-- In Ableton: Preferences → MIDI → enable "Sequencer" as MIDI input.

local uv              = require("luv")
local Engine          = require("sequencer/engine")
local Track           = require("sequencer/track")
local Step            = require("sequencer/step")

-- ── Sequence setup ────────────────────────────────────────────────────────────

local BPM             = 120
local PULSES_PER_BEAT = 4 -- clock resolution: 4 pulses per beat (16th-note grid)
local MIDI_CHANNEL    = 1

local engine          = Engine.new(BPM, PULSES_PER_BEAT, 1, 8)
local track           = Engine.getTrack(engine, 1)

-- C minor pentatonic: C3 D# F G A# (MIDI 48 51 53 55 58)
Track.setStep(track, 1, Step.new(48, 100, 4, 3))
Track.setStep(track, 2, Step.new(51, 90, 4, 2))
Track.setStep(track, 3, Step.new(53, 95, 4, 3))
Track.setStep(track, 4, Step.new(55, 85, 4, 2))
Track.setStep(track, 5, Step.new(58, 100, 4, 3))
Track.setStep(track, 6, Step.new(55, 80, 4, 2))
Track.setStep(track, 7, Step.new(53, 90, 4, 3))
Track.setStep(track, 8, Step.new(48, 70, 4, 0))  -- rest

-- ── Emit helpers ─────────────────────────────────────────────────────────────

local function emitNoteOn(pitch, velocity, channel)
    io.write("NOTE_ON " .. pitch .. " " .. velocity .. " " .. channel .. "\n")
    io.flush()
end

local function emitNoteOff(pitch, channel)
    io.write("NOTE_OFF " .. pitch .. " " .. channel .. "\n")
    io.flush()
end

-- ── Timer ────────────────────────────────────────────────────────────────────

local intervalMs = math.floor(engine.pulseIntervalMs)

local timer = uv.new_timer()
uv.timer_start(timer, 0, intervalMs, function()
    local events = Engine.tick(engine)
    for _, event in ipairs(events) do
        if event.type == "NOTE_ON" then
            emitNoteOn(event.pitch, event.velocity, event.channel)
        elseif event.type == "NOTE_OFF" then
            emitNoteOff(event.pitch, event.channel)
        end
    end
end)

uv.run()
