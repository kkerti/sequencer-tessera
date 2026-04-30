-- tests/test_track_ratchet.lua
local Track = require("track")
local Step  = require("step")
local M = {}

local function eq(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end end

function M.test_ratchet_produces_multiple_on_off()
    local tr = Track.new(8, 1)
    -- dur=12, gate=3, ratch=true: expect on@0, off@3, on@6, off@9, off again at end
    tr.steps[1] = Step.pack({ pitch=60, vel=100, dur=12, gate=3, ratch=true })
    Track.reset(tr)

    local total = {}
    for _ = 1, 13 do
        local out = {}
        Track.advance(tr, out)
        for _, e in ipairs(out) do total[#total+1] = e end
    end

    -- count NOTE_ONs
    local ons, offs = 0, 0
    for _, e in ipairs(total) do
        if e.type == Track.EV_ON then ons = ons + 1 end
        if e.type == Track.EV_OFF then offs = offs + 1 end
    end
    if ons < 2 then error("ratchet: expected >=2 NOTE_ONs, got " .. ons) end
    if offs < 2 then error("ratchet: expected >=2 NOTE_OFFs, got " .. offs) end
end

return M
