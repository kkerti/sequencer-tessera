-- fx/range.lua — RANGE: the performance limiter.
--
-- Clamps each note field to a [min,max] window. Values outside the window pin
-- to the nearest boundary (decided: clamp, not fold). These are the knobs you
-- sweep live to compress/shift a part. Each field is independently active:
-- leave min=0/max=127 (or lenMax huge) to pass a field through untouched.
--
-- Operates in place on the shared scratch buffer. Zero allocation.

local M = {}
M.__index = M

function M.new(p)
    p = p or {}
    return setmetatable({
        pitchMin = p.pitchMin or 0,   pitchMax = p.pitchMax or 127,
        velMin   = p.velMin   or 1,   velMax   = p.velMax   or 127,
        lenMin   = p.lenMin   or 1,   lenMax   = p.lenMax   or 65535,
    }, M)
end

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi else return v end
end

function M:process(buf)
    local P, L, V = buf.pitch, buf.len, buf.vel
    for i = 1, buf.n do
        P[i] = clamp(P[i], self.pitchMin, self.pitchMax)
        V[i] = clamp(V[i], self.velMin,   self.velMax)
        L[i] = clamp(L[i], self.lenMin,   self.lenMax)
    end
end

return M
