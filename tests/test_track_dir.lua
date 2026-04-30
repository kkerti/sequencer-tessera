-- tests/test_track_dir.lua
local Track = require("track")
local Step  = require("step")
local M = {}

local function eq(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end end

local function fillTrack(tr, len)
    for i = 1, len do
        tr.steps[i] = Step.pack({ pitch=59+i, vel=100, dur=1, gate=1 })
    end
    tr.len = len
end

local function collectPositions(tr, nSteps)
    local positions = {}
    Track.reset(tr)
    for _ = 1, nSteps do
        local out = {}
        Track.advance(tr, out) -- advances one pulse, with dur=1 each pulse = next step
        positions[#positions+1] = tr.pos
    end
    return positions
end

function M.test_forward()
    local tr = Track.new(8, 4)
    fillTrack(tr, 4)
    tr.dir = Track.DIR_FWD
    local p = collectPositions(tr, 8)
    eq(table.concat(p, ","), "1,2,3,4,1,2,3,4")
end

function M.test_reverse()
    local tr = Track.new(8, 4)
    fillTrack(tr, 4)
    tr.dir = Track.DIR_REV
    local p = collectPositions(tr, 8)
    -- reverse from pos=0: nextPos -> 0-1 = -1 -> wraps to len=4
    eq(p[1], 4)
    eq(p[2], 3)
    eq(p[3], 2)
    eq(p[4], 1)
    eq(p[5], 4)
end

function M.test_pingpong()
    local tr = Track.new(8, 4)
    fillTrack(tr, 4)
    tr.dir = Track.DIR_PP
    local p = collectPositions(tr, 8)
    -- 1,2,3,4 then bounce back: 3,2,1, then bounce: 2,3
    eq(p[1], 1); eq(p[2], 2); eq(p[3], 3); eq(p[4], 4)
    eq(p[5], 3); eq(p[6], 2); eq(p[7], 1); eq(p[8], 2)
end

function M.test_random_in_range()
    local tr = Track.new(8, 4)
    fillTrack(tr, 4)
    tr.dir = Track.DIR_RND
    math.randomseed(1)
    local p = collectPositions(tr, 50)
    for _, v in ipairs(p) do
        if v < 1 or v > 4 then error("out of range: " .. v) end
    end
end

return M
