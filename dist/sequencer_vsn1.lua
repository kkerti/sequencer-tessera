-- dist/sequencer_vsn1.lua (auto-generated; VSN1 handler glue)
local R={}
local _hostReq = require
local _seq
local function require(n)
    local r = R[n]
    if r ~= nil then return r end
    if not _seq then _seq = _hostReq("sequencer") end
    return _seq[n]
end
R["vsn1_app"]=(function()

local Engine = require("engine")
local Step = require("step")
local Persist = require("persist")
local M = {}
M.SAVE_PATH = "sequencer_data.lua"
M.CTL = nil
M.lastPh = -1
local SBUF = {}
function M.init(controls)
 M.CTL = controls
 controls.dirtyAll()
 return M
end
local function valueFor(stp, f, shift)
 if f == 2 then return Step.pitch(stp) end
 if f == 3 then return Step.vel(stp) end
 if f == 4 then
 if shift then return Step.dur(stp) end
 return Step.gate(stp)
 end
 return 0
end
function M.pushEN16()
 local CTL = M.CTL; if not CTL then return end
 local lo = (CTL.viewport - 1) * 16 + 1
 local tr = Engine.tracks[CTL.selT]
 local s = tr.steps
 local f = CTL.focus
 local sh = CTL.shift
 local mu = 0
 for i = 1, 16 do
 if Step.muted(s[lo + i - 1]) then mu = mu | (1 << (i - 1)) end
 end
 local sel = CTL.selS - lo + 1
 if sel < 1 or sel > 16 then sel = 0 end
 local cap = tr.lastStep - lo + 1
 if cap > 16 then cap = 16 elseif cap < 0 then cap = 0 end
 SBUF[1] = "EN16.U("
 SBUF[2] = mu
 SBUF[3] = ","
 SBUF[4] = f
 SBUF[5] = ","
 SBUF[6] = sel
 SBUF[7] = ","
 SBUF[8] = cap
 SBUF[9] = ","
 SBUF[10] = CTL.selT
 local n = 10
 for i = 0, 15 do
 n = n + 1; SBUF[n] = ","
 n = n + 1; SBUF[n] = valueFor(s[lo + i], f, sh)
 end
 n = n + 1; SBUF[n] = ");paint()"
 immediate_send(1, 0, table.concat(SBUF, "", 1, n))
end
function M.pushPlayhead()
 local CTL = M.CTL; if not CTL then return end
 local pos = Engine.tracks[CTL.selT].pos
 local lo = (CTL.viewport - 1) * 16 + 1
 local slot
 if pos == 0 then
 slot = 0
 else
 local r = pos - lo + 1
 slot = (r >= 1 and r <= 16) and r or 0
 end
 if slot ~= M.lastPh then
 M.lastPh = slot
 immediate_send(1, 0, "EN16.H(" .. slot .. ");paint()")
 end
end
function M.onKey(idx, pressed)
 local CTL = M.CTL
 if idx == 8 then
 CTL.setShift(pressed)
 M.pushEN16()
 elseif pressed and idx >= 1 and idx <= 6 then
 CTL.onKey(idx)
 M.pushEN16()
 elseif pressed and idx == 7 then
 if CTL.shift then
 Persist.save(M.SAVE_PATH)
 else
 if Persist.load(M.SAVE_PATH) then
 CTL.dirtyAll()
 M.pushEN16()
 end
 end
 end
end
function M.onTurn(dir)
 M.CTL.onEndless(dir)
 M.pushEN16()
end
function M.onClick()
 M.CTL.onEndlessClick()
 M.pushEN16()
end
function M.onSmallBtn(sidx)
 M.CTL.onSmallBtn(sidx)
 M.lastPh = -1
 M.pushEN16()
end
function M.fromEN16Turn(i, d)
 local CTL = M.CTL
 if i < 1 or i > 16 then return end
 local f = CTL.focus
 if f == CTL.MODE_STEP or f == CTL.MODE_LASTSTEP then return end
 local s = (CTL.viewport - 1) * 16 + i
 if s > Engine.tracks[CTL.selT].lastStep then return end
 CTL.setSelectedStep(s)
 CTL.setParam(f, CTL.selT, s, d)
 M.pushEN16()
end
function M.fromEN16Press(i)
 local CTL = M.CTL
 if i < 1 or i > 16 then return end
 local s = (CTL.viewport - 1) * 16 + i
 if CTL.shift then
 CTL.setSelectedStep(s)
 elseif CTL.focus == CTL.MODE_LASTSTEP then
 Engine.setLastStep(CTL.selT, s)
 CTL.dirtyAll()
 else
 local stp = Engine.tracks[CTL.selT].steps[s]
 Engine.setStepParam(CTL.selT, s, "mute",
 Step.muted(stp) and 0 or 1)
 CTL.dirtyAll()
 end
 M.pushEN16()
end
return M

end)()
return R.vsn1_app
