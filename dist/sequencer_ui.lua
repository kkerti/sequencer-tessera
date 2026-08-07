-- dist/sequencer_ui.lua (auto-generated; screen controls)
local R={}
local _hostReq = require
local _seq
local function require(n)
    local r = R[n]
    if r ~= nil then return r end
    if not _seq then _seq = _hostReq("sequencer") end
    return _seq[n]
end
R["controls"]=(function()

local Engine = require("engine")
local Step = require("step")
local M = {}
local MN = { "NOTE", "VEL", "GATE", "MUTE", "STEP", "LAST" }
local SWING_PCT = { "50", "58", "67", "75" }
local DUR_LADDER = { 6, 12, 24, 36, 48, 72 }
local function durIndex(v)
 local best, bestd = 1, math.huge
 for i = 1, #DUR_LADDER do
 local d = math.abs(DUR_LADDER[i] - v)
 if d < bestd then bestd = d; best = i end
 end
 return best
end
M.MODE_NOTE = 1
M.MODE_VEL = 2
M.MODE_GATE = 3
M.MODE_MUTE = 4
M.MODE_STEP = 5
M.MODE_LASTSTEP = 6
M.MODES = MN
M.selT, M.selS, M.viewport, M.focus, M.shift = 1, 1, 1, 1, false
M.arm = nil
M.random = false
local function vplo(v) return (v - 1) * 16 + 1 end
M.viewportLo = vplo
local dirty = true
local SWING_DETENTS = 4
local swingAccum = 0
local function bumpDur(t, s, d)
 local cur = Step.dur(Engine.tracks[t].steps[s])
 local idx = durIndex(cur) + d
 if idx < 1 then idx = 1 elseif idx > #DUR_LADDER then idx = #DUR_LADDER end
 Engine.setStepParam(t, s, "dur", DUR_LADDER[idx])
end
local function setParam(i, t, s, d)
 local stp = Engine.tracks[t].steps[s]
 if i == 1 then
 Engine.setStepParam(t, s, "pitch", Step.pitch(stp) + d)
 elseif i == 2 then
 Engine.setStepParam(t, s, "vel", Step.vel(stp) + d)
 elseif i == 3 then
 if M.shift then
 bumpDur(t, s, d)
 else
 Engine.setStepParam(t, s, "gate", Step.gate(stp) + d)
 end
 elseif i == 4 then
 Engine.setStepParam(t, s, "mute", Step.muted(stp) and 0 or 1)
 end
 dirty = true
end
M.setParam = setParam
local function dAll() dirty = true end
M.dirtyAll = dAll
M.dirtyValueCells = dAll
function M.setSelectedTrack(t)
 if t < 1 or t > #Engine.tracks or t == M.selT then return end
 M.selT = t; dirty = true
end
function M.setSelectedStep(s)
 if s < 1 or s > Engine.tracks[M.selT].cap or s == M.selS then return end
 M.selS = s
 M.viewport = ((s - 1) // 16) + 1
 dirty = true
end
function M.setViewport(v)
 if v < 1 or v > 4 or v == M.viewport then return end
 M.viewport = v
 local lo = vplo(v)
 if M.selS < lo or M.selS > lo + 15 then M.selS = lo end
 dirty = true
end
function M.onEndless(dir)
 local f = M.focus
 if f == M.MODE_LASTSTEP then
 if M.shift then
 swingAccum = swingAccum + dir
 local step = 0
 if swingAccum >= SWING_DETENTS then
 step = swingAccum // SWING_DETENTS
 elseif swingAccum <= -SWING_DETENTS then
 step = -((-swingAccum) // SWING_DETENTS)
 end
 if step ~= 0 then
 Engine.setSwing(Engine.swing + step)
 swingAccum = swingAccum - step * SWING_DETENTS
 end
 else
 local tr = Engine.tracks[M.selT]
 Engine.setLastStep(M.selT, tr.lastStep + dir)
 end
 elseif f == M.MODE_STEP then
 M.setSelectedStep(M.selS + dir)
 elseif f == M.MODE_NOTE and M.shift then
 local nxt = Engine.tracks[M.selT].scale + dir
 if nxt < 1 then nxt = #Engine.scales elseif nxt > #Engine.scales then nxt = 1 end
 Engine.setTrackScale(M.selT, nxt)
 elseif f >= M.MODE_NOTE and f <= M.MODE_MUTE then
 setParam(f, M.selT, M.selS, dir)
 end
 dirty = true
end
function M.onEndlessClick()
 local f = M.focus
 if f == M.MODE_LASTSTEP then
 if M.shift then
 Engine.setSwing(0)
 swingAccum = 0
 dirty = true
 end
 return
 end
 local stp = Engine.tracks[M.selT].steps[M.selS]
 Engine.setStepParam(M.selT, M.selS, "mute", Step.muted(stp) and 0 or 1)
 dirty = true
end
function M.onKey(idx)
 if idx < 1 or idx > #MN or idx == M.focus then return end
 M.focus = idx; swingAccum = 0; dirty = true
end
function M.setShift(b)
 b = b and true or false
 if b == M.shift then return end
 M.shift = b
 M.arm = nil
 swingAccum = 0
 dirty = true
end
function M.setArm(v)
 if v == "load" or v == "save" then
 if v == M.arm then return end
 M.arm = v
 else
 if M.arm == nil then return end
 M.arm = nil
 end
 dirty = true
end
function M.setRandom(b)
 b = b and true or false
 if b == M.random then return end
 M.random = b
 dirty = true
end
local rngSeeded = false
local function seedRng()
 if rngSeeded then return end
 rngSeeded = true
 if os and os.time then math.randomseed(os.time()) end
end
function M.randomizeParam(i)
 seedRng()
 local tr = Engine.tracks[M.selT]
 local lastStep = tr.lastStep
 for s = 1, lastStep do
 local stp = tr.steps[s]
 if i == M.MODE_NOTE then
 Engine.setStepParam(M.selT, s, "pitch", math.random(0, 127))
 elseif i == M.MODE_VEL then
 Engine.setStepParam(M.selT, s, "vel", math.random(0, 127))
 elseif i == M.MODE_GATE then
 if M.shift then
 Engine.setStepParam(M.selT, s, "dur", DUR_LADDER[math.random(#DUR_LADDER)])
 else
 local d = Step.dur(stp)
 Engine.setStepParam(M.selT, s, "gate", (d >= 1) and math.random(1, d) or 0)
 end
 elseif i == M.MODE_MUTE then
 Engine.setStepParam(M.selT, s, "mute", math.random(0, 1))
 end
 end
 dirty = true
end
function M.onSmallBtn(idx)
 if idx < 1 or idx > 4 then return end
 if M.shift then M.setSelectedTrack(idx) else M.setViewport(idx) end
end
local C_BG = { 18, 18, 20 }
local C_FG = { 240, 240, 240 }
local C_DIM = { 110, 110, 115 }
local C_LINE = { 60, 60, 65 }
local C_OOR = { 35, 35, 40 }
local C_HI = { 60, 60, 65 }
local C_HIFG = { 255, 255, 255 }
local C_WELL = { 55, 55, 58 }
local C_BAR = { 220, 220, 225 }
local C_MUTE = { 160, 30, 30 }
local C_SHIFT = { 255, 140, 20 }
local C_TRACK = {
 { 60, 130, 255 },
 { 255, 140, 20 },
 { 60, 200, 90 },
 { 180, 80, 220 },
}
local ROW_H = 22
local PARAMS = 4
local LS_Y = ROW_H * (1 + PARAMS) + 2
local LS_H = ROW_H
local STR_Y = LS_Y + LS_H + 4
local FOOT_H = ROW_H
local FOOT_Y = 240 - FOOT_H
local SLOT_W = 320 / 4
local STR_H = FOOT_Y - STR_Y - 1
local COL_W = 20
function M.draw(scr)
 if not dirty then return end
 dirty = false
 local tr = Engine.tracks[M.selT]
 local stp = tr.steps[M.selS]
 local f = M.focus
 local sh = M.shift
 scr:draw_rectangle_filled(0, 0, 319, 239, C_BG)
 local sw = Engine.swing
 local showSwHere = sh
 local swSuffix = (sw > 0 and not showSwHere) and " sw" or ""
 local tcol = C_TRACK[M.selT] or C_FG
 scr:draw_rectangle_filled(2, 2, 38, 20, tcol)
 scr:draw_text_fast("T" .. M.selT, 8, 4, 16, C_HIFG)
 scr:draw_text_fast(
 "S" .. M.selS .. " V" .. M.viewport .. swSuffix,
 56, 4, 16, C_FG)
 if sh then
 scr:draw_text_fast("SHIFT", 232, 4, 16, C_SHIFT)
 end
 local armTxt = (M.arm == "load") and "LOAD" or ((M.arm == "save") and "SAVE" or nil)
 if armTxt then
 scr:draw_text_fast(armTxt, 232, 4, 16, C_SHIFT)
 end
 if M.random then
 scr:draw_text_fast("RNDM", 272, 4, 16, C_SHIFT)
 end
 for i = 1, PARAMS do
 local y = ROW_H * i
 local active = (i == f)
 if active then
 scr:draw_rectangle_filled(0, y, 319, y + ROW_H - 1, C_HI)
 end
 local fg = active and C_HIFG or C_DIM
 local txt
 if i == M.MODE_NOTE then
 txt = "note " .. Step.pitch(stp) .. " " .. Step.noteName(Step.pitch(stp))
 .. " " .. Engine.scales[tr.scale].short
 elseif i == M.MODE_VEL then
 txt = "vel " .. Step.vel(stp)
 elseif i == M.MODE_GATE then
 if sh then
 txt = "dur " .. Step.dur(stp)
 else
 txt = "gate " .. Step.gate(stp)
 end
 elseif i == M.MODE_MUTE then
 txt = Step.muted(stp) and "mute MUTED" or "mute audible"
 end
 scr:draw_text_fast(txt, 6, y + 4, 16, fg)
 end
 scr:draw_rectangle_filled(0, LS_Y - 2, 319, LS_Y - 1, C_LINE)
 local lsActive = (f == M.MODE_LASTSTEP)
 if lsActive then
 scr:draw_rectangle_filled(0, LS_Y, 319, LS_Y + LS_H - 1, C_HI)
 end
 local lsTxt
 if sh then
 lsTxt = "swing " .. SWING_PCT[sw + 1] .. "%"
 else
 lsTxt = "last " .. tr.lastStep
 end
 scr:draw_text_fast(lsTxt, 6, LS_Y + 4, 16,
 lsActive and C_HIFG or C_DIM)
 local lo = vplo(M.viewport)
 local heat = (f == M.MODE_NOTE or f == M.MODE_VEL or f == M.MODE_GATE)
 local y0, y1 = STR_Y, STR_Y + STR_H - 1
 for c = 1, 16 do
 local s = lo + c - 1
 local x0 = (c - 1) * COL_W + 1
 local x1 = x0 + COL_W - 3
 local cs = tr.steps[s]
 local oor = (s > tr.lastStep)
 local mut = Step.muted(cs)
 local wellC
 if oor then wellC = C_OOR
 elseif mut then wellC = C_MUTE
 else wellC = C_WELL end
 scr:draw_rectangle_filled(x0, y0, x1, y1, wellC)
 if heat and not oor and not mut then
 local v
 if f == M.MODE_NOTE then v = Step.pitch(cs)
 elseif f == M.MODE_VEL then v = Step.vel(cs)
 else v = sh and Step.dur(cs) or Step.gate(cs) end
 local bh = (STR_H * v) // 127
 if v > 0 then
 if bh < 1 then bh = 1 end
 scr:draw_rectangle_filled(x0, y1 - bh + 1, x1, y1, C_BAR)
 end
 end
 if s == M.selS then
 scr:draw_rectangle(x0, y0, x1, y1, C_BAR)
 end
 end
 scr:draw_rectangle_filled(0, FOOT_Y - 2, 319, FOOT_Y - 1, C_LINE)
 local labels
 if sh then
 labels = { "T1", "T2", "T3", "T4" }
 else
 labels = { "V1", "V2", "LOAD", "SAVE" }
 end
 for i = 1, 4 do
 scr:draw_text_fast(labels[i], (i - 1) * SLOT_W + 6, FOOT_Y + 4, 16, C_DIM)
 end
 scr:draw_swap()
end
return M

end)()
return {
    screen = R.controls,
}
