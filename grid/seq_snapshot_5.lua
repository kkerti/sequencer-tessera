local Snapshot=require("seq_snapshot")
local Engine=require("seq_engine")
local Track=require("seq_track")
local Pattern=require("seq_pattern")
local Step=require("seq_step")
function Snapshot._snapshotRestoreTrackState(track, trackData)
    if trackData.loopStart ~= nil then
        Track.setLoopStart(track, trackData.loopStart)
    end
    if trackData.loopEnd ~= nil then
        Track.setLoopEnd(track, trackData.loopEnd)
    end
    if trackData.cursor ~= nil then
        track.cursor = trackData.cursor
    end
    if trackData.pulseCounter ~= nil then
        track.pulseCounter = trackData.pulseCounter
    end
end
