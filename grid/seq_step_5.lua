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
function Step.isPlayable(step)
    return step.active and step.duration > 0 and step.gate > 0
end
function Step.getPulseEvent(step, pulseCounter)

    if not Step.isPlayable(step) then
        return nil
    end

    if step.ratchet == 1 then
        if pulseCounter == 0 then
            return "NOTE_ON"
        end
        if pulseCounter == step.gate then
            return "NOTE_OFF"
        end
        return nil
    end

    -- Priority rule: NOTE_ON wins if on/off boundaries collide.
    if Step._stepIsRatchetOnPulse(step, pulseCounter) then
        return "NOTE_ON"
    end

    if Step._stepIsRatchetOffPulse(step, pulseCounter) then
        return "NOTE_OFF"
    end

    return nil
end
