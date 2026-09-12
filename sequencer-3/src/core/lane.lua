-- lane.lua — one lane's fixed storage + navigation.
--
-- A lane owns up to 16 steps held in preallocated parallel arrays (never a
-- table per step, never grown at runtime). Pure and alloc-free on the pulse
-- path.

local Sources = require("sources")

local M = {}

M.CAP = 16

local DIMS = {
    ["16x1"] = { width = 16, height = 1 },
    ["8x2"]  = { width = 8,  height = 2 },
    ["5x3"]  = { width = 5,  height = 3 },
    ["4x3"]  = { width = 4,  height = 3 },
    ["4x4"]  = { width = 4,  height = 4 },
}
M.DIMS = DIMS

function M.isValidDims(name) return DIMS[name] ~= nil end

function M.new(kind)
    local l = {
        type = kind or "note",
        dims = "16x1", width = 16, height = 1,
        length = 16, division = 1, divCount = 0,
        position = 1, emit = false, pendingReset = false, fired = false,
        channel = 1, controller = 1, midiNote = 60,
        scaleMask = 0xAB5, rawScaleMask = 0xAB5, root = 0,
        minNote = 0, maxNote = 127,
        minValue = 0, maxValue = 127,
        advanceSource = Sources.OFF,
        xAdvanceSource = Sources.OFF,
        yAdvanceSource = Sources.OFF,
        resetSource = Sources.OFF,
        randomSource = Sources.OFF,
        previousSource = Sources.OFF,
        shiftSource = Sources.OFF, shiftAmount = 1,
        addressSource = Sources.OFF,
        xAddressSource = Sources.OFF,
        yAddressSource = Sources.OFF,
        activeNote = nil, noteOffIn = 0, sustain = false,
        generator = 0,
        genBase = 60, genSpread = 12, genDownUp = 64,
        genVelSpread = 0, genGateSpread = 0, rng = 1,
        pitch = {}, velocity = {}, stepLength = {}, value = {}, gate = {},
    }
    for i = 1, M.CAP do
        l.pitch[i] = 60
        l.velocity[i] = 100
        l.stepLength[i] = 6
        l.value[i] = 0
        l.gate[i] = 0
    end
    return l
end

function M.usedSteps(lane) return lane.width * lane.height end

function M.limit(lane)
    if lane.height == 1 then return lane.length end
    return lane.width * lane.height
end

-- 1-based linear index for a 0-based (x, y).
function M.index(lane, x, y)
    return y * lane.width + x + 1
end

function M.setPosition(lane, p)
    local limit = M.limit(lane)
    if p < 1 then p = 1 elseif p > limit then p = limit end
    lane.position = p
    lane.emit = true
end

function M.advanceForward(lane)
    local limit = M.limit(lane)
    local p = lane.position + 1
    if p > limit then p = 1 end
    lane.position = p
    lane.emit = true
end

function M.advanceBackward(lane)
    local limit = M.limit(lane)
    local p = lane.position - 1
    if p < 1 then p = limit end
    lane.position = p
    lane.emit = true
end

function M.advanceX(lane)
    if lane.height == 1 then return M.advanceForward(lane) end
    local p = lane.position - 1
    local x = p % lane.width
    local y = p // lane.width
    x = (x + 1) % lane.width
    lane.position = y * lane.width + x + 1
    lane.emit = true
end

function M.advanceY(lane)
    if lane.height == 1 then return end
    local p = lane.position - 1
    local x = p % lane.width
    local y = p // lane.width
    y = (y + 1) % lane.height
    lane.position = y * lane.width + x + 1
    lane.emit = true
end

function M.randomizePosition(lane)
    lane.position = math.random(1, M.limit(lane))
    lane.emit = true
end

function M.setDims(lane, name)
    local d = DIMS[name]
    if not d then return false end
    lane.dims, lane.width, lane.height = name, d.width, d.height
    local used = lane.width * lane.height
    if lane.length > used then lane.length = used end
    if lane.position > M.limit(lane) then lane.position = 1 end
    return true
end

-- Positional rotate of step values. Preallocated scratch, alloc-free.
local scratch = {}
local function rotateOne(arr, used, amount)
    for i = 1, used do scratch[i] = arr[i] end
    for i = 1, used do arr[((i - 1 + amount) % used) + 1] = scratch[i] end
end

function M.rotate(lane, amount)
    local used = M.limit(lane)
    amount = amount % used
    if amount == 0 then return end
    if lane.type == "note" then
        rotateOne(lane.pitch, used, amount)
        rotateOne(lane.velocity, used, amount)
        rotateOne(lane.stepLength, used, amount)
    elseif lane.type == "mod" then
        rotateOne(lane.value, used, amount)
    else
        rotateOne(lane.gate, used, amount)
    end
end

return M
