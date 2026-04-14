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
function Step.resolvePitch(step, scaleTable, rootNote)
    if scaleTable == nil then
        return step.pitch
    end
    rootNote = rootNote or 0
    return Utils.quantizePitch(step.pitch, rootNote, scaleTable)
end
