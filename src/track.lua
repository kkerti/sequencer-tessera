-- track.lua
-- Track state + per-pulse advance + group edit.
--
-- A track is a fixed 64-step buffer of packed-int steps plus tiny runtime
-- state. Monophonic: at most one note in flight per track.
--
-- Regions: the 64-step buffer is divided into 4 fixed regions of 16 steps:
--   region 1 = steps 1..16    region 3 = steps 33..48
--   region 2 = steps 17..32   region 4 = steps 49..64
-- The engine tells the track which region is active; region switching
-- happens at-end-of-region per track and is coordinated by the engine.
--
-- Direction modes:
--   1 = forward
--   2 = reverse
--   3 = ping-pong
--   4 = random
--
-- Per-pulse cost: a few comparisons + a decrement when a note is active.
-- Zero allocations per pulse.

local Step = require("step")

local M = {}

local DIR_FWD, DIR_REV, DIR_PP, DIR_RND = 1, 2, 3, 4
M.DIR_FWD, M.DIR_REV, M.DIR_PP, M.DIR_RND = DIR_FWD, DIR_REV, DIR_PP, DIR_RND

local STEPS_PER_REGION = 16
M.STEPS_PER_REGION = STEPS_PER_REGION
local REGION_COUNT = 4
M.REGION_COUNT = REGION_COUNT

-- Region bounds helpers (1-based, inclusive).
local function regionLo(r) return (r - 1) * STEPS_PER_REGION + 1 end
local function regionHi(r) return r * STEPS_PER_REGION end
M.regionLo, M.regionHi = regionLo, regionHi

-- Build a fresh track. `cap` is fixed at 64 (region math assumes it).
function M.new(cap)
    cap = cap or 64
    local steps = {}
    local def = Step.pack({ pitch=60, vel=100, dur=6, gate=3, prob=127, active=true })
    for i = 1, cap do steps[i] = def end
    return {
        steps    = steps,
        cap      = cap,
        chan     = 1,
        div      = 1,        -- clock divider, 1..16
        dir      = DIR_FWD,
        ppDir    = 1,        -- ping-pong internal: 1 fwd, -1 rev
        -- runtime
        pos      = 0,        -- last fired step (0 = none yet)
        divAcc   = 0,        -- pulses since last advance
        stepAcc  = 0,        -- pulses left in current step
        -- region runtime
        curRegion   = 1,     -- region this track is currently playing
        regionDone  = false, -- set true when this track has crossed its own
                             -- region boundary while a switch is queued.
                             -- Engine clears this when it flips activeRegion.
        -- active note slot (for NOTE_OFF scheduling)
        actPitch = -1,
        actOff   = 0,        -- pulses (own-clock) until NOTE_OFF; 0 = no active note
        -- ratchet bookkeeping
        ratNext  = 0,
        ratState = 0,
    }
end

-- ----- direction stepping (region-aware) -----
--
-- nextPos returns the next step index AND whether this advance crosses a
-- region boundary (i.e. whether the track has just finished its current
-- region and would naturally wrap).
--
-- If `queuedRegion ~= 0` and we are about to wrap, we instead jump to the
-- queued region's lo/hi (depending on direction). The track sets
-- `regionDone = true` and updates `curRegion` so subsequent pulses play
-- from the new region.

local function nextPos(tr, queuedRegion)
    local d   = tr.dir
    local cur = tr.curRegion
    local lo  = regionLo(cur)
    local hi  = regionHi(cur)

    if d == DIR_FWD then
        local p = tr.pos + 1
        if tr.pos < lo or tr.pos > hi then p = lo end  -- first step / region change
        if p > hi then
            -- crossed boundary
            if queuedRegion ~= 0 then
                tr.curRegion = queuedRegion
                tr.regionDone = true
                return regionLo(queuedRegion)
            end
            return lo
        end
        return p

    elseif d == DIR_REV then
        local p = tr.pos - 1
        if tr.pos < lo or tr.pos > hi then p = hi end
        if p < lo then
            if queuedRegion ~= 0 then
                tr.curRegion = queuedRegion
                tr.regionDone = true
                return regionHi(queuedRegion)
            end
            return hi
        end
        return p

    elseif d == DIR_PP then
        -- if track was outside region (e.g. just initialized or region jumped
        -- without us crossing), snap to lo and start forward.
        if tr.pos < lo or tr.pos > hi then
            tr.ppDir = 1
            return lo
        end
        local p = tr.pos + tr.ppDir
        if p > hi then
            -- bounce; this counts as a region boundary
            if queuedRegion ~= 0 then
                tr.curRegion = queuedRegion
                tr.regionDone = true
                tr.ppDir = 1
                return regionLo(queuedRegion)
            end
            tr.ppDir = -1
            p = hi - 1
            if p < lo then p = lo end
            return p
        elseif p < lo then
            if queuedRegion ~= 0 then
                tr.curRegion = queuedRegion
                tr.regionDone = true
                tr.ppDir = 1
                return regionLo(queuedRegion)
            end
            tr.ppDir = 1
            p = lo + 1
            if p > hi then p = hi end
            return p
        end
        return p

    else  -- DIR_RND
        -- Random has no natural boundary. Engine signals piggyback flips by
        -- mutating tr.curRegion directly (see engine.applyRegionFlipForRandom).
        return math.random(lo, hi)
    end
