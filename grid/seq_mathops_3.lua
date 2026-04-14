local MathOps=require("seq_mathops")
local Track=require("seq_track")
local Step=require("seq_step")
local Utils=require("seq_utils")
local PARAM_BOUNDS = {
function MathOps.transpose(track, semitones, startIndex, endIndex)
    startIndex, endIndex = MathOps._mathOpsGetRange(track, startIndex, endIndex)

    for i = startIndex, endIndex do
        local step = Track.getStep(track, i)
        local nextPitch = Utils.clamp(Step.getPitch(step) + semitones, 0, 127)
        Step.setPitch(step, nextPitch)
    end
end
