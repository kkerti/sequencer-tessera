local Track=require("seq_track")
local Pattern=require("seq_pattern")
local Step=require("seq_step")

local DIRECTION_FORWARD = "forward"
local DIRECTION_REVERSE = "reverse"
local DIRECTION_PINGPONG = "pingpong"
local DIRECTION_RANDOM = "random"
local DIRECTION_BROWNIAN = "brownian"
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
