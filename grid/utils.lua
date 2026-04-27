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

function Utils.tableNew(n, default)
    local t = {}
    for i = 1, n do
        t[i] = default
    end
    return t
end

function Utils.tableCopy(t)
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = v
    end
    return copy
end

function Utils.clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

function Utils.pitchToName(midiNote)

    local noteIndex = (midiNote % 12) + 1
    local octave = math.floor(midiNote / 12) - 1
    return NOTE_NAMES[noteIndex] .. tostring(octave)
end

function Utils.quantizePitch(pitch, rootNote, scaleTable)

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
