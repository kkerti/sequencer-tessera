-- utils.lua
-- Shared utility functions. No sequencer-specific logic here.
-- Reusable across future Grid projects.

local Utils = {}

local NOTE_NAMES = {
    "C", "C#", "D", "Eb", "E", "F", "F#", "G", "G#", "A", "Bb", "B"
}

-- Creates a table of `n` elements all set to `default`.
function Utils.tableNew(n, default)
    assert(type(n) == "number" and n > 0, "tableNew: n must be a positive number")
    local t = {}
    for i = 1, n do
        t[i] = default
    end
    return t
end

-- Returns a shallow copy of table `t`.
function Utils.tableCopy(t)
    assert(type(t) == "table", "tableCopy: argument must be a table")
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = v
    end
    return copy
end

-- Clamps integer `value` to the range [min, max].
function Utils.clamp(value, min, max)
    assert(type(value) == "number", "clamp: value must be a number")
    assert(type(min) == "number", "clamp: min must be a number")
    assert(type(max) == "number", "clamp: max must be a number")
    if value < min then return min end
    if value > max then return max end
    return value
end

-- Converts a MIDI note number (0-127) to a pitch name (e.g. C4, Eb3).
function Utils.pitchToName(midiNote)
    assert(type(midiNote) == "number" and midiNote >= 0 and midiNote <= 127,
        "pitchToName: midiNote out of range 0-127")

    local noteIndex = (midiNote % 12) + 1
    local octave = math.floor(midiNote / 12) - 1
    return NOTE_NAMES[noteIndex] .. tostring(octave)
end

return Utils
