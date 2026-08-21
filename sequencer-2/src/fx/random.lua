-- fx/random.lua — RANDOM / CHANCE: probabilistic variation.
--
--   chance   : 0..100, percent probability a note PLAYS (100 = always).
--              A failed roll drops the note (buffer is compacted in place).
--   pitchJit : +/- semitones of random pitch offset.
--   velJit   : +/- velocity offset (result clamped 1..127).
--   octJit   : +/- octaves (12 semitones) of random offset.
--
-- Free-running by default: each loop rolls fresh, for living variation. A
-- per-instance LCG keeps this allocation-free and independent of math.random
-- (so two RANDOM effects don't share state, and playback is deterministic
-- given a seed). Since the M1 rack runs RANGE -> RANDOM -> SCALE, any pitch
-- jitter here is re-quantized to the scale afterwards and stays in key.

local M = {}
M.__index = M

function M.new(p)
    p = p or {}
    return setmetatable({
        chance   = p.chance   or 100,
        pitchJit = p.pitchJit or 0,
        velJit   = p.velJit   or 0,
        octJit   = p.octJit   or 0,
        seed     = (p.seed or 0x2545F491) & 0xFFFFFFFF,
    }, M)
end

-- 32-bit LCG (Numerical Recipes constants). Returns 0..32767.
function M:rand()
    local s = (self.seed * 1664525 + 1013904223) & 0xFFFFFFFF
    self.seed = s
    return (s >> 16) & 0x7FFF
end

-- Symmetric jitter in [-amt, +amt].
local function jit(self, amt)
    if amt == 0 then return 0 end
    return (self:rand() % (2 * amt + 1)) - amt
end

function M:process(buf)
    local P, V = buf.pitch, buf.vel
    local w = 0
    for r = 1, buf.n do
        local play = self.chance >= 100 or (self:rand() % 100) < self.chance
        if play then
            w = w + 1
            local p = P[r] + jit(self, self.pitchJit) + 12 * jit(self, self.octJit)
            if p < 0 then p = 0 elseif p > 127 then p = 127 end
            local v = V[r] + jit(self, self.velJit)
            if v < 1 then v = 1 elseif v > 127 then v = 127 end
            P[w] = p; V[w] = v; buf.len[w] = buf.len[r]
        end
    end
    buf.n = w
end

return M
