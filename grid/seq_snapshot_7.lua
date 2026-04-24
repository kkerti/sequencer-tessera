local Snapshot=require("seq_snapshot")
local Engine=require("seq_engine")
function Snapshot.toTable(engine)
    local data = {
        bpm = engine.bpm,
        pulsesPerBeat = engine.pulsesPerBeat,
        scaleName = engine.scaleName,
        rootNote = engine.rootNote,
        tracks = {},
    }

    for trackIndex = 1, engine.trackCount do
        data.tracks[trackIndex] = Snapshot._snapshotSerializeTrack(engine, trackIndex)
    end

    return data
end
function Snapshot.fromTable(data)
    local trackCount = #data.tracks
    local engine = Engine.new(data.bpm, data.pulsesPerBeat, trackCount, 0)

    if data.scaleName ~= nil then
        Engine.setScale(engine, data.scaleName, data.rootNote or 0)
    end

    for trackIndex = 1, trackCount do
        Snapshot._snapshotRestoreTrack(engine, trackIndex, data.tracks[trackIndex])
    end

    return engine
end
