local Track=require("seq_track")
local Pattern=require("seq_pattern")
function Track.insertPattern(track, patternIndex, stepCount)
    stepCount = stepCount or 8

    local newPat = Pattern.new(stepCount)

    -- Shift patterns forward.
    track.patternCount = track.patternCount + 1
    for i = track.patternCount, patternIndex + 1, -1 do
        track.patterns[i] = track.patterns[i - 1]
    end
    track.patterns[patternIndex] = newPat

    Track._trackAdjustLoopPointsAfterInsert(track, patternIndex, stepCount)

    track.cursor       = 1
    track.pulseCounter = 0
    return newPat
end
function Track.swapPatterns(track, indexA, indexB)

    if indexA == indexB then return end

    track.patterns[indexA], track.patterns[indexB] = track.patterns[indexB], track.patterns[indexA]

    -- Clear loop points since flat indices are now different.
    track.loopStart    = nil
    track.loopEnd      = nil
    track.cursor       = 1
    track.pulseCounter = 0
end
