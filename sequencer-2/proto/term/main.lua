-- proto/term/main.lua — headless terminal harness for the sequencer Core.
--
-- Drives the engine from an external clock and writes notes to stdout for
-- tools/bridge.py to relay into Ableton. Run from the repo root.
--
-- External clock (device-faithful), notes into Ableton:
--   python3 tools/bridge.py --lua "lua proto/term/main.lua"
--
-- Internal test clock (no Ableton needed; prints notes to the terminal):
--   lua proto/term/main.lua --bpm 120
--
-- Stdin protocol (one per line, from bridge.py): START | STOP | CLK | QUIT

package.path = "src/core/?.lua;src/fx/?.lua;src/hal/?.lua;" .. package.path

local Engine = require("engine")
local Event  = require("event")
local Driver = require("driver_stdio")

-- ---- args --------------------------------------------------------------
local bpm = nil
local gen, seed = false, 1
for i = 1, #arg do
    if arg[i] == "--bpm"  then bpm = tonumber(arg[i + 1]) end
    if arg[i] == "--gen"  then gen = true end
    if arg[i] == "--seed" then seed = tonumber(arg[i + 1]) or 1 end
end

-- ---- build a 2-track demo ---------------------------------------------
-- Track 1: A-minor melody + a chord on beat 1 (shows polyphony), ch 1.
-- Track 2: pentatonic bass in quarter notes, with a little RANDOM, ch 2.
Engine.init{
    trackCount = 2,
    tracks = {
        { chan = 1, scale = { scaleIndex = 3, root = 9 } },              -- A minor
        { chan = 2, scale = { scaleIndex = 8, root = 9 },                -- A min-pent
          random = { chance = 85, velJit = 18 },
          range  = { velMin = 40, velMax = 110 } },
    },
}

local STEP = 6  -- ticks per step at x1 (24 PPQN)
local function note(t, step, pitch, lenSteps, vel)
    Event.add(Engine.tracks[t].pattern.events, pitch, step * STEP, lenSteps * STEP, vel)
end

if gen then
    -- Generated: Euclidean, root ± spread, in key (A minor). --seed N to vary.
    local Generate = require("generate")
    local n1 = Generate.run(Engine.tracks[1].pattern, {
        scaleIndex = 3, root = 9, hits = 7, seed = seed,
        pitchRoot = 60, pitchSpread = 6, velRoot = 100, velSpread = 20 })
    local n2 = Generate.run(Engine.tracks[2].pattern, {
        scaleIndex = 8, root = 9, hits = 4, seed = seed + 100, rotate = 0,
        pitchRoot = 40, pitchSpread = 4, velRoot = 110, velSpread = 15,
        gateRoot = 18, gateSpread = 6 })
    io.stderr:write(string.format("[seq2] GENERATED  seed=%d  T1=%d notes  T2=%d notes\n", seed, n1, n2))
else
    -- Hand-authored demo. Track 1: A-minor melody + triad on step 0.
    note(1, 0, 57, 3, 100); note(1, 0, 60, 3, 90); note(1, 0, 64, 3, 90)
    note(1, 3, 67, 2, 95); note(1, 6, 71, 2, 95); note(1, 9, 60, 2, 90); note(1, 12, 64, 3, 100)
    -- Track 2 bass: quarter notes A2 / E3.
    note(2, 0, 45, 4, 110); note(2, 4, 52, 4, 100); note(2, 8, 45, 4, 110); note(2, 12, 52, 4, 100)
    io.stderr:write("[seq2] demo loaded: 2 tracks, 1 bar loop\n")
end

if bpm then
    -- Internal test clock. Busy-wait on os.clock (portable, no deps).
    local interval = 60.0 / (bpm * 24)   -- seconds per pulse at 24 PPQN
    local function sleep(sec) local t = os.clock() + sec; while os.clock() < t do end end
    io.stderr:write(string.format("[seq2] internal clock @ %g BPM (Ctrl-C to stop)\n", bpm))
    Engine.onStart()
    while true do
        Driver.emit(Engine.onPulse())
        sleep(interval)
    end
else
    Engine.onStart()  -- also (re)armed by START from bridge
    for line in io.lines() do
        if line == "CLK" then
            Driver.emit(Engine.onPulse())
        elseif line == "START" then
            Engine.onStart()
        elseif line == "STOP" then
            Driver.emit(Engine.onStop())
        elseif line == "QUIT" then
            break
        end
    end
end
