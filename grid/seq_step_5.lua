local Step=require("seq_step")
function Step.getRatchet(step)
    return step[Step._I_RATCH]
end
function Step.setRatchet(step, value)
    step[Step._I_RATCH] = value
end
function Step.getProbability(step)
    return step[Step._I_PROB]
end
function Step.setProbability(step, value)
    step[Step._I_PROB] = value
end
function Step.getActive(step)
    return step[Step._I_ACTIVE]
end
function Step.setActive(step, value)
    step[Step._I_ACTIVE] = value
end
function Step.isPlayable(step)
    return step[Step._I_ACTIVE] and step[Step._I_DUR] > 0 and step[Step._I_GATE] > 0
end
