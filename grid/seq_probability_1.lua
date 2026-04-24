local Probability=require("seq_probability")
local Step=require("seq_step")
function Probability.shouldPlay(step)
    local prob = Step.getProbability(step)
    if prob == nil or prob >= 100 then
        return true
    end
    if prob <= 0 then
        return false
    end
    local roll = math.random(1, 100)
    return roll <= prob
end
