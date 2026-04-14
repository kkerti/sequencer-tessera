local Snapshot=require("seq_snapshot")
local Engine=require("seq_engine")
local Track=require("seq_track")
local Pattern=require("seq_pattern")
local Step=require("seq_step")
function Snapshot._snapshotRestoreTrack(engine, trackIndex, trackData)
    local track = Engine.getTrack(engine, trackIndex)

    Track.setClockDiv(track, trackData.clockDiv)
    Track.setClockMult(track, trackData.clockMult)
    Track.setDirection(track, trackData.direction or "forward")
    if trackData.midiChannel ~= nil then
        Track.setMidiChannel(track, trackData.midiChannel)
    end

    for patternIndex = 1, #trackData.patterns do
        Snapshot._snapshotRestorePattern(track, patternIndex, trackData.patterns[patternIndex])
    end

    Snapshot._snapshotRestoreTrackState(track, trackData)
end
