local Track=require("seq_track")
local Pattern=require("seq_pattern")
local Step=require("seq_step")
local DIRECTION_FORWARD = "forward"
local DIRECTION_REVERSE = "reverse"
local DIRECTION_PINGPONG = "pingpong"
local DIRECTION_RANDOM = "random"
local DIRECTION_BROWNIAN = "brownian"
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
