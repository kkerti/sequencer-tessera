-- tests/test_track_region.lua
-- Region semantics within a single track:
--   - track plays only steps inside curRegion
--   - region switch happens at-end-of-region (not mid-region)
--   - per direction (FWD/REV/PP) the boundary is the natural wrap point

local Track = require("track")
local Step  = require("step")
local M = {}

local function eq(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end end

-- Seed all 64 steps with dur=1/gate=1 so every pulse advances exactly one
-- step. Pitch encodes the step index for easy assertions.
local function seedAll(tr)
    for i = 1, 64 do
        tr.steps[i] = Step.pack({ pitch=i % 128, vel=100, dur=1, gate=1 })
    end
end

local function positions(tr, n, queueGetter)
    local out = {}
    local res = {}
    for k = 1, n do
        local q = queueGetter and queueGetter(k) or 0
        Track.advance(tr, out, q)
        res[#res+1] = tr.pos
    end
    return res
end

function M.test_fwd_stays_in_region_2()
    local tr = Track.new()
    seedAll(tr)
    Track.reset(tr, 2)              -- region 2 = steps 17..32
    local p = positions(tr, 32)
    -- first 16 should be 17..32, then wrap to 17..32 again
    eq(p[1], 17); eq(p[16], 32); eq(p[17], 17); eq(p[32], 32)
end

function M.test_fwd_switch_at_boundary()
    local tr = Track.new()
    seedAll(tr)
    Track.reset(tr, 1)
    -- Queue region 3 from pulse 1; switch should happen after step 16.
    local p = positions(tr, 20, function(_) return 3 end)
    eq(p[1], 1); eq(p[16], 16)
    eq(p[17], 33, "should jump to region 3 lo")
    eq(p[18], 34)
    eq(tr.curRegion, 3)
    eq(tr.regionDone, true, "regionDone flag set after flip")
end

function M.test_rev_switch_at_boundary()
    local tr = Track.new()
    seedAll(tr)
    Track.reset(tr, 1)
    tr.dir = Track.DIR_REV
    -- region 1 reverse: starts at 16, walks down to 1, then should jump
    -- to region 4's hi (=64) on the next pulse if region 4 is queued.
    local p = positions(tr, 18, function(_) return 4 end)
    eq(p[1], 16); eq(p[16], 1)
    eq(p[17], 64, "should jump to queued region's hi")
    eq(p[18], 63)
    eq(tr.curRegion, 4)
end

function M.test_pp_switch_at_top_boundary()
    local tr = Track.new()
    seedAll(tr)
    Track.reset(tr, 1)
    tr.dir = Track.DIR_PP
    -- Ping-pong region 1: 1..16, then bounce. Queue region 2; the FIRST
    -- bounce (at step 16) is the boundary, so jump to region 2 lo.
    local p = positions(tr, 18, function(_) return 2 end)
    eq(p[1], 1); eq(p[16], 16)
    eq(p[17], 17, "PP top bounce + queue jumps to next region's lo")
    eq(p[18], 18)
    eq(tr.curRegion, 2)
end

function M.test_no_queue_means_loop()
    local tr = Track.new()
    seedAll(tr)
    Track.reset(tr, 4)              -- region 4 = steps 49..64
    local p = positions(tr, 32)
    eq(p[1], 49); eq(p[16], 64); eq(p[17], 49); eq(p[32], 64)
    eq(tr.curRegion, 4)
end

return M
