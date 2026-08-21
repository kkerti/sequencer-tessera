-- tests/test_scale.lua
local Engine = require("engine")
local Step   = require("step")
local Track  = require("track")
local Scale  = require("scale")
local M = {}

local function eq(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end end

function M.test_schema()
    eq(#Scale.SCALES, 5)
    eq(Scale.SCALES[1].name, "off")
    eq(Scale.SCALES[2].name, "maj")
    eq(Scale.SCALES[3].name, "min")
    eq(Scale.SCALES[4].mask, 0x295, "major pent mask")
    eq(Scale.SCALES[5].mask, 0x4A9, "minor pent mask")
end

function M.test_off_is_identity()
    eq(Scale.quantize(61, 0), 61)
    eq(Scale.quantize(0, 0), 0)
    eq(Scale.quantize(127, 0), 127)
end

function M.test_major_nearest_tone()
    local maj = Scale.SCALES[2].mask
    eq(Scale.quantize(60, maj), 60, "C stays C")
    eq(Scale.quantize(62, maj), 62, "D stays D")
    eq(Scale.quantize(61, maj), 62, "C#->D (up, tie)")
    eq(Scale.quantize(63, maj), 64, "Eb->E")
    eq(Scale.quantize(58, maj), 59, "Bb->B (up, tie)")
    eq(Scale.quantize(59, maj), 59, "B stays B (in major)")
    eq(Scale.quantize(64, maj), 64, "E stays E")
end

function M.test_major_pent_filter()
    local mp = Scale.SCALES[4].mask
    eq(Scale.quantize(61, mp), 62, "C#->D")
    eq(Scale.quantize(64, mp), 64, "E stays E (in pent)")
    eq(Scale.quantize(65, mp), 64, "F->E (nearest in pent)")
end

function M.test_engine_quantizes_emitted_pitch()
    Engine.init({ trackCount = 1 })
    Engine.setTrackScale(1, 2)   -- major
    eq(Engine.tracks[1].scale, 2)
    Engine.tracks[1].steps[1] = Step.pack({ pitch=61, vel=100, dur=4, gate=4 })
    Engine.onStart()
    local ev = Engine.onPulse()
    if not ev then error("expected event") end
    eq(ev[1].type, Track.EV_ON)
    eq(ev[1].pitch, 62, "61 quantized to D under major")
end

function M.test_engine_off_leaves_pitch()
    Engine.init({ trackCount = 1 })
    Engine.tracks[1].steps[1] = Step.pack({ pitch=61, vel=100, dur=4, gate=4 })
    Engine.onStart()
    local ev = Engine.onPulse()
    eq(ev[1].pitch, 61, "no scale -> raw pitch")
end

function M.test_engine_setTrackScale_clamps()
    Engine.init({ trackCount = 1 })
    Engine.setTrackScale(1, 99)
    eq(Engine.tracks[1].scale, #Engine.scales, "clamped high")
    Engine.setTrackScale(1, -3)
    eq(Engine.tracks[1].scale, 1, "clamped low")
end

function M.test_no_alloc_with_scale_enabled()
    Engine.init({ trackCount = 4, stepsPerTrack = 64 })
    for t = 1, 4 do
        Engine.setTrackScale(t, 3)  -- minor
        Engine.tracks[t].steps[1] = Step.pack({ pitch=61+t, vel=100, dur=2, gate=1 })
    end
    Engine.onStart()
    for _ = 1, 200 do Engine.onPulse() end
    local pre = collectgarbage("count")
    for _ = 1, 5000 do Engine.onPulse() end
    local delta = (collectgarbage("count") - pre) * 1024
    if delta > 64 then
        error(string.format("onPulse with scale allocated %.1f bytes", delta))
    end
end

return M
