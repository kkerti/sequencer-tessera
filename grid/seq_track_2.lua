local Track=require("seq_track")
local Pattern=require("seq_pattern")
local Step=require("seq_step")

local DIRECTION_FORWARD = "forward"
local DIRECTION_REVERSE = "reverse"
local DIRECTION_PINGPONG = "pingpong"
local DIRECTION_RANDOM = "random"
local DIRECTION_BROWNIAN = "brownian"
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
function Track._trackNextForward(cursor, rangeStart, rangeEnd)
    if cursor >= rangeEnd then
        return rangeStart
    end
    return cursor + 1
end
function Track._trackNextReverse(cursor, rangeStart, rangeEnd)
    if cursor <= rangeStart then
        return rangeEnd
    end
    return cursor - 1
end
