-- event.lua — polyphonic note store, structure-of-arrays.
--
-- A pattern's notes live in PARALLEL numeric arrays, never as per-note tables.
-- Chords = notes sharing `start`; off-grid = arbitrary `start`. Notes are kept
-- sorted ascending by `start` so playback scans with a moving cursor (see
-- track.lua) instead of searching, and allocates nothing on the hot path.
--
--   store = { n, cap, pitch[], start[], len[], vel[] }
--     pitch : 0..127
--     start : tick offset from pattern start (>= 0)
--     len   : ticks held (>= 1)
--     vel   : 1..127
--
-- add()/remove()/clear() run OFF the hot path (edit/record time). They may
-- shift array elements (insertion sort) but never grow past `cap`.

local M = {}

function M.new(cap)
    cap = cap or 256
    -- Arrays start EMPTY and grow as notes are added (edit-time = off the hot
    -- path). We deliberately do NOT pre-size to `cap`: on the Grid VM's small
    -- Lua heap, pre-filling every pattern to 256 slots exhausts memory even
    -- when the pattern holds a handful of notes. `cap` still bounds the max in
    -- add(). onPulse only READS slots 1..n, so playback stays zero-alloc.
    return { n = 0, cap = cap, pitch = {}, start = {}, len = {}, vel = {} }
end

function M.clear(s)
    s.n = 0
end

-- Insert a note, keeping the arrays sorted by `start`. Returns the index, or
-- nil if the store is full. Off the hot path.
function M.add(s, pitch, start, len, vel)
    if s.n >= s.cap then return nil end
    local P, S, L, V = s.pitch, s.start, s.len, s.vel
    local i = s.n
    -- Shift up until we find the slot where start belongs (stable for chords).
    while i >= 1 and S[i] > start do
        P[i + 1] = P[i]; S[i + 1] = S[i]; L[i + 1] = L[i]; V[i + 1] = V[i]
        i = i - 1
    end
    local at = i + 1
    P[at] = pitch; S[at] = start; L[at] = len; V[at] = vel
    s.n = s.n + 1
    return at
end

-- Remove the note at index `at` (1..n). Off the hot path.
function M.removeAt(s, at)
    if at < 1 or at > s.n then return end
    local P, S, L, V = s.pitch, s.start, s.len, s.vel
    for i = at, s.n - 1 do
        P[i] = P[i + 1]; S[i] = S[i + 1]; L[i] = L[i + 1]; V[i] = V[i + 1]
    end
    s.n = s.n - 1
end

return M
