-- track.lua
-- Track state + per-pulse advance (ER-101 model).
--
-- A track is a fixed 64-step buffer of packed-int steps plus tiny runtime
-- state. Monophonic: at most one note in flight per track. Always plays
-- forward.
--
-- Per-step duration model (ER-101 style):
--   `dur`  = how many engine pulses this step occupies before advancing.
--            1..127.  (0 is treated as 1.)
--   `gate` = how many of those `dur` pulses the note is held.  1..127,
--            capped at `dur` at fire time.  0 = silent step.
--
-- Per-track lastStep:
--   The track plays steps 1..lastStep, then wraps. Default 16, range 1..64.
--   Different lastStep across tracks gives free polyrhythm (e.g. 16/12/14)
--   without needing per-step `dur` games.
--
-- Per-pulse cost: a few comparisons + a decrement when a note is active.
-- Zero allocations per pulse.

local Step = require("step")

local M = {}

M.DEFAULT_LAST_STEP = 16

-- Build a fresh track. `cap` is the buffer capacity (default 64).
function M.new(cap)
    cap = cap or 64
    local steps = {}
    -- Default seed: dur=4 pulses per step, gate=2 pulses (50% gate).
    local def = Step.pack({ pitch=60, vel=100, dur=4, gate=2 })
    for i = 1, cap do steps[i] = def end
    return {
        steps    = steps,
        cap      = cap,
        chan     = 1,
        lastStep = M.DEFAULT_LAST_STEP,
        -- runtime
        pos      = 0,        -- last fired step (0 = none yet)
        stepAcc  = 0,        -- pulses left in current step (counts down)
        stepLen  = 0,        -- total length of current step (for UI %)
        -- active note slot
        actPitch = -1,
        actOff   = 0,        -- pulses until NOTE_OFF; 0 = no active note
        -- ratchet bookkeeping
        ratNext  = 0,
        ratState = 0,
    }
end

-- Forward-only stepping. Wraps at lastStep.
local function nextPos(tr)
    local p = tr.pos + 1
    if p > tr.lastStep or p < 1 then p = 1 end
    return p
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

local function fireStep(tr, out)
    local s = tr.steps[tr.pos]
    if Step.muted(s) then return end
    local p, v, g = Step.pitch(s), Step.vel(s), Step.gate(s)
    if g <= 0 then return end
    -- gate cannot exceed step length
    if g > tr.stepLen then g = tr.stepLen end

    -- Legato: same pitch, full gate, currently sustaining a same-pitch note.
    if tr.actPitch == p and g >= tr.stepLen and tr.actOff > 0 then
        tr.actOff = g
    else
        if tr.actPitch >= 0 then
            out[#out+1] = { type=EV_OFF, pitch=tr.actPitch, vel=0, ch=tr.chan }
        end
        out[#out+1] = { type=EV_ON, pitch=p, vel=v, ch=tr.chan }
        tr.actPitch = p
        tr.actOff   = g
    end

    if Step.ratch(s) then
        tr.ratNext  = g
        tr.ratState = 1
    else
        tr.ratNext  = 0
    end
end

-- advance: called once per *engine* pulse.
function M.advance(tr, out)
    if tr.stepAcc <= 0 then
        tr.pos = nextPos(tr)
        local s = tr.steps[tr.pos]
        local d = Step.dur(s)
        if d <= 0 then d = 1 end
        tr.stepAcc = d
        tr.stepLen = d
        fireStep(tr, out)
    else
        if tr.actOff > 0 then
            tr.actOff = tr.actOff - 1
            if tr.actOff == 0 then emitOff(tr, out) end
        end
    end

    -- ratchet toggle inside current step
    if tr.ratNext > 0 then
        tr.ratNext = tr.ratNext - 1
        if tr.ratNext == 0 then
            local s = tr.steps[tr.pos]
            local g = Step.gate(s)
            if g > tr.stepLen then g = tr.stepLen end
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

function M.setLastStep(tr, n)
    if n < 1 then n = 1 elseif n > tr.cap then n = tr.cap end
    tr.lastStep = n
end

-- start/stop housekeeping
function M.reset(tr)
    tr.pos      = 0
    tr.stepAcc  = 0
    tr.stepLen  = 0
    tr.actPitch = -1
    tr.actOff   = 0
    tr.ratNext  = 0
    tr.ratState = 0
end

function M.allOff(tr, out)
    emitOff(tr, out)
end

return M
