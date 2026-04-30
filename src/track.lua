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
--   So the track advances one step every `dur` pulses, and the playhead
--   visually dwells on a step for `dur` pulses. This is what makes the
--   column UI's clock-progress bar meaningful, and it gives real rhythm
--   without a separate per-track divider.
--
-- Regions: the 64-step buffer is divided into 4 fixed regions of 16 steps:
--   region 1 = steps 1..16    region 3 = steps 33..48
--   region 2 = steps 17..32   region 4 = steps 49..64
-- The engine tells the track which region is active; region switching
-- happens at-end-of-region per track and is coordinated by the engine.
--
-- Per-pulse cost: a few comparisons + a decrement when a note is active.
-- Zero allocations per pulse.

local Step = require("step")

local M = {}

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
    -- Default seed: dur=4 pulses per step, gate=2 pulses (50% gate).
    local def = Step.pack({ pitch=60, vel=100, dur=4, gate=2, prob=127 })
    for i = 1, cap do steps[i] = def end
    return {
        steps    = steps,
        cap      = cap,
        chan     = 1,
        -- runtime
        pos      = 0,        -- last fired step (0 = none yet)
        stepAcc  = 0,        -- pulses left in current step (counts down)
        stepLen  = 0,        -- total length of current step (for UI %)
        -- region runtime
        curRegion   = 1,
        regionDone  = false,
        -- active note slot
        actPitch = -1,
        actOff   = 0,        -- pulses until NOTE_OFF; 0 = no active note
        -- ratchet bookkeeping
        ratNext  = 0,
        ratState = 0,
    }
end

-- Forward-only stepping. Returns the next step index. If the advance
-- crosses the current region's high bound and a region switch is queued,
-- jumps to the queued region's lo and marks regionDone.
local function nextPos(tr, queuedRegion)
    local cur = tr.curRegion
    local lo  = regionLo(cur)
    local hi  = regionHi(cur)
    local p   = tr.pos + 1
    if tr.pos < lo or tr.pos > hi then p = lo end  -- first step / region change
    if p > hi then
        if queuedRegion ~= 0 then
            tr.curRegion = queuedRegion
            tr.regionDone = true
            return regionLo(queuedRegion)
        end
        return lo
    end
    return p
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

local function fireStep(tr, out)
    local s = tr.steps[tr.pos]
    if Step.muted(s) then return end
    if not rollProb(Step.prob(s)) then return end
    local p, v, g = Step.pitch(s), Step.vel(s), Step.gate(s)
    if g <= 0 then return end
    -- gate cannot exceed step length
    if g > tr.stepLen then g = tr.stepLen end

    -- Legato: same pitch, full gate, currently sustaining a same-pitch note.
    -- Extend the active note by `g` instead of off+on. The previous note
    -- has not yet emitted its NOTE_OFF (actOff > 0), so we just push it out.
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
-- `queuedRegion` is the engine's current queue (0 = none).
function M.advance(tr, out, queuedRegion)
    -- 1) step boundary FIRST so legato can detect a still-active prior note.
    if tr.stepAcc <= 0 then
        tr.pos = nextPos(tr, queuedRegion or 0)
        local s = tr.steps[tr.pos]
        local d = Step.dur(s)
        if d <= 0 then d = 1 end
        tr.stepAcc = d
        tr.stepLen = d
        fireStep(tr, out)
    else
        -- 2a) decrement active note (only when NOT firing a new step,
        --     so legato chains can set actOff fresh without an OFF leak).
        if tr.actOff > 0 then
            tr.actOff = tr.actOff - 1
            if tr.actOff == 0 then emitOff(tr, out) end
        end
    end

    -- 2b) ratchet toggle inside current step
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

-- start/stop housekeeping
function M.reset(tr, region)
    tr.pos        = 0
    tr.stepAcc    = 0
    tr.stepLen    = 0
    tr.actPitch   = -1
    tr.actOff     = 0
    tr.ratNext    = 0
    tr.ratState   = 0
    tr.curRegion  = region or 1
    tr.regionDone = false
end

function M.allOff(tr, out)
    emitOff(tr, out)
end

return M
