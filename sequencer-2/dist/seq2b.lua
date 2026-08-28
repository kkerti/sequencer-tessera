-- dist/seq2b.lua (Core runtime: engine+midi_rx; auto-generated)
local R={}
local _host=require
local _1
local function require(n)
 local r=R[n] if r~=nil then return r end
 if not _1 then _1=_host("seq2") end local m=_1[n] if m then return m end
 error('seq2 module not found: '..tostring(n))
end
R["sequence"]=(function()

local M = {}
function M.new(trackCount, slot)
 trackCount = trackCount or 4
 slot = slot or 1
 local s = { slot = {}, mute = {} }
 for t = 1, trackCount do
 s.slot[t] = slot
 s.mute[t] = false
 end
 return s
end
function M.newSong()
 return { steps = {}, syncBars = 1, pos = 1 }
end
return M

end)()
R["engine"]=(function()

local Track = require("track")
local Sequence = require("sequence")
local M = { tracks = {}, gt = -1, playing = false,
 sequences = {}, currentSeq = 1, song = { steps = {}, syncBars = 1, pos = 1 } }
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
 local n = opts.trackCount or 4
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
 local nSeq = opts.sequences or 4
 M.sequences = {}
 for k = 1, nSeq do
 M.sequences[k] = Sequence.new(n, k)
 end
 M.currentSeq = 1
 M.song = Sequence.newSong()
 for t = 1, n do M.tracks[t].seqMute = M.sequences[1].mute[t] end
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
function M.setSequence(id)
 local seq = M.sequences[id]
 if not seq then return M.out end
 M.out.n = 0
 for t = 1, #M.tracks do
 local tr = M.tracks[t]
 local slot = seq.slot[t]
 local mute = seq.mute[t]
 if slot ~= tr.activeSlot or mute ~= tr.seqMute then
 Track.flush(tr, M.out)
 if slot ~= tr.activeSlot then
 Track.setActiveSlot(tr, slot)
 end
 tr.seqMute = mute
 end
 end
 M.currentSeq = id
 return M.out
end
function M.setTrackMute(track, muted)
 local seq = M.sequences[M.currentSeq]
 if not seq or track < 1 or track > #M.tracks then
 return M.out
 end
 M.out.n = 0
 seq.mute[track] = muted and true or false
 M.tracks[track].seqMute = seq.mute[track]
 if seq.mute[track] then
 Track.flush(M.tracks[track], M.out)
 end
 return M.out
end
function M.songAdd(seqId)
 M.song.steps[#M.song.steps + 1] = seqId
end
function M.songClear()
 M.song.steps = {}
 M.song.pos = 1
end
function M.songRemoveAt(pos)
 local steps = M.song.steps
 if pos < 1 or pos > #steps then return end
 table.remove(steps, pos)
 if M.song.pos > #steps then M.song.pos = #steps end
 if M.song.pos < 1 then M.song.pos = 1 end
end
function M.songAdvance()
 local steps = M.song.steps
 if #steps == 0 then return M.out end
 M.song.pos = M.song.pos + 1
 if M.song.pos > #steps then M.song.pos = 1 end
 return M.setSequence(steps[M.song.pos])
end
return M

end)()
R["midirx"]=(function()

local Engine = require("engine")
local M = {}
function M.emit(out, send)
 for i = 1, out.n do
 if out.typ[i] == 1 then send(out.ch[i], 0x90, out.pitch[i], out.vel[i])
 else send(out.ch[i], 0x80, out.pitch[i], 0) end
 end
end
function M.handle(t, send)
 if t == 0xF8 then
 local o = Engine.onPulse()
 M.emit(o, send)
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
return { engine=R.engine, midirx=R.midirx, sequence=R.sequence }
