local Track=require("seq_track")
local Pattern=require("seq_pattern")
local Step=require("seq_step")
local DIRECTION_FORWARD = "forward"
local DIRECTION_REVERSE = "reverse"
local DIRECTION_PINGPONG = "pingpong"
local DIRECTION_RANDOM = "random"
local DIRECTION_BROWNIAN = "brownian"
function Track.duplicatePattern(track, srcIndex)

    local Utils  = require("utils")
    local src    = track.patterns[srcIndex]
    local count  = Pattern.getStepCount(src)
    local newPat = Pattern.new(0, Pattern.getName(src))

    newPat.steps     = {}
    newPat.stepCount = count
    for i = 1, count do
        newPat.steps[i] = Utils.tableCopy(src.steps[i])
    end

    -- Shift patterns after srcIndex forward by one slot.
    track.patternCount = track.patternCount + 1
    for i = track.patternCount, srcIndex + 2, -1 do
        track.patterns[i] = track.patterns[i - 1]
    end
    track.patterns[srcIndex + 1] = newPat
    return newPat
end
