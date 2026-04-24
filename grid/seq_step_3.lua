local Step=require("seq_step")
function Step._stepIsRatchetOffPulse(step, pulseCounter)
    local ratch = step[Step._I_RATCH]
    local dur   = step[Step._I_DUR]
    local gate  = step[Step._I_GATE]
    for i = 0, ratch - 1 do
        local startPulse    = math.floor((i * dur) / ratch)
        local nextStartPulse = math.floor(((i + 1) * dur) / ratch)
        local subDuration   = nextStartPulse - startPulse
        if subDuration < 1 then
            subDuration = 1
        end

        local offPulse = startPulse + gate
        if offPulse > startPulse + subDuration then
            offPulse = startPulse + subDuration
        end
        if offPulse >= dur then
            offPulse = dur - 1
        end

        if pulseCounter == offPulse then
            return true
        end
    end
    return false
end
