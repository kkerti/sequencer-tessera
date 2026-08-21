-- engine.lua — transport + the pulse hot path. Pure Core: no IO, no screen.
--
-- The engine owns the tracks, a monotonic global tick, and two PREALLOCATED
-- buffers reused every pulse so onPulse() allocates nothing:
--   engine.out     — events to emit this pulse: { n, typ[], pitch[], vel[], ch[] }
--                    typ 1 = note-on, 0 = note-off. The driver reads this.
--   engine.scratch — per-track note buffer the rack folds over.
--
-- Contract:
--   Engine.init{ trackCount=2 }
--   Engine.onStart()          -- rewind; fills nothing
--   Engine.onPulse()          -- advance one tick; fills engine.out
--   Engine.onStop()           -- fills engine.out with OFFs for held voices
--   -> after each, the caller emits Engine.out (driver), never per-pulse alloc.

local Track = require("track")

local M = { tracks = {}, gt = -1, playing = false }

local OUT_CAP     = 64
local SCRATCH_CAP = 64

local function newOut(cap)
    local o = { n = 0, typ = {}, pitch = {}, vel = {}, ch = {} }
    for i = 1, cap do o.typ[i]=0; o.pitch[i]=0; o.vel[i]=0; o.ch[i]=0 end
    return o
end

local function newScratch(cap)
    local s = { n = 0, pitch = {}, len = {}, vel = {} }
    for i = 1, cap do s.pitch[i]=0; s.len[i]=0; s.vel[i]=0 end
    return s
end

function M.init(opts)
    opts = opts or {}
    local n = opts.trackCount or 2
    M.tracks = {}
    for t = 1, n do
        local o = opts.tracks and opts.tracks[t] or {}
        o.chan = o.chan or t          -- default: track t -> MIDI channel t
        M.tracks[t] = Track.new(o)
    end
    M.gt = -1
    M.playing = false
    M.out = newOut(OUT_CAP)
    M.scratch = newScratch(SCRATCH_CAP)
    return M
end

function M.onStart()
    M.gt = -1
    for t = 1, #M.tracks do Track.reset(M.tracks[t]) end
    M.out.n = 0
    M.playing = true
end

-- Advance exactly one pulse. Fills M.out. Zero allocation.
function M.onPulse()
    if not M.playing then M.out.n = 0; return M.out end
    M.gt = M.gt + 1
    M.out.n = 0
    local scratch, out = M.scratch, M.out
    local tracks = M.tracks
    for t = 1, #tracks do
        Track.advance(tracks[t], M.gt, scratch, out)
    end
    return M.out
end

-- Stop: emit OFFs for everything still sounding, then halt.
function M.onStop()
    M.out.n = 0
    for t = 1, #M.tracks do Track.flush(M.tracks[t], M.out) end
    M.playing = false
    return M.out
end

-- All-notes-off without changing transport state.
function M.panic()
    M.out.n = 0
    for t = 1, #M.tracks do Track.flush(M.tracks[t], M.out) end
    return M.out
end

return M
