-- track.lua — one musical voice-group: pattern + rack + channel + playhead +
-- a fixed voice ring. This is the per-track slice of the pulse hot path;
-- advance() allocates nothing.
--
-- Voice ring (cap 4): each slot holds a sounding note's pitch + its global
-- off-tick. A 5th simultaneous note steals the slot with the earliest off-tick
-- (oldest-off), emitting that note's OFF first. Off-ticks use the engine's
-- monotonic global tick so loop wrap never confuses note-off timing.

local Pattern = require("pattern")
local Rack    = require("rack")
local Range   = require("range")
local Random  = require("random")
local Scale   = require("scale")

local M = {}

local VOICES = 4

-- Push one output event into the engine's preallocated emit buffer.
-- typ: 1 = note-on, 0 = note-off.
local function emit(out, typ, pitch, vel, ch)
    local n = out.n + 1
    out.n = n
    out.typ[n] = typ; out.pitch[n] = pitch; out.vel[n] = vel; out.ch[n] = ch
end

function M.new(opts)
    opts = opts or {}
    local rack = Rack.new()
    Rack.add(rack, Range.new(opts.range))    -- default order:
    Rack.add(rack, Random.new(opts.random))  --   RANGE -> RANDOM -> SCALE
    Rack.add(rack, Scale.new(opts.scale))
    local tr = {
        pattern  = opts.pattern or Pattern.new(),
        rack     = rack,
        chan     = opts.chan or 1,
        evCursor = 1,
        prevLocal = -1,
        -- voice ring
        vp = { 0, 0, 0, 0 },  -- pitch
        vo = { 0, 0, 0, 0 },  -- global off-tick
        va = { 0, 0, 0, 0 },  -- active flag
    }
    return tr
end

-- Rewind for transport PLAY. Does not emit OFFs (engine.panic handles that).
function M.reset(tr)
    tr.evCursor = 1
    tr.prevLocal = -1
    for i = 1, VOICES do tr.va[i] = 0 end
end

-- Allocate a voice slot for a new note. Steals oldest-off if full, emitting
-- the stolen note's OFF into `out`.
local function allocVoice(tr, out)
    local va, vo = tr.va, tr.vo
    for i = 1, VOICES do
        if va[i] == 0 then return i end
    end
    -- Full: steal the slot with the smallest off-tick.
    local victim, best = 1, vo[1]
    for i = 2, VOICES do
        if vo[i] < best then best = vo[i]; victim = i end
    end
    emit(out, 0, tr.vp[victim], 0, tr.chan)
    return victim
end

-- Advance this track by one pulse at global tick `gt`, using the shared
-- `scratch` note buffer for the rack, appending events to `out`.
function M.advance(tr, gt, scratch, out)
    local pat = tr.pattern
    local loop = Pattern.loopTicks(pat)
    local localTick = gt % loop
    if localTick < tr.prevLocal then tr.evCursor = 1 end  -- loop wrapped
    tr.prevLocal = localTick

    -- 1) Emit note-offs whose off-tick has arrived.
    local va, vo, vp = tr.va, tr.vo, tr.vp
    for i = 1, VOICES do
        if va[i] == 1 and vo[i] <= gt then
            emit(out, 0, vp[i], 0, tr.chan)
            va[i] = 0
        end
    end

    -- 2) Collect notes starting at this tick into the scratch buffer.
    local ev = pat.events
    local S = ev.start
    local cur = tr.evCursor
    while cur <= ev.n and S[cur] < localTick do cur = cur + 1 end
    scratch.n = 0
    while cur <= ev.n and S[cur] == localTick do
        local m = scratch.n + 1
        scratch.n = m
        scratch.pitch[m] = ev.pitch[cur]
        scratch.len[m]   = ev.len[cur]
        scratch.vel[m]   = ev.vel[cur]
        cur = cur + 1
    end
    tr.evCursor = cur

    if scratch.n == 0 then return end

    -- 3) Transform through the rack (may drop/alter notes).
    Rack.run(tr.rack, scratch)

    -- 4) Emit note-ons and schedule their offs.
    for i = 1, scratch.n do
        local slot = allocVoice(tr, out)
        local pitch = scratch.pitch[i]
        emit(out, 1, pitch, scratch.vel[i], tr.chan)
        vp[slot] = pitch
        vo[slot] = gt + scratch.len[i]
        va[slot] = 1
    end
end

-- Emit OFFs for every sounding voice (transport STOP / panic).
function M.flush(tr, out)
    for i = 1, VOICES do
        if tr.va[i] == 1 then
            emit(out, 0, tr.vp[i], 0, tr.chan)
            tr.va[i] = 0
        end
    end
end

return M
