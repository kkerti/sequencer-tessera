-- seq_data.lua — the sequence the headless build plays. Data + the action-API
-- calls that install it, and nothing else.
--
-- Deliberately NOT a preset table: applying one needs preset.lua (loadPreset),
-- and the whole point of the headless build is to load as little code as
-- possible. These are plain Engine.* calls, the same action API the Mac
-- harness and the GUI use.
--
-- THREE lanes, different divisions, so the console report visibly shows them
-- advancing at different rates against one clock:
--   L1  note  ch1   16ths      melody, 16 steps
--   L2  note  ch2   8ths       bass, 8 steps
--   L3  trig  ch10  16ths      drum pattern, 16 steps

local M = {}

local MELODY = { 69, 72, 76, 72, 67, 72, 76, 79,
                 69, 72, 76, 72, 65, 69, 72, 76 }
local BASS   = { 45, 45, 52, 45, 41, 41, 48, 41 }
local DRUM   = { 1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 0 }

local SIXTEENTH = 5        -- Sources.TRANSPORT_SIXTEENTH
local EIGHTH    = 4        -- Sources.TRANSPORT_EIGHTH

function M.apply(Engine)
    Engine.init{ lanes = 3, channel = 1 }

    -- L1 — melody, A minor, one step per 16th.
    Engine.setType(1, "note")
    Engine.setChannel(1, 1)
    Engine.setScale(1, 0x5AD, 9)
    Engine.setAdvanceSource(1, SIXTEENTH)
    for i = 1, 16 do
        Engine.setPitch(1, i, MELODY[i])
        Engine.setVelocity(1, i, 90)
        Engine.setStepLength(1, i, 4)
    end

    -- L2 — bass, 8 steps, one step per 8th.
    Engine.setType(2, "note")
    Engine.setChannel(2, 2)
    Engine.setLength(2, 8)
    Engine.setAdvanceSource(2, EIGHTH)
    for i = 1, 8 do
        Engine.setPitch(2, i, BASS[i])
        Engine.setVelocity(2, i, 105)
        Engine.setStepLength(2, i, 10)
    end

    -- L3 — drum trigs on ch10, one step per 16th.
    Engine.setType(3, "trig")
    Engine.setChannel(3, 10)
    Engine.setMidiNote(3, 36)
    Engine.setAdvanceSource(3, SIXTEENTH)
    for i = 1, 16 do Engine.setGate(3, i, DRUM[i]) end

    return true
end

return M
