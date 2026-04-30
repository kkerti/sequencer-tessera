-- tests/test_track_dir.lua
-- Direction tests within a single region (region 1 = steps 1..16).
local Track = require("track")
local Step  = require("step")
local M = {}

local function eq(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end end

-- All tests use region 1 (steps 1..16). We seed those 16 with dur=1 so each
-- pulse advances exactly one step.
local function fillRegion1(tr)
    for i = 1, 16 do
        tr.steps[i] = Step.pack({ pitch=59+i, vel=100, dur=1, gate=1 })
    end
end

local function collectPositions(tr, nSteps)
    local positions = {}
    Track.reset(tr, 1)  -- region 1
    for _ = 1, nSteps do
        local out = {}
        Track.advance(tr, out, 0)  -- no queued region
        positions[#positions+1] = tr.pos
    end
    return positions
end

function M.test_forward()
    local tr = Track.new()
    fillRegion1(tr)
    tr.dir = Track.DIR_FWD
    local p = collectPositions(tr, 18)
    -- 1..16 then wrap to 1, 2
    eq(p[1], 1); eq(p[16], 16); eq(p[17], 1); eq(p[18], 2)
end

function M.test_reverse()
    local tr = Track.new()
    fillRegion1(tr)
    tr.dir = Track.DIR_REV
    local p = collectPositions(tr, 18)
    -- starting from pos=0 (outside region): snap to hi=16, then 15..1, wrap to 16
    eq(p[1], 16); eq(p[2], 15); eq(p[16], 1); eq(p[17], 16); eq(p[18], 15)
end

function M.test_pingpong()
    local tr = Track.new()
    fillRegion1(tr)
    tr.dir = Track.DIR_PP
    local p = collectPositions(tr, 32)
    -- 1..16 then bounce: 15..1 then 2..16 ...
    eq(p[1], 1); eq(p[16], 16); eq(p[17], 15); eq(p[31], 1); eq(p[32], 2)
end

function M.test_random_in_range()
    local tr = Track.new()
    fillRegion1(tr)
    tr.dir = Track.DIR_RND
    math.randomseed(1)
    local p = collectPositions(tr, 50)
    for _, v in ipairs(p) do
        if v < 1 or v > 16 then error("out of range: " .. v) end
    end
end

return M
