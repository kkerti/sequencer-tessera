-- dist/euclid.lua (auto-generated; Euclidean Core)
local R={}
local function require(n) return R[n] end
R["euclidean.track"]=(function()

local M = {}
M.MAX_STEPS = 32
local EV_ON, EV_OFF = 1, 2
M.EV_ON, M.EV_OFF = EV_ON, EV_OFF
local function recompute(tr)
 local n = tr.steps
 local k = tr.events
 local r = tr.rot
 if n < 1 then n = 1 end
 if k < 0 then k = 0 elseif k > n then k = n end
 if r < 0 then r = 0 elseif r >= n then r = r % n end
 local mask = 0
 if k > 0 then
 local prev = 0
 for i = 1, n do
 local cur = (i * k) // n
 if cur ~= prev then
 local b = (i - 1 + r) % n
 mask = mask | (1 << b)
 end
 prev = cur
 end
 end
 tr.hits = mask
end
M.recompute = recompute
function M.new()
 local tr = {
 steps = 16,
 events = 4,
 rot = 0,
 key = 60,
 vel = 100,
 gate = 3,
 ppstep = 6,
 chan = 0,
 muted = 0,
 hits = 0,
 pos = -1,
 acc = 0,
 actOff = 0,
 actPitch = -1,
 actChan = 0,
 }
 recompute(tr)
 return tr
end
function M.reset(tr)
 tr.pos = -1
 tr.acc = 0
 tr.actOff = 0
 tr.actPitch = -1
end
local function emitOff(tr, out)
 if tr.actOff > 0 and tr.actPitch >= 0 then
 out[#out+1] = { type=EV_OFF, pitch=tr.actPitch, vel=0, ch=tr.actChan }
 tr.actOff = 0
 tr.actPitch = -1
 end
end
M.emitOff = emitOff
function M.allOff(tr, out)
 if tr.actOff > 0 and tr.actPitch >= 0 then
 out[#out+1] = { type=EV_OFF, pitch=tr.actPitch, vel=0, ch=tr.actChan }
 tr.actOff = 0
 tr.actPitch = -1
 end
end
function M.advance(tr, out)
 if tr.actOff > 0 then
 tr.actOff = tr.actOff - 1
 if tr.actOff == 0 then
 out[#out+1] = { type=EV_OFF, pitch=tr.actPitch, vel=0, ch=tr.actChan }
 tr.actPitch = -1
 end
 end
 if tr.acc <= 0 then
 local p = tr.pos + 1
 if p >= tr.steps then p = 0 end
 tr.pos = p
 local d = tr.ppstep
 if d <= 0 then d = 1 end
 tr.acc = d
 if tr.muted == 0 and (tr.hits >> p) & 1 == 1 then
 if tr.actOff > 0 then
 out[#out+1] = { type=EV_OFF, pitch=tr.actPitch, vel=0, ch=tr.actChan }
 tr.actOff = 0
 tr.actPitch = -1
 end
 local g = tr.gate
 if g > d then g = d end
 if g > 0 then
 out[#out+1] = { type=EV_ON, pitch=tr.key, vel=tr.vel, ch=tr.chan }
 tr.actOff = g
 tr.actPitch = tr.key
 tr.actChan = tr.chan
 end
 end
 end
 tr.acc = tr.acc - 1
end
local function clamp(v, lo, hi)
 if v < lo then return lo elseif v > hi then return hi else return v end
end
function M.setSteps(tr, n)
 n = clamp(n, 1, M.MAX_STEPS)
 if n == tr.steps then return end
 tr.steps = n
 if tr.events > n then tr.events = n end
 if tr.rot >= n then tr.rot = tr.rot % n end
 recompute(tr)
end
function M.setEvents(tr, k)
 k = clamp(k, 0, tr.steps)
 if k == tr.events then return end
 tr.events = k
 recompute(tr)
end
function M.setRot(tr, r)
 if tr.steps < 1 then return end
 r = r % tr.steps
 if r < 0 then r = r + tr.steps end
 if r == tr.rot then return end
 tr.rot = r
 recompute(tr)
end
function M.setKey(tr, p) tr.key = clamp(p, 0, 127) end
function M.setVel(tr, v) tr.vel = clamp(v, 1, 127) end
function M.setGate(tr, g) tr.gate = clamp(g, 1, 127) end
function M.setPpstep(tr, d) tr.ppstep= clamp(d, 1, 127) end
function M.setChan(tr, c) tr.chan = clamp(c, 0, 15) end
function M.setMuted(tr, m) tr.muted = (m and m ~= 0) and 1 or 0 end
function M.isHit(tr, i)
 if i < 0 or i >= tr.steps then return false end
 return ((tr.hits >> i) & 1) == 1
end
return M

end)()
R["euclidean.engine"]=(function()

local Track = require("euclidean.track")
local M = {}
M.tracks = {}
M.running = false
M.pulseCount = 0
local logFn = nil
function M.init(opts)
 opts = opts or {}
 local n = opts.trackCount or 4
 M.tracks = {}
 for i = 1, n do
 local tr = Track.new()
 tr.chan = i - 1
 M.tracks[i] = tr
 end
 M.running = false
 M.pulseCount = 0
 logFn = opts.log
end
local function log(s) if logFn then logFn(s) end end
function M.onStart()
 for i = 1, #M.tracks do Track.reset(M.tracks[i]) end
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
 M.pulseCount = M.pulseCount + 1
 for i = 1, #ts do
 Track.advance(ts[i], out)
 end
 if #out == 0 then return nil end
 return out
end
function M.setSteps(t, n)
 local tr = M.tracks[t]; if tr then Track.setSteps(tr, n) end
end
function M.setEvents(t, k)
 local tr = M.tracks[t]; if tr then Track.setEvents(tr, k) end
end
function M.setRot(t, r)
 local tr = M.tracks[t]; if tr then Track.setRot(tr, r) end
end
function M.setKey(t, p)
 local tr = M.tracks[t]; if tr then Track.setKey(tr, p) end
end
function M.setVel(t, v)
 local tr = M.tracks[t]; if tr then Track.setVel(tr, v) end
end
function M.setGate(t, g)
 local tr = M.tracks[t]; if tr then Track.setGate(tr, g) end
end
function M.setPpstep(t, d)
 local tr = M.tracks[t]; if tr then Track.setPpstep(tr, d) end
end
function M.setChan(t, c)
 local tr = M.tracks[t]; if tr then Track.setChan(tr, c) end
end
function M.setMuted(t, m)
 local tr = M.tracks[t]; if tr then Track.setMuted(tr, m) end
end
return M

end)()
return {
    Core = { track = R["euclidean.track"], engine = R["euclidean.engine"] },
    Controls = nil,
    App = nil,
    HAL = {},
    -- flat aliases for the UI shim's fall-through path. The UI bundle
    -- requires under the dotted form ("euclidean.track"); the host
    -- `require` returns this table and the shim looks up the dotted key
    -- directly via the alias map below.
    ["euclidean.track"]  = R["euclidean.track"],
    ["euclidean.engine"] = R["euclidean.engine"],
}
