-- sequencer/pattern.lua
-- A Pattern is a named, ordered list of Steps within a Track.
-- It is a purely organisational unit — no per-pattern clock parameters.
-- Patterns are contiguous slices of a track's step sequence (ER-101 model).
-- A Pattern owns its steps directly; the Track owns its Patterns.

local Step    = require("sequencer/step")

local Pattern = {}

local NAME_MAX_LEN = 32

-- Constructor.
-- stepCount : number of default Steps to pre-populate (default 0 = empty)
-- name      : optional string label (default "")
function Pattern.new(stepCount, name)
    stepCount = stepCount or 0
    name      = name or ""

    assert(type(stepCount) == "number" and stepCount >= 0 and math.floor(stepCount) == stepCount,
        "patternNew: stepCount must be a non-negative integer")
    assert(type(name) == "string" and #name <= NAME_MAX_LEN,
        "patternNew: name must be a string of max " .. NAME_MAX_LEN .. " characters")

    local steps = {}
    for i = 1, stepCount do
        steps[i] = Step.new()
    end

    return {
        steps     = steps,
        stepCount = stepCount,
        name      = name,
    }
end

-- Returns the number of steps in this pattern.
function Pattern.getStepCount(pattern)
    return pattern.stepCount
end

-- Returns the Step at 1-based index, or nil if out of range.
function Pattern.getStep(pattern, index)
    assert(type(index) == "number" and index >= 1 and index <= pattern.stepCount,
        "patternGetStep: index out of range 1-" .. pattern.stepCount)
    return pattern.steps[index]
end

-- Replaces the Step at 1-based index.
function Pattern.setStep(pattern, index, step)
    assert(type(index) == "number" and index >= 1 and index <= pattern.stepCount,
        "patternSetStep: index out of range 1-" .. pattern.stepCount)
    assert(type(step) == "number", "patternSetStep: step must be a packed integer")
    pattern.steps[index] = step
end

-- Returns the pattern name.
function Pattern.getName(pattern)
    return pattern.name
end

-- Sets the pattern name.
function Pattern.setName(pattern, name)
    assert(type(name) == "string" and #name <= NAME_MAX_LEN,
        "patternSetName: name must be a string of max " .. NAME_MAX_LEN .. " characters")
    pattern.name = name
end

return Pattern
