local Track=require("seq_track")
local Pattern=require("seq_pattern")
local Step=require("seq_step")
local DIRECTION_FORWARD = "forward"
local DIRECTION_REVERSE = "reverse"
local DIRECTION_PINGPONG = "pingpong"
local DIRECTION_RANDOM = "random"
local DIRECTION_BROWNIAN = "brownian"
function Track.getCurrentStep(track)
    return Track._trackGetStepAtFlat(track, track.cursor)
end
function Track.setLoopStart(track, index)
    local stepCount = Track._trackComputeStepCount(track)
    if track.loopEnd ~= nil then
    end
    track.loopStart = index
end
function Track.setLoopEnd(track, index)
    local stepCount = Track._trackComputeStepCount(track)
    if track.loopStart ~= nil then
    end
    track.loopEnd = index
end
function Track.clearLoopStart(track)
    track.loopStart = nil
end
function Track.clearLoopEnd(track)
    track.loopEnd = nil
end
function Track.getLoopStart(track)
    return track.loopStart
end
