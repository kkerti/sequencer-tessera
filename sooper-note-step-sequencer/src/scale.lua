-- scale.lua
-- Musical scale definitions + pitch quantization. Pure, zero allocation.
--
-- Each scale is a 12-bit mask: bit k = pitch class k (0..11) is a scale
-- tone. Index 1 is the "off" (chromatic) entry whose mask is 0 — no
-- quantization. Kept deliberately small: one integer per scale plus one
-- function. No per-pulse tables.
--
-- quantize(p, mask) snaps a MIDI pitch (0..127) to the nearest tone of the
-- given scale, octave-aware (crosses octave boundaries correctly, e.g. a
-- B snaps up to the next C rather than onto nothing). Returns p unchanged
-- when it is already on-scale, and always returns 0..127.

local M = {}

-- name, short (row display), 12-bit mask. Bits (LSB = pitch class 0 = C).
M.SCALES = {
    { name = "off",      short = "off",   mask = 0x000 },  -- 1: chromatic / no quantization
    { name = "maj",      short = "Maj",   mask = 0xAB5 },  -- 2: Ionian      {0,2,4,5,7,9,11}
    { name = "min",      short = "Min",   mask = 0x5AD },  -- 3: natural min {0,2,3,5,7,8,10}
    { name = "maj pent", short = "MajP",  mask = 0x295 },  -- 4: major pent  {0,2,4,7,9}
    { name = "min pent", short = "MinP",  mask = 0x4A9 },  -- 5: minor pent  {0,3,5,7,10}
}

function M.quantize(p, mask)
    if mask == 0 then return p end
    local pc = p % 12
    if (mask >> pc) & 1 == 1 then return p end
    local base = (p // 12) * 12
    for d = 1, 12 do
        local up = pc + d
        if up < 12 then
            if (mask >> up) & 1 == 1 then return base + up end
        else
            local u = up - 12
            if (mask >> u) & 1 == 1 then return base + 12 + u end
        end
        local dn = pc - d
        if dn >= 0 then
            if (mask >> dn) & 1 == 1 then return base + dn end
        else
            local dd = dn + 12
            if (mask >> dd) & 1 == 1 then
                local r = base - 12 + dd
                if r < 0 then return 0 end
                return r
            end
        end
    end
    return p
end

return M
