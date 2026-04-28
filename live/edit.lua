-- live/edit.lua
-- In-place editor for compiled songs. Operates directly on the flat event
-- arrays produced by tools/song_compile.lua. Designed to run on Grid.
--
-- Addressing model: event-index-based. The caller addresses an event by its
-- 1-based index into the compiled song's parallel arrays (atPulse, kind,
-- pitch, velocity, channel).
--
-- Operations are O(1) edits — setPitch, setVelocity, mute, unmute. Safe to
-- apply at any time; the player picks up the new values on its next read of
-- that event.
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

return Edit
