-- tests/sequence_runner.lua
-- Runs listenable + assertable sequence scenarios.
-- Drives the engine directly with an inline pulse loop. Probability is the
-- only live-decision the runner inlines (it's a per-step engine concern);
-- swing and scale quantization were intentionally removed — apply them
-- downstream of MIDI if you need them.
--
-- Usage:
--   lua tests/sequence_runner.lua 01_basic_patterns
--   lua tests/sequence_runner.lua all

local Engine      = require("sequencer/engine")
local Probability = require("sequencer/probability")
local Step        = require("sequencer/step")
local Tui         = require("tui")
local Helpers     = require("tests.sequences._helpers")

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

-- Minimal pulse driver — replaces the old rich player for test purposes.
-- Returns a function `tick(emit)` that emits event tables {type,pitch,velocity,channel}.
local function makeDriver(engine)
    local pulseCount   = 0
    local probSuppressed = {}
    for i = 1, engine.trackCount do probSuppressed[i] = false end

    return function(emit)
        pulseCount = pulseCount + 1

        for ti = 1, engine.trackCount do
            local track = engine.tracks[ti]
            track.clockAccum = track.clockAccum + track.clockMult
            local advanceCount = math.floor(track.clockAccum / track.clockDiv)
            track.clockAccum = track.clockAccum % track.clockDiv

            for _ = 1, advanceCount do
                local step, event = Engine.advanceTrack(engine, ti)
                if event == "NOTE_ON" then
                    if Probability.shouldPlay(step) then
                        probSuppressed[ti] = false
                        local channel = track.midiChannel or ti
                        local pitch   = Step.getPitch(step)
                        emit({
                            type = "NOTE_ON", pitch = pitch,
                            velocity = Step.getVelocity(step), channel = channel,
                        })
                    else
                        probSuppressed[ti] = true
                    end
                elseif event == "NOTE_OFF" then
                    if probSuppressed[ti] then
                        probSuppressed[ti] = false
                    else
                        local channel = track.midiChannel or ti
                        local pitch   = Step.getPitch(step)
                        emit({
                            type = "NOTE_OFF", pitch = pitch,
                            velocity = 0, channel = channel,
                        })
                    end
                end
            end
        end

        Engine.onPulse(engine, pulseCount)
    end
end

local function runScenario(name)
    local scenario = loadScenario(name)
    local engine = scenario.build(Helpers)
    local pulseLimit = pulsesArg or scenario.defaultPulses or 16

    local tick = makeDriver(engine)

    local eventsPerPulse = {}
    local noteOnPitches = {}
    local noteOnCount = 0
    local noteOffCount = 0

    print("[CASE:" .. scenario.name .. "] " .. scenario.description)

    for pulse = 1, pulseLimit do
        local pulseEvents = {}
        tick(function(ev) pulseEvents[#pulseEvents + 1] = ev end)
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
