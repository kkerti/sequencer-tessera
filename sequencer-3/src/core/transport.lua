-- transport.lua — the single 24-PPQN pulse path.
--
-- External MIDI clock (0xF8) and the internal timer both call Engine.onPulse;
-- the transport counts pulses and lets lanes ask whether a tap fired. Pure and
-- alloc-free.

local Sources = require("sources")

local M = {}

M.PPQN = 24

function M.new()
    return { running = false, pulse = 0 }
end

function M.start(t)
    t.running = true
    t.pulse = 0
end

function M.stop(t)
    t.running = false
end

function M.tick(t)
    if not t.running then return false end
    t.pulse = t.pulse + 1
    return true
end

function M.fired(t, interval)
    if not t.running or interval <= 0 then return false end
    return (t.pulse % interval) == 0
end

function M.tapFired(t, source)
    local interval = Sources.TRANSPORT_INTERVAL[source]
    if not interval then return false end
    return M.fired(t, interval)
end

return M
