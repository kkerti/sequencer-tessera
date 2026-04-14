local Track=require("seq_track")
local Pattern=require("seq_pattern")
local Step=require("seq_step")

local DIRECTION_FORWARD = "forward"
local DIRECTION_REVERSE = "reverse"
local DIRECTION_PINGPONG = "pingpong"
local DIRECTION_RANDOM = "random"
local DIRECTION_BROWNIAN = "brownian"
function Track._trackDispatchDirection(track, cursor, rangeStart, rangeEnd)
    if track.direction == DIRECTION_FORWARD then
        return Track._trackNextForward(cursor, rangeStart, rangeEnd)
    end
    if track.direction == DIRECTION_REVERSE then
        return Track._trackNextReverse(cursor, rangeStart, rangeEnd)
    end
    if track.direction == DIRECTION_RANDOM then
        return Track._trackNextRandom(rangeStart, rangeEnd)
    end
    if track.direction == DIRECTION_BROWNIAN then
        return Track._trackNextBrownian(cursor, rangeStart, rangeEnd)
    end
    return Track._trackNextPingPong(track, cursor, rangeStart, rangeEnd)
end
