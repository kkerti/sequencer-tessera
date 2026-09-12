-- generate.lua — step generators for a lane. Pure, alloc-free.
--
-- Gamut: fills a lane with values drawn around a base note, quantized to the
-- lane's scale, biased by `downUp` (0 = all below the base, 127 = all above),
-- with optional velocity/gate spread. Deterministic for a given `seed`.
--
-- Euclid: fills a Trig/Gate lane with `hits` onsets spread across the steps.
--
-- Live use: Engine.onPulse calls `step` for a lane whose generator is on, so
-- the value at the playhead is regenerated as it arrives. All arithmetic, no
-- allocation.

local Scales = require("scales")

local M = {}

local RNG_MOD = 2147483647

function M.seed(lane, seed)
    local s = (seed or 1) % RNG_MOD
    if s <= 0 then s = 1 end
    lane.rng = s
end

function M.configure(lane, opts)
    opts = opts or {}
    lane.genBase = opts.base or 60
    lane.genSpread = opts.spread or 12
    lane.genDownUp = opts.downUp or 64
    lane.genVelSpread = opts.velSpread or 0
    lane.genGateSpread = opts.gateSpread or 0
    M.seed(lane, opts.seed or 1)
end

-- Advance the per-lane LCG and return an integer in [lo, hi].
local function nextInt(lane, lo, hi)
    lane.rng = (lane.rng * 1103515245 + 12345) % RNG_MOD
    local span = hi - lo + 1
    local v = lo + math.floor((lane.rng / RNG_MOD) * span)
    if v > hi then v = hi end
    return v
end

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi else return v end
end

function M.step(lane, pos)
    pos = pos or lane.position
    if lane.type == "note" then
        local up = math.floor(lane.genSpread * lane.genDownUp / 127 + 0.5)
        local down = lane.genSpread - up
        local off = nextInt(lane, -down, up)
        lane.pitch[pos] = clamp(Scales.quantize(lane.genBase + off, lane.scaleMask),
                                lane.minNote, lane.maxNote)
        if lane.genVelSpread > 0 then
            lane.velocity[pos] = clamp(100 + nextInt(lane, -lane.genVelSpread, lane.genVelSpread), 1, 127)
        end
        if lane.genGateSpread > 0 then
            lane.stepLength[pos] = math.max(1, 6 + nextInt(lane, -lane.genGateSpread, lane.genGateSpread))
        end
    elseif lane.type == "mod" then
        local mid = (lane.minValue + lane.maxValue) // 2
        lane.value[pos] = clamp(mid + nextInt(lane, -lane.genSpread, lane.genSpread), 0, 127)
    else
        -- Trig/Gate: `genSpread` reads as density percent (0..100), default 50.
        local density = (lane.genSpread > 0 and lane.genSpread <= 100) and lane.genSpread or 50
        lane.gate[pos] = (nextInt(lane, 0, 99) < density) and 1 or 0
    end
end

local function usedSteps(lane)
    if lane.height == 1 then return lane.length end
    return lane.width * lane.height
end

function M.fill(lane)
    local used = usedSteps(lane)
    for i = 1, used do M.step(lane, i) end
end

function M.euclidean(lane, opts)
    opts = opts or {}
    local used = usedSteps(lane)
    local hits = opts.hits or math.max(1, used // 4)
    if hits > used then hits = used end
    local rotate = opts.rotate or 0
    for i = 1, used do
        local idx = ((i - 1) + rotate) % used
        lane.gate[i] = (((idx * hits) % used) < hits) and 1 or 0
    end
    return true
end

return M
