-- tests/sequence_player.lua
-- Plays a scenario in real time and emits MIDI line protocol to stdout.
--
-- Usage:
--   lua tests/sequence_player.lua list
--   lua tests/sequence_player.lua 01_basic_patterns
--   lua tests/sequence_player.lua 01_basic_patterns no-tui

local uv = require("luv")
local Engine = require("sequencer/engine")
local Track = require("sequencer/track")
local Tui = require("tui")
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
        if SCENARIOS[i] == name then
            return true
        end
    end
    return false
end

local function printUsage()
    io.stderr:write("Usage:\n")
    io.stderr:write("  lua tests/sequence_player.lua list\n")
    io.stderr:write("  lua tests/sequence_player.lua <scenario-name> [no-tui] [gate-ms=45] [ch1=1] [ch2=10]\n")
    io.stderr:write("\nScenarios:\n")
    for i = 1, #SCENARIOS do
        io.stderr:write("  - " .. SCENARIOS[i] .. "\n")
    end
end

local scenarioName = arg[1]
if scenarioName == nil or scenarioName == "help" or scenarioName == "-h" or scenarioName == "--help" then
    printUsage()
    os.exit(0)
end

if scenarioName == "list" then
    for i = 1, #SCENARIOS do
        print(SCENARIOS[i])
    end
    os.exit(0)
end

if not hasScenario(scenarioName) then
    io.stderr:write("Unknown scenario: " .. tostring(scenarioName) .. "\n")
    printUsage()
    os.exit(1)
end

local withTui = true
local shortGateMs = 45
local trackChannelOverrides = {}

for i = 2, #arg do
    local token = arg[i]
    if token == "no-tui" then
        withTui = false
    else
        local gateValue = token:match("^gate%-ms=(%d+)$")
        if gateValue ~= nil then
            shortGateMs = tonumber(gateValue)
        else
            local trackIndex, channel = token:match("^ch(%d+)=(%d+)$")
            if trackIndex ~= nil and channel ~= nil then
                trackChannelOverrides[tonumber(trackIndex)] = tonumber(channel)
            end
        end
    end
end

local scenario = require("tests.sequences." .. scenarioName)
local engine = scenario.build(Helpers)

for trackIndex, channel in pairs(trackChannelOverrides) do
    if trackIndex >= 1 and trackIndex <= engine.trackCount then
        Track.setMidiChannel(engine.tracks[trackIndex], channel)
    end
end

local intervalMs = math.floor(engine.pulseIntervalMs)
local pulseCount = 0

local function emitNoteOn(pitch, velocity, channel)
    io.write("NOTE_ON " .. pitch .. " " .. velocity .. " " .. channel .. "\n")
end

local function emitNoteOff(pitch, channel)
    io.write("NOTE_OFF " .. pitch .. " " .. channel .. "\n")
end

local pendingOffTimers = {}

local function scheduleShortNoteOff(pitch, channel)
    if shortGateMs <= 0 then
        return
    end

    local timer = uv.new_timer()
    pendingOffTimers[#pendingOffTimers + 1] = timer
    uv.timer_start(timer, shortGateMs, 0, function()
        emitNoteOff(pitch, channel)
        io.flush()
        uv.timer_stop(timer)
        timer:close()
    end)
end

-- Cancels all pending short-gate timers and emits NOTE_OFF events for every
-- note the engine currently tracks as sounding.
local function flushAllNotes()
    for _, t in ipairs(pendingOffTimers) do
        if not t:is_closing() then
            uv.timer_stop(t)
            t:close()
        end
    end
    pendingOffTimers = {}

    local offEvents = Engine.allNotesOff(engine)
    for _, event in ipairs(offEvents) do
        emitNoteOff(event.pitch, event.channel)
    end
    io.flush()
end

if withTui then
    io.stderr:write("[SCENARIO] " .. scenario.name .. " - " .. scenario.description .. "\n")
    io.stderr:write("[OPTIONS] gate-ms=" .. shortGateMs .. "\n")
end

local timer = uv.new_timer()

-- ── Signal handling — clean shutdown ─────────────────────────────────────────
local sigint = uv.new_signal()
uv.signal_start(sigint, "sigint", function()
    io.stderr:write("[player] SIGINT received — flushing notes and exiting\n")
    flushAllNotes()
    uv.timer_stop(timer)
    uv.stop()
end)

uv.timer_start(timer, 0, intervalMs, function()
    pulseCount = pulseCount + 1
    local events = Engine.tick(engine)

    for i = 1, #events do
        local event = events[i]
        if event.type == "NOTE_ON" then
            emitNoteOn(event.pitch, event.velocity, event.channel)
            scheduleShortNoteOff(event.pitch, event.channel)
        elseif event.type == "NOTE_OFF" then
            if shortGateMs <= 0 then
                emitNoteOff(event.pitch, event.channel)
            end
        end
    end
    io.flush()

    if withTui then
        io.stderr:write(Tui.renderTickTrace(engine, pulseCount, events) .. "\n")
        if pulseCount % engine.pulsesPerBeat == 0 then
            io.stderr:write(Tui.render(engine, pulseCount, events) .. "\n")
        end
        io.stderr:flush()
    end
end)

uv.run()
