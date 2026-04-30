-- track.lua
-- Track state + per-pulse advance + group edit.
--
-- A track is a fixed-size array of packed-int steps plus a tiny runtime state.
-- Monophonic: at most one note in flight per track (active-note slot).
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

-- Build a fresh track. `n` = step capacity, `len` = active length.
function M.new(n, len)
    n = n or 64
    len = len or 16
    local steps = {}
    local def = Step.pack({ pitch=60, vel=100, dur=6, gate=3, prob=127, active=true })
    for i = 1, n do steps[i] = def end
    return {
        steps    = steps,
        cap      = n,
        len      = len,
        chan     = 1,
        div      = 1,        -- clock divider, 1..16
        dir      = DIR_FWD,
        ppDir    = 1,        -- ping-pong internal: 1 fwd, -1 rev
        -- runtime
        pos      = 0,        -- last fired step (0 = none yet, will go to 1 on first tick)
        divAcc   = 0,        -- pulses since last advance
        stepAcc  = 0,        -- pulses elapsed in current step (counts in own-clock units)
        -- active note slot (for NOTE_OFF scheduling)
        actPitch = -1,
        actOff   = 0,        -- pulses (own-clock) until NOTE_OFF; 0 = no active note
        -- ratchet bookkeeping (only when current step has ratch)
        ratNext  = 0,        -- pulses until next ratchet on/off toggle; 0 = inactive
        ratState = 0,        -- 0 = off-phase, 1 = on-phase
    }
end

-- ----- direction stepping -----

local function nextPos(tr)
    local len = tr.len
    if len <= 1 then return 1 end
    local d = tr.dir
    if d == DIR_FWD then
        local p = tr.pos + 1
        if p > len then p = 1 end
        return p
    elseif d == DIR_REV then
        local p = tr.pos - 1
        if p < 1 then p = len end
        return p
    elseif d == DIR_PP then
        local p = tr.pos + tr.ppDir
        if p > len then tr.ppDir = -1; p = len - 1; if p < 1 then p = 1 end
        elseif p < 1 then tr.ppDir = 1; p = 2; if p > len then p = len end end
        return p
    else  -- DIR_RND
        return math.random(1, len)
    end
end

-- Probability roll. Returns true if step should fire.
local function rollProb(prob)
    if prob >= 127 then return true end
    if prob <= 0 then return false end
    return math.random(0, 126) < prob
end

-- ----- advance: called once per *engine* pulse.
-- Returns nothing; appends events to `out` (an array passed in).
-- `out` entry shape: { type, pitch, vel, ch }

local EV_ON, EV_OFF = 1, 2
M.EV_ON, M.EV_OFF = EV_ON, EV_OFF

local function emitOff(tr, out)
    if tr.actPitch >= 0 then
        out[#out+1] = { type=EV_OFF, pitch=tr.actPitch, vel=0, ch=tr.chan }
        tr.actPitch = -1
        tr.actOff = 0
    end
end

-- Sentinel for "sustain through next boundary". Encoded as a very large counter.
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
        -- legato: keep slot, just refresh sustain
        tr.actOff = SUSTAIN
    else
        if tr.actPitch >= 0 then
            out[#out+1] = { type=EV_OFF, pitch=tr.actPitch, vel=0, ch=tr.chan }
        end
        out[#out+1] = { type=EV_ON, pitch=p, vel=v, ch=tr.chan }
        tr.actPitch = p
        tr.actOff   = sustain and SUSTAIN or g
    end

    -- ratchet bookkeeping
    if Step.ratch(s) and g > 0 then
        tr.ratNext  = g
        tr.ratState = 1
    else
        tr.ratNext  = 0
    end
end

function M.advance(tr, out)
    -- clock divider
    tr.divAcc = tr.divAcc + 1
    if tr.divAcc < tr.div then
        return
    end
    tr.divAcc = 0

    -- 1) decrement active note (sustain marker is left alone; boundary handles it)
    if tr.actOff > 0 and tr.actOff ~= SUSTAIN then
        tr.actOff = tr.actOff - 1
        if tr.actOff == 0 then
            emitOff(tr, out)
        end
    end

    -- 2) ratchet toggle inside the current step
    if tr.ratNext > 0 then
        tr.ratNext = tr.ratNext - 1
        if tr.ratNext == 0 then
            local s = tr.steps[tr.pos]
            local g = Step.gate(s)
            if tr.ratState == 1 then
                -- turn off, schedule on
                emitOff(tr, out)
                tr.ratState = 0
                tr.ratNext  = g
            else
                -- turn on again (same pitch)
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
        tr.pos = nextPos(tr)
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
function M.reset(tr)
    tr.pos      = 0
    tr.divAcc   = 0
    tr.stepAcc  = 0
    tr.actPitch = -1
    tr.actOff   = 0
    tr.ratNext  = 0
    tr.ratState = 0
    tr.ppDir    = 1
end

function M.allOff(tr, out)
    emitOff(tr, out)
end

return M
