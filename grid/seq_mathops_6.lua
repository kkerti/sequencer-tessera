local MathOps=require("seq_mathops")
local Track=require("seq_track")
local Utils=require("seq_utils")
function MathOps.randomize(track, param, minValue, maxValue, startIndex, endIndex)
    startIndex, endIndex = MathOps._mathOpsGetRange(track, startIndex, endIndex)

    local hardMin = MathOps._PARAM_BOUNDS[param].min
    local hardMax = MathOps._PARAM_BOUNDS[param].max
    minValue = Utils.clamp(minValue, hardMin, hardMax)
    maxValue = Utils.clamp(maxValue, hardMin, hardMax)

    for i = startIndex, endIndex do
        local step = Track.getStep(track, i)
        local nextValue = math.random(minValue, maxValue)
        MathOps._mathOpsSetValue(step, param, nextValue)
    end
end
