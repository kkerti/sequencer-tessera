local Track=require("seq_track")
local Pattern=require("seq_pattern")
function Track.patternStartIndex(track, patternIndex)
    local offset = 0
    for i = 1, patternIndex - 1 do
        offset = offset + Pattern.getStepCount(track.patterns[i])
    end
    return offset + 1
end
function Track.patternEndIndex(track, patternIndex)
    local offset = 0
    for i = 1, patternIndex do
        offset = offset + Pattern.getStepCount(track.patterns[i])
    end
    return offset
end
function Track.copyPattern(track, srcIndex)

    local Utils  = require("utils")
    local src    = track.patterns[srcIndex]
    local count  = Pattern.getStepCount(src)
    local newPat = Pattern.new(0, Pattern.getName(src))

    newPat.steps     = {}
    newPat.stepCount = count
    for i = 1, count do
        newPat.steps[i] = Utils.tableCopy(src.steps[i])
    end

    track.patternCount = track.patternCount + 1
    track.patterns[track.patternCount] = newPat
    return newPat
end
