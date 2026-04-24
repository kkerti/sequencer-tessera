local Engine=require("seq_engine")
local Track=require("seq_track")
local Scene=require("seq_scene")
function Engine.reset(engine)
    for i = 1, engine.trackCount do
        Track.reset(engine.tracks[i])
    end
    if engine.sceneChain and Scene.chainIsActive(engine.sceneChain) then
        Scene.chainReset(engine.sceneChain)
        local current = Scene.chainGetCurrent(engine.sceneChain)
        if current then
            Scene.applyToTracks(current, engine.tracks, engine.trackCount)
        end
    end
end
