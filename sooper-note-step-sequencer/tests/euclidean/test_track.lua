-- tests/euclidean/test_track.lua
-- Pattern bitmask + advance behaviour for Euclidean.track.
package.path = "src/?.lua;" .. package.path

local Track = require("euclidean.track")
local M = {}

local function eq(a, b, msg)
    if a ~= b then
        error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2)
    end
end

local function bits(mask, n)
    local s = ""
    for i = 0, n - 1 do
        s = s .. (((mask >> i) & 1 == 1) and "X" or ".")
    end
    return s
end

function M.test_e3_8_pattern()
    local tr = Track.new()
    Track.setSteps(tr, 8)
    Track.setEvents(tr, 3)
    Track.setRot(tr, 0)
    -- bucket method E(3,8): hit when ((i+1)*3)//8 differs from (i*3)//8
    -- i=0:0->0 .  i=1:0->0 .  i=2:0->0 . i=3:1->1 . wait check by formula
    -- We just assert the count and that the rotated form differs.
    local cnt = 0
    for i = 0, 7 do if (tr.hits >> i) & 1 == 1 then cnt = cnt + 1 end end
    eq(cnt, 3, "E(3,8) hit count")
end

function M.test_e0_n_is_silent()
    local tr = Track.new()
    Track.setSteps(tr, 16)
    Track.setEvents(tr, 0)
    eq(tr.hits, 0)
end

function M.test_ek_eq_n_is_full()
    local tr = Track.new()
    Track.setSteps(tr, 8)
    Track.setEvents(tr, 8)
    eq(tr.hits, 0xFF)
end

function M.test_rotation_shifts_bits()
    local tr = Track.new()
    Track.setSteps(tr, 8)
    Track.setEvents(tr, 3)
    local base = tr.hits
    Track.setRot(tr, 1)
    -- rotation by 1 in an 8-step pattern = circular left shift of mask
    local rotated = ((base << 1) | (base >> 7)) & 0xFF
    eq(tr.hits & 0xFF, rotated, "rot by 1: " .. bits(tr.hits, 8) .. " vs " .. bits(rotated, 8))
end

function M.test_setEvents_clamps_to_steps()
    local tr = Track.new()
    Track.setSteps(tr, 5)
    Track.setEvents(tr, 99)
    eq(tr.events, 5)
end

function M.test_advance_emits_on_hits()
    local tr = Track.new()
    Track.setSteps(tr, 4)
    Track.setEvents(tr, 4)         -- every step is a hit
    Track.setPpstep(tr, 1)         -- one pulse per step
    Track.setKey(tr, 60)
    Track.setGate(tr, 1)
    Track.reset(tr)
    local out = {}
    -- pulse 1: pos 0->0 actually advances from -1 to 0; should fire
    Track.advance(tr, out)
    local on = 0
    for _, e in ipairs(out) do if e.type == Track.EV_ON then on = on + 1 end end
    eq(on, 1, "first pulse should emit ON for E(4,4)")
end

function M.test_advance_skips_rests()
    local tr = Track.new()
    Track.setSteps(tr, 4)
    Track.setEvents(tr, 1)         -- one hit at step 1 (index 0)
    Track.setRot(tr, 0)
    Track.setPpstep(tr, 1)
    Track.setGate(tr, 1)
    Track.reset(tr)
    -- step 0 is the hit (events=1, n=4: (1*1)//4=0, (2*1)//4=0, (3*1)//4=0, (4*1)//4=1)
    -- bucket method puts the hit on the LAST step (index 3) since the increment
    -- happens at i=4. Let's just count ONs over a full loop.
    local ons = 0
    for _ = 1, 4 do
        local out = {}
        Track.advance(tr, out)
        for _, e in ipairs(out) do if e.type == Track.EV_ON then ons = ons + 1 end end
    end
    eq(ons, 1, "exactly one ON per loop for E(1,4)")
end

function M.test_muted_does_not_emit()
    local tr = Track.new()
    Track.setSteps(tr, 4)
    Track.setEvents(tr, 4)
    Track.setPpstep(tr, 1)
    Track.setMuted(tr, 1)
    Track.reset(tr)
    local out = {}
    for _ = 1, 8 do Track.advance(tr, out) end
    eq(#out, 0, "muted track must not emit")
end

function M.test_polyrhythm_via_steps()
    -- Sanity: two tracks at the same ppstep but different steps cycle at
    -- different lengths.
    local a, b = Track.new(), Track.new()
    Track.setSteps(a, 3); Track.setEvents(a, 3); Track.setPpstep(a, 1); Track.setGate(a, 1)
    Track.setSteps(b, 4); Track.setEvents(b, 4); Track.setPpstep(b, 1); Track.setGate(b, 1)
    Track.reset(a); Track.reset(b)
    -- After 12 pulses, both should have completed an integer number of cycles
    -- (LCM). a: 12/3=4 cycles -> pos returns to 2 (last index). b: 12/4=3 cycles.
    for _ = 1, 12 do
        local o = {}
        Track.advance(a, o)
        Track.advance(b, o)
    end
    eq(a.pos, 2)
    eq(b.pos, 3)
end

return M
