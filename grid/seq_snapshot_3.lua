local Snapshot=require("seq_snapshot")
local Engine=require("seq_engine")
local Track=require("seq_track")
function Snapshot._snapshotSerializeTrack(engine, trackIndex)
    local track = Engine.getTrack(engine, trackIndex)
    local t = {
        clockDiv = Track.getClockDiv(track),
        clockMult = Track.getClockMult(track),
        direction = Track.getDirection(track),
        midiChannel = Track.getMidiChannel(track),
        loopStart = Track.getLoopStart(track),
        loopEnd = Track.getLoopEnd(track),
        cursor = track.cursor,
        pulseCounter = track.pulseCounter,
        patterns = {},
    }

    local patternCount = Track.getPatternCount(track)
    for patternIndex = 1, patternCount do
        t.patterns[patternIndex] = Snapshot._snapshotSerializePattern(Track.getPattern(track, patternIndex))
    end

    return t
end
