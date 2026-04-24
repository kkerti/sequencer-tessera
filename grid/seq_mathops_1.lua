local MathOps=require("seq_mathops")
MathOps._PARAM_BOUNDS = {
    pitch = { min = 0, max = 127 },
    velocity = { min = 0, max = 127 },
    duration = { min = 0, max = 99 },
    gate = { min = 0, max = 99 },
    ratchet = { min = 1, max = 4 },
}
