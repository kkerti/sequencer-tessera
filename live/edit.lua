-- live/edit.lua
-- In-place editor for compiled songs. Operates directly on the flat event
-- arrays produced by tools/song_compile.lua. Designed to run on Grid.
--
-- Addressing model: event-index-based. The caller addresses an event by its
-- 1-based index into the compiled song's parallel arrays (atPulse, kind,
-- pitch, velocity, channel). Group-aware operations like setRatchet take an
-- explicit (firstEventIdx, currentCount) pair — the caller is responsible
-- for tracking which contiguous events form a ratchet group, since the
-- compiled schema does not preserve source-step boundaries.
--
-- Operation classes:
--   * O(1) edits  — setPitch, setVelocity, mute, unmute. Safe to apply at
--                   any time; the player picks up the new values on its next
--                   read of that event.
--   * Splice edits — setRatchet. Inserts/removes event rows; shifts every
--                   parallel array. NOT safe mid-loop because the player's
--                   cursor would be invalidated. Queue these via
--                   queueRatchetEdit() and call applyQueue() from the
--                   song's onLoopBoundary hook.
--
-- kind[] values (must match player.lua):
--   1 = NOTE_ON (active)
--   0 = NOTE_OFF (active)
--   2 = NOTE_ON muted (player skips)
--   3 = NOTE_OFF muted (player skips)

local Edit = {}

-- ---------------------------------------------------------------------------
-- O(1) edits — apply immediately. Safe at any pulse.
-- ---------------------------------------------------------------------------

-- Set pitch on a NOTE_ON event. Also updates the matching NOTE_OFF (looked
-- up via pairOff[] when present, otherwise via a forward scan on the
-- ORIGINAL pitch — we must locate the mate before mutating, otherwise the
-- pitch-based scan would search for a note that no longer exists, leaving
-- the old NOTE_OFF in place and producing a hung note on the new pitch).
-- For songs without probability sidecars, we pay an O(N) scan per call to
-- find the NOTE_OFF — acceptable for a human-driven editor on small songs.
function Edit.setPitch(song, eventIdx, midiNote)
    local kind = song.kind[eventIdx]
    -- Locate the mate FIRST, while song.pitch[eventIdx] still holds the
    -- original pitch that findMate needs to match against.
    local mateIdx
    if song.pairOff and (kind == 1 or kind == 2) then
        mateIdx = song.pairOff[eventIdx]
        if mateIdx == 0 then mateIdx = nil end
    end
    if not mateIdx then
        mateIdx = Edit.findMate(song, eventIdx)
    end
    -- Now safe to mutate. Both ON and OFF carry pitch; we update both halves
    -- so the NOTE_OFF targets the right note number on the wire.
    song.pitch[eventIdx] = midiNote
    if mateIdx then song.pitch[mateIdx] = midiNote end
end

-- Set velocity on a NOTE_ON event. NOTE_OFF velocity stays 0.
-- Also updates srcVelocity[] (writer-side baseline) when present so the
-- probability/jitter writer doesn't snap velocity back on the next loop.
function Edit.setVelocity(song, eventIdx, velocity)
    if song.kind[eventIdx] == 1 or song.kind[eventIdx] == 2 then
        song.velocity[eventIdx] = velocity
        if song.srcVelocity then song.srcVelocity[eventIdx] = velocity end
    end
end

-- Mute an event. Flips kind 1->2 (NOTE_ON) and 0->3 (NOTE_OFF). The player
-- skips kinds 2 and 3 silently. Idempotent.
function Edit.mute(song, eventIdx)
    local k = song.kind[eventIdx]
    if k == 1 then
        song.kind[eventIdx] = 2
    elseif k == 0 then
        song.kind[eventIdx] = 3
    end
end

-- Mute a NOTE_ON together with its matching NOTE_OFF. The pair stays linked,
-- so unmutePair restores both. Use this for "mute this note" UX; use mute()
-- alone if you really want to mute one half only.
function Edit.mutePair(song, eventIdx)
    Edit.mute(song, eventIdx)
    local mate = Edit.findMate(song, eventIdx)
    if mate then Edit.mute(song, mate) end
end

-- Unmute an event. Inverse of mute.
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

-- ---------------------------------------------------------------------------
-- Lookup helpers
-- ---------------------------------------------------------------------------

-- Returns true for NOTE_ON kinds (active or muted), false for NOTE_OFF.
local function isOn(k) return k == 1 or k == 2 end

