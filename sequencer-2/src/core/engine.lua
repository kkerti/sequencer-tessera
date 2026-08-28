-- engine.lua — transport + the pulse hot path + the composition layer.
-- Pure Core: no IO, no screen.
--
-- The engine owns the tracks, a monotonic global tick, and two PREALLOCATED
-- buffers reused every pulse so onPulse() allocates nothing:
--   engine.out     — events to emit this pulse: { n, typ[], pitch[], vel[], ch[] }
--                    typ 1 = note-on, 0 = note-off. The driver reads this.
--   engine.scratch — per-track note buffer the rack folds over.
--
-- Composition layer (resident metadata, no note data):
--   engine.sequences — array of Sequence (scene) tables; all resident.
--   engine.currentSeq — the active sequence id.
--   engine.song — { steps = {..}, syncBars = 1, pos = 1 }, a chain of sequence-ids.
--
-- Switching a sequence = for each track whose slot (or mute) changed, flush its
-- sounding voices and select the new slot. OFF the hot path; never called from
-- onPulse. The FS-swap of inactive patterns is the persistence layer's job and
-- stays out of the pulse path entirely.
--
-- Contract:
--   Engine.init{ trackCount=4 }
--   Engine.onStart()          -- rewind; fills nothing
--   Engine.onPulse()          -- advance one tick; fills engine.out
--   Engine.onStop()           -- fills engine.out with OFFs for held voices
--   Engine.setSequence(id)    -- swap active slots per track; fills OFFs in out
--   Engine.setTrackMute(t,m)  -- sequence-local mute toggle
--   Engine.songAdd/songAdvance/songClear
--   -> after each, the caller emits Engine.out (driver), never per-pulse alloc.

local Track    = require("track")
local Sequence = require("sequence")

local M = { tracks = {}, gt = -1, playing = false,
            sequences = {}, currentSeq = 1, song = { steps = {}, syncBars = 1, pos = 1 } }

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
    local n = opts.trackCount or 4
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

    -- Sequences: SEQ k selects slot k on every track (Hermod "SEQ1 = all P1").
    local nSeq = opts.sequences or 4
    M.sequences = {}
    for k = 1, nSeq do
        M.sequences[k] = Sequence.new(n, k)
    end
    M.currentSeq = 1
    M.song = Sequence.newSong()
    for t = 1, n do M.tracks[t].seqMute = M.sequences[1].mute[t] end
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

-- ---- composition layer (off the hot path) -----------------------------

-- Switch to sequence `id`: flush + swap the active slot of every track whose
-- slot or mute changed. Fills M.out with note-offs for the swapped tracks.
function M.setSequence(id)
    local seq = M.sequences[id]
    if not seq then return M.out end
    M.out.n = 0
    for t = 1, #M.tracks do
        local tr = M.tracks[t]
        local slot = seq.slot[t]
        local mute = seq.mute[t]
        if slot ~= tr.activeSlot or mute ~= tr.seqMute then
            Track.flush(tr, M.out)        -- stop notes sounding from the old slot/mute
            if slot ~= tr.activeSlot then
                Track.setActiveSlot(tr, slot)
            end
            tr.seqMute = mute
        end
    end
    M.currentSeq = id
    return M.out
end

-- Toggle a track's mute in the CURRENT sequence only (pattern-local mute).
function M.setTrackMute(track, muted)
    local seq = M.sequences[M.currentSeq]
    if not seq or track < 1 or track > #M.tracks then
        return M.out
    end
    M.out.n = 0
    seq.mute[track] = muted and true or false
    M.tracks[track].seqMute = seq.mute[track]
    if seq.mute[track] then
        Track.flush(M.tracks[track], M.out)  -- silence a track the moment it mutes
    end
    return M.out
end

-- ---- song (chain of sequence-ids) -------------------------------------

function M.songAdd(seqId)
    M.song.steps[#M.song.steps + 1] = seqId
end

function M.songClear()
    M.song.steps = {}
    M.song.pos = 1
end

-- Remove the song step at `pos` (1..n).
function M.songRemoveAt(pos)
    local steps = M.song.steps
    if pos < 1 or pos > #steps then return end
    table.remove(steps, pos)
    if M.song.pos > #steps then M.song.pos = #steps end
    if M.song.pos < 1 then M.song.pos = 1 end
end

-- Advance to the next song step (wrapping) and switch to its sequence.
-- Caller emits the returned out. Advances are otherwise triggered by the App
-- counting bars (syncBars) off the hot path — this just does the switch.
function M.songAdvance()
    local steps = M.song.steps
    if #steps == 0 then return M.out end
    M.song.pos = M.song.pos + 1
    if M.song.pos > #steps then M.song.pos = 1 end
    return M.setSequence(steps[M.song.pos])
end

return M
