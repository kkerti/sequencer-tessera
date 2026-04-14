local Scene=require("seq_scene")
local NAME_MAX_LEN = 32
local MAX_SCENES   = 32
function Scene.chainCompletePass(chain)
    if chain.sceneCount == 0 then
        return false
    end

    chain.repeatCount = chain.repeatCount + 1
    local current = chain.scenes[chain.cursor]

    if chain.repeatCount >= current.repeats then
        -- Advance to next scene.
        chain.repeatCount = 0
        chain.beatCount   = 0
        if chain.cursor >= chain.sceneCount then
            chain.cursor = 1 -- wrap
        else
            chain.cursor = chain.cursor + 1
        end
        return true
    end

    return false
end
function Scene.chainBeat(chain)
    if chain.sceneCount == 0 then
        return false
    end

    chain.beatCount = chain.beatCount + 1
    local current = chain.scenes[chain.cursor]

    if chain.beatCount >= current.lengthBeats then
        chain.beatCount = 0
        return Scene.chainCompletePass(chain)
    end

    return false
end
function Scene.chainJumpTo(chain, index)
    chain.cursor      = index
    chain.repeatCount = 0
    chain.beatCount   = 0
end
