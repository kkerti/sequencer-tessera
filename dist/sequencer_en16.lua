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
M.SH = {}
for i = 1, 16 do M.SH[i] = 0 end
M.focus = 1
M.lastStep = 16
M.selR = 1
M.shift = 0
M.ph = 0
local MR = { 30, 255, 240, 220, 60, 70, 230 }
local MG = { 200, 140, 210, 50, 120, 70, 230 }
local MB = { 220, 30, 40, 50, 255, 75, 230 }
M.MR, M.MG, M.MB = MR, MG, MB
M.LAST = {}
for i = 1, 16 do M.LAST[i] = -1 end
M.dirty = true
local function muted(p) return ((p >> 29) & 1) == 1 end
function M.S(i, p)
 if i >= 1 and i <= 16 then
 M.SH[i] = p
 M.dirty = true
 end
end
function M.V(p1,p2,p3,p4,p5,p6,p7,p8,p9,p10,p11,p12,p13,p14,p15,p16)
 M.SH[1]=p1 M.SH[2]=p2 M.SH[3]=p3 M.SH[4]=p4
 M.SH[5]=p5 M.SH[6]=p6 M.SH[7]=p7 M.SH[8]=p8
 M.SH[9]=p9 M.SH[10]=p10 M.SH[11]=p11 M.SH[12]=p12
 M.SH[13]=p13 M.SH[14]=p14 M.SH[15]=p15 M.SH[16]=p16
 M.dirty = true
end
function M.M(f, L, sR, sh)
 M.focus = f
 M.lastStep = L
 M.selR = sR
 M.shift = sh
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
 local f, ls = M.focus, M.lastStep
 local mr, mg, mb = MR[f], MG[f], MB[f]
 local SH, LAST = M.SH, M.LAST
 local ph = M.ph
 local sel = M.selR
 local cap = (ls < 16) and ls or 16
 for i = 1, 16 do
 local r, g, b
 if i > cap then
 r, g, b = 0, 0, 0
 elseif i == ph then
 r, g, b = 255, 255, 255
 elseif i == sel then
 r, g, b = mr, mg, mb
 elseif muted(SH[i]) then
 r, g, b = 60, 0, 0
 else
 r = (mr * 80) >> 8
 g = (mg * 80) >> 8
 b = (mb * 80) >> 8
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
