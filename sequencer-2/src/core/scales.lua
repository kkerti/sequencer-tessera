-- scales.lua — musical scale masks + pitch quantization. Pure, alloc-free.
--
-- Each scale is a 12-bit mask: bit k (0..11) set => pitch class k is in the
-- scale. Index 1 is "off" (mask 0) = no quantization. A key/root rotates the
-- mask; precompute the rotated mask once (see fx/scale.lua) and pass it here.
--
-- quantize(p, mask) snaps MIDI pitch 0..127 to the nearest in-mask tone,
-- octave-aware, tie -> down. Returns p unchanged if already on-scale.
-- Ported and extended from ../sequencer-1/src/scale.lua.

local M = {}

-- name, short (UI), 12-bit mask (LSB = pitch class 0 = C).
M.SCALES = {
    { name = "off",        short = "off",  mask = 0x000 }, -- 1 chromatic
    { name = "major",      short = "Maj",  mask = 0xAB5 }, -- {0,2,4,5,7,9,11}
    { name = "minor",      short = "Min",  mask = 0x5AD }, -- {0,2,3,5,7,8,10}
    { name = "harm min",   short = "HMin", mask = 0x9AD }, -- {0,2,3,5,7,8,11}
    { name = "dorian",     short = "Dor",  mask = 0x6AD }, -- {0,2,3,5,7,9,10}
    { name = "phrygian",   short = "Phr",  mask = 0x5AB }, -- {0,1,3,5,7,8,10}
    { name = "mixolydian", short = "Mix",  mask = 0x6B5 }, -- {0,2,4,5,7,9,10}
    { name = "min pent",   short = "MinP", mask = 0x4A9 }, -- {0,3,5,7,10}
}

-- Rotate a 12-bit mask up by `root` semitones (0..11). Precompute per key.
function M.rotate(mask, root)
    root = root % 12
    if root == 0 then return mask end
    return ((mask << root) | (mask >> (12 - root))) & 0xFFF
end

-- Move `d` scale DEGREES from `pitch` along the scale `mask` (d may be < 0).
-- With mask 0 (chromatic) a degree is a semitone. Result clamped 0..127.
-- Used by the pattern generator to place notes root ± spread degrees, in key.
function M.step(pitch, mask, d)
    if mask == 0 then
        local r = pitch + d
        if r < 0 then return 0 elseif r > 127 then return 127 else return r end
    end
    local p = M.quantize(pitch, mask)      -- ensure we start on a scale tone
    local dir = (d >= 0) and 1 or -1
    for _ = 1, (d >= 0 and d or -d) do
        local q = p + dir
        while q >= 0 and q <= 127 and ((mask >> (q % 12)) & 1) == 0 do q = q + dir end
        if q < 0 then return 0 elseif q > 127 then return 127 else p = q end
    end
    return p
end

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
