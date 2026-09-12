-- io/midi_in.lua — the Mac host adapter's incoming-MIDI mapping.
--
-- Turns incoming MIDI into the engine's external sources. Fixed convention,
-- documented and easy to change:
--   note 36 + n  ->  external.n trigger   (n = 0..7)
--   CC   20 + n  ->  external.n value      (n = 0..7)
--
-- This is source routing only (ADR-0005): no step editing, no preset load.

local Engine = require("engine")

local M = {}

M.noteBase = 36
M.ccBase   = 20
M.count    = 8

function M.noteOn(note, velocity)
    if not velocity or velocity <= 0 then return false end
    local i = note - M.noteBase + 1
    if i >= 1 and i <= M.count then
        Engine.triggerExternal(i)
        return true
    end
    return false
end

function M.controlChange(cc, value)
    local i = cc - M.ccBase + 1
    if i >= 1 and i <= M.count then
        Engine.setExternalValue(i, value)
        return true
    end
    return false
end

-- Parse one bridge line: "NOTE <note> <vel> <ch>" or "CC <cc> <val> <ch>".
function M.handle(line)
    if line:sub(1, 5) == "NOTE " then
        local note, velocity = line:match("NOTE (%d+) (%d+)")
        if note then return M.noteOn(tonumber(note), tonumber(velocity)) end
    elseif line:sub(1, 3) == "CC " then
        local cc, value = line:match("CC (%d+) (%d+)")
        if cc then return M.controlChange(tonumber(cc), tonumber(value)) end
    end
    return false
end

return M
