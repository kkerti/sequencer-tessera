-- sequencer/mathops.lua
-- Parameter operations applied to step ranges.

local Seq   = require("sequencer")
require("authoring")           -- extend Step/Pattern/Track with editor methods
local Track = Seq.Track
local Step  = Seq.Step
local Utils = Seq.Utils

local MathOps = {}

local PARAM_BOUNDS = {
    pitch = { min = 0, max = 127 },
    velocity = { min = 0, max = 127 },
    duration = { min = 0, max = 99 },
    gate = { min = 0, max = 99 },
}

local function mathOpsGetRange(track, startIndex, endIndex)
    local stepCount = Track.getStepCount(track)
    startIndex = startIndex or 1
    endIndex = endIndex or stepCount

    assert(type(startIndex) == "number" and startIndex >= 1 and startIndex <= stepCount,
        "mathOps: startIndex out of range")
    assert(type(endIndex) == "number" and endIndex >= 1 and endIndex <= stepCount,
        "mathOps: endIndex out of range")
    assert(startIndex <= endIndex, "mathOps: startIndex must be <= endIndex")

    return startIndex, endIndex
end

local function mathOpsGetValue(step, param)
    if param == "pitch" then return Step.getPitch(step) end
    if param == "velocity" then return Step.getVelocity(step) end
    if param == "duration" then return Step.getDuration(step) end
    if param == "gate" then return Step.getGate(step) end
    error("mathOps: unsupported param")
end

local function mathOpsSetValue(step, param, value)
    -- Returns a new packed step. Steps are immutable integers; setters are pure.
    if param == "pitch" then return Step.setPitch(step, value) end
    if param == "velocity" then return Step.setVelocity(step, value) end
    if param == "duration" then return Step.setDuration(step, value) end
    if param == "gate" then return Step.setGate(step, value) end
    error("mathOps: unsupported param")
end

function MathOps.transpose(track, semitones, startIndex, endIndex)
    assert(type(semitones) == "number", "mathOpsTranspose: semitones must be a number")
    startIndex, endIndex = mathOpsGetRange(track, startIndex, endIndex)

    for i = startIndex, endIndex do
        local step = Track.getStep(track, i)
        local nextPitch = Utils.clamp(Step.getPitch(step) + semitones, 0, 127)
        Track.setStep(track, i, Step.setPitch(step, nextPitch))
    end
end

function MathOps.jitter(track, param, amount, startIndex, endIndex)
    assert(PARAM_BOUNDS[param] ~= nil, "mathOpsJitter: unsupported param")
    assert(type(amount) == "number" and amount >= 0, "mathOpsJitter: amount must be >= 0")
    startIndex, endIndex = mathOpsGetRange(track, startIndex, endIndex)

    local min = PARAM_BOUNDS[param].min
    local max = PARAM_BOUNDS[param].max

    for i = startIndex, endIndex do
        local step = Track.getStep(track, i)
        local current = mathOpsGetValue(step, param)
        local delta = math.random(-amount, amount)
        local nextValue = Utils.clamp(current + delta, min, max)
        nextValue = math.floor(nextValue)
        Track.setStep(track, i, mathOpsSetValue(step, param, nextValue))
    end
end

function MathOps.randomize(track, param, minValue, maxValue, startIndex, endIndex)
    assert(PARAM_BOUNDS[param] ~= nil, "mathOpsRandomize: unsupported param")
    assert(type(minValue) == "number" and type(maxValue) == "number" and minValue <= maxValue,
        "mathOpsRandomize: invalid bounds")
    startIndex, endIndex = mathOpsGetRange(track, startIndex, endIndex)

    local hardMin = PARAM_BOUNDS[param].min
    local hardMax = PARAM_BOUNDS[param].max
    minValue = Utils.clamp(minValue, hardMin, hardMax)
    maxValue = Utils.clamp(maxValue, hardMin, hardMax)

    for i = startIndex, endIndex do
        local step = Track.getStep(track, i)
        local nextValue = math.random(minValue, maxValue)
        Track.setStep(track, i, mathOpsSetValue(step, param, nextValue))
    end
end

return MathOps
