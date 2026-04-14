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
function Step._stepIsRatchetOnPulse(step, pulseCounter)
    for i = 0, step.ratchet - 1 do
        local startPulse = math.floor((i * step.duration) / step.ratchet)
        if pulseCounter == startPulse then
            return true
        end
    end
    return false
end
