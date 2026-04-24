local Step=require("seq_step")
local Utils=require("seq_utils")
function Step.getPulseEvent(step, pulseCounter)

    if not Step.isPlayable(step) then
        return nil
    end

    if step[Step._I_RATCH] == 1 then
        if pulseCounter == 0 then
            return "NOTE_ON"
        end
        if pulseCounter == step[Step._I_GATE] then
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
function Step.resolvePitch(step, scaleTable, rootNote)
    if scaleTable == nil then
        return step[Step._I_PITCH]
    end
    rootNote = rootNote or 0
    return Utils.quantizePitch(step[Step._I_PITCH], rootNote, scaleTable)
end
