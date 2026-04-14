local Track=require("seq_track")
local Pattern=require("seq_pattern")
local Step=require("seq_step")
local DIRECTION_FORWARD = "forward"
local DIRECTION_REVERSE = "reverse"
local DIRECTION_PINGPONG = "pingpong"
local DIRECTION_RANDOM = "random"
local DIRECTION_BROWNIAN = "brownian"
function Track.getLoopEnd(track)
    return track.loopEnd
end
function Track.setClockDiv(track, value)
    track.clockDiv = value
end
function Track.getClockDiv(track)
    return track.clockDiv
end
function Track.setClockMult(track, value)
    track.clockMult = value
end
function Track.getClockMult(track)
    return track.clockMult
end
function Track.setMidiChannel(track, channel)
    track.midiChannel = channel
end
function Track.clearMidiChannel(track)
    track.midiChannel = nil
end
function Track.getMidiChannel(track)
    return track.midiChannel
end
