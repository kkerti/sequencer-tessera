local Track=require("seq_track")
local Pattern=require("seq_pattern")
local Step=require("seq_step")
local DIRECTION_FORWARD = "forward"
local DIRECTION_REVERSE = "reverse"
local DIRECTION_PINGPONG = "pingpong"
local DIRECTION_RANDOM = "random"
local DIRECTION_BROWNIAN = "brownian"
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
