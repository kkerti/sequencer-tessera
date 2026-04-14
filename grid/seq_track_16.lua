local Track=require("seq_track")
local Pattern=require("seq_pattern")
local Step=require("seq_step")
local DIRECTION_FORWARD = "forward"
local DIRECTION_REVERSE = "reverse"
local DIRECTION_PINGPONG = "pingpong"
local DIRECTION_RANDOM = "random"
local DIRECTION_BROWNIAN = "brownian"
function Track.getStepCount(track)
    return Track._trackComputeStepCount(track)
end
function Track.getStep(track, index)
    local stepCount = Track._trackComputeStepCount(track)
    return Track._trackGetStepAtFlat(track, index)
end
function Track.setStep(track, index, step)
    local stepCount = Track._trackComputeStepCount(track)

    local offset = 0
    for i = 1, track.patternCount do
        local pat      = track.patterns[i]
        local patCount = Pattern.getStepCount(pat)
        if index <= offset + patCount then
            Pattern.setStep(pat, index - offset, step)
            return
        end
        offset = offset + patCount
    end
end
