-- tools/memprofile.lua
-- Memory profiler for the sequencer engine using collectgarbage("count").
--
-- Usage:
--   lua tools/memprofile.lua                          -- runs all scenarios
--   lua tools/memprofile.lua 11_four_track_dark_polyrhythm
--   lua tools/memprofile.lua 11_four_track_dark_polyrhythm 128
--
-- Reports:
--   1. Baseline Lua VM overhead (before any sequencer code loads)
--   2. After requiring all modules
--   3. After Engine.new (empty engine)
--   4. After Scenario.build (engine with all steps/patterns/tracks)
--   5. Peak during tick loop (worst-case mid-performance)
--   6. After full run + GC (steady state)
--
-- All values are in KB. The "engine-only" column subtracts the module
-- baseline so you see what the sequencer data structures actually cost.

local function memKB()
    collectgarbage("collect")
    collectgarbage("collect")
    return collectgarbage("count")  -- returns KB (float)
end

local function fmt(kb)
    if kb >= 1024 then
        return string.format("%.1f KB  (%.2f MB)", kb, kb / 1024)
    end
    return string.format("%.1f KB", kb)
end

-- ─── Phase 0: bare VM ───────────────────────────────────────────────────
local bareVM = memKB()

-- ─── Phase 1: require modules ───────────────────────────────────────────
local Engine = require("sequencer/engine")
local Track = require("sequencer/track")
local Step = require("sequencer/step")
local Pattern = require("sequencer/pattern")
local MathOps = require("sequencer/mathops")
local Snapshot = require("sequencer/snapshot")
local Scene = require("sequencer/scene")
local Probability = require("sequencer/probability")
local Utils = require("utils")
local Helpers = require("tests.sequences._helpers")

local afterModules = memKB()

-- ─── Scenario selection ─────────────────────────────────────────────────
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

local scenarioArg = arg[1] or "all"
local pulsesArg = tonumber(arg[2])

local toRun = {}
if scenarioArg == "all" then
    toRun = SCENARIOS
else
    toRun = { scenarioArg }
end

-- ─── Run each scenario ──────────────────────────────────────────────────
local BUDGET_KB = 100  -- 100 KB ESP32 budget

for _, name in ipairs(toRun) do
    print(string.rep("=", 72))
    print("SCENARIO: " .. name)
    print(string.rep("=", 72))

    -- force clean state
    collectgarbage("collect")
    collectgarbage("collect")

    local scenario = require("tests.sequences." .. name)
    local pulses = pulsesArg or scenario.defaultPulses or 64

    -- Phase 2: build engine
    local beforeBuild = memKB()
    local engine = scenario.build(Helpers)
    local afterBuild = memKB()

    -- count steps/patterns/tracks for context
    local totalSteps = 0
    local totalPatterns = 0
    for i = 1, #engine.tracks do
        totalSteps = totalSteps + Track.getStepCount(engine.tracks[i])
        totalPatterns = totalPatterns + engine.tracks[i].patternCount
    end

    -- Phase 3: tick loop — track peak
    local peakMem = afterBuild
    local eventsTotal = 0

    for pulse = 1, pulses do
        local events = Engine.tick(engine)
        eventsTotal = eventsTotal + #events
        -- sample memory every 4 pulses to reduce overhead
        if pulse % 4 == 0 then
            local now = collectgarbage("count")  -- no full GC, raw allocation
            if now > peakMem then
                peakMem = now
            end
        end
    end

    -- one final precise peak sample
    local finalRaw = collectgarbage("count")
    if finalRaw > peakMem then
        peakMem = finalRaw
    end

    -- Phase 4: post-run steady state
    local afterRun = memKB()

    -- ─── Report ─────────────────────────────────────────────────────
    print()
    print("  Configuration:")
    print("    Tracks:    " .. #engine.tracks)
    print("    Patterns:  " .. totalPatterns)
    print("    Steps:     " .. totalSteps)
    print("    Pulses:    " .. pulses)
    print("    Events:    " .. eventsTotal)
    print()
    print("  Memory breakdown:")
    print("    Bare Lua VM:           " .. fmt(bareVM))
    print("    After module require:  " .. fmt(afterModules))
    print("    Modules overhead:      " .. fmt(afterModules - bareVM))
    print()
    print("    Before engine build:   " .. fmt(beforeBuild))
    print("    After engine build:    " .. fmt(afterBuild))
    print("    Engine data cost:      " .. fmt(afterBuild - beforeBuild))
    print()
    print("    Peak during playback:  " .. fmt(peakMem))
    print("    Peak engine-only:      " .. fmt(peakMem - afterModules))
    print()
    print("    After run + GC:        " .. fmt(afterRun))
    print("    Steady-state engine:   " .. fmt(afterRun - afterModules))
    print()

    -- budget check
    local enginePeak = peakMem - afterModules
    local pct = (enginePeak / BUDGET_KB) * 100
    print(string.format("  ESP32 budget: %.1f / %d KB used (%.0f%%)", enginePeak, BUDGET_KB, pct))

    if enginePeak > BUDGET_KB then
        print("  *** OVER BUDGET ***")
    else
        print(string.format("  %.1f KB headroom remaining", BUDGET_KB - enginePeak))
    end

    -- per-step cost estimate
    if totalSteps > 0 then
        local perStep = (afterBuild - beforeBuild) / totalSteps
        print(string.format("\n  Per-step cost: ~%.1f bytes", perStep * 1024))
        local maxSteps = math.floor((BUDGET_KB - (afterBuild - beforeBuild - (afterBuild - beforeBuild) / totalSteps * totalSteps)) / perStep)
        -- simpler: how many steps could fit in budget
        local budgetForSteps = BUDGET_KB - (afterBuild - beforeBuild) + (perStep * totalSteps)
        local estimatedMaxSteps = math.floor(budgetForSteps / perStep)
        print(string.format("  Est. max steps in %d KB: ~%d", BUDGET_KB, estimatedMaxSteps))
    end

    print()

    -- cleanup for next scenario
    engine = nil
    scenario = nil
    collectgarbage("collect")
    collectgarbage("collect")
end
