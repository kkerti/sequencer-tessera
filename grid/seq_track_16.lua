local Track=require("seq_track")
function Track.clearLoopStart(track)
    track.loopStart = nil
end
function Track.clearLoopEnd(track)
    track.loopEnd = nil
end
function Track.getLoopStart(track)
    return track.loopStart
end
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
