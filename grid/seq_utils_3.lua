local Utils=require("seq_utils")
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
    return Utils._NOTE_NAMES[noteIndex] .. tostring(octave)
end
