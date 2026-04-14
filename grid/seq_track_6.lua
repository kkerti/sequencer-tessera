local Track=require("seq_track")
local Pattern=require("seq_pattern")
local Step=require("seq_step")

local DIRECTION_FORWARD = "forward"
local DIRECTION_REVERSE = "reverse"
local DIRECTION_PINGPONG = "pingpong"
local DIRECTION_RANDOM = "random"
local DIRECTION_BROWNIAN = "brownian"
function Track._trackGetNextCursor(track, cursor)
    local stepCount = Track._trackComputeStepCount(track)
    if stepCount == 0 then
        return 1
    end

    local rangeStart = track.loopStart or 1
    local rangeEnd = track.loopEnd or stepCount

    if cursor < rangeStart or cursor > rangeEnd then
        return Track._trackResetOutOfRange(track, rangeStart, rangeEnd)
    end

    return Track._trackDispatchDirection(track, cursor, rangeStart, rangeEnd)
end
