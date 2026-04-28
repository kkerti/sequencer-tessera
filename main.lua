-- main.lua
-- Dev harness for the full stack: inline song description → in-memory compile
-- → lite player + song-writer (probability re-roll on each loop).
--
-- This is the "live edit" workflow: tweak the song table below, save, re-run.
-- Pipe to bridge.py for MIDI:
--
--   lua main.lua | python3 bridge.py
--
-- See main_lite.lua for the "ship-ready" workflow that loads a precompiled
-- song from compiled/.

local uv          = require("luv")
local SongCompile = require("tools/song_compile")
local SongWriter  = require("sequencer/song_writer")
local Player      = require("player/player")

-- ── Song description ─────────────────────────────────────────────────────────

local songSource = {
    bpm = 120, ppb = 4,
    bars = 4, beatsPerBar = 4,
    tracks = {
        -- Track 1 — bass line, 2 patterns
        {
            channel = 1, direction = "forward", clockDiv = 1, clockMult = 1,
            patterns = {
                {
                    name = "A",
                    steps = {
                        {58, 100, 4, 3}, {55, 90, 4, 3}, {53, 95, 4, 3}, {51, 85, 4, 3},
                        {48, 100, 4, 3}, {51, 80, 4, 2}, {53, 90, 4, 3}, {55, 70, 4, 0},
                    },
                },
                {
                    name = "B",
                    steps = {
                        {48, 100, 2, 2}, {48, 80, 2, 1, 2}, {55, 100, 4, 3}, {53, 90, 2, 2},
                        {51, 85, 2, 1, 2}, {53, 95, 4, 3}, {48, 75, 2, 2}, {48, 100, 2, 0},
                    },
                },
            },
        },
        -- Track 2 — chord stabs, half-speed pingpong
        {
            channel = 2, direction = "pingpong", clockDiv = 2, clockMult = 1,
            patterns = {
                {
                    name = "C",
                    steps = {
                        {60, 80, 4, 3}, {60, 75, 4, 3}, {67, 80, 4, 3}, {63, 70, 4, 2},
                        {60, 90, 2, 2}, {63, 85, 2, 1}, {67, 90, 4, 3}, {70, 80, 4, 0},
                    },
                },
            },
        },
    },
}

-- ── Compile to flat song ─────────────────────────────────────────────────────

local song = SongCompile.compile(songSource)

-- Wire the song-writer for per-loop probability re-rolls (no-op when the
-- song has no probability fields).
if song.hasProbability then
    song.onLoopBoundary = SongWriter.rollNextLoop
end

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
    io.stderr:write("[main] SIGINT — flushing notes and exiting\n")
    flushAllNotes()
    uv.timer_stop(timer)
    uv.stop()
end)

io.stderr:write(string.format(
    "[main] bpm=%d  events=%d  durationPulses=%d  hasProbability=%s  tick=%dms\n",
    song.bpm, song.eventCount, song.durationPulses,
    tostring(song.hasProbability and true or false), intervalMs))

uv.timer_start(timer, 0, intervalMs, function()
    Player.tick(player, emit)
    io.flush()
end)

uv.run()
