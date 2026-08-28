-- sequence.lua — Sequence (scene) + Song: the composition layer.
--
-- A Sequence is CHEAP metadata, not note data: one pattern-slot index per track
-- plus a per-track mute that is local to this sequence. Because it is only
-- small ints + bools, every sequence can stay resident regardless of count
-- (note data is what gets swapped to FS, and that stays capped to the active
-- sequence — see docs/ARCHITECTURE.md §4 / §11.1).
--
--   sequence = { slot = { 1, 1, 1, 1 }, mute = { false, ... } }
--
-- A Song is Hermod's simplest shape: an ordered chain of sequence-ids (which
-- may repeat). The gap between steps is ONE global setting (syncBars), not
-- per-step state.
--
--   song = { steps = { 1, 2, 1, 3 }, syncBars = 1, pos = 1 }

local M = {}

-- New sequence of `trackCount` tracks; every track starts on slot `slot`
-- (default 1), unmuted. Hermod: "SEQ1 holds all the P1 of the tracks".
function M.new(trackCount, slot)
    trackCount = trackCount or 4
    slot = slot or 1
    local s = { slot = {}, mute = {} }
    for t = 1, trackCount do
        s.slot[t] = slot
        s.mute[t] = false
    end
    return s
end

-- New empty song (not yet playing: pos points at step 1, which does not exist).
function M.newSong()
    return { steps = {}, syncBars = 1, pos = 1 }
end

return M
