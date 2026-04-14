local Snapshot=require("seq_snapshot")
local Engine=require("seq_engine")
local Track=require("seq_track")
local Pattern=require("seq_pattern")
local Step=require("seq_step")
function Snapshot.fromTable(data)
    local trackCount = #data.tracks
    local engine = Engine.new(data.bpm, data.pulsesPerBeat, trackCount, 0)

    if data.swingPercent ~= nil then
        Engine.setSwing(engine, data.swingPercent)
    end
    if data.scaleName ~= nil then
        Engine.setScale(engine, data.scaleName, data.rootNote or 0)
    end
    engine.pulseCount = data.pulseCount or 0

    for trackIndex = 1, trackCount do
        Snapshot._snapshotRestoreTrack(engine, trackIndex, data.tracks[trackIndex])
    end

    return engine
end
