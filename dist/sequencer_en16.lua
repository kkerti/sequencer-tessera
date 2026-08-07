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
M.MODE_NOTE = 1
M.MODE_VEL = 2
M.MODE_GATE = 3
M.MODE_MUTE = 4
M.MODE_LASTSTEP = 5
M.PAL = {
 { 60, 130, 255 },
 { 255, 140, 20 },
 { 60, 200, 90 },
 { 180, 80, 220 },
}
M.mu = 0
M.focus = 1
M.sel = 1
M.cap = 16
M.tr = 1
M.ph = 0
M.vals = {}
for i = 1, 16 do M.vals[i] = 0 end
M.LAST = {}
for i = 1, 16 do M.LAST[i] = -1 end
M.dirty = true
function M.U(mu, f, sel, cap, tr, v1,v2,v3,v4,v5,v6,v7,v8,v9,v10,v11,v12,v13,v14,v15,v16)
 M.mu, M.focus, M.sel, M.cap, M.tr = mu, f, sel, cap, tr
 local V = M.vals
 V[1]=v1 or 0; V[2]=v2 or 0; V[3]=v3 or 0; V[4]=v4 or 0
 V[5]=v5 or 0; V[6]=v6 or 0; V[7]=v7 or 0; V[8]=v8 or 0
 V[9]=v9 or 0; V[10]=v10 or 0; V[11]=v11 or 0; V[12]=v12 or 0
 V[13]=v13 or 0; V[14]=v14 or 0; V[15]=v15 or 0; V[16]=v16 or 0
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
 local LAST, V = M.LAST, M.vals
 local heat = (f == M.MODE_NOTE or f == M.MODE_VEL or f == M.MODE_GATE)
 local pal = M.PAL[M.tr] or M.PAL[1]
 local pr, pg, pb = pal[1], pal[2], pal[3]
 local FLOOR = 14
 local LIFT = M._LIFT
 for i = 1, 16 do
 local r, g, b
 if i > cap then
 r, g, b = 0, 0, 0
 elseif (mu >> (i - 1)) & 1 == 1 then
 if i == ph then
 r, g, b = 255, 255, 255
 elseif i == sel then
 r, g, b = 255, 80, 80
 else
 r, g, b = 120, 0, 0
 end
 elseif i == ph then
 r, g, b = 255, 255, 255
 elseif i == sel then
 r, g, b = 255, 255, 255
 elseif heat then
 local v = V[i] or 0
 if v < 0 then v = 0 elseif v > 127 then v = 127 end
 local lifted = LIFT[v + 1]
 local k = FLOOR + ((255 - FLOOR) * lifted) // 255
 r = (pr * k) // 255
 g = (pg * k) // 255
 b = (pb * k) // 255
 else
 r = (pr * FLOOR) // 255
 g = (pg * FLOOR) // 255
 b = (pb * FLOOR) // 255
 end
 local packed = (r << 16) | (g << 8) | b
 if LAST[i] ~= packed then
 LAST[i] = packed
 emit(i - 1, r, g, b)
 end
 end
end
M._LIFT = {}
do
 local L = M._LIFT
 for v = 0, 127 do
 local t = v / 127
 local lifted = t ^ 0.5
 L[v + 1] = (lifted * 255) // 1
 end
end
return M

end)()
return R.controls_en16
