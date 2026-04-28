local Edit = {}

function Edit.setPitch(song, eventIdx, midiNote)
    local kind = song.kind[eventIdx]

    local mateIdx
    if song.pairOff and (kind == 1 or kind == 2) then
        mateIdx = song.pairOff[eventIdx]
        if mateIdx == 0 then mateIdx = nil end
    end
    if not mateIdx then
        mateIdx = Edit.findMate(song, eventIdx)
    end

    song.pitch[eventIdx] = midiNote
    if mateIdx then song.pitch[mateIdx] = midiNote end
end

function Edit.setVelocity(song, eventIdx, velocity)
    if song.kind[eventIdx] == 1 or song.kind[eventIdx] == 2 then
        song.velocity[eventIdx] = velocity
        if song.srcVelocity then song.srcVelocity[eventIdx] = velocity end
    end
end

function Edit.mute(song, eventIdx)
    local k = song.kind[eventIdx]
    if k == 1 then
        song.kind[eventIdx] = 2
    elseif k == 0 then
        song.kind[eventIdx] = 3
    end
end

function Edit.mutePair(song, eventIdx)
    Edit.mute(song, eventIdx)
    local mate = Edit.findMate(song, eventIdx)
    if mate then Edit.mute(song, mate) end
end

function Edit.unmute(song, eventIdx)
    local k = song.kind[eventIdx]
    if k == 2 then
        song.kind[eventIdx] = 1
    elseif k == 3 then
        song.kind[eventIdx] = 0
    end
end

function Edit.unmutePair(song, eventIdx)
    Edit.unmute(song, eventIdx)
    local mate = Edit.findMate(song, eventIdx)
    if mate then Edit.unmute(song, mate) end
end

local function isOn(k) return k == 1 or k == 2 end

function Edit.findMate(song, eventIdx)
    local k       = song.kind[eventIdx]
    local pitch   = song.pitch[eventIdx]
    local channel = song.channel[eventIdx]
    local count   = song.eventCount

    if isOn(k) then
        for j = eventIdx + 1, count do
            local kj = song.kind[j]
            if (kj == 0 or kj == 3)
               and song.pitch[j] == pitch
               and song.channel[j] == channel then
                return j
            end
        end
    else
        for j = eventIdx - 1, 1, -1 do
            local kj = song.kind[j]
            if (kj == 1 or kj == 2)
               and song.pitch[j] == pitch
               and song.channel[j] == channel then
                return j
            end
        end
    end
    return nil
end

return Edit
