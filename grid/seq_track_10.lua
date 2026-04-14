local Track=require("seq_track")
local Pattern=require("seq_pattern")
local Step=require("seq_step")
local DIRECTION_FORWARD = "forward"
local DIRECTION_REVERSE = "reverse"
local DIRECTION_PINGPONG = "pingpong"
local DIRECTION_RANDOM = "random"
local DIRECTION_BROWNIAN = "brownian"
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
