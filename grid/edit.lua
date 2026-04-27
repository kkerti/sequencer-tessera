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

local function arrInsert(arr, pos, value)
    table.insert(arr, pos, value)
end

local function arrRemove(arr, pos)
    table.remove(arr, pos)
end

function Edit.setRatchet(song, spec)
    local firstOnIdx       = spec.firstOnIdx
    local currentCount     = spec.currentCount
    local currentSubPulses = spec.currentSubPulses
    local currentGate      = spec.currentGate
    local newCount         = spec.newCount
    local newSubPulses     = spec.newSubPulses
    local newGate          = spec.newGate

    local atPulse  = song.atPulse
    local kind     = song.kind
    local pitch    = song.pitch
    local velocity = song.velocity
    local channel  = song.channel
    local pairOff  = song.pairOff
    local srcProb  = song.srcStepProb
    local srcVel   = song.srcVelocity

    local basePulse  = atPulse[firstOnIdx]
    local basePitch  = pitch[firstOnIdx]
    local baseVel    = velocity[firstOnIdx]
    local baseCh     = channel[firstOnIdx]
    local baseProb   = srcProb and srcProb[firstOnIdx] or 0
    local baseSrcVel = srcVel and srcVel[firstOnIdx] or baseVel

    local groupEndPulse = basePulse + (currentCount - 1) * currentSubPulses + currentGate
    local i = firstOnIdx
    while i <= song.eventCount do
        if atPulse[i] > groupEndPulse then break end
        if pitch[i] == basePitch and channel[i] == baseCh then
            arrRemove(atPulse, i); arrRemove(kind, i); arrRemove(pitch, i)
            arrRemove(velocity, i); arrRemove(channel, i)
            if pairOff then arrRemove(pairOff, i) end
            if srcProb then arrRemove(srcProb, i) end
            if srcVel then arrRemove(srcVel, i) end
            song.eventCount = song.eventCount - 1
        else
            i = i + 1
        end
    end

    local newRows = {}
    for r = 1, newCount do
        local onPulse = basePulse + (r - 1) * newSubPulses
        local offPulse = onPulse + newGate
        newRows[#newRows + 1] = {
            at = onPulse, k = 1, p = basePitch, v = baseVel, c = baseCh,
            isOn = true,
        }
        newRows[#newRows + 1] = {
            at = offPulse, k = 0, p = basePitch, v = 0, c = baseCh,
            isOn = false,
        }
    end
    table.sort(newRows, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        return a.k < b.k
    end)

    for _, row in ipairs(newRows) do
        local pos = 1
        while pos <= song.eventCount do
            if atPulse[pos] > row.at
               or (atPulse[pos] == row.at and kind[pos] > row.k) then
                break
            end
            pos = pos + 1
        end
        arrInsert(atPulse, pos, row.at)
        arrInsert(kind, pos, row.k)
        arrInsert(pitch, pos, row.p)
        arrInsert(velocity, pos, row.v)
        arrInsert(channel, pos, row.c)
        if pairOff then arrInsert(pairOff, pos, 0) end
        if srcProb then
            arrInsert(srcProb, pos, row.isOn and baseProb or 0)
        end
        if srcVel then
            arrInsert(srcVel, pos, row.isOn and baseSrcVel or 0)
        end
        song.eventCount = song.eventCount + 1
    end

    if pairOff then
        Edit.rebuildPairOff(song)
    end

    return song.eventCount
end

function Edit.rebuildPairOff(song)
    local count = song.eventCount
    local pairOff = song.pairOff
    if not pairOff then return end

    for k = 1, count do pairOff[k] = 0 end
    for k = 1, count do
        local kk = song.kind[k]
        if kk == 1 or kk == 2 then
            local p, c = song.pitch[k], song.channel[k]
            for j = k + 1, count do
                local kj = song.kind[j]
                if (kj == 0 or kj == 3)
                   and song.pitch[j] == p and song.channel[j] == c then
                    pairOff[k] = j
                    break
                end
            end
        end
    end
end

function Edit.queueRatchetEdit(queue, spec)
    queue[#queue + 1] = { op = "ratchet", spec = spec }
    return #queue
end

function Edit.applyQueue(song, queue)
    local n = #queue
    for i = 1, n do
        local e = queue[i]
        if e.op == "ratchet" then
            Edit.setRatchet(song, e.spec)
        end
        queue[i] = nil
    end
    return n
end

function Edit.newQueue() return {} end

return Edit
