-- seq_data.lua — the sequence the headless build plays. Data + the lane-field
-- writes that install it, and nothing else.
--
-- Deliberately NOT a preset table (applying one needs preset.lua) and NOT the
-- setters (they live in the lazy editing bundle, edit.lua): the whole point of
-- the headless build is to compile as little code as possible.
--
-- THREE lanes, different divisions, so the console report visibly shows them
-- advancing at different rates against one clock:
--   L1  note  ch1   16ths      melody, 16 steps
--   L2  note  ch2   8ths       bass, 8 steps
--   L3  trig  ch10  16ths      drum pattern, 16 steps

local Scales = require("scales")

local M = {}

local MELODY = { 69, 72, 76, 72, 67, 72, 76, 79,
                 69, 72, 76, 72, 65, 69, 72, 76 }
local BASS   = { 45, 45, 52, 45, 41, 41, 48, 41 }
local DRUM   = { 1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 0 }

local SIXTEENTH = 5        -- Sources.TRANSPORT_SIXTEENTH
local EIGHTH    = 4        -- Sources.TRANSPORT_EIGHTH

function M.apply(Engine)
    Engine.init{ lanes = 3, channel = 1 }
    local a, b, c = Engine.lanes[1], Engine.lanes[2], Engine.lanes[3]

    -- L1 — melody, A minor, one step per 16th.
    a.channel = 1
    a.rawScaleMask, a.root = 0x5AD, 9
    a.scaleMask = Scales.rotate(0x5AD, 9)
    a.advanceSource = SIXTEENTH
    for i = 1, 16 do
        a.pitch[i] = MELODY[i]; a.velocity[i] = 90; a.stepLength[i] = 4
    end

    -- L2 — bass, 8 steps, one step per 8th.
    b.channel = 2
    b.length = 8
    b.advanceSource = EIGHTH
    for i = 1, 8 do
        b.pitch[i] = BASS[i]; b.velocity[i] = 105; b.stepLength[i] = 10
    end

    -- L3 — drum trigs on ch10, one step per 16th.
    c.type = "trig"
    c.channel = 10
    c.midiNote = 36
    c.advanceSource = SIXTEENTH
    for i = 1, 16 do c.gate[i] = DRUM[i] end

    return true
end

return M
