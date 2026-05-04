-- dist/sequencer_ui.lua (auto-generated; Controls layer)
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
local MODES = {
 { name="NOTE", r= 30, g=200, b=220 },
 { name="VEL", r=255, g=140, b= 30 },
 { name="GATE", r=240, g=210, b= 40 },
 { name="MUTE", r=220, g= 50, b= 50 },
 { name="STEP", r= 60, g=120, b=255 },
 { name="--", r= 70, g= 70, b= 75 },
 { name="LASTSTEP", r=230, g=230, b=230 },
}
M.MODES = MODES
M.MODE_NOTE = 1
M.MODE_VEL = 2
M.MODE_GATE = 3
M.MODE_MUTE = 4
M.MODE_STEP = 5
M.MODE_LASTSTEP = 7
function M.modeColor(i)
 local m = MODES[i] or MODES[1]
 return m.r, m.g, m.b
end
M.selT = 1
M.selS = 1
M.viewport = 1
M.focus = 1
M.shift = false
local function viewportLo(v) return (v - 1) * 16 + 1 end
M.viewportLo = viewportLo
local function setParam(i, t, s, d)
 local stp = Engine.tracks[t].steps[s]
 if i == M.MODE_NOTE then
 Engine.setStepParam(t, s, "pitch", Step.pitch(stp) + d)
 elseif i == M.MODE_VEL then
 Engine.setStepParam(t, s, "vel", Step.vel(stp) + d)
 elseif i == M.MODE_GATE then
 if M.shift then
 Engine.setStepParam(t, s, "dur", Step.dur(stp) + d)
 else
 Engine.setStepParam(t, s, "gate", Step.gate(stp) + d)
 end
 elseif i == M.MODE_MUTE then
 Engine.setStepParam(t, s, "mute", Step.muted(stp) and 0 or 1)
 end
end
M.setParam = setParam
local needsFullRepaint = true
local lastPhCol = -1
local function dirtyAll()
 needsFullRepaint = true
 lastPhCol = -1
end
M.dirtyAll = dirtyAll
function M.dirtyValueCells()
 needsFullRepaint = true
end
function M.setSelectedTrack(t)
 if t < 1 or t > #Engine.tracks then return end
 if t == M.selT then return end
 M.selT = t
 dirtyAll()
