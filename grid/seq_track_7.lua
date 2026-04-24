local Track=require("seq_track")
function Track._trackShiftLoopAfterDelete(value, delStart, delEnd, delCount)
    if value == nil then return nil end
    if value >= delStart and value <= delEnd then return nil end
    if value > delEnd then return value - delCount end
    return value
end
function Track._trackAdjustLoopPointsAfterInsert(track, patternIndex, stepCount)
    if stepCount <= 0 then
        return
    end
    local insertStart = Track.patternStartIndex(track, patternIndex)
    if track.loopStart ~= nil and track.loopStart >= insertStart then
        track.loopStart = track.loopStart + stepCount
    end
    if track.loopEnd ~= nil and track.loopEnd >= insertStart then
        track.loopEnd = track.loopEnd + stepCount
    end
end
