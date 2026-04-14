local Scene=require("seq_scene")
local NAME_MAX_LEN = 32
local MAX_SCENES   = 32
function Scene.getLengthBeats(scene)
    return scene.lengthBeats
end
function Scene.setName(scene, name)
    scene.name = name
end
function Scene.getName(scene)
    return scene.name
end
function Scene.newChain()
    return {
        scenes       = {},
        sceneCount   = 0,
        cursor       = 1,     -- 1-based index into scenes
        repeatCount  = 0,     -- how many full passes have completed for current scene
        beatCount    = 0,     -- beats elapsed within the current pass
        active       = false, -- whether the chain is driving loop points
    }
end
function Scene.chainAppend(chain, scene)

    chain.sceneCount = chain.sceneCount + 1
    chain.scenes[chain.sceneCount] = scene
    return scene
end
function Scene.chainInsert(chain, index, scene)

    chain.sceneCount = chain.sceneCount + 1
    for i = chain.sceneCount, index + 1, -1 do
        chain.scenes[i] = chain.scenes[i - 1]
    end
    chain.scenes[index] = scene
    return scene
end
