-- src/euclidean/track.lua
-- Euclidean track: a rotated E(events, steps) rhythm + fixed key + per-track
-- step rate.
--
-- State (per track):
--   steps    1..MAX_STEPS               cycle length
--   events   0..steps                   number of hits
--   rot      0..steps-1                 rotation (offset) of the pattern
--   key      0..127                     MIDI pitch fired on each hit
--   vel      1..127                     MIDI velocity for hits
--   gate     1..127 pulses              note-on hold time
--   ppstep   1..127 pulses              external pulses per pattern step
--   chan     0..15                      MIDI channel
--   muted    0/1                        silence the track (still advances)
--
-- Cached at edit time, never per pulse:
--   hits     Lua int (bitmask, bit i set = step (i+1) is a hit)
--
-- Runtime (cleared on reset):
--   pos      0..steps-1   index of LAST fired step (-1 = none yet)
--   acc      pulses left in current step
--   actOff   pulses until note-off (0 = no active note)
--
-- Pattern algorithm: integer-bucket Euclidean. For step index i (0-based,
-- after rotation), hit = ((i+1)*events)//steps ~= (i*events)//steps. This
-- matches Bjorklund for almost all musically useful (k,n) and is O(n) with
-- zero allocations. Recomputed only when events/steps/rot change.
--
-- Per-pulse cost: one decrement, one comparison, optional bit test. Zero alloc.

local M = {}

M.MAX_STEPS = 32

local EV_ON, EV_OFF = 1, 2
M.EV_ON, M.EV_OFF = EV_ON, EV_OFF

-- ---------- pattern recompute ----------

-- Compute the events-out-of-steps bitmask, then rotate it. Bit 0 = step 1.
-- Pure local arithmetic, no allocations.
local function recompute(tr)
    local n  = tr.steps
    local k  = tr.events
    local r  = tr.rot
    if n < 1 then n = 1 end
    if k < 0 then k = 0 elseif k > n then k = n end
    if r < 0 then r = 0 elseif r >= n then r = r % n end

    local mask = 0
    if k > 0 then
        local prev = 0
        for i = 1, n do
            local cur = (i * k) // n
            if cur ~= prev then
                -- raw bit (i-1) is a hit; apply rotation
                local b = (i - 1 + r) % n
                mask = mask | (1 << b)
            end
            prev = cur
        end
    end
    tr.hits = mask
end
M.recompute = recompute

-- ---------- constructor ----------

function M.new()
    local tr = {
        steps   = 16,
        events  = 4,
        rot     = 0,
        key     = 60,
        vel     = 100,
        gate    = 3,
        ppstep  = 6,        -- 16th note at 24 PPQN
        chan    = 0,
        muted   = 0,
        hits    = 0,
        pos     = -1,
        acc     = 0,
        actOff  = 0,
    }
    recompute(tr)
    return tr
end

-- ---------- runtime ----------

function M.reset(tr)
    tr.pos    = -1
    tr.acc    = 0
    tr.actOff = 0
end

local function emitOff(tr, out)
    if tr.actOff > 0 then
        out[#out+1] = { type=EV_OFF, pitch=tr.key, vel=0, ch=tr.chan }
        tr.actOff = 0
    end
end
M.emitOff = emitOff

function M.allOff(tr, out)
    if tr.actOff > 0 then
        out[#out+1] = { type=EV_OFF, pitch=tr.key, vel=0, ch=tr.chan }
        tr.actOff = 0
    end
end

-- One external pulse. Emits NOTE_ON when a step boundary lands on a hit
-- (and the track isn't muted); emits NOTE_OFF when actOff counts down to 0.
function M.advance(tr, out)
    -- note-off countdown ticks every pulse
    if tr.actOff > 0 then
        tr.actOff = tr.actOff - 1
        if tr.actOff == 0 then
            out[#out+1] = { type=EV_OFF, pitch=tr.key, vel=0, ch=tr.chan }
        end
    end

    if tr.acc <= 0 then
        local p = tr.pos + 1
        if p >= tr.steps then p = 0 end
        tr.pos = p
        local d = tr.ppstep
        if d <= 0 then d = 1 end
        tr.acc = d

        if tr.muted == 0 and (tr.hits >> p) & 1 == 1 then
            -- if a prior note is still sounding, close it before re-firing
            if tr.actOff > 0 then
                out[#out+1] = { type=EV_OFF, pitch=tr.key, vel=0, ch=tr.chan }
                tr.actOff = 0
            end
            local g = tr.gate
            if g > d then g = d end
            if g > 0 then
                out[#out+1] = { type=EV_ON, pitch=tr.key, vel=tr.vel, ch=tr.chan }
                tr.actOff = g
            end
        end
    end

    tr.acc = tr.acc - 1
end

-- ---------- setters (recompute hits when needed) ----------

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi else return v end
end

function M.setSteps(tr, n)
    n = clamp(n, 1, M.MAX_STEPS)
    if n == tr.steps then return end
    tr.steps = n
    if tr.events > n then tr.events = n end
    if tr.rot >= n then tr.rot = tr.rot % n end
    recompute(tr)
end

function M.setEvents(tr, k)
    k = clamp(k, 0, tr.steps)
    if k == tr.events then return end
    tr.events = k
    recompute(tr)
end

function M.setRot(tr, r)
    if tr.steps < 1 then return end
    r = r % tr.steps
    if r < 0 then r = r + tr.steps end
    if r == tr.rot then return end
    tr.rot = r
    recompute(tr)
end

function M.setKey(tr, p)        tr.key   = clamp(p, 0,   127) end
function M.setVel(tr, v)        tr.vel   = clamp(v, 1,   127) end
function M.setGate(tr, g)       tr.gate  = clamp(g, 1,   127) end
function M.setPpstep(tr, d)     tr.ppstep= clamp(d, 1,   127) end
function M.setChan(tr, c)       tr.chan  = clamp(c, 0,    15) end
function M.setMuted(tr, m)      tr.muted = (m and m ~= 0) and 1 or 0 end

-- True iff step index i (0-based) is a hit in the rotated pattern.
function M.isHit(tr, i)
    if i < 0 or i >= tr.steps then return false end
    return ((tr.hits >> i) & 1) == 1
end

return M
