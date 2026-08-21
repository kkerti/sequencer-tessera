-- tests/test_swing.lua
-- Global swing: pulses-of-delay applied to fires landing on off-beat 16ths.
-- Engine assumes 24 PPQN: 16th = 6 pulses, off-beat 16th = pulse 6, 18, ...

local Engine = require("engine")
local Step   = require("step")
local Track  = require("track")
local M = {}

local function eq(a, b, msg)
    if a ~= b then
        error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2)
    end
end

-- Configure a single track of identical 16th-note steps (dur=6, gate=3).
local function setupOneTrack(pitch)
    Engine.init({ trackCount = 1 })
    local tr = Engine.tracks[1]
    local seed = Step.pack({ pitch = pitch or 60, vel = 100, dur = 6, gate = 3 })
    for i = 1, tr.cap do tr.steps[i] = seed end
end

-- Drive `n` pulses, return a list of pulse indices (0-based) at which an
-- EV_ON fired on track 1.
local function gatherOnPulses(n)
    local hits = {}
    for p = 0, n - 1 do
        local ev = Engine.onPulse()
        if ev then
            for _, e in ipairs(ev) do
                if e.type == Track.EV_ON then
                    hits[#hits + 1] = p
                end
            end
        end
    end
    return hits
end

local function listEq(a, b, msg)
    if #a ~= #b then
        error((msg or "") .. " length differs: got " .. #a .. " expected " .. #b, 2)
    end
    for i = 1, #a do
        if a[i] ~= b[i] then
            error((msg or "") .. " index " .. i .. " expected " .. tostring(b[i])
                .. " got " .. tostring(a[i]), 2)
        end
    end
end

function M.test_default_swing_is_zero()
    Engine.init({})
    eq(Engine.swing, 0)
end

function M.test_setSwing_clamps_0_to_3()
    Engine.init({})
    Engine.setSwing(-5); eq(Engine.swing, 0)
    Engine.setSwing(99); eq(Engine.swing, 3)
    Engine.setSwing(2);  eq(Engine.swing, 2)
end

function M.test_swing_zero_fires_every_6_pulses()
    setupOneTrack(60)
    Engine.setSwing(0)
    Engine.onStart()
    local hits = gatherOnPulses(36)
    -- straight 16ths: 0, 6, 12, 18, 24, 30
    listEq(hits, { 0, 6, 12, 18, 24, 30 }, "straight grid")
end

function M.test_swing_2_delays_offbeat_16ths()
    setupOneTrack(60)
    Engine.setSwing(2)
    Engine.onStart()
    local hits = gatherOnPulses(36)
    -- on-beat (0, 12, 24) unchanged. Off-beat fires deferred by 2 pulses:
    -- pulse 6 -> fires at 8, then dur=6 -> next on-beat at 14? NO.
    -- Trace: pulse 6 was the firing pulse, deferred. stepAcc set to 2 + advance
    -- decrements to 1. pulse 7: stepAcc 0 -> wait, advance decrements then checks?
    -- Inspect the actual hits to lock the spec rather than guess.
    -- Expected: every other 16th delayed by exactly 2.
    --   on-beats stay at 0, 12, 24
    --   off-beats move 6 -> 8, 18 -> 20, 30 -> 32
    listEq(hits, { 0, 8, 12, 20, 24, 32 }, "swung grid")
end

function M.test_swing_does_not_alter_onbeat_fires()
    setupOneTrack(60)
    Engine.setSwing(3)
    Engine.onStart()
    local hits = gatherOnPulses(48)
    -- on-beat fires must remain at multiples of 12
    eq(hits[1], 0, "first fire at pulse 0")
    eq(hits[3], 12, "third fire (next on-beat) at pulse 12")
    eq(hits[5], 24, "fifth fire (next on-beat) at pulse 24")
    eq(hits[7], 36, "seventh fire (next on-beat) at pulse 36")
end

function M.test_onStart_resets_pulseCount()
    setupOneTrack(60)
    Engine.setSwing(2)
    Engine.onStart()
    gatherOnPulses(20)
    Engine.onStart()
    eq(Engine.pulseCount, 0, "pulseCount reset")
    local hits = gatherOnPulses(15)
    listEq(hits, { 0, 8, 12 }, "second run starts cleanly swung")
end

function M.test_pulseCount_only_advances_when_running()
    Engine.init({})
    Engine.pulseCount = 0
    Engine.onPulse()        -- not running
    eq(Engine.pulseCount, 0)
    Engine.onStart()
    Engine.onPulse()
    eq(Engine.pulseCount, 1)
end

function M.test_offgrid_dur_pattern_unaffected_by_swing()
    -- A track with all dur=8 fires at 0, 8, 16, 24... none of which hit the
    -- swing target (pulse % 12 == 6). The track must be untouched by swing.
    Engine.init({ trackCount = 1 })
    local tr = Engine.tracks[1]
    local seed = Step.pack({ pitch = 60, vel = 100, dur = 8, gate = 4 })
    for i = 1, tr.cap do tr.steps[i] = seed end
    Engine.setSwing(3)
    Engine.onStart()
    local hits = gatherOnPulses(40)
    listEq(hits, { 0, 8, 16, 24, 32 }, "off-grid pattern unaffected")
end

return M
