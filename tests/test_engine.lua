-- tests/test_engine.lua
local Engine = require("engine")
local Step   = require("step")
local Track  = require("track")
local M = {}

local function eq(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end end

function M.test_init_creates_tracks()
    Engine.init({ trackCount = 4, stepsPerTrack = 64 })
    eq(#Engine.tracks, 4)
    eq(Engine.tracks[1].cap, 64)
    eq(Engine.tracks[1].chan, 1)
    eq(Engine.tracks[4].chan, 4)
end

function M.test_pulse_when_stopped_returns_nil()
    Engine.init({})
    eq(Engine.onPulse(), nil)
end

function M.test_start_then_pulse_emits()
    Engine.init({ trackCount = 1 })
    Engine.tracks[1].steps[1] = Step.pack({ pitch=60, vel=100, dur=4, gate=2 })
    Engine.onStart()
    local ev = Engine.onPulse()
    if not ev then error("expected events on first pulse after start") end
    eq(ev[1].type, Track.EV_ON)
    eq(ev[1].pitch, 60)
end

function M.test_stop_emits_alloff()
    Engine.init({ trackCount = 1 })
    Engine.tracks[1].steps[1] = Step.pack({ pitch=60, vel=100, dur=8, gate=8 })
    Engine.onStart()
    Engine.onPulse()  -- triggers note on
    local off = Engine.onStop()
    local foundOff = false
    for _, e in ipairs(off) do
        if e.type == Track.EV_OFF and e.pitch == 60 then foundOff = true end
    end
    if not foundOff then error("expected NOTE_OFF on stop") end
end

function M.test_setStepParam_through_engine()
    Engine.init({ trackCount = 2 })
    Engine.setStepParam(2, 5, "pitch", 72)
    eq(Step.pitch(Engine.tracks[2].steps[5]), 72)
end

function M.test_groupEdit_through_engine()
    Engine.init({ trackCount = 1 })
    Engine.groupEdit(1, 1, 4, "set", "vel", 50)
    for i = 1, 4 do eq(Step.vel(Engine.tracks[1].steps[i]), 50) end
end

return M
