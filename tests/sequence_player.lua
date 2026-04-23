-- tests/sequence_player.lua
-- Plays a scenario in real time and emits MIDI line protocol to stdout.
-- Routes through player/player.lua — os.clock() drives gate/NOTE_OFF timing.
--
-- Usage:
--   lua tests/sequence_player.lua list
--   lua tests/sequence_player.lua 01_basic_patterns
--   lua tests/sequence_player.lua 09_full_stack_performance no-tui
--   lua tests/sequence_player.lua 10_four_track_polyrhythm_showcase ch1=1 ch2=10
--
-- Pipe to bridge to hear in Ableton:
--   lua tests/sequence_player.lua 11_four_track_dark_polyrhythm | python3 bridge.py

local uv      = require("luv")
local Engine  = require("sequencer/engine")
local Player  = require("player/player")
local Track   = require("sequencer/track")
local Tui     = require("tui")
local Helpers = require("tests.sequences._helpers")

local SCENARIOS = {
    "01_basic_patterns",
    "02_direction_modes",
    "03_ratchet_showcase",
    "04_swing_showcase",
    "05_scale_quantizer",
    "06_clock_div_mult_polyrhythm",
    "07_mathops_mutation",
    "08_snapshot_roundtrip",
    "09_full_stack_performance",
    "10_four_track_polyrhythm_showcase",
    "11_four_track_dark_polyrhythm",
}

local function hasScenario(name)
    for i = 1, #SCENARIOS do
        if SCENARIOS[i] == name then return true end
    end
    return false
end

local function printUsage()
    io.stderr:write("Usage:\n")
    io.stderr:write("  lua tests/sequence_player.lua list\n")
    io.stderr:write("  lua tests/sequence_player.lua <scenario-name> [no-tui] [ch1=1] [ch2=10]\n")
    io.stderr:write("\nScenarios:\n")
    for i = 1, #SCENARIOS do
        io.stderr:write("  - " .. SCENARIOS[i] .. "\n")
    end
end

-- ── Argument parsing ──────────────────────────────────────────────────────────

local scenarioName = arg[1]
if scenarioName == nil or scenarioName == "help" or scenarioName == "-h" or scenarioName == "--help" then
    printUsage()
    os.exit(0)
end

if scenarioName == "list" then
    for i = 1, #SCENARIOS do print(SCENARIOS[i]) end
    os.exit(0)
end

if not hasScenario(scenarioName) then
    io.stderr:write("Unknown scenario: " .. tostring(scenarioName) .. "\n")
    printUsage()
    os.exit(1)
end

local withTui = true
local trackChannelOverrides = {}

for i = 2, #arg do
    local token = arg[i]
    if token == "no-tui" then
        withTui = false
    else
        local trackIndex, channel = token:match("^ch(%d+)=(%d+)$")
        if trackIndex ~= nil and channel ~= nil then
            trackChannelOverrides[tonumber(trackIndex)] = tonumber(channel)
        end
    end
end

-- ── Build engine from scenario ────────────────────────────────────────────────

local scenario = require("tests.sequences." .. scenarioName)
local engine   = scenario.build(Helpers)

for trackIndex, channel in pairs(trackChannelOverrides) do
    if trackIndex >= 1 and trackIndex <= engine.trackCount then
        Track.setMidiChannel(engine.tracks[trackIndex], channel)
    end
end

-- ── Wrap in player ────────────────────────────────────────────────────────────

local player = Player.new(engine, engine.bpm, uv.now)

-- Scenarios store swing as engine.swingPercent (raw field) and scale via
-- Engine.setScale (stored as engine.scaleName / engine.scaleTable).
-- Apply both to the player here.
if engine.swingPercent and engine.swingPercent > 50 then
    Player.setSwing(player, engine.swingPercent)
end
if engine.scaleName then
    Player.setScale(player, engine.scaleName, engine.rootNote or 0)
end

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
local pulseCount = 0
local timer      = uv.new_timer()

local sigint = uv.new_signal()
uv.signal_start(sigint, "sigint", function()
    io.stderr:write("[sequence_player] SIGINT — flushing notes\n")
    flushAll()
    uv.timer_stop(timer)
    uv.stop()
end)

if withTui then
    io.stderr:write("[SCENARIO] " .. scenario.name .. " — " .. scenario.description .. "\n")
    io.stderr:write("[BPM] " .. engine.bpm)
    if engine.swingPercent and engine.swingPercent > 50 then
        io.stderr:write("  [SWING] " .. engine.swingPercent .. "%")
    end
    if engine.scaleName then
        io.stderr:write("  [SCALE] " .. engine.scaleName)
    end
    io.stderr:write("\n")
end

uv.timer_start(timer, 0, intervalMs, function()
    pulseCount = pulseCount + 1
    Player.tick(player, onMidiEvent)
    io.flush()

    if withTui then
        -- Pass empty events table to TUI (events were consumed by callback).
        io.stderr:write(Tui.renderTickTrace(engine, pulseCount, {}) .. "\n")
        if pulseCount % engine.pulsesPerBeat == 0 then
            io.stderr:write(Tui.render(engine, pulseCount, {}) .. "\n")
        end
        io.stderr:flush()
    end
end)

uv.run()
