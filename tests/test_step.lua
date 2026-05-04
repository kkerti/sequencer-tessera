-- tests/test_step.lua
local Step = require("step")
local M = {}

local function eq(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end end

function M.test_pack_unpack_defaults()
    local s = Step.pack({})
    eq(Step.pitch(s), 60, "default pitch")
    eq(Step.vel(s), 100, "default vel")
    eq(Step.dur(s), 6, "default dur")
    eq(Step.gate(s), 3, "default gate")
    eq(Step.ratch(s), false, "default ratch")
    eq(Step.muted(s), false, "default muted")
end

function M.test_pack_full()
    local s = Step.pack({ pitch=72, vel=127, dur=24, gate=12, ratch=true })
    eq(Step.pitch(s), 72)
    eq(Step.vel(s), 127)
    eq(Step.dur(s), 24)
    eq(Step.gate(s), 12)
    eq(Step.ratch(s), true)
end

function M.test_clamp()
    local s = Step.pack({ pitch=200, vel=-5 })
    eq(Step.pitch(s), 127)
    eq(Step.vel(s), 0)
end

function M.test_set_returns_new_value()
    local s = Step.pack({ pitch=60 })
    local s2 = Step.set(s, "pitch", 72)
    eq(Step.pitch(s2), 72)
    eq(Step.pitch(s), 60, "original unchanged")
end

function M.test_set_each_field_isolated()
    local s = Step.pack({})
    s = Step.set(s, "pitch", 100)
    s = Step.set(s, "vel", 50)
    s = Step.set(s, "dur", 24)
    s = Step.set(s, "gate", 12)
    s = Step.set(s, "ratch", 1)
    eq(Step.pitch(s), 100)
    eq(Step.vel(s), 50)
    eq(Step.dur(s), 24)
    eq(Step.gate(s), 12)
    eq(Step.ratch(s), true)
end

function M.test_note_name_basic()
    eq(Step.noteName(60), "C4")
    eq(Step.noteName(61), "C#4")
    eq(Step.noteName(0),  "C-1")
    eq(Step.noteName(127), "G9")
    eq(Step.noteName(69), "A4")
end

return M
