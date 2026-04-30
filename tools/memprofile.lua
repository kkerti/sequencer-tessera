-- tools/memprofile.lua
-- Measure Lua heap usage of the sequencer at key milestones.
--
-- Reports KB of live Lua heap (per `collectgarbage("count")`).
-- IMPORTANT: this is host-side macOS Lua 5.4; the on-device ESP32 LuaVM
-- allocator may differ. Treat numbers as ratios and rough estimates, not
-- as authoritative device memory figures.
--
-- Usage:
--   lua tools/memprofile.lua

package.path = "src/?.lua;" .. package.path

local function gc_kb()
    collectgarbage("collect")
    collectgarbage("collect")
    return collectgarbage("count") -- KB
end

local function row(label, kb_now, kb_prev)
    local delta = kb_prev and (kb_now - kb_prev) or 0
    io.write(string.format("  %-44s  %8.2f KB   (%+7.3f KB)\n", label, kb_now, delta))
end

io.write("=== Sequencer memory profile (Lua " .. _VERSION .. ", 64-bit ints: "
    .. tostring(math.maxinteger == 0x7FFFFFFFFFFFFFFF) .. ") ===\n\n")

local base = gc_kb()
row("baseline (Lua + this script)", base, nil)

-- 1) Load step module only
local Step = require("step")
local k_step = gc_kb()
row("after require step", k_step, base)

-- 2) Load track module
local Track = require("track")
local k_track = gc_kb()
row("after require track", k_track, k_step)

-- 3) Load engine
local Engine = require("engine")
local k_engine = gc_kb()
row("after require engine", k_engine, k_track)

-- 4) Init engine with 4 tracks x 64 steps
Engine.init({ trackCount = 4, stepsPerTrack = 64 })
local k_init = gc_kb()
row("after engine.init(4 tracks, 64 steps)", k_init, k_engine)

-- 5) Per-track-count scaling (re-init each time)
io.write("\n  -- track count scaling (64 steps each) --\n")
local k_prev = k_init
for _, n in ipairs({1, 2, 4, 8}) do
    Engine.init({ trackCount = n, stepsPerTrack = 64 })
    local k = gc_kb()
    row(string.format("engine.init(%d tracks)", n), k, k_prev)
    k_prev = k
end

-- 6) Per-step-cap scaling (4 tracks)
io.write("\n  -- step capacity scaling (4 tracks) --\n")
k_prev = gc_kb()
for _, cap in ipairs({16, 32, 64, 128, 256}) do
    Engine.init({ trackCount = 4, stepsPerTrack = cap })
    local k = gc_kb()
    row(string.format("engine.init(4 tracks, %d steps)", cap), k, k_prev)
    k_prev = k
end

-- 7) Hypothetical Model B: simulate 4 banks of 4 tracks x 64 steps
io.write("\n  -- hypothetical pattern banks (Model B, parked) --\n")
Engine.init({ trackCount = 4, stepsPerTrack = 64 })
local k_one = gc_kb()
row("engine.init (1 bank baseline)", k_one, nil)
local banks = {}
for b = 1, 4 do
    banks[b] = {}
    for t = 1, 4 do
        local steps = {}
        local def = Step.pack({})
        for i = 1, 64 do steps[i] = def end
        banks[b][t] = steps
    end
end
local k_banks = gc_kb()
row("+ 4 extra banks of 4x64 step buffers", k_banks, k_one)
banks = nil

-- 8) Per-pulse allocation check
io.write("\n  -- per-pulse allocation (must be ~zero) --\n")
Engine.init({ trackCount = 4, stepsPerTrack = 64 })
-- seed something so events fire
for t = 1, 4 do
    Engine.tracks[t].steps[1] = Step.pack({ pitch=60+t, vel=100, dur=2, gate=1 })
end
Engine.onStart()
-- prime
for _ = 1, 100 do Engine.onPulse() end
local k_pre = gc_kb()
local N = 10000
for _ = 1, N do Engine.onPulse() end
collectgarbage("collect")
local k_post = collectgarbage("count")
io.write(string.format("  %d pulses: heap %.2f -> %.2f KB (delta %+.3f KB, %+.3f bytes/pulse)\n",
    N, k_pre, k_post, k_post - k_pre, ((k_post - k_pre) * 1024) / N))

io.write("\nDone.\n")
