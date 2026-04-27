-- sequencer_lite/pattern.lua
-- LITE BUILD: copy of sequencer/pattern.lua with require paths rewritten.
-- See docs/dropped-features.md.
--
-- A Pattern is a named, ordered list of Steps within a Track.

local Step    = require("sequencer_lite/step")

local Pattern = {}

local NAME_MAX_LEN = 32

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

function Pattern.getStepCount(pattern)
    return pattern.stepCount
end

function Pattern.getStep(pattern, index)
    assert(type(index) == "number" and index >= 1 and index <= pattern.stepCount,
        "patternGetStep: index out of range 1-" .. pattern.stepCount)
    return pattern.steps[index]
end

function Pattern.setStep(pattern, index, step)
    assert(type(index) == "number" and index >= 1 and index <= pattern.stepCount,
        "patternSetStep: index out of range 1-" .. pattern.stepCount)
    assert(type(step) == "table", "patternSetStep: step must be a table")
    pattern.steps[index] = step
end

function Pattern.getName(pattern)
    return pattern.name
end

function Pattern.setName(pattern, name)
    assert(type(name) == "string" and #name <= NAME_MAX_LEN,
        "patternSetName: name must be a string of max " .. NAME_MAX_LEN .. " characters")
    pattern.name = name
end

return Pattern
