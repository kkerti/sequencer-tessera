-- engine.lua
-- 4-track engine. Externally clocked. Pure: returns events, does no IO.
--
-- No regions. Polyrhythm comes from per-track lastStep + per-step dur.

local Track = require("track")

local M = {}

M.tracks = {}     -- public read; UI may read directly
M.running = false
M.rootPitch = 0   -- 0..11 (C..B); display-only key signature, global
M.scaleMode = 0   -- 0 = major, 1 = minor; display-only, global
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
    logFn = opts.log
end

local function log(s) if logFn then logFn(s) end end

function M.onStart()
    for i = 1, #M.tracks do Track.reset(M.tracks[i]) end
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

-- Called once per external pulse. Returns events array, or nil if none.
function M.onPulse()
    if not M.running then return nil end
    local out = {}
    local ts  = M.tracks
    local n   = #ts

    for i = 1, n do
        Track.advance(ts[i], out)
    end

    if #out == 0 then return nil end
    return out
end

-- ----- convenience setters -----

function M.setStepParam(t, i, name, val)
    local tr = M.tracks[t]; if not tr then return end
    Track.setStepParam(tr, i, name, val)
end

function M.setLastStep(t, n)
    local tr = M.tracks[t]; if not tr then return end
    Track.setLastStep(tr, n)
end

function M.setTrackChan(t, ch)
    local tr = M.tracks[t]; if not tr then return end
    if ch < 1 then ch = 1 end
    if ch > 16 then ch = 16 end
    tr.chan = ch
end

-- Display-only key signature. Global to all tracks. Engine never reads
-- these values during onPulse — they exist only for the UI to show.
function M.setRootPitch(p)
    M.rootPitch = p % 12
end

function M.setScaleMode(m)
    M.scaleMode = (m ~= 0) and 1 or 0
end

return M
