-- dist/sequencer.lua (auto-generated; Core only)
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
local SH_MUTE = 28
local function clamp7(v) if v < 0 then return 0 elseif v > 127 then return 127 else return v end end
local function clamp1(v) if v and v ~= 0 then return 1 else return 0 end end
function M.pack(t)
 local p = clamp7(t.pitch or 60)
 local v = clamp7(t.vel or 100)
 local d = clamp7(t.dur or 6)
 local g = clamp7(t.gate or 3)
 local m = clamp1(t.mute)
 return shl(p, SH_PITCH) | shl(v, SH_VEL) | shl(d, SH_DUR) | shl(g, SH_GATE)
 | shl(m, SH_MUTE)
end
function M.pitch(s) return band(shr(s, SH_PITCH), M7) end
function M.vel(s) return band(shr(s, SH_VEL), M7) end
function M.dur(s) return band(shr(s, SH_DUR), M7) end
function M.gate(s) return band(shr(s, SH_GATE), M7) end
function M.muted(s) return band(shr(s, SH_MUTE), 1) == 1 end
local function setField(s, shift, mask, value)
 return (s & ~shl(mask, shift)) | shl(value & mask, shift)
end
local FIELD = {
 pitch = { SH_PITCH, M7, clamp7 },
 vel = { SH_VEL, M7, clamp7 },
 dur = { SH_DUR, M7, clamp7 },
 gate = { SH_GATE, M7, clamp7 },
 mute = { SH_MUTE, 1, clamp1 },
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
 elseif name == "mute" then return M.muted(s) and 1 or 0
 end
end
M.FIELDS = { "pitch", "vel", "dur", "gate", "mute" }
local NOTE_NAMES = { "C","C#","D","D#","E","F","F#","G","G#","A","A#","B" }
function M.noteName(p)
 if p < 0 then p = 0 elseif p > 127 then p = 127 end
 local oct = (p // 12) - 1
 return NOTE_NAMES[(p % 12) + 1] .. tostring(oct)
end
return M

end)()
R["track"]=(function()

local Step = require("step")
local M = {}
M.DEFAULT_LAST_STEP = 16
function M.new(cap)
 cap = cap or 64
 local steps = {}
 local def = Step.pack({ pitch=60, vel=100, dur=6, gate=3 })
 for i = 1, cap do steps[i] = def end
 return {
 steps = steps,
 cap = cap,
 chan = 0,
 lastStep = M.DEFAULT_LAST_STEP,
 pos = 0,
 stepAcc = 0,
 stepLen = 0,
 actPitch = -1,
 actOff = 0,
 }
end
local function nextPos(tr)
 local p = tr.pos + 1
 if p > tr.lastStep or p < 1 then p = 1 end
 return p
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
local function fireStep(tr, out)
 local s = tr.steps[tr.pos]
 if Step.muted(s) then return end
 local p, v, g = Step.pitch(s), Step.vel(s), Step.gate(s)
 if g <= 0 then return end
 if g > tr.stepLen then g = tr.stepLen end
 if tr.actPitch == p and g >= tr.stepLen and tr.actOff > 0 then
 tr.actOff = g
 else
 if tr.actPitch >= 0 then
 out[#out+1] = { type=EV_OFF, pitch=tr.actPitch, vel=0, ch=tr.chan }
 end
 out[#out+1] = { type=EV_ON, pitch=p, vel=v, ch=tr.chan }
 tr.actPitch = p
 tr.actOff = g
 end
end
function M.advance(tr, out)
 if tr.stepAcc <= 0 then
 tr.pos = nextPos(tr)
 local s = tr.steps[tr.pos]
 local d = Step.dur(s)
 if d <= 0 then d = 1 end
 tr.stepAcc = d
 tr.stepLen = d
 fireStep(tr, out)
 else
 if tr.actOff > 0 then
 tr.actOff = tr.actOff - 1
 if tr.actOff == 0 then emitOff(tr, out) end
 end
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
function M.setLastStep(tr, n)
 if n < 1 then n = 1 elseif n > tr.cap then n = tr.cap end
 tr.lastStep = n
end
function M.reset(tr)
 tr.pos = 0
 tr.stepAcc = 0
 tr.stepLen = 0
 tr.actPitch = -1
 tr.actOff = 0
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
M.pulseCount = 0
M.swing = 0
local logFn = nil
function M.init(opts)
 opts = opts or {}
 local n = opts.trackCount or 4
 local cap = opts.stepsPerTrack or 64
 M.tracks = {}
 for i = 1, n do
 M.tracks[i] = Track.new(cap)
 M.tracks[i].chan = i - 1
 end
 M.running = false
 M.pulseCount = 0
 M.swing = 0
 M._swingOwed = {}
 for i = 1, n do M._swingOwed[i] = 0 end
 logFn = opts.log
end
local function log(s) if logFn then logFn(s) end end
function M.onStart()
 for i = 1, #M.tracks do
 Track.reset(M.tracks[i])
 M._swingOwed[i] = 0
 end
 M.pulseCount = 0
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
 local n = #ts
 local sw = M.swing
 local pc = M.pulseCount
 local owe = M._swingOwed
 M.pulseCount = pc + 1
 local swingPulse = sw > 0 and ((pc % 12) == 6)
 for i = 1, n do
 local tr = ts[i]
 local owed = owe[i]
 local atFire = (tr.stepAcc <= 0)
 if atFire and swingPulse and owed == 0 then
 tr.stepAcc = sw
 tr.stepLen = sw
 owe[i] = sw
 atFire = false
 end
 Track.advance(tr, out)
 if atFire and owed > 0 then
 local left = tr.stepAcc - owed
 if left < 0 then left = 0 end
 tr.stepAcc = left
 owe[i] = 0
 end
 end
 if #out == 0 then return nil end
 return out
end
function M.setStepParam(t, i, name, val)
 local tr = M.tracks[t]; if not tr then return end
 Track.setStepParam(tr, i, name, val)
end
function M.setLastStep(t, n)
 local tr = M.tracks[t]; if not tr then return end
 Track.setLastStep(tr, n)
end
function M.setTrackChan(t, ch)
 local tr = M.tracks[t]; if not tr then return end
 if ch < 0 then ch = 0 end
 if ch > 15 then ch = 15 end
 tr.chan = ch
end
function M.setSwing(s)
 if s < 0 then s = 0 elseif s > 3 then s = 3 end
 M.swing = s
end
return M

end)()
R["midi_rx"]=(function()

local Engine = require("engine")
local M = {}
function M.handle(t, send)
 if t == 0xF8 then
 local events = Engine.onPulse()
 if events then
 for i = 1, #events do
 local e = events[i]
 if e.type == 1 then send(e.ch, 0x90, e.pitch, e.vel)
 else send(e.ch, 0x80, e.pitch, 0) end
 end
 end
 return "tick"
 elseif t == 0xFA then
 Engine.onStart()
 return "start"
 elseif t == 0xFB then
 if not Engine.running then Engine.onStart() end
 return "start"
 elseif t == 0xFC then
 local off = Engine.onStop()
 if off then
 for i = 1, #off do send(off[i].ch, 0x80, off[i].pitch, 0) end
 end
 return "stop"
 end
end
return M

end)()
R["persist"]=(function()

local Engine = require("engine")
local M = {}
function M.save(path)
 local f = io.open(path, "w")
 if not f then return false end
 f:write("return{swing=", Engine.swing, ",tracks={")
 for ti = 1, #Engine.tracks do
 local tr = Engine.tracks[ti]
 f:write("{chan=", tr.chan, ",lastStep=", tr.lastStep, ",steps={")
 local s = tr.steps
 for i = 1, tr.cap do
 if i > 1 then f:write(",") end
 f:write(s[i])
 end
 f:write("}},")
 end
 f:write("}}")
 f:close()
 return true
end
function M.load(path)
 local f = io.open(path, "r")
 if not f then return false end
 local src = f:read("*a")
 f:close()
 local chunk, _ = load(src, "save", "t")
 if not chunk then return false end
 local ok, data = pcall(chunk)
 if not ok or type(data) ~= "table" or type(data.tracks) ~= "table" then
 return false
 end
 if type(data.swing) == "number" then Engine.setSwing(data.swing | 0) end
 for ti = 1, #Engine.tracks do
 local td = data.tracks[ti]
 if type(td) == "table" then
 local tr = Engine.tracks[ti]
 if type(td.chan) == "number" then
 Engine.setTrackChan(ti, td.chan | 0)
 end
 if type(td.lastStep) == "number" then
 Engine.setLastStep(ti, td.lastStep | 0)
 end
 if type(td.steps) == "table" then
 local ds = td.steps
 local s = tr.steps
 for i = 1, tr.cap do
 local v = ds[i]
 if type(v) == "number" then s[i] = v | 0 end
 end
 end
 end
 end
 return true
end
return M

end)()
return {
    Core     = { step = R.step, track = R.track, engine = R.engine, midi_rx = R.midi_rx, persist = R.persist },
    App      = nil,   -- lazy-loaded; require("sequencer_ui") to populate
    Controls = nil,   -- lazy-loaded; require("sequencer_ui") to populate
    HAL      = {},
    -- flat aliases (same table refs); UI bundle resolves through these
    step    = R.step,
    track   = R.track,
    engine  = R.engine,
    midi_rx = R.midi_rx,
    persist = R.persist,
}
