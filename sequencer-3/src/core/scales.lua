-- scales.lua — 12-TET scale masks + pitch quantization. Pure, alloc-free.
--
-- Each scale is a 12-bit mask: bit k (0..11) set => pitch class k is in the
-- scale. Mask 0 means "off" (no quantization). A root rotates the mask;
-- `setScale` stores the rotated form so the pulse path can quantize directly.
--
-- quantize(p, mask) snaps a MIDI pitch 0..127 to the nearest in-mask tone,
-- octave-aware, tie -> down. On-scale pitches pass through unchanged.

local M = {}

-- Common masks (LSB = pitch class 0 = C), for presets and hand edits; no
-- table of them ships, nothing on the device reads one:
--   off 0x000 · major 0xAB5 · minor 0x5AD · harm min 0x9AD · dorian 0x6AD
--   phrygian 0x5AB · mixolydian 0x6B5 · min pent 0x4A9

M.MAJOR = 0xAB5
M.MINOR = 0x5AD

-- Rotate a 12-bit mask up by `root` semitones (0..11). Precompute per key.
function M.rotate(mask, root)
    root = (root or 0) % 12
    if root == 0 then return mask & 0xFFF end
    return ((mask << root) | (mask >> (12 - root))) & 0xFFF
end

function M.quantize(p, mask)
    if mask == 0 then return p end
    local pc = p % 12
    if (mask >> pc) & 1 == 1 then return p end
    local base = (p // 12) * 12
    for d = 1, 12 do
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
        local up = pc + d
        if up < 12 then
            if (mask >> up) & 1 == 1 then return base + up end
        else
            local u = up - 12
            if (mask >> u) & 1 == 1 then return base + 12 + u end
        end
    end
    return p
end

return M
