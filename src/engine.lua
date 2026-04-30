-- engine.lua
-- 4-track engine. Externally clocked. Pure: returns events, does no IO.
--
-- Region coordination:
--   - `activeRegion` (1..4) is the region all tracks are *currently* playing.
--   - `queuedRegion` (0..4; 0 = none) is the region scheduled to switch to
--     at each track's next region boundary.
--   - Per pulse, after advancing tracks, we scan for `regionDone` flags.
--     When all 4 tracks have flipped, we update `activeRegion` and clear
--     the queue.

local Track = require("track")

local M = {}

M.tracks = {}     -- public read; UI may read directly
M.running = false
M.activeRegion = 1
M.queuedRegion = 0
local logFn = nil

function M.init(opts)
    opts = opts or {}
    local n   = opts.trackCount or 4
    local cap = opts.stepsPerTrack or 64
    M.tracks = {}
    for i = 1, n do
        M.tracks[i] = Track.new(cap)
        M.tracks[i].chan = i
    end
    M.running = false
    M.activeRegion = 1
    M.queuedRegion = 0
    logFn = opts.log
end

local function log(s) if logFn then logFn(s) end end

function M.onStart()
    for i = 1, #M.tracks do Track.reset(M.tracks[i], M.activeRegion) end
    M.queuedRegion = 0
    M.running = true
    log("START")
end

function M.onStop()
    local out = {}
    for i = 1, #M.tracks do Track.allOff(M.tracks[i], out) end
    M.running = false
    log("STOP")
    return out
end

-- Schedule a region switch. r ∈ 1..4. Pass the currently active region
-- to cancel the queue (engine clamps invalid values).
function M.setQueuedRegion(r)
    if r == nil or r < 1 or r > Track.REGION_COUNT then
        M.queuedRegion = 0
        return
    end
    if r == M.activeRegion then
        M.queuedRegion = 0
        return
    end
    M.queuedRegion = r
end

-- Called once per external pulse. Returns events array, or nil if none.
function M.onPulse()
    if not M.running then return nil end
    local out = {}
    local ts  = M.tracks
    local n   = #ts
    local q   = M.queuedRegion

    for i = 1, n do
        Track.advance(ts[i], out, q)
    end

    -- If a region switch is queued and all tracks have crossed their own
    -- boundary, finalize the global flip.
    if q ~= 0 then
        local allFlipped = true
        for i = 1, n do
            if not ts[i].regionDone then allFlipped = false; break end
        end
        if allFlipped then
            M.activeRegion = q
            M.queuedRegion = 0
            for i = 1, n do ts[i].regionDone = false end
        end
    end

    if #out == 0 then return nil end
    return out
end

-- ----- convenience setters -----

function M.setStepParam(t, i, name, val)
    local tr = M.tracks[t]; if not tr then return end
    Track.setStepParam(tr, i, name, val)
end

function M.setTrackChan(t, ch)
    local tr = M.tracks[t]; if not tr then return end
    if ch < 1 then ch = 1 end
    if ch > 16 then ch = 16 end
    tr.chan = ch
end

return M
