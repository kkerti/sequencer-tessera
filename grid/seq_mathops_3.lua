local MathOps=require("seq_mathops")
local Step=require("seq_step")
function MathOps._mathOpsSetValue(step, param, value)
    if param == "pitch" then Step.setPitch(step, value); return end
    if param == "velocity" then Step.setVelocity(step, value); return end
    if param == "duration" then Step.setDuration(step, value); return end
    if param == "gate" then Step.setGate(step, value); return end
    if param == "ratchet" then Step.setRatchet(step, value); return end
    error("mathOps: unsupported param")
end
