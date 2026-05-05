-- dist/euclid_vsn1.lua (auto-generated; Euclidean VSN1 glue)
local R={}
local _hostReq = require
local _seq
local function require(n)
    local r = R[n]
    if r ~= nil then return r end
    if not _seq then _seq = _hostReq("euclid") end
    return _seq[n]
end
R["euclidean.vsn1_app"]=(function()

local Engine = require("euclidean.engine")
local M = {}
M.CTL = nil
function M.init(controls)
 M.CTL = controls
 controls.dirtyAll()
 return M
end
function M.onKey(idx, pressed)
 local CTL = M.CTL
 if idx == 8 then
 CTL.setShift(pressed)
 elseif pressed and idx >= 1 and idx <= 4 then
 CTL.onKey(idx)
 end
end
function M.onTurn(dir) M.CTL.onEndless(dir) end
function M.onClick() M.CTL.onEndlessClick() end
function M.onSmallBtn(sidx) M.CTL.onSmallBtn(sidx) end
function M.draw(scr) M.CTL.draw(scr) end
return M

end)()
return R["euclidean.vsn1_app"]
