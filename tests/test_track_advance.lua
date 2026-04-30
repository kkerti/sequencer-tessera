-- tests/test_track_advance.lua
local Track = require("track")
local Step  = require("step")
local M = {}

local function eq(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end end

local function pulse(tr, n)
    local out = {}
    for _ = 1, n do Track.advance(tr, out) end
    return out
end

function M.test_basic_note_on_off()
    local tr = Track.new(8, 4)
    tr.steps[1] = Step.pack({ pitch=60, vel=100, dur=4, gate=2 })
    tr.steps[2] = Step.pack({ pitch=62, vel=100, dur=4, gate=2 })
    Track.reset(tr)

    -- pulse 1: step 1 starts -> NOTE_ON 60
    local out = pulse(tr, 1)
    eq(#out, 1); eq(out[1].type, Track.EV_ON); eq(out[1].pitch, 60)

    -- pulse 2: gate still on (gate=2, decremented from 2 to 1)
    out = pulse(tr, 1); eq(#out, 0)

    -- pulse 3: gate hits 0 -> NOTE_OFF 60
    out = pulse(tr, 1); eq(#out, 1); eq(out[1].type, Track.EV_OFF); eq(out[1].pitch, 60)

    -- pulse 4: still in step 1 (dur=4)
    out = pulse(tr, 1); eq(#out, 0)

    -- pulse 5: step 2 starts -> NOTE_ON 62
    out = pulse(tr, 1); eq(#out, 1); eq(out[1].type, Track.EV_ON); eq(out[1].pitch, 62)
end

function M.test_legato()
    local tr = Track.new(8, 2)
    -- gate >= dur, same pitch → no off-on; pitch sustained
    tr.steps[1] = Step.pack({ pitch=60, vel=100, dur=4, gate=4 })
    tr.steps[2] = Step.pack({ pitch=60, vel=100, dur=4, gate=4 })
    Track.reset(tr)

    local out = pulse(tr, 1) -- pos 1 fires
    eq(#out, 1); eq(out[1].type, Track.EV_ON)

    -- run through dur=4 pulses; on pulse 5 step 2 fires
    -- expect NO off+on in between (legato) since pitch same and gate>=dur
    local total = {}
    for _ = 1, 8 do
        local o = pulse(tr, 1)
        for _, e in ipairs(o) do total[#total+1] = e end
    end
    -- only the next NOTE_ON for step 2 (still pitch 60, slot extends)
    -- under our impl: same pitch + g>=dur => extend, no event emitted
    -- so total should be empty across the next 8 pulses
    eq(#total, 0, "legato: no extra events")
end

function M.test_rest_step_active_false()
    local tr = Track.new(8, 2)
    tr.steps[1] = Step.pack({ pitch=60, vel=100, dur=4, gate=2, active=false })
    tr.steps[2] = Step.pack({ pitch=62, vel=100, dur=4, gate=2 })
    Track.reset(tr)

    local out = pulse(tr, 1) -- step 1 fires but inactive -> nothing
    eq(#out, 0)

    -- advance 4 pulses to reach step 2
    out = pulse(tr, 4)
    -- expect NOTE_ON 62 in there
    local found = false
    for _, e in ipairs(out) do if e.type == Track.EV_ON and e.pitch == 62 then found = true end end
    if not found then error("expected NOTE_ON 62 within 4 pulses") end
end

function M.test_clock_divider()
    local tr = Track.new(8, 2)
    tr.div = 2
    tr.steps[1] = Step.pack({ pitch=60, vel=100, dur=2, gate=1 })
    tr.steps[2] = Step.pack({ pitch=62, vel=100, dur=2, gate=1 })
    Track.reset(tr)

    -- div=2: every 2 external pulses = 1 advance
    local out = pulse(tr, 1); eq(#out, 0, "first pulse swallowed")
    out = pulse(tr, 1); eq(out[1].type, Track.EV_ON); eq(out[1].pitch, 60)
end

return M
