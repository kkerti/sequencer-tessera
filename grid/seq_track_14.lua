local Track=require("seq_track")
function Track.pastePattern(track, destIndex, srcPattern)

    local Utils   = require("utils")
    local dest    = track.patterns[destIndex]
    local count   = srcPattern.stepCount

    -- Replace steps.
    dest.steps     = {}
    dest.stepCount = count
    for i = 1, count do
        dest.steps[i] = Utils.tableCopy(srcPattern.steps[i])
    end
    dest.name = srcPattern.name

    -- Cursor reset for safety — step count may have changed.
    track.cursor       = 1
    track.pulseCounter = 0
end
function Track.getStepCount(track)
    return Track._trackComputeStepCount(track)
end
function Track.getStep(track, index)
    local stepCount = Track._trackComputeStepCount(track)
    return Track._trackGetStepAtFlat(track, index)
end
