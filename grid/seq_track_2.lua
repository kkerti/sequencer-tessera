local Track=require("seq_track")
local Pattern=require("seq_pattern")
function Track._trackIsDirectionValid(direction)
    return direction == Track._DIRECTION_FORWARD or
        direction == Track._DIRECTION_REVERSE or
        direction == Track._DIRECTION_PINGPONG or
        direction == Track._DIRECTION_RANDOM or
        direction == Track._DIRECTION_BROWNIAN
end
function Track._trackComputeStepCount(track)
    local total = 0
    for i = 1, track.patternCount do
        total = total + Pattern.getStepCount(track.patterns[i])
    end
    return total
end
function Track._trackGetStepAtFlat(track, flatIndex)
    local offset = 0
    for i = 1, track.patternCount do
        local pat      = track.patterns[i]
        local patCount = Pattern.getStepCount(pat)
        if flatIndex <= offset + patCount then
            return Pattern.getStep(pat, flatIndex - offset)
        end
        offset = offset + patCount
    end
    return nil
end
