-- utils.lua
-- Shared utility functions. No sequencer-specific logic here.
-- Reusable across future Grid projects.

local Utils = {}

local NOTE_NAMES = {
    "C", "C#", "D", "Eb", "E", "F", "F#", "G", "G#", "A", "Bb", "B"
}

Utils.SCALES = {}
Utils.SCALES.chromatic        = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 }
Utils.SCALES.major            = { 0, 2, 4, 5, 7, 9, 11 }
Utils.SCALES.naturalMinor     = { 0, 2, 3, 5, 7, 8, 10 }
Utils.SCALES.harmonicMinor    = { 0, 2, 3, 5, 7, 8, 11 }
Utils.SCALES.melodicMinor     = { 0, 2, 3, 5, 7, 9, 11 }
Utils.SCALES.dorian           = { 0, 2, 3, 5, 7, 9, 10 }
Utils.SCALES.phrygian         = { 0, 1, 3, 5, 7, 8, 10 }
Utils.SCALES.lydian           = { 0, 2, 4, 6, 7, 9, 11 }
Utils.SCALES.mixolydian       = { 0, 2, 4, 5, 7, 9, 10 }
Utils.SCALES.locrian          = { 0, 1, 3, 5, 6, 8, 10 }
Utils.SCALES.majorPentatonic  = { 0, 2, 4, 7, 9 }
Utils.SCALES.minorPentatonic  = { 0, 3, 5, 7, 10 }
Utils.SCALES.blues            = { 0, 3, 5, 6, 7, 10 }
Utils.SCALES.wholeTone        = { 0, 2, 4, 6, 8, 10 }
Utils.SCALES.diminished       = { 0, 2, 3, 5, 6, 8, 9, 11 }
Utils.SCALES.arabic           = { 0, 1, 4, 5, 7, 8, 11 }
Utils.SCALES.hungarianMinor   = { 0, 2, 3, 6, 7, 8, 11 }
Utils.SCALES.persian          = { 0, 1, 4, 5, 6, 8, 11 }
Utils.SCALES.japanese         = { 0, 1, 5, 7, 8 }
Utils.SCALES.egyptian         = { 0, 2, 5, 7, 10 }
Utils.SCALES.spanish          = { 0, 1, 3, 4, 5, 6, 8, 10 }
Utils.SCALES.iwato            = { 0, 1, 5, 6, 10 }
Utils.SCALES.hirajoshi        = { 0, 2, 3, 7, 8 }
Utils.SCALES.inSen            = { 0, 1, 5, 7, 10 }
Utils.SCALES.pelog            = { 0, 1, 3, 7, 8 }
Utils.SCALES.prometheus       = { 0, 2, 4, 6, 9, 10 }
Utils.SCALES.neapolitanMajor  = { 0, 1, 3, 5, 7, 9, 11 }
Utils.SCALES.neapolitanMinor  = { 0, 1, 3, 5, 7, 8, 11 }
Utils.SCALES.enigmatic        = { 0, 1, 4, 6, 8, 10, 11 }
Utils.SCALES.leadingWholeTone = { 0, 2, 4, 6, 8, 10, 11 }

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

-- Quantizes a MIDI note to a scale table (semitone offsets 0-11).
-- Chooses the nearest pitch class in the same octave or adjacent octave.
function Utils.quantizePitch(pitch, rootNote, scaleTable)
    assert(type(pitch) == "number" and pitch >= 0 and pitch <= 127, "quantizePitch: pitch out of range 0-127")
    assert(type(rootNote) == "number" and rootNote >= 0 and rootNote <= 11,
        "quantizePitch: rootNote out of range 0-11")
    assert(type(scaleTable) == "table" and #scaleTable > 0, "quantizePitch: scaleTable must be a non-empty table")

    local best = nil
    local bestDistance = nil

    local baseOctave = math.floor(pitch / 12)
    for octave = baseOctave - 1, baseOctave + 1 do
        for i = 1, #scaleTable do
            local degree = scaleTable[i]
            local candidate = octave * 12 + ((rootNote + degree) % 12)
            if candidate >= 0 and candidate <= 127 then
                local distance = math.abs(candidate - pitch)
                if best == nil or distance < bestDistance or (distance == bestDistance and candidate < best) then
                    best = candidate
                    bestDistance = distance
                end
            end
        end
    end

    if best == nil then
        return Utils.clamp(pitch, 0, 127)
    end

    return best
end

return Utils