end

-- Probability roll. Returns true if step should fire.
local function rollProb(prob)
    if prob >= 127 then return true end
    if prob <= 0 then return false end
    return math.random(0, 126) < prob
end

local EV_ON, EV_OFF = 1, 2
M.EV_ON, M.EV_OFF = EV_ON, EV_OFF

local function emitOff(tr, out)
    if tr.actPitch >= 0 then
        out[#out+1] = { type=EV_OFF, pitch=tr.actPitch, vel=0, ch=tr.chan }
        tr.actPitch = -1
        tr.actOff = 0
    end
end

-- Sentinel for "sustain through next boundary".
local SUSTAIN = 0x7FFFFFFF

local function fireStep(tr, out)
    local s = tr.steps[tr.pos]
    if not Step.active(s) then return end
    if not rollProb(Step.prob(s)) then return end
    local p, v, g = Step.pitch(s), Step.vel(s), Step.gate(s)
    if g <= 0 then return end
    local dur = Step.dur(s)
    local sustain = (g >= dur)

    if tr.actPitch == p and sustain then
        tr.actOff = SUSTAIN
    else
        if tr.actPitch >= 0 then
            out[#out+1] = { type=EV_OFF, pitch=tr.actPitch, vel=0, ch=tr.chan }
        end
        out[#out+1] = { type=EV_ON, pitch=p, vel=v, ch=tr.chan }
        tr.actPitch = p
        tr.actOff   = sustain and SUSTAIN or g
    end

    if Step.ratch(s) and g > 0 then
        tr.ratNext  = g
        tr.ratState = 1
    else
        tr.ratNext  = 0
    end
end

-- advance: called once per *engine* pulse.
-- `queuedRegion` is the engine's current queue (0 = none).
function M.advance(tr, out, queuedRegion)
    -- clock divider
    tr.divAcc = tr.divAcc + 1
    if tr.divAcc < tr.div then return end
    tr.divAcc = 0

    -- 1) decrement active note
    if tr.actOff > 0 and tr.actOff ~= SUSTAIN then
        tr.actOff = tr.actOff - 1
        if tr.actOff == 0 then emitOff(tr, out) end
    end

    -- 2) ratchet toggle inside current step
    if tr.ratNext > 0 then
        tr.ratNext = tr.ratNext - 1
        if tr.ratNext == 0 then
            local s = tr.steps[tr.pos]
            local g = Step.gate(s)
            if tr.ratState == 1 then
                emitOff(tr, out)
                tr.ratState = 0
                tr.ratNext  = g
            else
                local p, v = Step.pitch(s), Step.vel(s)
                out[#out+1] = { type=EV_ON, pitch=p, vel=v, ch=tr.chan }
                tr.actPitch = p
                tr.actOff   = g
                tr.ratState = 1
                tr.ratNext  = g
            end
        end
    end

    -- 3) step boundary?
    if tr.stepAcc <= 0 then
        tr.pos = nextPos(tr, queuedRegion or 0)
        local s = tr.steps[tr.pos]
        local d = Step.dur(s)
        if d <= 0 then d = 1 end
        tr.stepAcc = d
        fireStep(tr, out)
    end
    tr.stepAcc = tr.stepAcc - 1
end

-- ----- public mutation API -----

function M.setStepParam(tr, i, name, val)
    if i < 1 or i > tr.cap then return end
    tr.steps[i] = Step.set(tr.steps[i], name, val)
end

function M.getStepParam(tr, i, name)
    if i < 1 or i > tr.cap then return nil end
    return Step.get(tr.steps[i], name)
end

-- group edit: op = "set" | "add" | "rand"
-- "rand" interprets val as { min, max } table
function M.groupEdit(tr, from, to, op, name, val)
    if from > to then from, to = to, from end
    if from < 1 then from = 1 end
    if to > tr.cap then to = tr.cap end
    if op == "set" then
        for i = from, to do
            tr.steps[i] = Step.set(tr.steps[i], name, val)
        end
    elseif op == "add" then
        for i = from, to do
            local cur = Step.get(tr.steps[i], name)
            tr.steps[i] = Step.set(tr.steps[i], name, cur + val)
        end
    elseif op == "rand" then
        local lo, hi = val[1], val[2]
        for i = from, to do
            tr.steps[i] = Step.set(tr.steps[i], name, math.random(lo, hi))
        end
    end
end

-- start/stop housekeeping
function M.reset(tr, region)
    tr.pos        = 0
    tr.divAcc     = 0
    tr.stepAcc    = 0
    tr.actPitch   = -1
    tr.actOff     = 0
    tr.ratNext    = 0
    tr.ratState   = 0
    tr.ppDir      = 1
    tr.curRegion  = region or 1
    tr.regionDone = false
end

function M.allOff(tr, out)
    emitOff(tr, out)
end

return M
