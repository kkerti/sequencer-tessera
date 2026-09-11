-- midi/out.lua — turn the engine's preallocated event buffer into sink calls.
--
-- The sink is supplied by the host adapter (stdio on Mac, gms on Grid), so the
-- Core stays device-agnostic. Event buffer: out.typ 1=note on, 0=note off,
-- 2=control; out.pitch/velocity/channel carry the payload.

local M = {}

local function noop() end
M.sink = noop

function M.setSink(fn) M.sink = fn end

function M.emit(out)
    local n = out.n
    if n == 0 then return end
    local typ, pitch, velocity, channel = out.typ, out.pitch, out.velocity, out.channel
    for i = 1, n do
        M.sink(typ[i], pitch[i], velocity[i], channel[i])
    end
end

return M
