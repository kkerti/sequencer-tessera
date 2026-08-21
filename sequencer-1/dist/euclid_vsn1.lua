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
M.clockMode = "external"
M.bpm = 120
M.playing = false
local NOOP = function() end
M._bpmCb = NOOP
M._transportCb = NOOP
local function bpmToMs(b)
 if b < 30 then b = 30 elseif b > 240 then b = 240 end
 return 60000 // (b * 24)
end
M._bpmToMs = bpmToMs
function M.init(controls)
 M.CTL = controls
 if controls.setApp then controls.setApp(M) end
 controls.dirtyAll()
 return M
end
function M.setClockMode(mode)
 if mode ~= "internal" and mode ~= "external" then return end
 M.clockMode = mode
 if M.CTL then M.CTL.dirtyAll() end
end
function M.setBpmCallback(fn) M._bpmCb = fn or NOOP end
function M.setTransportCallback(fn) M._transportCb = fn or NOOP end
function M.getBpm() return M.bpm end
function M.setBpm(b)
 if b < 30 then b = 30 elseif b > 240 then b = 240 end
 if b == M.bpm then return end
 M.bpm = b
 if M.CTL then M.CTL.dirtyAll() end
 M._bpmCb(bpmToMs(b))
end
function M.toggleTransport()
 if M.clockMode ~= "internal" then return end
 if M.playing then
 M.playing = false
 M._transportCb(false)
 Engine.onStop()
 else
 M.playing = true
 Engine.onStart()
 M._transportCb(true)
 end
 if M.CTL then M.CTL.dirtyAll() end
end
function M.onKey(idx, pressed)
 local CTL = M.CTL
 if idx == 8 then
 CTL.setShift(pressed)
 return
 end
 if not pressed then return end
 if idx >= 1 and idx <= 5 then
 CTL.onKey(idx)
 elseif idx == 6 then
 if M.clockMode == "internal" then CTL.onKey(idx) end
 elseif idx == 7 then
 if M.clockMode == "internal" then M.toggleTransport() end
 end
end
function M.onTurn(dir) M.CTL.onEndless(dir) end
function M.onClick() M.CTL.onEndlessClick() end
function M.onSmallBtn(sidx) M.CTL.onSmallBtn(sidx) end
function M.draw(scr) M.CTL.draw(scr) end
return M

end)()
return R["euclidean.vsn1_app"]
