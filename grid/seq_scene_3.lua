local Scene=require("seq_scene")
local NAME_MAX_LEN = 32
local MAX_SCENES   = 32
function Scene.chainRemove(chain, index)

    for i = index, chain.sceneCount - 1 do
        chain.scenes[i] = chain.scenes[i + 1]
    end
    chain.scenes[chain.sceneCount] = nil
    chain.sceneCount = chain.sceneCount - 1

    -- Adjust cursor if needed.
    if chain.cursor > chain.sceneCount then
        chain.cursor = math.max(1, chain.sceneCount)
    end
end
function Scene.chainGetScene(chain, index)
    return chain.scenes[index]
end
function Scene.chainGetCount(chain)
    return chain.sceneCount
end
function Scene.chainGetCurrent(chain)
    if chain.sceneCount == 0 then
        return nil
    end
    return chain.scenes[chain.cursor]
end
function Scene.chainReset(chain)
    chain.cursor      = 1
    chain.repeatCount = 0
    chain.beatCount   = 0
end
function Scene.chainSetActive(chain, active)
    chain.active = active
end
function Scene.chainIsActive(chain)
    return chain.active
end
