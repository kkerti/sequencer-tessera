local Track=require("seq_track")
function Track._trackDispatchDirection(track, cursor, rangeStart, rangeEnd)
    if track.direction == Track._DIRECTION_FORWARD then
        return Track._trackNextForward(cursor, rangeStart, rangeEnd)
    end
    if track.direction == Track._DIRECTION_REVERSE then
        return Track._trackNextReverse(cursor, rangeStart, rangeEnd)
    end
    if track.direction == Track._DIRECTION_RANDOM then
        return Track._trackNextRandom(rangeStart, rangeEnd)
    end
    if track.direction == Track._DIRECTION_BROWNIAN then
        return Track._trackNextBrownian(cursor, rangeStart, rangeEnd)
    end
    return Track._trackNextPingPong(track, cursor, rangeStart, rangeEnd)
end
