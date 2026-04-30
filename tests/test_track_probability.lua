-- tests/test_track_probability.lua
local Track = require("track")
local Step  = require("step")
local M = {}

function M.test_prob_zero_never_fires()
    local tr = Track.new()
    -- Set all 16 steps in region 1 to prob=0 so no step in the playable
    -- region can ever fire.
    for i = 1, 16 do
        tr.steps[i] = Step.pack({ pitch=60, vel=100, dur=4, gate=2, prob=0 })
    end
    Track.reset(tr, 1)
    local total = {}
    for _ = 1, 100 do
        local out = {}
        Track.advance(tr, out, 0)
        for _, e in ipairs(out) do total[#total+1] = e end
    end
    if #total ~= 0 then error("prob=0 should never fire, got " .. #total .. " events") end
end

function M.test_prob_max_always_fires()
    local tr = Track.new()
    tr.steps[1] = Step.pack({ pitch=60, vel=100, dur=4, gate=2, prob=127 })
    tr.steps[2] = Step.pack({ pitch=62, vel=100, dur=4, gate=2, prob=127 })
    Track.reset(tr, 1)
    local ons = 0
    for _ = 1, 8 do
        local out = {}
        Track.advance(tr, out, 0)
        for _, e in ipairs(out) do if e.type == Track.EV_ON then ons = ons + 1 end end
    end
    if ons ~= 2 then error("prob=127 should fire both steps; got " .. ons) end
end

function M.test_prob_mid_fires_some()
    math.randomseed(42)
    local tr = Track.new()
    tr.steps[1] = Step.pack({ pitch=60, vel=100, dur=4, gate=2, prob=64 })
    Track.reset(tr, 1)
    local ons = 0
    for _ = 1, 400 do
        local out = {}
        Track.advance(tr, out, 0)
        for _, e in ipairs(out) do if e.type == Track.EV_ON then ons = ons + 1 end end
    end
    -- 400 pulses / dur=4 = ~100 step entries; ~50 should fire
    if ons < 30 or ons > 70 then error("prob=64 expected ~50 fires, got " .. ons) end
end

return M
