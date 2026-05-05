-- src/euclidean/engine.lua
-- 4-track Euclidean engine. Externally clocked. Pure: returns events, no IO.
--
-- Each track owns its own (events, steps, rotation, key) plus a per-track
-- pulses-per-step rate. Polyrhythm + poly-meter come for free from per-track
-- ppstep + steps. No global swing (yet). No internal clock.

local Track = require("euclidean.track")

local M = {}

M.tracks   = {}
M.running  = false
M.pulseCount = 0
local logFn = nil

function M.init(opts)
    opts = opts or {}
    local n = opts.trackCount or 4
    M.tracks = {}
    for i = 1, n do
        local tr = Track.new()
        tr.chan = i - 1
        M.tracks[i] = tr
    end
    M.running    = false
    M.pulseCount = 0
    logFn = opts.log
end

local function log(s) if logFn then logFn(s) end end

function M.onStart()
    for i = 1, #M.tracks do Track.reset(M.tracks[i]) end
    M.pulseCount = 0
    M.running    = true
    log("START")
end

function M.onStop()
    local out = {}
    for i = 1, #M.tracks do Track.allOff(M.tracks[i], out) end
    M.running = false
    log("STOP")
    return out
end

-- One external pulse. Returns events array, or nil if none.
-- Zero allocations per pulse on the hot path: the only `{}` is the `out`
-- table, and only entries are pushed when an event actually fires. Tracks
-- with no events at this pulse cost one comparison + one decrement.
function M.onPulse()
    if not M.running then return nil end
    local out = {}
    local ts  = M.tracks
    M.pulseCount = M.pulseCount + 1
    for i = 1, #ts do
        Track.advance(ts[i], out)
    end
    if #out == 0 then return nil end
    return out
end

-- ---------- public setters ----------

function M.setSteps(t, n)
    local tr = M.tracks[t]; if tr then Track.setSteps(tr, n) end
end
function M.setEvents(t, k)
    local tr = M.tracks[t]; if tr then Track.setEvents(tr, k) end
end
function M.setRot(t, r)
    local tr = M.tracks[t]; if tr then Track.setRot(tr, r) end
end
function M.setKey(t, p)
    local tr = M.tracks[t]; if tr then Track.setKey(tr, p) end
end
function M.setVel(t, v)
    local tr = M.tracks[t]; if tr then Track.setVel(tr, v) end
end
function M.setGate(t, g)
    local tr = M.tracks[t]; if tr then Track.setGate(tr, g) end
end
function M.setPpstep(t, d)
    local tr = M.tracks[t]; if tr then Track.setPpstep(tr, d) end
end
function M.setChan(t, c)
    local tr = M.tracks[t]; if tr then Track.setChan(tr, c) end
end
function M.setMuted(t, m)
    local tr = M.tracks[t]; if tr then Track.setMuted(tr, m) end
end

return M
