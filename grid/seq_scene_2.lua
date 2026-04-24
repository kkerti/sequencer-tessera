local Scene=require("seq_scene")
function Scene.new(repeats, lengthBeats, name, trackLoops)
    repeats     = repeats or 1
    lengthBeats = lengthBeats or 4
    name        = name or ""
    trackLoops  = trackLoops or {}


    return {
        repeats     = repeats,
        lengthBeats = lengthBeats,
        name        = name,
        trackLoops  = trackLoops,
    }
end
function Scene.setTrackLoop(scene, trackIndex, loopStart, loopEnd)

    if loopStart == nil and loopEnd == nil then
        scene.trackLoops[trackIndex] = nil
        return
    end


    scene.trackLoops[trackIndex] = {
        loopStart = loopStart,
        loopEnd   = loopEnd,
    }
end
function Scene.getTrackLoop(scene, trackIndex)
    return scene.trackLoops[trackIndex]
end
function Scene.setRepeats(scene, repeats)
    scene.repeats = repeats
end
function Scene.getRepeats(scene)
    return scene.repeats
end
function Scene.setLengthBeats(scene, lengthBeats)
    scene.lengthBeats = lengthBeats
end