end
function M.setSelectedStep(s)
 if s < 1 or s > Engine.tracks[M.selT].cap then return end
 if s == M.selS then return end
 M.selS = s
 local v = ((s - 1) // 16) + 1
 if v ~= M.viewport then M.viewport = v end
 needsFullRepaint = true
end
function M.setViewport(v)
 if v < 1 or v > 4 then return end
 if v == M.viewport then return end
 M.viewport = v
 local lo = viewportLo(v)
 if M.selS < lo or M.selS > lo + 15 then M.selS = lo end
 dirtyAll()
end
function M.onEndless(dir)
 local f = M.focus
 if f == M.MODE_LASTSTEP then
 local tr = Engine.tracks[M.selT]
 Engine.setLastStep(M.selT, tr.lastStep + dir)
 needsFullRepaint = true
 elseif f == M.MODE_STEP then
 local tr = Engine.tracks[M.selT]
 local s = M.selS + dir
 if s < 1 then s = tr.lastStep end
 if s > tr.lastStep then s = 1 end
 M.setSelectedStep(s)
 elseif f == M.MODE_NOTE or f == M.MODE_VEL
 or f == M.MODE_GATE or f == M.MODE_MUTE then
 setParam(f, M.selT, M.selS, dir)
 needsFullRepaint = true
 end
end
function M.onEndlessClick()
 local f = M.focus
 if f == M.MODE_LASTSTEP or f == M.MODE_STEP then return end
 if f == M.MODE_MUTE and M.shift then
 local stp = Engine.tracks[M.selT].steps[M.selS]
 Engine.setStepParam(M.selT, M.selS, "ratch",
 Step.ratch(stp) and 0 or 1)
 else
 local stp = Engine.tracks[M.selT].steps[M.selS]
 Engine.setStepParam(M.selT, M.selS, "mute",
 Step.muted(stp) and 0 or 1)
 end
 needsFullRepaint = true
end
function M.onKey(idx)
 if idx < 1 or idx > 7 then return end
 if idx == 6 then return end
 if idx == M.focus then return end
 M.focus = idx
 dirtyAll()
end
function M.setShift(b)
 if b == M.shift then return end
 M.shift = b and true or false
end
function M.onSmallBtn(idx)
 if idx < 1 or idx > 4 then return end
 if M.shift then
 M.setSelectedTrack(idx)
 else
 M.setViewport(idx)
 end
end
local C_BG = { 18, 18, 20 }
local C_TEXT = { 240, 240, 240 }
local C_DIM = { 110, 110, 115 }
local C_GUIDE = { 60, 60, 65 }
local C_OOR = { 45, 45, 50 }
local C_PLAYHEAD = { 40, 90, 160 }
local HDR_H = 22
local PARAM_Y = 30
local PARAM_H = 20
local PARAMS_N = 5
local LS_Y = PARAM_Y + PARAMS_N * PARAM_H + 2
local LS_H = 18
local CTX_Y = LS_Y + LS_H + 4
local CTX_H = 240 - CTX_Y - 1
local COL_W = 20
local PARAM_LABELS = { "pitch", "vel", "gate", "mute", "step" }
local function modeRGB(i) return { M.modeColor(i) } end
local function drawHeader(scr)
 local stp = Engine.tracks[M.selT].steps[M.selS]
 scr:draw_rectangle_filled(0, 0, 319, HDR_H - 1, C_BG)
 local left = "T" .. M.selT
 .. " S" .. string.format("%02d", M.selS)
 .. " V" .. M.viewport
 scr:draw_text_fast(left, 4, 4, 14, C_TEXT)
 scr:draw_text_fast(MODES[M.focus].name, 130, 4, 14, modeRGB(M.focus))
 local p = Step.pitch(stp)
 scr:draw_text_fast(Step.noteName(p) .. " (" .. p .. ")",
 210, 4, 14, C_TEXT)
 scr:draw_rectangle_filled(0, HDR_H, 319, HDR_H, C_GUIDE)
end
local function drawParamRow(scr, i)
 local stp = Engine.tracks[M.selT].steps[M.selS]
 local y = PARAM_Y + (i - 1) * PARAM_H
 local active = (i == M.focus)
 local mc = MODES[i]
 local bg = active and { mc.r, mc.g, mc.b } or C_BG
 scr:draw_rectangle_filled(0, y, 319, y + PARAM_H - 1, bg)
 local fg = active and C_TEXT or C_DIM
 scr:draw_text_fast(PARAM_LABELS[i], 4, y + 4, 12, fg)
 local val, max, glyph
 if i == M.MODE_NOTE then
 val, max = Step.pitch(stp), 127
 elseif i == M.MODE_VEL then
 val, max = Step.vel(stp), 127
 elseif i == M.MODE_GATE then
 if M.shift then
 val, max = Step.dur(stp), 127
 glyph = nil
 scr:draw_text_fast("dur", 4, y + 4, 12, fg)
 else
 val, max = Step.gate(stp), 127
 end
 elseif i == M.MODE_MUTE then
 glyph = Step.muted(stp) and "MUTED" or "audible"
 if Step.ratch(stp) then glyph = glyph .. " R" end
 elseif i == M.MODE_STEP then
 val, max = M.selS, Engine.tracks[M.selT].lastStep
 end
 if glyph then
 scr:draw_text_fast(glyph, 80, y + 4, 12, fg)
 elseif val then
 scr:draw_text_fast(tostring(val), 80, y + 4, 12, fg)
 local bx, bw = 130, 180
 scr:draw_rectangle(bx, y + 4, bx + bw - 1, y + PARAM_H - 6,
 active and C_TEXT or C_GUIDE)
 local fw = (val * (bw - 2)) // (max > 0 and max or 1)
 if fw > 0 then
 scr:draw_rectangle_filled(bx + 1, y + 5,
 bx + 1 + fw - 1, y + PARAM_H - 7,
 active and C_TEXT or C_DIM)
 end
 end
end
local function drawLastStepRow(scr)
 local tr = Engine.tracks[M.selT]
 local active = (M.focus == M.MODE_LASTSTEP)
 local mc = MODES[M.MODE_LASTSTEP]
 local bg = active and { mc.r, mc.g, mc.b } or C_BG
 scr:draw_rectangle_filled(0, LS_Y, 319, LS_Y + LS_H - 1, bg)
 scr:draw_rectangle_filled(0, LS_Y - 2, 319, LS_Y - 1, C_GUIDE)
 local fg = active and C_TEXT or C_DIM
 scr:draw_text_fast("lastStep", 4, LS_Y + 3, 12, fg)
 scr:draw_text_fast(tostring(tr.lastStep), 80, LS_Y + 3, 12, fg)
 local bx, bw = 130, 180
 scr:draw_rectangle(bx, LS_Y + 3, bx + bw - 1, LS_Y + LS_H - 5,
 active and C_TEXT or C_GUIDE)
 local fw = (tr.lastStep * (bw - 2)) // 64
 if fw > 0 then
 scr:draw_rectangle_filled(bx + 1, LS_Y + 4,
 bx + 1 + fw - 1, LS_Y + LS_H - 6,
 active and C_TEXT or C_DIM)
 end
end
local function drawCtxStrip(scr)
 local tr = Engine.tracks[M.selT]
 local lo = viewportLo(M.viewport)
 scr:draw_rectangle_filled(0, CTX_Y, 319, 239, C_BG)
 local selRGB = modeRGB(M.focus)
 for c = 1, 16 do
 local s = lo + c - 1
 local stp = tr.steps[s]
 local oor = (s > tr.lastStep)
 local x0 = (c - 1) * COL_W + 1
 local x1 = x0 + COL_W - 3
 local isSel = (s == M.selS)
 local isPh = Engine.running and (tr.pos == s)
 local bg = isPh and C_PLAYHEAD or (oor and C_OOR or C_BG)
 scr:draw_rectangle_filled(x0, CTX_Y, x1,
 CTX_Y + CTX_H - 1, bg)
 if not oor and not Step.muted(stp) then
 local p = Step.pitch(stp)
 local h = (p * (CTX_H - 4)) // 127
 if h > 0 then
 local top = CTX_Y + 2 + (CTX_H - 4 - h)
 local fill = (isPh or isSel) and C_TEXT or C_DIM
 scr:draw_rectangle_filled(x0 + 1, top, x1 - 1,
 CTX_Y + CTX_H - 3, fill)
 end
 end
 if isSel then
 scr:draw_rectangle(x0, CTX_Y, x1,
 CTX_Y + CTX_H - 1, selRGB)
 end
 end
end
function M.draw(scr)
 local tr = Engine.tracks[M.selT]
 local ctxDirty = false
 local lo = viewportLo(M.viewport)
 if Engine.running then
 local c = tr.pos - lo + 1
 if c < 1 or c > 16 then c = 0 end
 if c ~= lastPhCol then ctxDirty = true; lastPhCol = c end
 elseif lastPhCol ~= -1 then
 ctxDirty = true; lastPhCol = -1
 end
 local any = needsFullRepaint
 if needsFullRepaint then
 scr:draw_rectangle_filled(0, 0, 319, 239, C_BG)
 drawHeader(scr)
 for i = 1, PARAMS_N do drawParamRow(scr, i) end
 drawLastStepRow(scr)
 drawCtxStrip(scr)
 needsFullRepaint = false
 elseif ctxDirty then
 drawCtxStrip(scr)
 any = true
 end
 if any then scr:draw_swap() end
end
return M

end)()
R["controls_en16"]=(function()

local Engine = require("engine")
local Step = require("step")
local Controls = require("controls")
local M = {}
M.NUM_ENC = 16
M.LED = {
 valueMax = 200,
 valueMin = 20,
 audibleBase = 30,
 playhead = 255,
 off = 0,
 beautify = 0,
}
local function resolve(idx)
 if idx < 1 or idx > 16 then return nil, nil end
 local tr = Engine.tracks[Controls.selT]
 if not tr then return nil, nil end
 return tr, Controls.viewportLo(Controls.viewport) + (idx - 1)
end
function M.onEncoder(idx, delta)
 local f = Controls.focus
 if f == Controls.MODE_LASTSTEP or f == Controls.MODE_STEP then return end
 local tr, s = resolve(idx)
 if not tr then return end
 Controls.setSelectedStep(s)
 local d = delta > 0 and 1 or -1
 Controls.setParam(f, Controls.selT, s, d)
 Controls.dirtyValueCells()
end
function M.onEncoderPress(idx)
 local tr, s = resolve(idx)
 if not tr then return end
 if Controls.focus == Controls.MODE_LASTSTEP then
 Engine.setLastStep(Controls.selT, s)
 else
 local newMute = Step.muted(tr.steps[s]) and 0 or 1
 Engine.setStepParam(Controls.selT, s, "mute", newMute)
 end
 Controls.dirtyValueCells()
end
local function modeValue(stp, focus)
 if focus == Controls.MODE_NOTE then return Step.pitch(stp) end
 if focus == Controls.MODE_VEL then return Step.vel(stp) end
 if focus == Controls.MODE_GATE then
 if Controls.shift then return Step.dur(stp) end
 return Step.gate(stp)
 end
 if focus == Controls.MODE_MUTE then
 return Step.muted(stp) and 0 or 127
 end
 if focus == Controls.MODE_STEP then
 return 127
 end
 return 127
end
local function scaleColor(r, g, b, brightness)
 local f = brightness
 return (r * f) // 255, (g * f) // 255, (b * f) // 255
end
function M.refreshLeds(emit)
 local tr = Engine.tracks[Controls.selT]; if not tr then return end
 local lo = Controls.viewportLo(Controls.viewport)
 local focus = Controls.focus
 local mr, mg, mb = Controls.modeColor(focus)
 local L = M.LED
 local ph = 0
 if Engine.running and tr.pos >= lo and tr.pos < lo + 16 then
 ph = tr.pos - lo + 1
 end
 for i = 1, 16 do
 local s = lo + i - 1
 local oor = (s > tr.lastStep)
 local stp = tr.steps[s]
 local muted = (not oor) and Step.muted(stp)
 local pr, pg, pb
 if oor or muted then
 pr, pg, pb = L.off, L.off, L.off
 elseif i == ph then
 pr, pg, pb = L.playhead, L.playhead, L.playhead
 else
 pr, pg, pb = L.audibleBase, L.audibleBase, L.audibleBase
 end
 emit(i, 1, pr, pg, pb)
 local tr_, tg_, tb_
 if oor or muted then
 tr_, tg_, tb_ = L.off, L.off, L.off
 else
 local v = modeValue(stp, focus)
 local b = L.valueMin + ((L.valueMax - L.valueMin) * v) // 127
 tr_, tg_, tb_ = scaleColor(mr, mg, mb, b)
 end
 emit(i, 2, tr_, tg_, tb_)
 end
end
return M

end)()
return {
    screen = R.controls,
    en16   = R.controls_en16,
}
