local Engine=require("seq_engine")
local Track=require("seq_track")
local Step=require("seq_step")
local Utils=require("seq_utils")
local Performance=require("seq_performance")
local Scene=require("seq_scene")
local Probability=require("seq_probability")
function Engine.setSceneChain(engine, chain)
    if chain ~= nil then
    end
    engine.sceneChain = chain
end
function Engine.getSceneChain(engine)
    return engine.sceneChain
end
function Engine.clearSceneChain(engine)
    engine.sceneChain = nil
end
function Engine.activateSceneChain(engine)
    local chain = engine.sceneChain

    Scene.chainSetActive(chain, true)
    Scene.chainReset(chain)

    -- Apply the first scene's loop points.
    local current = Scene.chainGetCurrent(chain)
    if current then
        Scene.applyToTracks(current, engine.tracks, engine.trackCount)
    end
end
