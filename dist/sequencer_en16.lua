-- dist/sequencer_en16.lua (auto-generated; EN16 satellite)
local R={}
local _hostReq = require
local _seq
local function require(n)
    local r = R[n]
    if r ~= nil then return r end
    if not _seq then _seq = _hostReq("sequencer") end
    return _seq[n]
end
R["controls_en16"]=(function()

local M = {}
M.NUM_ENC = 16
M.mu = 0
M.focus = 1
M.sel = 1
M.cap = 16
M.ph = 0
local MR = { 30, 255, 240, 220, 60, 70, 230 }
local MG = { 200, 140, 210, 50, 120, 70, 230 }
local MB = { 220, 30, 40, 50, 255, 75, 230 }
M.MR, M.MG, M.MB = MR, MG, MB
M.LAST = {}
for i = 1, 16 do M.LAST[i] = -1 end
M.dirty = true
function M.U(mu, f, sel, cap)
 M.mu, M.focus, M.sel, M.cap = mu, f, sel, cap
 M.dirty = true
end
function M.H(slot)
 if slot ~= M.ph then
 M.ph = slot
 M.dirty = true
 end
end
function M.invalidateAll()
 for i = 1, 16 do M.LAST[i] = -1 end
 M.dirty = true
end
function M.refresh(emit)
 if not M.dirty then return end
 M.dirty = false
 local f, cap, sel, ph, mu = M.focus, M.cap, M.sel, M.ph, M.mu
 local mr, mg, mb = MR[f], MG[f], MB[f]
 local LAST = M.LAST
 local dr = (mr * 80) >> 8
 local dg = (mg * 80) >> 8
 local db = (mb * 80) >> 8
 for i = 1, 16 do
 local r, g, b
 if i > cap then
 r, g, b = 0, 0, 0
 elseif i == ph then
 r, g, b = 255, 255, 255
 elseif i == sel then
 r, g, b = mr, mg, mb
 elseif (mu >> (i - 1)) & 1 == 1 then
 r, g, b = 60, 0, 0
 else
 r, g, b = dr, dg, db
 end
 local packed = (r << 16) | (g << 8) | b
 if LAST[i] ~= packed then
 LAST[i] = packed
 emit(i - 1, r, g, b)
 end
 end
end
return M

end)()
return R.controls_en16
