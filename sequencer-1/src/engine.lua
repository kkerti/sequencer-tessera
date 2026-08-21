-- engine.lua
-- 4-track engine. Externally clocked. Pure: returns events, does no IO.
--
-- No regions. Polyrhythm comes from per-track lastStep + per-step dur.

local Track  = require("track")
local Scale  = require("scale")

local M = {}

M.tracks = {}     -- public read; UI may read directly
M.scales = Scale.SCALES  -- public read; scale definitions (name + mask)
M.running = false
M.pulseCount = 0  -- absolute pulse counter since last onStart; for swing grid
M.swing = 0       -- 0..3 pulses of delay applied to off-beat 16ths (24 PPQN)
local logFn = nil

function M.init(opts)
    opts = opts or {}
    local n   = opts.trackCount or 4
    local cap = opts.stepsPerTrack or 64
    M.tracks = {}
    for i = 1, n do
        M.tracks[i] = Track.new(cap)
        M.tracks[i].chan = i - 1     -- channels are 0-based on the wire
    end
    M.running = false
    M.pulseCount = 0
    M.swing = 0
    -- swingOwed[i] = pulses each track was deferred and must compensate on
    -- its next real fire. Preallocated; never reassigned.
    M._swingOwed = {}
    for i = 1, n do M._swingOwed[i] = 0 end
    logFn = opts.log
end

local function log(s) if logFn then logFn(s) end end

function M.onStart()
    for i = 1, #M.tracks do
        Track.reset(M.tracks[i])
        M._swingOwed[i] = 0
    end
    M.pulseCount = 0
    M.running = true
    log("START")
end

function M.onStop()
    local out = {}
    for i = 1, #M.tracks do Track.allOff(M.tracks[i], out) end
    M.running = false
    log("STOP")
    return out
end

-- Called once per external pulse. Returns events array, or nil if none.
-- Swing model (24 PPQN assumption): when M.swing > 0 and the current pulse
-- is the off-beat 16th (pulseCount % 12 == 6), any track whose step is
-- about to fire on this pulse has its fire deferred by `swing` pulses.
-- The next real fire on that track has its remaining duration shortened
-- by the same amount, so the following on-beat returns to the grid.
-- Tracks whose `dur` pattern doesn't land on the swing target pulse are
-- unaffected — swing only acts on fires that coincide with the swing grid.
function M.onPulse()
    if not M.running then return nil end
    local out = {}
    local ts  = M.tracks
    local n   = #ts
    local sw  = M.swing
    local pc  = M.pulseCount
    local owe = M._swingOwed
    M.pulseCount = pc + 1
    local swingPulse = sw > 0 and ((pc % 12) == 6)

    for i = 1, n do
        local tr = ts[i]
        local owed = owe[i]
        local atFire = (tr.stepAcc <= 0)

        if atFire and swingPulse and owed == 0 then
            -- defer this fire by `sw` pulses; advance() will tick note-off
            -- and decrement stepAcc, no fire emitted this pulse
            tr.stepAcc = sw
            tr.stepLen = sw
            owe[i] = sw
            atFire = false
        end

        Track.advance(tr, out)

        -- if a real fire just happened and we owed time from a prior defer,
        -- shorten the just-started step's remainder to land back on grid
        if atFire and owed > 0 then
            local left = tr.stepAcc - owed
            if left < 0 then left = 0 end
            tr.stepAcc = left
            owe[i] = 0
        end
    end

    if #out == 0 then return nil end
    return out
end

-- ----- convenience setters -----

function M.setStepParam(t, i, name, val)
    local tr = M.tracks[t]; if not tr then return end
    Track.setStepParam(tr, i, name, val)
end

function M.setLastStep(t, n)
    local tr = M.tracks[t]; if not tr then return end
    Track.setLastStep(tr, n)
end

function M.setTrackChan(t, ch)
    local tr = M.tracks[t]; if not tr then return end
    if ch < 0 then ch = 0 end
    if ch > 15 then ch = 15 end
    tr.chan = ch
end

-- Select the quantization scale for a track (index into M.scales; 1 = off).
function M.setTrackScale(t, idx)
    local tr = M.tracks[t]; if not tr then return end
    Track.setScale(tr, idx)
end

-- Global swing depth in pulses (0..3 at 24 PPQN → 50/58/67/75% feel).
function M.setSwing(s)
    if s < 0 then s = 0 elseif s > 3 then s = 3 end
    M.swing = s
end

return M
