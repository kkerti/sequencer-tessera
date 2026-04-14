local Snapshot=require("seq_snapshot")
local Engine=require("seq_engine")
local Track=require("seq_track")
local Pattern=require("seq_pattern")
local Step=require("seq_step")
function Snapshot._snapshotSerializeStep(step)
    return {
        pitch = Step.getPitch(step),
        velocity = Step.getVelocity(step),
        duration = Step.getDuration(step),
        gate = Step.getGate(step),
        ratchet = Step.getRatchet(step),
        probability = Step.getProbability(step),
        active = Step.getActive(step),
    }
end
function Snapshot._snapshotSerializePattern(pattern)
    local p = {
        name = Pattern.getName(pattern),
        steps = {},
    }
    local stepCount = Pattern.getStepCount(pattern)
    for stepIndex = 1, stepCount do
        p.steps[stepIndex] = Snapshot._snapshotSerializeStep(Pattern.getStep(pattern, stepIndex))
    end
    return p
end
