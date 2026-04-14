local Step={}
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
require("seq_step_1")
require("seq_step_2")
require("seq_step_3")
require("seq_step_4")
require("seq_step_5")
require("seq_step_6")
return Step
