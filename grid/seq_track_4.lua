local Track=require("seq_track")
function Track._trackNextPingPong(track, cursor, rangeStart, rangeEnd)
    if rangeStart == rangeEnd then
        return rangeStart
    end

    if track.pingPongDir > 0 then
        if cursor >= rangeEnd then
            track.pingPongDir = -1
            return cursor - 1
        end
        return cursor + 1
    end

    if cursor <= rangeStart then
        track.pingPongDir = 1
        return cursor + 1
    end
    return cursor - 1
end
function Track._trackResetOutOfRange(track, rangeStart, rangeEnd)
    if track.direction == Track._DIRECTION_REVERSE then
        return rangeEnd
    end
    if track.direction == Track._DIRECTION_RANDOM then
        return Track._trackNextRandom(rangeStart, rangeEnd)
    end
    return rangeStart
end
