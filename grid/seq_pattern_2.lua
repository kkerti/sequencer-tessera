local Pattern=require("seq_pattern")
local Step=require("seq_step")
function Pattern.new(stepCount, name)
    stepCount = stepCount or 0
    name      = name or ""


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
    return pattern.steps[index]
end
function Pattern.setStep(pattern, index, step)
    pattern.steps[index] = step
end
function Pattern.getName(pattern)
    return pattern.name
end
function Pattern.setName(pattern, name)
    pattern.name = name
end
