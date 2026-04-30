-- tests/test_track_group_edit.lua
local Track = require("track")
local Step  = require("step")
local M = {}

local function eq(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end end

function M.test_set_range()
    local tr = Track.new(8, 8)
    Track.groupEdit(tr, 2, 5, "set", "pitch", 72)
    eq(Step.pitch(tr.steps[1]), 60)
    eq(Step.pitch(tr.steps[2]), 72)
    eq(Step.pitch(tr.steps[5]), 72)
    eq(Step.pitch(tr.steps[6]), 60)
end

function M.test_add_range()
    local tr = Track.new(8, 8)
    Track.groupEdit(tr, 1, 4, "add", "pitch", 5)
    eq(Step.pitch(tr.steps[1]), 65)
    eq(Step.pitch(tr.steps[4]), 65)
    eq(Step.pitch(tr.steps[5]), 60)
end

function M.test_rand_range_in_bounds()
    math.randomseed(1)
    local tr = Track.new(8, 8)
    Track.groupEdit(tr, 1, 8, "rand", "vel", { 80, 100 })
    for i = 1, 8 do
        local v = Step.vel(tr.steps[i])
        if v < 80 or v > 100 then error("vel out of range: " .. v) end
    end
end

function M.test_swapped_from_to()
    local tr = Track.new(8, 8)
    Track.groupEdit(tr, 5, 2, "set", "pitch", 80)
    eq(Step.pitch(tr.steps[2]), 80)
    eq(Step.pitch(tr.steps[5]), 80)
end

return M
