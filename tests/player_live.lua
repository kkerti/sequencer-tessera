-- tests/player_live.lua
-- Live playback test: routes MIDI through bridge.py to Ableton.
-- This is a MANUAL test — it produces audio. Not part of automated CI.
--
-- Usage:
--   lua tests/player_live.lua | python3 bridge.py
--
-- Plays a 4-bar C minor pentatonic phrase at 120 BPM on channel 1.
-- Listen in Ableton on the "Sequencer" virtual MIDI port.
-- Press Ctrl+C to stop cleanly.
--
-- What to listen for:
--   - Smooth gate lengths (wall-clock driven, not pulse-counter driven)
--   - Swing feel at 56% on the bass pattern
--   - Notes quantized to C minor pentatonic scale

local uv     = require("luv")
local Engine = require("sequencer/engine")
local Player = require("player/player")
local Track  = require("sequencer/track")
local Step   = require("sequencer/step")

-- ── Sequence ──────────────────────────────────────────────────────────────────

local engine = Engine.new(120, 4, 1, 0)
local track  = Engine.getTrack(engine, 1)
Track.setMidiChannel(track, 1)

-- 8-step C minor pentatonic groove
Track.addPattern(track, 8)
Track.setStep(track, 1, Step.new(48, 100, 4, 3))   -- C3
Track.setStep(track, 2, Step.new(51,  90, 4, 3))   -- Eb3
Track.setStep(track, 3, Step.new(53,  95, 4, 3))   -- F3
Track.setStep(track, 4, Step.new(55,  85, 2, 2))   -- G3 eighth
Track.setStep(track, 5, Step.new(55,  80, 2, 1, 2)) -- G3 ratchet
Track.setStep(track, 6, Step.new(53,  90, 4, 3))   -- F3
Track.setStep(track, 7, Step.new(51,  85, 4, 3))   -- Eb3
Track.setStep(track, 8, Step.new(48, 100, 4, 0))   -- C3 rest

local player = Player.new(engine, 120, uv.now)
Player.setSwing(player, 56)
Player.setScale(player, "minorPentatonic", 0)
Player.start(player)

-- ── MIDI emit ─────────────────────────────────────────────────────────────────

local function onMidiEvent(event)
    if event.type == "NOTE_ON" then
        io.write("NOTE_ON "  .. event.pitch .. " " .. event.velocity .. " " .. event.channel .. "\n")
    elseif event.type == "NOTE_OFF" then
        io.write("NOTE_OFF " .. event.pitch .. " " .. event.channel .. "\n")
    end
end

local function flushAll()
    local offs = Player.allNotesOff(player)
    for _, ev in ipairs(offs) do
        io.write("NOTE_OFF " .. ev.pitch .. " " .. ev.channel .. "\n")
    end
    io.flush()
end

-- ── Timer ─────────────────────────────────────────────────────────────────────

local intervalMs = math.floor(player.pulseIntervalMs)
local timer      = uv.new_timer()

local sigint = uv.new_signal()
uv.signal_start(sigint, "sigint", function()
    io.stderr:write("[player_live] SIGINT — flushing notes\n")
    flushAll()
    uv.timer_stop(timer)
    uv.stop()
end)

uv.timer_start(timer, 0, intervalMs, function()
    Player.tick(player, onMidiEvent)
    io.flush()
end)

io.stderr:write("[player_live] running at 120 BPM — Ctrl+C to stop\n")
uv.run()
