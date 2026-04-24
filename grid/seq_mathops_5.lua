local MathOps=require("seq_mathops")
local Track=require("seq_track")
local Utils=require("seq_utils")
function MathOps.jitter(track, param, amount, startIndex, endIndex)
    startIndex, endIndex = MathOps._mathOpsGetRange(track, startIndex, endIndex)

    local min = MathOps._PARAM_BOUNDS[param].min
    local max = MathOps._PARAM_BOUNDS[param].max

    for i = startIndex, endIndex do
        local step = Track.getStep(track, i)
        local current = MathOps._mathOpsGetValue(step, param)
        local delta = math.random(-amount, amount)
        local nextValue = Utils.clamp(current + delta, min, max)
        nextValue = math.floor(nextValue)
        MathOps._mathOpsSetValue(step, param, nextValue)
    end
end
