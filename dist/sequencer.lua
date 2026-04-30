-- dist/sequencer.lua (auto-generated; do not edit)
local R={}
local function require(n) return R[n] end
R["step"]=(function()

local M = {}
local band, bor, shl, shr = (bit32 and bit32.band) or function(a,b) return a & b end,
 (bit32 and bit32.bor) or function(a,b) return a | b end,
 (bit32 and bit32.lshift) or function(a,n) return a << n end,
 (bit32 and bit32.rshift) or function(a,n) return a >> n end
local M7 = 0x7F
local SH_PITCH = 0
local SH_VEL = 7
local SH_DUR = 14
local SH_GATE = 21
local SH_RAT = 28
local SH_ACT = 29
local SH_PROB = 30
local function clamp7(v) if v < 0 then return 0 elseif v > 127 then return 127 else return v end end
local function clamp1(v) if v and v ~= 0 then return 1 else return 0 end end
function M.pack(t)
 local p = clamp7(t.pitch or 60)
 local v = clamp7(t.vel or 100)
 local d = clamp7(t.dur or 6)
 local g = clamp7(t.gate or 3)
 local r = clamp1(t.ratch)
 local a = clamp1(t.active ~= false and 1 or 0)
 local pr = clamp7(t.prob or 127)
 return shl(p, SH_PITCH) | shl(v, SH_VEL) | shl(d, SH_DUR) | shl(g, SH_GATE)
 | shl(r, SH_RAT) | shl(a, SH_ACT) | shl(pr, SH_PROB)
end
function M.pitch(s) return band(shr(s, SH_PITCH), M7) end
function M.vel(s) return band(shr(s, SH_VEL), M7) end
function M.dur(s) return band(shr(s, SH_DUR), M7) end
function M.gate(s) return band(shr(s, SH_GATE), M7) end
function M.ratch(s) return band(shr(s, SH_RAT), 1) == 1 end
function M.active(s) return band(shr(s, SH_ACT), 1) == 1 end
function M.prob(s) return band(shr(s, SH_PROB), M7) end
local function setField(s, shift, mask, value)
 return (s & ~shl(mask, shift)) | shl(value & mask, shift)
end
local FIELD = {
 pitch = { SH_PITCH, M7, clamp7 },
 vel = { SH_VEL, M7, clamp7 },
 dur = { SH_DUR, M7, clamp7 },
 gate = { SH_GATE, M7, clamp7 },
 ratch = { SH_RAT, 1, clamp1 },
 active = { SH_ACT, 1, clamp1 },
 prob = { SH_PROB, M7, clamp7 },
}
function M.set(s, name, value)
 local f = FIELD[name]; if not f then return s end
 return setField(s, f[1], f[2], f[3](value))
end
function M.get(s, name)
 if name == "pitch" then return M.pitch(s)
 elseif name == "vel" then return M.vel(s)
 elseif name == "dur" then return M.dur(s)
 elseif name == "gate" then return M.gate(s)
 elseif name == "ratch" then return M.ratch(s) and 1 or 0
 elseif name == "active" then return M.active(s) and 1 or 0
 elseif name == "prob" then return M.prob(s)
 end
end
M.FIELDS = { "pitch", "vel", "dur", "gate", "ratch", "active", "prob" }
return M

end)()
R["track"]=(function()

local Step = require("step")
local M = {}
local DIR_FWD, DIR_REV, DIR_PP, DIR_RND = 1, 2, 3, 4
M.DIR_FWD, M.DIR_REV, M.DIR_PP, M.DIR_RND = DIR_FWD, DIR_REV, DIR_PP, DIR_RND
function M.new(n, len)
 n = n or 64
 len = len or 16
 local steps = {}
 local def = Step.pack({ pitch=60, vel=100, dur=6, gate=3, prob=127, active=true })
 for i = 1, n do steps[i] = def end
 return {
 steps = steps,
 cap = n,
 len = len,
 chan = 1,
 div = 1,
 dir = DIR_FWD,
 ppDir = 1,
 pos = 0,
 divAcc = 0,
 stepAcc = 0,
 actPitch = -1,
 actOff = 0,
 ratNext = 0,
 ratState = 0,
 }
end
local function nextPos(tr)
 local len = tr.len
 if len <= 1 then return 1 end
 local d = tr.dir
 if d == DIR_FWD then
 local p = tr.pos + 1
 if p > len then p = 1 end
 return p
 elseif d == DIR_REV then
 local p = tr.pos - 1
 if p < 1 then p = len end
 return p
 elseif d == DIR_PP then
 local p = tr.pos + tr.ppDir
 if p > len then tr.ppDir = -1; p = len - 1; if p < 1 then p = 1 end
 elseif p < 1 then tr.ppDir = 1; p = 2; if p > len then p = len end end
 return p
 else
 return math.random(1, len)
 end
end
local function rollProb(prob)
 if prob >= 127 then return true end
 if prob <= 0 then return false end
 return math.random(0, 126) < prob
end
local EV_ON, EV_OFF = 1, 2
M.EV_ON, M.EV_OFF = EV_ON, EV_OFF
local function emitOff(tr, out)
 if tr.actPitch >= 0 then
 out[#out+1] = { type=EV_OFF, pitch=tr.actPitch, vel=0, ch=tr.chan }
 tr.actPitch = -1
 tr.actOff = 0
 end
end
local SUSTAIN = 0x7FFFFFFF
local function fireStep(tr, out)
 local s = tr.steps[tr.pos]
 if not Step.active(s) then return end
 if not rollProb(Step.prob(s)) then return end
 local p, v, g = Step.pitch(s), Step.vel(s), Step.gate(s)
 if g <= 0 then return end
 local dur = Step.dur(s)
 local sustain = (g >= dur)
 if tr.actPitch == p and sustain then
 tr.actOff = SUSTAIN
 else
 if tr.actPitch >= 0 then
 out[#out+1] = { type=EV_OFF, pitch=tr.actPitch, vel=0, ch=tr.chan }
 end
 out[#out+1] = { type=EV_ON, pitch=p, vel=v, ch=tr.chan }
 tr.actPitch = p
 tr.actOff = sustain and SUSTAIN or g
 end
 if Step.ratch(s) and g > 0 then
 tr.ratNext = g
 tr.ratState = 1
 else
 tr.ratNext = 0
 end
end
function M.advance(tr, out)
 tr.divAcc = tr.divAcc + 1
 if tr.divAcc < tr.div then
 return
 end
 tr.divAcc = 0
 if tr.actOff > 0 and tr.actOff ~= SUSTAIN then
 tr.actOff = tr.actOff - 1
 if tr.actOff == 0 then
 emitOff(tr, out)
 end
 end
 if tr.ratNext > 0 then
 tr.ratNext = tr.ratNext - 1
 if tr.ratNext == 0 then
 local s = tr.steps[tr.pos]
 local g = Step.gate(s)
 if tr.ratState == 1 then
 emitOff(tr, out)
 tr.ratState = 0
 tr.ratNext = g
 else
 local p, v = Step.pitch(s), Step.vel(s)
 out[#out+1] = { type=EV_ON, pitch=p, vel=v, ch=tr.chan }
 tr.actPitch = p
 tr.actOff = g
 tr.ratState = 1
 tr.ratNext = g
 end
 end
 end
 if tr.stepAcc <= 0 then
 tr.pos = nextPos(tr)
 local s = tr.steps[tr.pos]
 local d = Step.dur(s)
 if d <= 0 then d = 1 end
 tr.stepAcc = d
 fireStep(tr, out)
 end
 tr.stepAcc = tr.stepAcc - 1
end
function M.setStepParam(tr, i, name, val)
 if i < 1 or i > tr.cap then return end
 tr.steps[i] = Step.set(tr.steps[i], name, val)
end
function M.getStepParam(tr, i, name)
 if i < 1 or i > tr.cap then return nil end
 return Step.get(tr.steps[i], name)
end
function M.groupEdit(tr, from, to, op, name, val)
 if from > to then from, to = to, from end
 if from < 1 then from = 1 end
 if to > tr.cap then to = tr.cap end
 if op == "set" then
 for i = from, to do
 tr.steps[i] = Step.set(tr.steps[i], name, val)
 end
 elseif op == "add" then
 for i = from, to do
 local cur = Step.get(tr.steps[i], name)
 tr.steps[i] = Step.set(tr.steps[i], name, cur + val)
 end
 elseif op == "rand" then
 local lo, hi = val[1], val[2]
 for i = from, to do
 tr.steps[i] = Step.set(tr.steps[i], name, math.random(lo, hi))
 end
 end
end
function M.reset(tr)
 tr.pos = 0
 tr.divAcc = 0
 tr.stepAcc = 0
 tr.actPitch = -1
 tr.actOff = 0
 tr.ratNext = 0
 tr.ratState = 0
 tr.ppDir = 1
end
function M.allOff(tr, out)
 emitOff(tr, out)
end
return M

end)()
R["engine"]=(function()

local Track = require("track")
local M = {}
M.tracks = {}
M.running = false
local logFn = nil
function M.init(opts)
 opts = opts or {}
 local n = opts.trackCount or 4
 local cap = opts.stepsPerTrack or 64
 local len = opts.defaultLen or 16
 M.tracks = {}
 for i = 1, n do
 M.tracks[i] = Track.new(cap, len)
 M.tracks[i].chan = i
 end
 M.running = false
 logFn = opts.log
end
local function log(s) if logFn then logFn(s) end end
function M.onStart()
 for i = 1, #M.tracks do Track.reset(M.tracks[i]) end
 M.running = true
 log("START")
end
function M.onStop()
 local out = {}
 for i = 1, #M.tracks do Track.allOff(M.tracks[i], out) end
 M.running = false
 log("STOP")
 return out
end
function M.onPulse()
 if not M.running then return nil end
 local out = {}
 local ts = M.tracks
 for i = 1, #ts do
 Track.advance(ts[i], out)
 end
 if #out == 0 then return nil end
 return out
end
function M.setStepParam(t, i, name, val)
 local tr = M.tracks[t]; if not tr then return end
 Track.setStepParam(tr, i, name, val)
end
function M.groupEdit(t, from, to, op, name, val)
 local tr = M.tracks[t]; if not tr then return end
 Track.groupEdit(tr, from, to, op, name, val)
end
function M.setTrackLen(t, len)
 local tr = M.tracks[t]; if not tr then return end
 if len < 1 then len = 1 end
 if len > tr.cap then len = tr.cap end
 tr.len = len
end
function M.setTrackDiv(t, div)
 local tr = M.tracks[t]; if not tr then return end
 if div < 1 then div = 1 end
 if div > 16 then div = 16 end
 tr.div = div
end
function M.setTrackDir(t, dir)
 local tr = M.tracks[t]; if not tr then return end
 if dir < 1 or dir > 4 then return end
 tr.dir = dir
 tr.ppDir = 1
end
function M.setTrackChan(t, ch)
 local tr = M.tracks[t]; if not tr then return end
 if ch < 1 then ch = 1 end
 if ch > 16 then ch = 16 end
 tr.chan = ch
end
return M

end)()
R["controls"]=(function()

local Engine = require("engine")
local Track = require("track")
local Step = require("step")
local M = {}
M.selT = 1
M.selS = 1
M.focus = 3
local CELLS = {
 { "TRACK", "track", function(t,s) return t end,
 function(t,s,d) M.selT = ((t - 1 + d) % 4) + 1 end, 1, 4 },
 { "STEP", "step", function(t,s) return s end,
 function(t,s,d)
 local tr = Engine.tracks[t]
 local n = (s - 1 + d) % tr.len
 M.selS = n + 1
 end, 1, 64 },
 { "NOTE", "pitch",
 function(t,s) return Engine.tracks[t].steps[s] and Step.pitch(Engine.tracks[t].steps[s]) or 0 end,
 function(t,s,d)
 local cur = Step.pitch(Engine.tracks[t].steps[s])
 Engine.setStepParam(t, s, "pitch", cur + d)
 end, 0, 127 },
 { "VEL", "vel",
 function(t,s) return Step.vel(Engine.tracks[t].steps[s]) end,
 function(t,s,d)
 local cur = Step.vel(Engine.tracks[t].steps[s])
 Engine.setStepParam(t, s, "vel", cur + d)
 end, 0, 127 },
 { "DUR", "dur",
 function(t,s) return Step.dur(Engine.tracks[t].steps[s]) end,
 function(t,s,d)
 local cur = Step.dur(Engine.tracks[t].steps[s])
 Engine.setStepParam(t, s, "dur", cur + d)
 end, 1, 127 },
 { "GATE", "gate",
 function(t,s) return Step.gate(Engine.tracks[t].steps[s]) end,
 function(t,s,d)
 local cur = Step.gate(Engine.tracks[t].steps[s])
 Engine.setStepParam(t, s, "gate", cur + d)
 end, 0, 127 },
 { "RATCH", "ratch",
 function(t,s) return Step.ratch(Engine.tracks[t].steps[s]) and 1 or 0 end,
 function(t,s,d)
 local cur = Step.ratch(Engine.tracks[t].steps[s]) and 1 or 0
 Engine.setStepParam(t, s, "ratch", (cur + d) % 2)
 end, 0, 1 },
 { "PROB", "prob",
 function(t,s) return Step.prob(Engine.tracks[t].steps[s]) end,
 function(t,s,d)
 local cur = Step.prob(Engine.tracks[t].steps[s])
 Engine.setStepParam(t, s, "prob", cur + d)
 end, 0, 127 },
}
M.CELLS = CELLS
local dirty = { true, true, true, true, true, true, true, true }
local function dirtyAll() for i=1,8 do dirty[i] = true end end
M.dirtyAll = dirtyAll
function M.onEndless(dir)
 local cell = CELLS[M.focus]
 cell[4](M.selT, M.selS, dir)
 dirty[M.focus] = true
 if M.focus == 1 or M.focus == 2 then dirtyAll() end
end
function M.onKey(idx)
 if idx < 1 or idx > 8 then return end
 dirty[M.focus] = true
 M.focus = idx
 dirty[idx] = true
end
local CELL_W, CELL_H = 80, 120
local function cellRect(i)
 local col = (i - 1) % 4
 local row = math.floor((i - 1) / 4)
 return col * CELL_W, row * CELL_H
end
local COL_BG_ACTIVE = { 200, 30, 30 }
local COL_BG_INACTIVE = { 40, 40, 40 }
local COL_FG = { 230, 230, 230 }
local function drawCell(scr, i)
 local x, y = cellRect(i)
 local cell = CELLS[i]
 local val = cell[3](M.selT, M.selS)
 local bg = (i == M.focus) and COL_BG_ACTIVE or COL_BG_INACTIVE
 scr:draw_rectangle_filled(x, y, x + CELL_W - 1, y + CELL_H - 1, bg)
 scr:draw_text_fast(cell[1], x + 4, y + 6, 8, COL_FG)
 scr:draw_text_fast(tostring(val), x + 4, y + 24, 16, COL_FG)
end
function M.draw(scr)
 local any = false
 for i = 1, 8 do
 if dirty[i] then
 drawCell(scr, i)
 dirty[i] = false
 any = true
 end
 end
 if any then scr:draw_swap() end
end
return M

end)()
return R
