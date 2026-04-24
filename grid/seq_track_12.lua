local Track=require("seq_track")
function Track.deletePattern(track, patternIndex)

    local delStart = Track.patternStartIndex(track, patternIndex)
    local delEnd   = Track.patternEndIndex(track, patternIndex)
    local delCount = delEnd - delStart + 1

    Track._trackRemovePatternFromArray(track, patternIndex)

    track.loopStart = Track._trackShiftLoopAfterDelete(track.loopStart, delStart, delEnd, delCount)
    track.loopEnd   = Track._trackShiftLoopAfterDelete(track.loopEnd,   delStart, delEnd, delCount)

    track.cursor       = 1
    track.pulseCounter = 0
end
