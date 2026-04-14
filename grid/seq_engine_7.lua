local Engine=require("seq_engine")
local Track=require("seq_track")
local Step=require("seq_step")
local Utils=require("seq_utils")
local Performance=require("seq_performance")
local Scene=require("seq_scene")
local Probability=require("seq_probability")
function Engine._engineResetSceneChain(engine)
    if engine.sceneChain == nil or not Scene.chainIsActive(engine.sceneChain) then
        return
    end
    Scene.chainReset(engine.sceneChain)
    local current = Scene.chainGetCurrent(engine.sceneChain)
    if current then
        Scene.applyToTracks(current, engine.tracks, engine.trackCount)
    end
end
