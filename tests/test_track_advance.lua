-- tests/test_track_advance.lua
local Track = require("track")
local Step  = require("step")
local M = {}

local function eq(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end end

local function pulse(tr, n)
    local out = {}
    for _ = 1, n do Track.advance(tr, out, 0) end
    return out
end

function M.test_basic_note_on_off()
    local tr = Track.new()
    tr.steps[1] = Step.pack({ pitch=60, vel=100, dur=4, gate=2 })
    tr.steps[2] = Step.pack({ pitch=62, vel=100, dur=4, gate=2 })
    Track.reset(tr, 1)

    -- pulse 1: step 1 starts -> NOTE_ON 60
    local out = pulse(tr, 1)
    eq(#out, 1); eq(out[1].type, Track.EV_ON); eq(out[1].pitch, 60)

    -- pulse 2: gate still on
    out = pulse(tr, 1); eq(#out, 0)

    -- pulse 3: gate hits 0 -> NOTE_OFF 60
    out = pulse(tr, 1); eq(#out, 1); eq(out[1].type, Track.EV_OFF); eq(out[1].pitch, 60)

    -- pulse 4: still in step 1 (dur=4)
    out = pulse(tr, 1); eq(#out, 0)

    -- pulse 5: step 2 starts -> NOTE_ON 62
    out = pulse(tr, 1); eq(#out, 1); eq(out[1].type, Track.EV_ON); eq(out[1].pitch, 62)
end

function M.test_legato()
    local tr = Track.new()
    -- Make all steps share pitch 60 and dur=4/gate=4 so legato extends across
    -- region boundaries indefinitely (no off-on between steps).
    for i = 1, 16 do
        tr.steps[i] = Step.pack({ pitch=60, vel=100, dur=4, gate=4 })
    end
    Track.reset(tr, 1)

    local out = pulse(tr, 1)
    eq(#out, 1); eq(out[1].type, Track.EV_ON)

    local total = {}
    for _ = 1, 8 do
        local o = pulse(tr, 1)
        for _, e in ipairs(o) do total[#total+1] = e end
    end
    eq(#total, 0, "legato: no extra events")
end

function M.test_rest_step_active_false()
    local tr = Track.new()
    tr.steps[1] = Step.pack({ pitch=60, vel=100, dur=4, gate=2, active=false })
    tr.steps[2] = Step.pack({ pitch=62, vel=100, dur=4, gate=2 })
    Track.reset(tr, 1)

    local out = pulse(tr, 1)
    eq(#out, 0)

    out = pulse(tr, 4)
    local found = false
    for _, e in ipairs(out) do if e.type == Track.EV_ON and e.pitch == 62 then found = true end end
    if not found then error("expected NOTE_ON 62 within 4 pulses") end
end

function M.test_clock_divider()
    local tr = Track.new()
    tr.div = 2
    tr.steps[1] = Step.pack({ pitch=60, vel=100, dur=2, gate=1 })
    tr.steps[2] = Step.pack({ pitch=62, vel=100, dur=2, gate=1 })
    Track.reset(tr, 1)

    local out = pulse(tr, 1); eq(#out, 0, "first pulse swallowed")
    out = pulse(tr, 1); eq(out[1].type, Track.EV_ON); eq(out[1].pitch, 60)
end

return M
