local Track=require("seq_track")
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
function Track._trackRemovePatternFromArray(track, patternIndex)
    for i = patternIndex, track.patternCount - 1 do
        track.patterns[i] = track.patterns[i + 1]
    end
    track.patterns[track.patternCount] = nil
    track.patternCount = track.patternCount - 1
end
