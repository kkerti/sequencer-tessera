-- tests/sequence_runner.lua
-- Runs listenable + assertable sequence scenarios.
--
-- Usage:
--   lua tests/sequence_runner.lua 01_basic_patterns
--   lua tests/sequence_runner.lua all

local Engine  = require("sequencer/engine")
local Player  = require("player/player")
local Tui     = require("tui")
local Helpers = require("tests.sequences._helpers")

local scenarioArg = arg[1] or "all"
local pulsesArg = tonumber(arg[2])

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

local function loadScenario(name)
    return require("tests.sequences." .. name)
end

local function runScenario(name)
    local scenario = loadScenario(name)
    local engine = scenario.build(Helpers)
    local pulseLimit = pulsesArg or scenario.defaultPulses or 16

    -- Wrap engine in a player for MIDI emission.
    local player = Player.new(engine, engine.bpm, function() return 0 end)
    -- Apply swing/scale if the scenario stored them on the engine table
    -- (legacy scenarios may set engine.swingPercent / engine.scaleName directly).
    if engine.swingPercent and engine.swingPercent > 50 then
        Player.setSwing(player, engine.swingPercent)
    end
    if engine.scaleName then
        Player.setScale(player, engine.scaleName, engine.rootNote or 0)
    end
    Player.start(player)

    local eventsPerPulse = {}
    local noteOnPitches = {}
    local noteOnCount = 0
    local noteOffCount = 0

    print("[CASE:" .. scenario.name .. "] " .. scenario.description)

    for pulse = 1, pulseLimit do
        local pulseEvents = {}
        Player.tick(player, function(ev)
            pulseEvents[#pulseEvents + 1] = ev
        end)
        eventsPerPulse[pulse] = pulseEvents

        for i = 1, #pulseEvents do
            local event = pulseEvents[i]
            if event.type == "NOTE_ON" then
                noteOnCount = noteOnCount + 1
                noteOnPitches[#noteOnPitches + 1] = event.pitch
            elseif event.type == "NOTE_OFF" then
                noteOffCount = noteOffCount + 1
            end
        end

        print(Tui.renderTickTrace(engine, pulse, pulseEvents))
        if pulse % engine.pulsesPerBeat == 0 then
            print(Tui.render(engine, pulse, pulseEvents))
        end
    end

    local result = {
        eventsPerPulse = eventsPerPulse,
        noteOnPitches = noteOnPitches,
        noteOnCount = noteOnCount,
        noteOffCount = noteOffCount,
        pulseLimit = pulseLimit,
    }

    scenario.assert(Helpers, result)
    print("[ASSERT:PASS] " .. scenario.name)
end

if scenarioArg == "all" then
    for i = 1, #SCENARIOS do
        runScenario(SCENARIOS[i])
    end
    print("[DONE] all scenarios passed")
else
    runScenario(scenarioArg)
end
