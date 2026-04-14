local Step=require("seq_step")
local Utils=require("seq_utils")
local PITCH_MIN    = 0
local PITCH_MAX    = 127
local VELOCITY_MIN = 0
local VELOCITY_MAX = 127
local DURATION_MIN = 0
local DURATION_MAX = 99
local GATE_MIN     = 0
local GATE_MAX     = 99
local RATCHET_MIN  = 1
local RATCHET_MAX  = 4
local PROB_MIN     = 0
local PROB_MAX     = 100
function Step.getDuration(step)
    return step.duration
end
function Step.setDuration(step, value)
    step.duration = value
end
function Step.getGate(step)
    return step.gate
end
function Step.setGate(step, value)
    step.gate = value
end
function Step.getRatchet(step)
    return step.ratchet
end
function Step.setRatchet(step, value)
    step.ratchet = value
end
function Step.getProbability(step)
    return step.probability
end
function Step.setProbability(step, value)
    step.probability = value
end
function Step.getActive(step)
    return step.active
end
function Step.setActive(step, value)
    step.active = value
end
