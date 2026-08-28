-- track.lua — one musical voice-group: pattern slots + rack + channel +
-- playhead + a fixed voice ring. This is the per-track slice of the pulse hot
-- path; advance() allocates nothing.
--
-- Pattern slots: a track has up to SLOTS addressable patterns (Hermod's
-- P1..P16 scaled down). Only the ACTIVE slot's Pattern is resident on the hot
-- path (`tr.pattern`); the others may be nil until authored (file-swap fills
-- them in the persistence layer). Selecting a slot is an off-hot-path action.
--
-- Voice ring (cap 4): each slot holds a sounding note's pitch + its global
-- off-tick. A 5th simultaneous note steals the slot with the earliest off-tick
-- (oldest-off), emitting that note's OFF first. Off-ticks use the engine's
-- monotonic global tick so loop wrap never confuses note-off timing.
--
-- Nap (transient, not saved): mute this track for `napLoops` of its OWN loops,
-- then wake for `wakeLoops`, alternating. The rack/generator keep running
-- underneath — only note-ON emission is suppressed — so a track wakes into an
-- evolved state (PPW Loop Nap/Loop Wake). The counter flip is alloc-free and
-- runs in the wrap bookkeeping below.
--
-- Auto-reroll (transient): set `due` on every `everyLoops` of the track's own
-- loops. The regenerate itself is NOT alloc-free, so only the flag is set on
-- the hot path; the App services `due` off the hot path (see engine/control).

local Pattern = require("pattern")
local Rack    = require("rack")
local Range   = require("range")
local Random  = require("random")
local Scale   = require("scale")

local M = {}

local VOICES = 4
local SLOTS  = 4

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
    local nSlots = opts.slots or SLOTS
    local slots = {}
    if opts.patterns then
        for s = 1, nSlots do slots[s] = opts.patterns[s] end
    end
    local active = opts.activeSlot or 1
    if not slots[active] then
        slots[active] = opts.pattern or Pattern.new()
    end
    local tr = {
        slots      = slots,
        nSlots     = nSlots,
        activeSlot = active,
        pattern    = slots[active],
        rack       = rack,
        chan       = opts.chan or 1,
        evCursor   = 1,
        prevLocal  = -1,
        seqMute    = false,           -- sequence-local mute (set by engine)
        -- voice ring
        vp = { 0, 0, 0, 0 },          -- pitch
        vo = { 0, 0, 0, 0 },          -- global off-tick
        va = { 0, 0, 0, 0 },          -- active flag
        -- transient performance state (not saved; see header)
        nap  = { armed = false, napLoops = 4, wakeLoops = 4, counter = 0, muted = false },
        auto = { armed = false, everyLoops = 4, counter = 0, due = false },
    }
    return tr
end

-- Rewind for transport PLAY. Does not emit OFFs (engine.panic handles that).
function M.reset(tr)
    tr.evCursor = 1
    tr.prevLocal = -1
    for i = 1, VOICES do tr.va[i] = 0 end
end

-- Select a pattern slot, authoring a fresh pattern if never authored.
-- Off the hot path. Resets the playhead/voices (RESTART semantics; the engine
-- flushes sounding voices before this on a mid-play switch).
function M.setActiveSlot(tr, slot)
    if slot < 1 or slot > tr.nSlots then return false end
    if not tr.slots[slot] then
        tr.slots[slot] = Pattern.new()  -- author fresh; persistence layer loads instead
    end
    tr.activeSlot = slot
    tr.pattern = tr.slots[slot]
    M.reset(tr)
    return true
end

-- ---- nap / auto-reroll arming (App actions, off the hot path) ----------
function M.armNap(tr, napLoops, wakeLoops)
    tr.nap.armed = true
    tr.nap.napLoops = napLoops or 4
    tr.nap.wakeLoops = wakeLoops or 4
    tr.nap.counter = tr.nap.wakeLoops   -- start awake
    tr.nap.muted = false
end

function M.disarmNap(tr)
    tr.nap.armed = false
    tr.nap.counter = 0
    tr.nap.muted = false
end

function M.armAuto(tr, everyLoops)
    tr.auto.armed = true
    tr.auto.everyLoops = everyLoops or 4
    tr.auto.counter = tr.auto.everyLoops
    tr.auto.due = false
end

function M.disarmAuto(tr)
    tr.auto.armed = false
    tr.auto.due = false
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
    local s0, loopLen = Pattern.loopWindow(pat)
    local localTick
    if gt >= s0 then localTick = s0 + (gt - s0) % loopLen
    else localTick = gt end            -- before the loop region's first start

    if localTick < tr.prevLocal then
        -- Loop wrapped: rewind cursor + alloc-free nap/auto-reroll bookkeeping.
        tr.evCursor = 1
        local nap = tr.nap
        if nap.armed then
            nap.counter = nap.counter - 1
            if nap.counter <= 0 then
                nap.muted = not nap.muted
                nap.counter = nap.muted and nap.napLoops or nap.wakeLoops
            end
        end
        local auto = tr.auto
        if auto.armed then
            auto.counter = auto.counter - 1
            if auto.counter <= 0 then
                auto.due = true
                auto.counter = auto.everyLoops
            end
        end
    end
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

    -- 4) Emit note-ons and schedule their offs. A napped or sequence-muted
    --    track suppresses only the note-ON here; the rack still ran above.
    if tr.nap.muted or tr.seqMute then return end
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
