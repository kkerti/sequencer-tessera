local Snapshot=require("seq_snapshot")
local Engine=require("seq_engine")
local Track=require("seq_track")
local Pattern=require("seq_pattern")
local Step=require("seq_step")
function Snapshot.toTable(engine)
    local data = {
        bpm = engine.bpm,
        pulsesPerBeat = engine.pulsesPerBeat,
        pulseCount = engine.pulseCount,
        swingPercent = engine.swingPercent,
        scaleName = engine.scaleName,
        rootNote = engine.rootNote,
        tracks = {},
    }

    for trackIndex = 1, engine.trackCount do
        data.tracks[trackIndex] = Snapshot._snapshotSerializeTrack(engine, trackIndex)
    end

    return data
end
