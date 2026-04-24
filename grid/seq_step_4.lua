local Step=require("seq_step")
function Step.new(pitch, velocity, duration, gate, ratchet, probability)
    pitch       = pitch or 60
    velocity    = velocity or 100
    duration    = duration or 4
    gate        = gate or 2
    ratchet     = ratchet or 1
    probability = probability or 100


    return { pitch, velocity, duration, gate, ratchet, probability, true }
end
function Step.getPitch(step)
    return step[Step._I_PITCH]
end
function Step.setPitch(step, value)
    step[Step._I_PITCH] = value
end
function Step.getVelocity(step)
    return step[Step._I_VEL]
end
function Step.setVelocity(step, value)
    step[Step._I_VEL] = value
end
function Step.getDuration(step)
    return step[Step._I_DUR]
end
function Step.setDuration(step, value)
    step[Step._I_DUR] = value
end
function Step.getGate(step)
    return step[Step._I_GATE]
end
function Step.setGate(step, value)
    step[Step._I_GATE] = value
end
