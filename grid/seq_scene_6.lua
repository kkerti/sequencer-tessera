local Scene=require("seq_scene")
function Scene.applyToTracks(scene, tracks, trackCount)

    local Track = require("sequencer/track")

    for trackIndex = 1, trackCount do
        local loopOverride = scene.trackLoops[trackIndex]
        if loopOverride ~= nil then
            -- Clear first to avoid validation order issues.
            Track.clearLoopStart(tracks[trackIndex])
            Track.clearLoopEnd(tracks[trackIndex])
            Track.setLoopStart(tracks[trackIndex], loopOverride.loopStart)
            Track.setLoopEnd(tracks[trackIndex], loopOverride.loopEnd)
        end
    end
end
