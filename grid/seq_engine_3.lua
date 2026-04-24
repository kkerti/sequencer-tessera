local Engine=require("seq_engine")
local Utils=require("seq_utils")
function Engine.setScale(engine, scaleName, rootNote)
    rootNote = rootNote or 0
    engine.scaleName  = scaleName
    engine.scaleTable = Utils.SCALES[scaleName]
    engine.rootNote   = rootNote
end
function Engine.clearScale(engine)
    engine.scaleName  = nil
    engine.scaleTable = nil
    engine.rootNote   = 0
end
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
