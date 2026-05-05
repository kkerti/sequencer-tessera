-- tests/euclidean/test_no_alloc.lua
-- Locks zero per-pulse retained allocations for the Euclidean engine.
package.path = "src/?.lua;" .. package.path

local Engine = require("euclidean.engine")

local M = {}

local function gc_kb()
    collectgarbage("collect")
    collectgarbage("collect")
    return collectgarbage("count")
end

function M.test_onPulse_does_not_allocate()
    Engine.init({ trackCount = 4 })
    for t = 1, 4 do
        Engine.setSteps(t, 16)
        Engine.setEvents(t, t * 2)      -- varied densities
        Engine.setRot(t, t)
        Engine.setPpstep(t, 2 + t)
        Engine.setKey(t, 60 + t)
        Engine.setGate(t, 1)
    end
    Engine.onStart()
    for _ = 1, 200 do Engine.onPulse() end

    local pre = gc_kb()
    local N = 5000
    for _ = 1, N do Engine.onPulse() end
    local post = gc_kb()

    local delta_bytes = (post - pre) * 1024
    if delta_bytes > 64 then
        error(string.format(
            "euclid.engine.onPulse retained %.1f bytes over %d pulses (%.4f B/pulse)",
            delta_bytes, N, delta_bytes / N))
    end
end

function M.test_onPulse_stopped_does_not_allocate()
    Engine.init({ trackCount = 4 })
    local pre = gc_kb()
    for _ = 1, 5000 do Engine.onPulse() end
    local post = gc_kb()
    local delta_bytes = (post - pre) * 1024
    if delta_bytes > 32 then
        error("stopped euclid.engine.onPulse retained " .. delta_bytes .. " bytes")
    end
end

return M
