local Step=require("seq_step")
function Step._stepIsRatchetOnPulse(step, pulseCounter)
    local ratch = step[Step._I_RATCH]
    local dur   = step[Step._I_DUR]
    for i = 0, ratch - 1 do
        local startPulse = math.floor((i * dur) / ratch)
        if pulseCounter == startPulse then
            return true
        end
    end
    return false
end