-- Find the NOTE_OFF matching a NOTE_ON at eventIdx (or vice versa) by
-- forward/backward scan on (pitch, channel). Returns the mate's index, or
-- nil if not found.
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

-- ---------------------------------------------------------------------------
-- Ratchet edit — splice operation, queued for loop boundary
-- ---------------------------------------------------------------------------
--
-- A ratchet group is a contiguous sequence of NOTE_ON/NOTE_OFF pairs at
-- evenly-spaced sub-pulses, originating from one source step. The compiled
-- schema does not record the group, so the caller passes a spec describing
-- both the current layout (so we know what to remove) and the new layout
-- (so we know what to insert):
--   firstOnIdx       — index of the first NOTE_ON in the existing group
--   currentCount     — current ratchet count
--   currentSubPulses — current pulse spacing between successive NOTE_ONs
--   currentGate      — current gate length per ratchet
--   newCount         — desired ratchet count after edit (>= 1)
--   newSubPulses     — desired pulse spacing
--   newGate          — desired gate length
--
-- The new group preserves pitch / velocity / channel from the first NOTE_ON.

local function arrInsert(arr, pos, value)
    table.insert(arr, pos, value)
end

local function arrRemove(arr, pos)
    table.remove(arr, pos)
end

-- Apply a ratchet edit immediately. Mutates song in place. Returns the new
-- eventCount. Do not call mid-loop; use queueRatchetEdit/applyQueue instead.
--
-- Parameters describe BOTH the current group layout (so we know what to
-- remove) and the new group layout (so we know what to insert). The caller
-- is the source of truth for both, since the compiled schema does not record
-- ratchet-group boundaries.
--
-- spec table fields:
--   firstOnIdx     — index of the first NOTE_ON in the existing group
--   currentCount   — how many NOTE_ON pairs are in the group right now
--   currentSubPulses — pulse spacing between NOTE_ONs in the existing group
--   currentGate    — gate length per ratchet in the existing group
--   newCount       — desired NOTE_ON count after the edit (>= 1)
--   newSubPulses   — pulse spacing between NOTE_ONs after the edit
--   newGate        — gate length per ratchet after the edit
--
-- Implementation strategy:
--   1. Remove every event row belonging to the current group (matched by
--      pitch + channel within the current group's pulse window).
--   2. Insert 2*newCount fresh rows at the right position.
--   3. Rebuild pairOff[] from scratch by pairing each NOTE_ON with its
--      forward-nearest NOTE_OFF on the same (pitch, channel). Cheap on the
--      ~200-event songs we ship; not called per pulse.
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

    -- Step 1: remove every row belonging to the current group.
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

    -- Step 2: build the new group's rows in temporal order.
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

    -- Step 3: splice each row at the correct position to maintain global
    -- (atPulse asc, kind asc) ordering. We re-scan for the insertion point
    -- per row because earlier inserts shift indices.
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

    -- Step 4: rebuild pairOff[] from scratch (only when sidecar present).
    if pairOff then
        Edit.rebuildPairOff(song)
    end

    return song.eventCount
end

-- Rebuilds pairOff[] by scanning for each NOTE_ON's forward-nearest NOTE_OFF
-- on the same (pitch, channel). O(N^2) worst case; fine for editor use.
function Edit.rebuildPairOff(song)
    local count = song.eventCount
    local pairOff = song.pairOff
    if not pairOff then return end
    -- Reset every entry first.
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

-- ---------------------------------------------------------------------------
-- Edit queue — defer splice ops until the next loop boundary
-- ---------------------------------------------------------------------------
--
-- The player's cursor walks the parallel arrays linearly. Splicing rows
-- in/out mid-loop would invalidate the cursor. Queue ratchet edits and
-- drain the queue from song.onLoopBoundary, when the cursor is reset to 1.

-- Queue a ratchet edit. `spec` has the same fields as Edit.setRatchet.
-- Returns a token (the queue index) for cancellation.
function Edit.queueRatchetEdit(queue, spec)
    queue[#queue + 1] = { op = "ratchet", spec = spec }
    return #queue
end

-- Drain all queued edits against the song. Call from onLoopBoundary.
-- Mutates queue in place (clears it). Returns the number of edits applied.
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

-- Build a fresh empty queue. Just a plain table; provided for symmetry.
function Edit.newQueue() return {} end

return Edit
