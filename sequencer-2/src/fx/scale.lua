-- fx/scale.lua — SCALE: quantize pitch to a key.
--
--   scaleIndex : index into scales.SCALES (1 = off / chromatic).
--   root       : key, 0..11 (0 = C). Rotates the scale mask.
--
-- The rotated mask is precomputed whenever scale/root change (setScale/setRoot)
-- so the per-note hot path is a single scales.quantize() call, allocation-free.

local Scales = require("scales")

local M = {}
M.__index = M

function M.new(p)
    p = p or {}
    local self = setmetatable({
        scaleIndex = p.scaleIndex or 1,
        root       = p.root or 0,
        mask       = 0,
    }, M)
    self:recompute()
    return self
end

function M:recompute()
    local base = (Scales.SCALES[self.scaleIndex] or Scales.SCALES[1]).mask
    self.mask = Scales.rotate(base, self.root)
end

function M:setScale(i) self.scaleIndex = i; self:recompute() end
function M:setRoot(r)  self.root = r % 12; self:recompute() end

function M:process(buf)
    if self.mask == 0 then return end
    local P = buf.pitch
    for i = 1, buf.n do
        P[i] = Scales.quantize(P[i], self.mask)
    end
end

return M
