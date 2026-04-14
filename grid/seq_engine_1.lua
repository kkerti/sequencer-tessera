local Engine=require("seq_engine")
local Track=require("seq_track")
local Step=require("seq_step")
local Utils=require("seq_utils")
local Performance=require("seq_performance")
local Scene=require("seq_scene")
local Probability=require("seq_probability")
function Engine._engineInitTracks(trackCount, stepCount)
    local tracks = {}
    local probSuppressed = {}
    for i = 1, trackCount do
        local track = Track.new()
        if stepCount > 0 then
            Track.addPattern(track, stepCount)
        end
        tracks[i] = track
        probSuppressed[i] = false
    end
    return tracks, probSuppressed
end
function Engine._noteKey(pitch, channel)
    return pitch .. ":" .. channel
end
