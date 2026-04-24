-- main_lite.lua
-- Dev harness for the LITE player + compiled song stack.
-- Mirrors what runs on the Grid module, but uses luv as the timer source
-- and emits MIDI via the line protocol consumed by bridge.py.
--
-- Usage:
--   lua main_lite.lua | python3 bridge.py
--
-- In Ableton: Preferences → MIDI → enable "Sequencer" as MIDI input.

local uv     = require("luv")
-- Sidecar arrays live next to the compiled song.
package.path = "compiled/?.lua;" .. package.path
local Player = require("player_lite/player")
local song   = require("compiled/dark_groove")

-- ── Clock + emit ─────────────────────────────────────────────────────────────

local function clockFn() return uv.now() end

local function emit(eventType, pitch, velocity, channel)
    if eventType == "NOTE_ON" then
        io.write("NOTE_ON " .. pitch .. " " .. velocity .. " " .. channel .. "\n")
    else
        io.write("NOTE_OFF " .. pitch .. " " .. channel .. "\n")
    end
end

-- ── Player ───────────────────────────────────────────────────────────────────

local player     = Player.new(song, clockFn)
local intervalMs = math.floor(player.pulseMs / 2)

Player.start(player)

-- ── Timer ────────────────────────────────────────────────────────────────────

local timer  = uv.new_timer()
local sigint = uv.new_signal()

local function flushAllNotes()
    local offs = Player.allNotesOff(player)
    for _, e in ipairs(offs) do
        io.write("NOTE_OFF " .. e.pitch .. " " .. e.channel .. "\n")
    end
    io.flush()
end

uv.signal_start(sigint, "sigint", function()
    io.stderr:write("[main_lite] SIGINT — flushing notes and exiting\n")
    flushAllNotes()
    uv.timer_stop(timer)
    uv.stop()
end)

io.stderr:write(string.format(
    "[main_lite] bpm=%d  events=%d  durationPulses=%d  tick=%dms\n",
    song.bpm, song.eventCount, song.durationPulses, intervalMs))

uv.timer_start(timer, 0, intervalMs, function()
    Player.tick(player, emit)
    io.flush()
end)

uv.run()
