-- tests/sequence_runner.lua
-- Runs listenable + assertable sequence scenarios.
-- Drives the engine via the real Driver — same code path used live.
--
-- Usage:
--   lua tests/sequence_runner.lua 01_basic_patterns
--   lua tests/sequence_runner.lua all

local Driver  = require("sequencer").Driver
local Tui     = require("tui")
local Helpers = require("tests.sequences._helpers")

local scenarioArg = arg[1] or "all"
local pulsesArg = tonumber(arg[2])

local SCENARIOS = {
    "01_basic_patterns",
    "02_direction_modes",
    "03_ratchet_showcase",
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
    local scenario   = loadScenario(name)
    local engine     = scenario.build(Helpers)
    local pulseLimit = pulsesArg or scenario.defaultPulses or 16

    local driver = Driver.new(engine)
    Driver.start(driver)

    local eventsPerPulse = {}
    local noteOnPitches  = {}
    local noteOnCount    = 0
    local noteOffCount   = 0

    print("[CASE:" .. scenario.name .. "] " .. scenario.description)

    for pulse = 1, pulseLimit do
        local pulseEvents = {}
        Driver.externalPulse(driver, function(kind, pitch, velocity, channel)
            local ev = {
                type     = kind,
                pitch    = pitch,
                velocity = velocity or 0,
                channel  = channel,
            }
            pulseEvents[#pulseEvents + 1] = ev
            if kind == "NOTE_ON" then
                noteOnCount = noteOnCount + 1
                noteOnPitches[#noteOnPitches + 1] = pitch
            elseif kind == "NOTE_OFF" then
                noteOffCount = noteOffCount + 1
            end
        end)
        eventsPerPulse[pulse] = pulseEvents

        print(Tui.renderTickTrace(engine, pulse, pulseEvents))
        if pulse % engine.pulsesPerBeat == 0 then
            print(Tui.render(engine, pulse, pulseEvents))
        end
    end

    local result = {
        eventsPerPulse = eventsPerPulse,
        noteOnPitches  = noteOnPitches,
        noteOnCount    = noteOnCount,
        noteOffCount   = noteOffCount,
        pulseLimit     = pulseLimit,
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
