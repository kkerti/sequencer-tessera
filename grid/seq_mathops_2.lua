local MathOps=require("seq_mathops")
local Track=require("seq_track")
local Step=require("seq_step")
function MathOps._mathOpsGetRange(track, startIndex, endIndex)
    local stepCount = Track.getStepCount(track)
    startIndex = startIndex or 1
    endIndex = endIndex or stepCount


    return startIndex, endIndex
end
function MathOps._mathOpsGetValue(step, param)
    if param == "pitch" then return Step.getPitch(step) end
    if param == "velocity" then return Step.getVelocity(step) end
    if param == "duration" then return Step.getDuration(step) end
    if param == "gate" then return Step.getGate(step) end
    if param == "ratchet" then return Step.getRatchet(step) end
    error("mathOps: unsupported param")
end
