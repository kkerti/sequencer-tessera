local Track=require("seq_track")
local Pattern=require("seq_pattern")
local Step=require("seq_step")
local DIRECTION_FORWARD = "forward"
local DIRECTION_REVERSE = "reverse"
local DIRECTION_PINGPONG = "pingpong"
local DIRECTION_RANDOM = "random"
local DIRECTION_BROWNIAN = "brownian"
function Track.setDirection(track, direction)
    track.direction = direction
    if direction == DIRECTION_PINGPONG then
        track.pingPongDir = 1
    end
end
function Track.getDirection(track)
    return track.direction
end
