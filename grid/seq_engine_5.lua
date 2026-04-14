local Engine=require("seq_engine")
local Track=require("seq_track")
local Step=require("seq_step")
local Utils=require("seq_utils")
local Performance=require("seq_performance")
local Scene=require("seq_scene")
local Probability=require("seq_probability")
function Engine._engineTickSceneChain(engine)
    if engine.sceneChain == nil or not Scene.chainIsActive(engine.sceneChain) then
        return
    end
    if engine.pulseCount % engine.pulsesPerBeat ~= 0 then
        return
    end
    local advanced = Scene.chainBeat(engine.sceneChain)
    if advanced then
        local current = Scene.chainGetCurrent(engine.sceneChain)
        if current then
            Scene.applyToTracks(current, engine.tracks, engine.trackCount)
        end
    end
end
