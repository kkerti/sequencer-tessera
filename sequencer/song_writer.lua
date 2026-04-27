-- sequencer/song_writer.lua
-- In-place rewriter for compiled songs.
--
-- The player is a pure tape-deck: it walks the song's flat event arrays and
-- emits MIDI without any randomness or recomputation. All "live" decisions
-- (probability rolls, future jitter, future random direction) happen here,
-- in `rollNextLoop`, which the player invokes once per loop boundary via
-- `song.onLoopBoundary`.
--
-- Key design points:
--   * Mutation only — no allocation, no table.insert, no table.remove.
--   * Mutes a NOTE_ON by flipping kind from 1 to 2 (and its paired NOTE_OFF
--     from 0 to 3). The player skips kind ~= 0 and kind ~= 1 with a single
--     branch. No cursor surgery needed.
--   * Touches only events whose source step has prob < 100 (or jitter > 0
--     in the future). Static slots are not visited beyond a numeric check.
--   * Skips entirely if `song.hasProbability` is false — static songs pay
--     zero cost per loop.
--
-- Bind to a player by setting `song.onLoopBoundary = SongWriter.rollNextLoop`
-- after compiling.

local SongWriter = {}

-- Rolls fresh randomness for the next loop, mutating the song in place.
-- Called by the player at loop wrap.
--   song      : compiled song table
--   loopIndex : integer, the loop about to play (1, 2, 3, ...) — unused by
--               the default writer but available for hosts that want it.
function SongWriter.rollNextLoop(song, loopIndex)
    if not song.hasProbability then return end

    local kind        = song.kind
    local pairOff     = song.pairOff
    local srcStepProb = song.srcStepProb
    local n           = song.eventCount

    for i = 1, n do
        local k = kind[i]
        -- Only consider NOTE_ON-class slots (1 = active, 2 = muted).
        if k == 1 or k == 2 then
            local prob = srcStepProb[i]
            -- Make a fresh decision every loop. prob=100 always plays,
            -- prob=0 never plays, otherwise roll. The paired NOTE_OFF
            -- mirrors the decision so muted notes never sound.
            local play = (prob >= 100)
                         or (prob > 0 and math.random(1, 100) <= prob)
            if play then
                kind[i] = 1
                local off = pairOff[i]
                if off > 0 then kind[off] = 0 end
            else
                kind[i] = 2
                local off = pairOff[i]
                if off > 0 then kind[off] = 3 end
            end
        end
    end
end

return SongWriter
