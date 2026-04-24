local Engine=require("seq_engine")
local Track=require("seq_track")
local Scene=require("seq_scene")
function Engine.activateSceneChain(engine)
    local chain = engine.sceneChain
    Scene.chainSetActive(chain, true)
    Scene.chainReset(chain)
    local current = Scene.chainGetCurrent(chain)
    if current then
        Scene.applyToTracks(current, engine.tracks, engine.trackCount)
    end
end
function Engine.deactivateSceneChain(engine)
    local chain = engine.sceneChain
    if chain then
        Scene.chainSetActive(chain, false)
    end
end
function Engine.advanceTrack(engine, trackIndex)
    local track = engine.tracks[trackIndex]
    local step  = Track.getCurrentStep(track)
    local event = Track.advance(track)
    return step, event
end
function Engine.onPulse(engine, pulseCount)
    Engine._engineTickSceneChain(engine, pulseCount)
end
