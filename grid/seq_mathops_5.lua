local MathOps=require("seq_mathops")
local Track=require("seq_track")
local Step=require("seq_step")
local Utils=require("seq_utils")
local PARAM_BOUNDS = {
function MathOps.randomize(track, param, minValue, maxValue, startIndex, endIndex)
    startIndex, endIndex = MathOps._mathOpsGetRange(track, startIndex, endIndex)

    local hardMin = PARAM_BOUNDS[param].min
    local hardMax = PARAM_BOUNDS[param].max
    minValue = Utils.clamp(minValue, hardMin, hardMax)
    maxValue = Utils.clamp(maxValue, hardMin, hardMax)

    for i = startIndex, endIndex do
        local step = Track.getStep(track, i)
        local nextValue = math.random(minValue, maxValue)
        MathOps._mathOpsSetValue(step, param, nextValue)
    end
end
