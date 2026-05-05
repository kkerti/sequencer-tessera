-- tests/test_persist.lua
local Engine  = require("engine")
local Step    = require("step")
local Persist = require("persist")
local M = {}

local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end
end

local TMP = "/tmp/sequencer_test_save.lua"

local function rm() os.remove(TMP) end

function M.test_save_load_roundtrip()
    Engine.init({ trackCount = 4, stepsPerTrack = 64 })
    -- mutate state
    Engine.tracks[1].steps[1] = Step.pack({ pitch=72, vel=110, dur=8, gate=4 })
    Engine.tracks[1].steps[16] = Step.pack({ pitch=48, vel=64,  dur=12, gate=12, mute=true })
    Engine.tracks[2].steps[5] = Step.pack({ pitch=36, vel=127, dur=24, gate=18 })
    Engine.setLastStep(2, 12)
    Engine.setLastStep(3, 14)
    Engine.setTrackChan(4, 9)
    Engine.setSwing(2)

    local snap = {}
    for ti = 1, 4 do
        local tr = Engine.tracks[ti]
        local s = { chan=tr.chan, lastStep=tr.lastStep, steps={} }
        for i = 1, tr.cap do s.steps[i] = tr.steps[i] end
        snap[ti] = s
    end
    local snapSwing = Engine.swing

    eq(Persist.save(TMP), true, "save returned false")

    -- wipe engine
    Engine.init({ trackCount = 4, stepsPerTrack = 64 })
    eq(Engine.swing, 0, "swing post-init")
    eq(Engine.tracks[2].lastStep, 16, "lastStep post-init")

    eq(Persist.load(TMP), true, "load returned false")

    eq(Engine.swing, snapSwing, "swing restored")
    for ti = 1, 4 do
        eq(Engine.tracks[ti].chan, snap[ti].chan, "chan t" .. ti)
        eq(Engine.tracks[ti].lastStep, snap[ti].lastStep, "lastStep t" .. ti)
        for i = 1, 64 do
            eq(Engine.tracks[ti].steps[i], snap[ti].steps[i], "step t" .. ti .. " i" .. i)
        end
    end
    rm()
end

function M.test_load_missing_file_returns_false()
    Engine.init({ trackCount = 4, stepsPerTrack = 64 })
    rm()
    eq(Persist.load(TMP), false)
end

function M.test_load_corrupt_file_returns_false()
    Engine.init({ trackCount = 4, stepsPerTrack = 64 })
    local f = io.open(TMP, "w"); f:write("this is not lua {{{"); f:close()
    eq(Persist.load(TMP), false)
    rm()
end

function M.test_load_preserves_runtime_fields()
    Engine.init({ trackCount = 4, stepsPerTrack = 64 })
    Engine.tracks[1].steps[1] = Step.pack({ pitch=60, vel=100, dur=4, gate=2 })
    Persist.save(TMP)
    -- start engine, advance a couple of pulses to put runtime state in place
    Engine.onStart()
    Engine.onPulse(); Engine.onPulse()
    local trBefore = Engine.tracks[1]
    -- load should not replace track tables (UI may hold refs)
    Persist.load(TMP)
    if Engine.tracks[1] ~= trBefore then error("track table identity changed") end
    rm()
end

return M
