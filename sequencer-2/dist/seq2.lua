-- dist/seq2.lua (Core + midi_rx; auto-generated)
local R={}
local function require(n) return R[n] end
R["event"]=(function()

local M = {}
function M.new(cap)
 cap = cap or 256
 return { n = 0, cap = cap, pitch = {}, start = {}, len = {}, vel = {} }
end
function M.clear(s)
 s.n = 0
end
function M.add(s, pitch, start, len, vel)
 if s.n >= s.cap then return nil end
 local P, S, L, V = s.pitch, s.start, s.len, s.vel
 local i = s.n
 while i >= 1 and S[i] > start do
 P[i + 1] = P[i]; S[i + 1] = S[i]; L[i + 1] = L[i]; V[i + 1] = V[i]
 i = i - 1
 end
 local at = i + 1
 P[at] = pitch; S[at] = start; L[at] = len; V[at] = vel
 s.n = s.n + 1
 return at
end
function M.removeAt(s, at)
 if at < 1 or at > s.n then return end
 local P, S, L, V = s.pitch, s.start, s.len, s.vel
 for i = at, s.n - 1 do
 P[i] = P[i + 1]; S[i] = S[i + 1]; L[i] = L[i + 1]; V[i] = V[i + 1]
 end
 s.n = s.n - 1
end
return M

end)()
R["scales"]=(function()

local M = {}
M.SCALES = {
 { name = "off", short = "off", mask = 0x000 },
 { name = "major", short = "Maj", mask = 0xAB5 },
 { name = "minor", short = "Min", mask = 0x5AD },
 { name = "harm min", short = "HMin", mask = 0x9AD },
 { name = "dorian", short = "Dor", mask = 0x6AD },
 { name = "phrygian", short = "Phr", mask = 0x5AB },
 { name = "mixolydian", short = "Mix", mask = 0x6B5 },
 { name = "min pent", short = "MinP", mask = 0x4A9 },
}
function M.rotate(mask, root)
 root = root % 12
 if root == 0 then return mask end
 return ((mask << root) | (mask >> (12 - root))) & 0xFFF
end
function M.step(pitch, mask, d)
 if mask == 0 then
 local r = pitch + d
 if r < 0 then return 0 elseif r > 127 then return 127 else return r end
 end
 local p = M.quantize(pitch, mask)
 local dir = (d >= 0) and 1 or -1
 for _ = 1, (d >= 0 and d or -d) do
 local q = p + dir
 while q >= 0 and q <= 127 and ((mask >> (q % 12)) & 1) == 0 do q = q + dir end
 if q < 0 then return 0 elseif q > 127 then return 127 else p = q end
 end
 return p
end
function M.quantize(p, mask)
 if mask == 0 then return p end
 local pc = p % 12
 if (mask >> pc) & 1 == 1 then return p end
 local base = (p // 12) * 12
 for d = 1, 12 do
 local up = pc + d
 if up < 12 then
 if (mask >> up) & 1 == 1 then return base + up end
 else
 local u = up - 12
 if (mask >> u) & 1 == 1 then return base + 12 + u end
 end
 local dn = pc - d
 if dn >= 0 then
 if (mask >> dn) & 1 == 1 then return base + dn end
 else
 local dd = dn + 12
 if (mask >> dd) & 1 == 1 then
 local r = base - 12 + dd
 if r < 0 then return 0 end
 return r
 end
 end
 end
 return p
end
return M

end)()
R["range"]=(function()

local M = {}
M.__index = M
function M.new(p)
 p = p or {}
 return setmetatable({
 pitchMin = p.pitchMin or 0, pitchMax = p.pitchMax or 127,
 velMin = p.velMin or 1, velMax = p.velMax or 127,
 lenMin = p.lenMin or 1, lenMax = p.lenMax or 65535,
 }, M)
end
local function clamp(v, lo, hi)
 if v < lo then return lo elseif v > hi then return hi else return v end
end
function M:process(buf)
 local P, L, V = buf.pitch, buf.len, buf.vel
 for i = 1, buf.n do
 P[i] = clamp(P[i], self.pitchMin, self.pitchMax)
 V[i] = clamp(V[i], self.velMin, self.velMax)
 L[i] = clamp(L[i], self.lenMin, self.lenMax)
 end
end
return M

end)()
R["random"]=(function()

local M = {}
M.__index = M
function M.new(p)
 p = p or {}
 return setmetatable({
 chance = p.chance or 100,
 pitchJit = p.pitchJit or 0,
 velJit = p.velJit or 0,
 octJit = p.octJit or 0,
 seed = (p.seed or 0x2545F491) & 0xFFFFFFFF,
 }, M)
end
function M:rand()
 local s = (self.seed * 1664525 + 1013904223) & 0xFFFFFFFF
 self.seed = s
 return (s >> 16) & 0x7FFF
end
local function jit(self, amt)
 if amt == 0 then return 0 end
 return (self:rand() % (2 * amt + 1)) - amt
end
function M:process(buf)
 local P, V = buf.pitch, buf.vel
 local w = 0
 for r = 1, buf.n do
 local play = self.chance >= 100 or (self:rand() % 100) < self.chance
 if play then
 w = w + 1
 local p = P[r] + jit(self, self.pitchJit) + 12 * jit(self, self.octJit)
 if p < 0 then p = 0 elseif p > 127 then p = 127 end
 local v = V[r] + jit(self, self.velJit)
 if v < 1 then v = 1 elseif v > 127 then v = 127 end
 P[w] = p; V[w] = v; buf.len[w] = buf.len[r]
 end
 end
 buf.n = w
end
return M

end)()
R["scale"]=(function()

local Scales = require("scales")
local M = {}
M.__index = M
function M.new(p)
 p = p or {}
 local self = setmetatable({
 scaleIndex = p.scaleIndex or 1,
 root = p.root or 0,
 mask = 0,
 }, M)
 self:recompute()
 return self
end
function M:recompute()
 local base = (Scales.SCALES[self.scaleIndex] or Scales.SCALES[1]).mask
 self.mask = Scales.rotate(base, self.root)
end
function M:setScale(i) self.scaleIndex = i; self:recompute() end
function M:setRoot(r) self.root = r % 12; self:recompute() end
function M:process(buf)
 if self.mask == 0 then return end
 local P = buf.pitch
 for i = 1, buf.n do
 P[i] = Scales.quantize(P[i], self.mask)
 end
end
return M

end)()
R["rack"]=(function()

local M = {}
local MAX_SLOTS = 8
function M.new()
 return { n = 0, fx = {} }
end
function M.add(rack, effect)
 if rack.n >= MAX_SLOTS then return false end
 rack.n = rack.n + 1
 rack.fx[rack.n] = effect
 return true
end
function M.run(rack, buf)
 local fx = rack.fx
 for i = 1, rack.n do
 fx[i]:process(buf)
 end
end
return M

end)()
R["pattern"]=(function()

local Event = require("event")
local M = {}
M.ZOOM = { { name = "/2", tps = 12 }, { name = "x1", tps = 6 },
 { name = "2/3", tps = 4 }, { name = "x2", tps = 3 } }
function M.new(opts)
 opts = opts or {}
 return {
 events = Event.new(opts.cap or 256),
 length = opts.length or 16,
 zoom = opts.zoom or 6,
 fxValues = nil,
 }
end
function M.loopTicks(p)
 return p.length * p.zoom
end
return M

end)()
R["track"]=(function()

local Pattern = require("pattern")
local Rack = require("rack")
local Range = require("range")
local Random = require("random")
local Scale = require("scale")
local M = {}
local VOICES = 4
local function emit(out, typ, pitch, vel, ch)
 local n = out.n + 1
 out.n = n
 out.typ[n] = typ; out.pitch[n] = pitch; out.vel[n] = vel; out.ch[n] = ch
end
function M.new(opts)
 opts = opts or {}
 local rack = Rack.new()
 Rack.add(rack, Range.new(opts.range))
 Rack.add(rack, Random.new(opts.random))
 Rack.add(rack, Scale.new(opts.scale))
 local tr = {
 pattern = opts.pattern or Pattern.new(),
 rack = rack,
 chan = opts.chan or 1,
 evCursor = 1,
 prevLocal = -1,
 vp = { 0, 0, 0, 0 },
 vo = { 0, 0, 0, 0 },
 va = { 0, 0, 0, 0 },
 }
 return tr
end
function M.reset(tr)
 tr.evCursor = 1
 tr.prevLocal = -1
 for i = 1, VOICES do tr.va[i] = 0 end
end
local function allocVoice(tr, out)
 local va, vo = tr.va, tr.vo
 for i = 1, VOICES do
 if va[i] == 0 then return i end
 end
 local victim, best = 1, vo[1]
 for i = 2, VOICES do
 if vo[i] < best then best = vo[i]; victim = i end
 end
 emit(out, 0, tr.vp[victim], 0, tr.chan)
 return victim
end
function M.advance(tr, gt, scratch, out)
 local pat = tr.pattern
 local loop = Pattern.loopTicks(pat)
 local localTick = gt % loop
 if localTick < tr.prevLocal then tr.evCursor = 1 end
 tr.prevLocal = localTick
 local va, vo, vp = tr.va, tr.vo, tr.vp
 for i = 1, VOICES do
 if va[i] == 1 and vo[i] <= gt then
 emit(out, 0, vp[i], 0, tr.chan)
 va[i] = 0
 end
 end
 local ev = pat.events
 local S = ev.start
 local cur = tr.evCursor
 while cur <= ev.n and S[cur] < localTick do cur = cur + 1 end
 scratch.n = 0
 while cur <= ev.n and S[cur] == localTick do
 local m = scratch.n + 1
 scratch.n = m
 scratch.pitch[m] = ev.pitch[cur]
 scratch.len[m] = ev.len[cur]
 scratch.vel[m] = ev.vel[cur]
 cur = cur + 1
 end
 tr.evCursor = cur
 if scratch.n == 0 then return end
 Rack.run(tr.rack, scratch)
 for i = 1, scratch.n do
 local slot = allocVoice(tr, out)
 local pitch = scratch.pitch[i]
 emit(out, 1, pitch, scratch.vel[i], tr.chan)
 vp[slot] = pitch
 vo[slot] = gt + scratch.len[i]
 va[slot] = 1
 end
end
function M.flush(tr, out)
 for i = 1, VOICES do
 if tr.va[i] == 1 then
 emit(out, 0, tr.vp[i], 0, tr.chan)
 tr.va[i] = 0
 end
 end
end
return M

end)()
R["engine"]=(function()

local Track = require("track")
local M = { tracks = {}, gt = -1, playing = false }
local OUT_CAP = 64
local SCRATCH_CAP = 64
local function newOut(cap)
 local o = { n = 0, typ = {}, pitch = {}, vel = {}, ch = {} }
 for i = 1, cap do o.typ[i]=0; o.pitch[i]=0; o.vel[i]=0; o.ch[i]=0 end
 return o
end
local function newScratch(cap)
 local s = { n = 0, pitch = {}, len = {}, vel = {} }
 for i = 1, cap do s.pitch[i]=0; s.len[i]=0; s.vel[i]=0 end
 return s
end
function M.init(opts)
 opts = opts or {}
 local n = opts.trackCount or 2
 M.tracks = {}
 for t = 1, n do
 local o = opts.tracks and opts.tracks[t] or {}
 o.chan = o.chan or t
 M.tracks[t] = Track.new(o)
 end
 M.gt = -1
 M.playing = false
 M.out = newOut(OUT_CAP)
 M.scratch = newScratch(SCRATCH_CAP)
 return M
end
function M.onStart()
 M.gt = -1
 for t = 1, #M.tracks do Track.reset(M.tracks[t]) end
 M.out.n = 0
 M.playing = true
end
function M.onPulse()
 if not M.playing then M.out.n = 0; return M.out end
 M.gt = M.gt + 1
 M.out.n = 0
 local scratch, out = M.scratch, M.out
 local tracks = M.tracks
 for t = 1, #tracks do
 Track.advance(tracks[t], M.gt, scratch, out)
 end
 return M.out
end
function M.onStop()
 M.out.n = 0
 for t = 1, #M.tracks do Track.flush(M.tracks[t], M.out) end
 M.playing = false
 return M.out
end
function M.panic()
 M.out.n = 0
 for t = 1, #M.tracks do Track.flush(M.tracks[t], M.out) end
 return M.out
end
return M

end)()
R["generate"]=(function()

local Event = require("event")
local Scales = require("scales")
local M = {}
local function isOnset(i, hits, M_)
 if hits <= 0 then return false end
 if hits >= M_ then return true end
 return (i * hits) // M_ ~= ((i - 1) * hits) // M_
end
function M.run(pattern, opts)
 opts = opts or {}
 local ev = pattern.events
 local M_ = pattern.length
 local tps = pattern.zoom
 local scaleIndex = opts.scaleIndex or 1
 local root = (opts.root or 0) % 12
 local mask = Scales.rotate((Scales.SCALES[scaleIndex] or Scales.SCALES[1]).mask, root)
 local hits = opts.hits or math.max(1, M_ // 4)
 local rotate = (opts.rotate or 0) % M_
 local pRoot = opts.pitchRoot or (57 + root)
 local pSpr = opts.pitchSpread or 4
 local vRoot = opts.velRoot or 100
 local vSpr = opts.velSpread or 20
 local gRoot = opts.gateRoot or tps
 local gSpr = opts.gateSpread or (tps // 2)
 local seed = (opts.seed or 1) & 0xFFFFFFFF
 local function rnd() seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF; return (seed >> 16) & 0x7FFF end
 local function ri(lo, hi) if hi <= lo then return lo end return lo + rnd() % (hi - lo + 1) end
 Event.clear(ev)
 local count = 0
 for i = 0, M_ - 1 do
 if isOnset(i, hits, M_) then
 local s = (i + rotate) % M_
 local pitch = Scales.step(pRoot, mask, ri(-pSpr, pSpr))
 local vel = vRoot + ri(-vSpr, vSpr)
 if vel < 1 then vel = 1 elseif vel > 127 then vel = 127 end
 local gate = gRoot + ri(-gSpr, gSpr)
 if gate < 1 then gate = 1 end
 Event.add(ev, pitch, s * tps, gate, vel)
 count = count + 1
 end
 end
 return count
end
return M

end)()
R["midirx"]=(function()

local Engine = require("engine")
local M = {}
function M.handle(t, send)
 if t == 0xF8 then
 local o = Engine.onPulse()
 for i = 1, o.n do
 if o.typ[i] == 1 then send(o.ch[i], 0x90, o.pitch[i], o.vel[i])
 else send(o.ch[i], 0x80, o.pitch[i], 0) end
 end
 return "tick"
 elseif t == 0xFA then
 Engine.onStart()
 return "start"
 elseif t == 0xFB then
 if not Engine.playing then Engine.onStart() end
 return "start"
 elseif t == 0xFC then
 local o = Engine.onStop()
 for i = 1, o.n do send(o.ch[i], 0x80, o.pitch[i], 0) end
 return "stop"
 end
end
return M

end)()
return {
    engine=R.engine, track=R.track, pattern=R.pattern, rack=R.rack,
    event=R.event, scales=R.scales, generate=R.generate, midirx=R.midirx,
    range=R.range, random=R.random, scalefx=R.scale,
}
