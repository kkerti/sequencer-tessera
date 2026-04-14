local Utils=require("seq_utils")
local NOTE_NAMES = {
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
