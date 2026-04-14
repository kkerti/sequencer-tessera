local Engine=require("seq_engine")
local Track=require("seq_track")
local Step=require("seq_step")
local Utils=require("seq_utils")
local Performance=require("seq_performance")
local Scene=require("seq_scene")
local Probability=require("seq_probability")
function Engine._engineAdvanceTrack(engine, trackIndex, events)
    local track = engine.tracks[trackIndex]
    track.clockAccum = track.clockAccum + track.clockMult
    local advanceCount = math.floor(track.clockAccum / track.clockDiv)
    track.clockAccum = track.clockAccum % track.clockDiv

    for _ = 1, advanceCount do
        local step = Track.getCurrentStep(track)
        local event = Track.advance(track)
        Engine._engineProcessTrackEvent(engine, trackIndex, step, event, events)
    end
end
