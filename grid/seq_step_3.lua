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
function Step.new(pitch, velocity, duration, gate, ratchet, probability)
    pitch       = pitch or 60
    velocity    = velocity or 100
    duration    = duration or 4
    gate        = gate or 2
    ratchet     = ratchet or 1
    probability = probability or 100


    return {
        pitch       = pitch,
        velocity    = velocity,
        duration    = duration,
        gate        = gate,
        ratchet     = ratchet,
        probability = probability,
        active      = true,
    }
end
function Step.getPitch(step)
    return step.pitch
end
function Step.setPitch(step, value)
    step.pitch = value
end
function Step.getVelocity(step)
    return step.velocity
end
function Step.setVelocity(step, value)
    step.velocity = value
end
