-- dist/seq2_ui.lua (screen; auto-generated)
local R={}
local _host=require
local _seq
local function require(n)
    local r=R[n] if r~=nil then return r end
    if not _seq then _seq=_host("seq2") end
    return _seq[n]
end
R["control"]=(function()

local M = { mode = "PLAY", track = 1, sel = 1, shift = false, setup = false,
 step = 0, field = 1, seqPage = "SLOT", seqTrack = 1, songCur = 1 }
local E, S
local NOTE = { "C","C#","D","D#","E","F","F#","G","G#","A","A#","B" }
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi else return v end end
local function noteName(m) return NOTE[m % 12 + 1] .. (m // 12 - 1) end
local function Tr(t) return E.tracks[t] end
local function Sg(t) return E.tracks[t].staged end
local DEFAULTS = {
 { scaleIndex=3, root=9, hits=7, rotate=0, seed=1,
 pitchRoot=60, pitchSpread=6, velRoot=100, velSpread=20, gateRoot=6, gateSpread=3 },
 { scaleIndex=8, root=9, hits=4, rotate=0, seed=2,
 pitchRoot=40, pitchSpread=4, velRoot=110, velSpread=15, gateRoot=18, gateSpread=6 },
}
local function defaults(t)
 local d = DEFAULTS[((t - 1) % 2) + 1]
 local c = {}
 for k, v in pairs(d) do c[k] = v end
 c.seed = t
 return c
end
local function initStaged(t)
 local tr = E.tracks[t]
 local s = {}
 for k, v in pairs(tr.gen) do s[k] = v end
 s.length = tr.pattern.length
 s.zoom = tr.pattern.zoom
 tr.staged = s
 tr.dirty = false
end
local function regen(t)
 local tr = E.tracks[t]
 local g = tr.gen
 local sc = tr.rack.fx[3]
 sc:setScale(g.scaleIndex); sc:setRoot(g.root)
 S.generate.run(tr.pattern, g)
end
local function commit(t)
 local tr = E.tracks[t]
 local s = tr.staged
 local g = tr.gen
 tr.pattern.length = clamp(s.length, 1, 64)
 tr.pattern.zoom = s.zoom
 for k, v in pairs(s) do
 if k ~= "length" and k ~= "zoom" then g[k] = v end
 end
 g.hits = clamp(g.hits, 1, tr.pattern.length)
 regen(t)
 tr.dirty = false
end
M.commit = commit
local function reroll(t)
 local g = E.tracks[t].gen
 g.seed = g.seed + 1
 E.tracks[t].staged.seed = g.seed
 regen(t)
end
M.reroll = function() reroll(M.track) end
function M.bind(engine, seq)
 if E then return end
 E, S = engine, seq
 for t = 1, #E.tracks do
 E.tracks[t].gen = defaults(t)
 initStaged(t)
 regen(t)
 end
end
function M.frame()
 if not E then return end
 for t = 1, #E.tracks do
 local tr = E.tracks[t]
 if tr.auto.due then
 tr.auto.due = false
 reroll(t)
 end
 end
end
local P = {}
local function add(label, show, edit) P[#P + 1] = { label = label, show = show, edit = edit } end
local function dirty(t) E.tracks[t].dirty = true end
local function sNum(key, lo, hi)
 return function(d)
 local s = Sg(M.track)
 s[key] = clamp(s[key] + d, lo, hi)
 dirty(M.track)
 end
end
add("SCALE", function() return S.scales.SCALES[Sg(M.track).scaleIndex].name end,
 function(d) local s = Sg(M.track); s.scaleIndex = clamp(s.scaleIndex + d, 1, #S.scales.SCALES); dirty(M.track) end)
add("KEY", function() return noteName(Sg(M.track).root):gsub("%-?%d", "") end,
 function(d) local s = Sg(M.track); s.root = (s.root + d) % 12; dirty(M.track) end)
add("HITS", function() local s = Sg(M.track); return s.hits .. " / " .. s.length end,
 function(d) local s = Sg(M.track); s.hits = clamp(s.hits + d, 1, s.length); dirty(M.track) end)
add("ROTATE", function() return tostring(Sg(M.track).rotate) end,
 function(d) local s = Sg(M.track); s.rotate = (s.rotate + d) % s.length; dirty(M.track) end)
add("PITCH", function() return noteName(Sg(M.track).pitchRoot) end,
 sNum("pitchRoot", 24, 96))
add("SPREAD", function() return Sg(M.track).pitchSpread .. " deg" end,
 sNum("pitchSpread", 0, 12))
add("VEL", function() return tostring(Sg(M.track).velRoot) end,
 sNum("velRoot", 1, 127))
add("GATE", function() return Sg(M.track).gateRoot .. "t" end,
 sNum("gateRoot", 1, 48))
add("SEED", function() return tostring(Sg(M.track).seed) end,
 function(d) local s = Sg(M.track); s.seed = math.max(1, s.seed + d); dirty(M.track) end)
add("LENGTH", function() return Sg(M.track).length .. " st" end,
 function(d) local s = Sg(M.track); s.length = clamp(s.length + d, 1, 64); s.hits = clamp(s.hits, 1, s.length); dirty(M.track) end)
add("ZOOM", function() return "z" .. Sg(M.track).zoom end,
 function(d) local z = S.pattern.ZOOM; local s = Sg(M.track); local i = 1
 for k, v in ipairs(z) do if v.tps == s.zoom then i = k end end
 s.zoom = z[clamp(i + d, 1, #z)].tps; dirty(M.track) end)
add("CHANCE", function() return Tr(M.track).rack.fx[2].chance .. "%" end,
 function(d) local r = Tr(M.track).rack.fx[2]; r.chance = clamp(r.chance + d, 0, 100) end)
M.params = P
local COARSE = { [7] = 5, [8] = 2, [12] = 5 }
local PLAY_SEL = { [1] = 3, [2] = 2, [3] = 1, [4] = 6, [5] = 7 }
local function nextTrack(dir)
 local n = #E.tracks
 M.track = ((M.track - 1 + dir) % n) + 1
 local len = E.tracks[M.track].pattern.length
 if M.step < 0 or M.step >= len then M.step = 0 end
end
local function nextMode()
 if M.mode == "PLAY" then
 M.mode = "STEP"; M.setup = false
 local len = E.tracks[M.track].pattern.length
 if M.step < 0 or M.step >= len then M.step = 0 end
 elseif M.mode == "STEP" then M.mode = "SEQ"
 else M.mode = "PLAY" end
end
local function emitOut()
 if gms and E.out.n > 0 then S.midirx.emit(E.out, gms) end
end
local function toggleNap(t)
 local tr = E.tracks[t]
 if tr.nap.armed then S.track.disarmNap(tr) else S.track.armNap(tr, 2, 2) end
end
local function toggleAuto(t)
 local tr = E.tracks[t]
 if tr.auto.armed then S.track.disarmAuto(tr) else S.track.armAuto(tr, 2) end
end
local function addAtStep(t, step)
 local pat = E.tracks[t].pattern
 if step < 0 or step >= pat.length then return end
 if S.pattern.findEventAtStep(pat, step, pat.zoom) then return end
 S.event.add(pat.events, 60, step * pat.zoom, pat.zoom, 100)
end
local function deleteAtStep(t, step)
 local pat = E.tracks[t].pattern
 while true do
 local i = S.pattern.findEventAtStep(pat, step, pat.zoom)
 if not i then break end
 S.event.removeAt(pat.events, i)
 end
end
local function editAtStep(t, step, field, dir)
 local pat = E.tracks[t].pattern
 local tick = step * pat.zoom
 local ev = pat.events
 for i = 1, ev.n do
 if ev.start[i] == tick then
 if field == 1 then ev.pitch[i] = clamp(ev.pitch[i] + dir, 0, 127)
 elseif field == 2 then ev.len[i] = math.max(1, ev.len[i] + dir * pat.zoom)
 else ev.vel[i] = clamp(ev.vel[i] + dir * 5, 1, 127) end
 end
 end
end
local function octaveAtStep(t, step, d)
 local pat = E.tracks[t].pattern
 local tick = step * pat.zoom
 local ev = pat.events
 for i = 1, ev.n do
 if ev.start[i] == tick then ev.pitch[i] = clamp(ev.pitch[i] + d, 0, 127) end
 end
end
function M.turn(d)
 if not E then return end
 local s = (d > 0 and 1 or -1)
 if M.mode == "PLAY" then
 local p = P[M.sel]; if not p then return end
 p.edit(s * (COARSE[M.sel] or 1))
 elseif M.mode == "STEP" then
 local len = E.tracks[M.track].pattern.length
 M.step = clamp(M.step + s, 0, len - 1)
 elseif M.seqPage == "SLOT" then
 local seq = E.sequences[E.currentSeq]
 local t = M.seqTrack
 seq.slot[t] = clamp(seq.slot[t] + s, 1, E.tracks[t].nSlots)
 E.setSequence(E.currentSeq); emitOut()
 else
 local n = #E.song.steps
 if n > 0 then M.songCur = ((M.songCur - 1 + s) % n) + 1 end
 end
end
function M.click(down)
 if not down or not E then return end
 if M.mode == "PLAY" then
 reroll(M.track)
 elseif M.mode == "STEP" then
 M.field = M.field % 3 + 1
 elseif M.seqPage == "SLOT" then
 local n = #E.sequences
 E.setSequence((E.currentSeq % n) + 1); emitOut()
 else
 local steps = E.song.steps
 if #steps > 0 then
 M.songCur = clamp(M.songCur, 1, #steps)
 E.setSequence(steps[M.songCur]); emitOut()
 end
 end
end
function M.key(n, down)
 if not down or not E then return end
 if n == 0 then M.shift = not M.shift; return end
 if n == 7 then nextMode(); return end
 local sh = M.shift
 if M.mode == "PLAY" then
 if M.setup then
 if sh then
 if n == 1 then commit(M.track)
 elseif n == 4 then M.setup = false end
 else
 if n == 1 then M.sel = (M.sel - 2) % #P + 1
 elseif n == 2 then M.sel = M.sel % #P + 1
 elseif n == 6 then nextTrack(1) end
 end
 else
 if sh then
 if n == 1 then commit(M.track)
 elseif n == 2 then toggleNap(M.track)
 elseif n == 3 then toggleAuto(M.track)
 elseif n == 4 then M.setup = true
 elseif n == 6 then nextTrack(-1) end
 else
 if PLAY_SEL[n] then M.sel = PLAY_SEL[n] end
 if n == 6 then nextTrack(1) end
 end
 end
 elseif M.mode == "STEP" then
 if sh then
 if n == 1 then deleteAtStep(M.track, M.step) end
 else
 if n == 1 then addAtStep(M.track, M.step)
 elseif n == 2 then octaveAtStep(M.track, M.step, -12)
 elseif n == 3 then octaveAtStep(M.track, M.step, 12)
 elseif n == 4 then editAtStep(M.track, M.step, M.field, -1)
 elseif n == 5 then editAtStep(M.track, M.step, M.field, 1)
 elseif n == 6 then nextTrack(1) end
 end
 else
 if M.seqPage == "SLOT" then
 if n >= 1 and n <= 4 then M.seqTrack = n end
 if n == 5 then M.seqPage = "SONG"; M.songCur = 1 end
 if n == 6 then
 local seq = E.sequences[E.currentSeq]
 E.setTrackMute(M.seqTrack, not seq.mute[M.seqTrack]); emitOut()
 end
 else
 if n == 1 then E.songAdd(E.currentSeq) end
 if n == 2 then
 local nsteps = #E.song.steps
 if nsteps > 0 then
 E.songRemoveAt(M.songCur)
 if M.songCur > #E.song.steps then M.songCur = #E.song.steps end
 if M.songCur < 1 then M.songCur = 1 end
 end
 end
 if n == 5 then M.seqPage = "SLOT" end
 if n == 6 then E.songClear(); M.songCur = 1 end
 end
 end
end
return M

end)()
R["draw"]=(function()

local Pattern = require("pattern")
local M = {}
local BG = {12, 12, 16}
local DIM = {60, 60, 60}
local GREY = {130, 130, 130}
local WHITE = {235, 235, 235}
local ORANGE = {249, 150, 0}
local DIMOR = {150, 95, 20}
local CYAN = {0, 200, 220}
local GREEN = {90, 220, 120}
local PLO, PHI = 40, 84
local NOTE = { "C","C#","D","D#","E","F","F#","G","G#","A","A#","B" }
local function noteName(m) return NOTE[m % 12 + 1] .. (m // 12 - 1) end
local function localTickOf(pat, gt)
 if gt < 0 then return 0 end
 local s0, loopLen = Pattern.loopWindow(pat)
 if gt < s0 then return 0 end
 return s0 + (gt - s0) % loopLen
end
local function roll(scr, tr, gt, cursorStep)
 local pat = tr.pattern
 local ev = pat.events
 local full = Pattern.loopTicks(pat)
 local lt = localTickOf(pat, gt)
 local rowH = 116 / (PHI - PLO)
 for i = 1, ev.n do
 local s, l, p = ev.start[i], ev.len[i], ev.pitch[i]
 local x1 = 2 + s / full * 316
 local x2 = 2 + (s + l) / full * 316
 if x2 - x1 < 2 then x2 = x1 + 2 end
 local y = 118 - (p - PLO) * rowH
 local act = (lt >= s and lt < s + l)
 scr:draw_rectangle_filled(x1, y - rowH / 2, x2, y + rowH / 2, act and ORANGE or DIMOR)
 end
 local px = 2 + lt / full * 316
 scr:draw_line(px, 0, px, 119, CYAN)
 local le = pat.loopEnd or pat.length
 if le < pat.length then
 local xa = 2 + (pat.loopStart or 0) * pat.zoom / full * 316
 local xb = 2 + le * pat.zoom / full * 316
 scr:draw_line(xa, 0, xa, 119, GREY)
 scr:draw_line(xb, 0, xb, 119, GREY)
 end
 if cursorStep then
 local cx = 2 + cursorStep / pat.length * 316
 scr:draw_line(cx, 0, cx, 119, WHITE)
 end
 return lt
end
local function drawPlay(scr, eng, ctl)
 local t = ctl.track
 local tr = eng.tracks[t]
 scr:draw_rectangle_filled(0, 0, 319, 239, BG)
 roll(scr, tr, eng.gt)
 scr:draw_line(0, 120, 319, 120, DIM)
 scr:draw_text_fast("PLAY", 8, 126, 16, ORANGE)
 scr:draw_text_fast("T" .. t, 62, 126, 16, WHITE)
 scr:draw_text_fast("SEQ" .. eng.currentSeq .. "/" .. #eng.sequences, 98, 130, 12, GREY)
 scr:draw_text_fast(eng.playing and "RUN" or "STOP", 260, 126, 16, eng.playing and ORANGE or DIM)
 local p = ctl.params[ctl.sel]
 if p then
 local val = p.show()
 if tr.dirty then val = val .. " *" end
 scr:draw_text_fast(p.label, 8, 150, 16, GREY)
 scr:draw_text_fast(val, 8, 174, 24, tr.dirty and ORANGE or WHITE)
 end
 local flags = ""
 if tr.nap.armed then flags = flags .. (tr.nap.muted and "NAP!" or "nap") .. " " end
 if tr.auto.armed then flags = flags .. "auto " end
 if ctl.shift then flags = flags .. "SHIFT" end
 if flags ~= "" then scr:draw_text_fast(flags, 8, 214, 8, GREEN) end
 scr:draw_text_fast("S+1 COMMIT S+2 NAP S+3 AUTO S+4 SETUP KS7 MODE", 6, 228, 8, DIM)
 scr:draw_swap()
end
local function drawSetup(scr, eng, ctl)
 scr:draw_rectangle_filled(0, 0, 319, 239, BG)
 scr:draw_text_fast("SETUP (S+4 exit)", 8, 6, 16, ORANGE)
 scr:draw_text_fast("T" .. ctl.track, 284, 6, 16, WHITE)
 if eng.tracks[ctl.track].dirty then scr:draw_text_fast("*", 196, 6, 16, ORANGE) end
 scr:draw_line(0, 26, 319, 26, DIM)
 local rows = #ctl.params
 local leftN = math.ceil(rows / 2)
 for i = 1, rows do
 local left = (i <= leftN)
 local x = left and 16 or 172
 local row = left and (i - 1) or (i - leftN - 1)
 local y = 32 + row * 26
 local sel = (i == ctl.sel)
 if sel then scr:draw_text_fast(">", x - 12, y, 16, WHITE) end
 scr:draw_text_fast(ctl.params[i].label, x, y, 16, sel and WHITE or GREY)
 scr:draw_text_fast(ctl.params[i].show(), x + 82, y, 16, sel and ORANGE or WHITE)
 end
 scr:draw_line(0, 214, 319, 214, DIM)
 scr:draw_text_fast("S+1 COMMIT KS1/2 NAV KS6 TRK KS7 MODE", 6, 224, 8, GREY)
 scr:draw_swap()
end
local FIELD = { "PITCH", "LEN", "VEL" }
local function drawStep(scr, eng, ctl)
 local t = ctl.track
 local tr = eng.tracks[t]
 scr:draw_rectangle_filled(0, 0, 319, 239, BG)
 roll(scr, tr, eng.gt, ctl.step)
 scr:draw_line(0, 120, 319, 120, DIM)
 scr:draw_text_fast("STEP", 8, 126, 16, ORANGE)
 scr:draw_text_fast("T" .. t, 60, 126, 16, WHITE)
 scr:draw_text_fast("st " .. (ctl.step + 1), 98, 130, 12, GREY)
 local pat = tr.pattern
 local ev = pat.events
 local tick = ctl.step * pat.zoom
 local pitch, len, vel, found
 for i = 1, ev.n do
 if ev.start[i] == tick then
 pitch, len, vel, found = ev.pitch[i], ev.len[i], ev.vel[i], true
 break
 end
 end
 scr:draw_text_fast(FIELD[ctl.field], 8, 150, 16, GREY)
 local val = "-"
 if found then
 if ctl.field == 1 then val = noteName(pitch)
 elseif ctl.field == 2 then val = len .. "t"
 else val = tostring(vel) end
 end
 scr:draw_text_fast(val, 8, 174, 24, WHITE)
 scr:draw_text_fast("KS1 ADD S+1 DEL KS2/3 OCT KS4/5 EDIT KS6 TRK", 6, 228, 8, DIM)
 scr:draw_swap()
end
local function drawSeqSlot(scr, eng, ctl)
 local t = ctl.track
 scr:draw_rectangle_filled(0, 0, 319, 239, BG)
 roll(scr, eng.tracks[t], eng.gt)
 scr:draw_line(0, 120, 319, 120, DIM)
 scr:draw_text_fast("SEQ", 8, 126, 16, ORANGE)
 scr:draw_text_fast("SLOT", 52, 130, 12, GREY)
 scr:draw_text_fast(eng.currentSeq .. "/" .. #eng.sequences, 100, 126, 16, WHITE)
 local seq = eng.sequences[eng.currentSeq]
 for k = 1, #eng.tracks do
 local x = 8 + (k - 1) * 78
 local sel = (k == ctl.seqTrack)
 local label = "T" .. k .. ":P" .. seq.slot[k] .. (seq.mute[k] and "m" or "")
 scr:draw_text_fast(label, x, 156, 16, sel and ORANGE or WHITE)
 end
 scr:draw_text_fast("KS1-4 TRK KS5 SONG KS6 MUTE", 6, 190, 8, DIM)
 scr:draw_text_fast("enc SLOT click NEXT SEQ KS7 MODE", 6, 202, 8, DIM)
 scr:draw_swap()
end
local function drawSeqSong(scr, eng, ctl)
 local t = ctl.track
 scr:draw_rectangle_filled(0, 0, 319, 239, BG)
 roll(scr, eng.tracks[t], eng.gt)
 scr:draw_line(0, 120, 319, 120, DIM)
 scr:draw_text_fast("SEQ", 8, 126, 16, ORANGE)
 scr:draw_text_fast("SONG", 52, 130, 12, GREY)
 scr:draw_text_fast("sync " .. eng.song.syncBars .. " bar", 102, 130, 12, GREY)
 local steps = eng.song.steps
 if #steps == 0 then
 scr:draw_text_fast("(empty)", 8, 156, 16, DIM)
 else
 local s = ""
 for i = 1, #steps do
 if i == ctl.songCur then s = s .. "[" .. steps[i] .. "] " else s = s .. steps[i] .. " " end
 end
 scr:draw_text_fast(s, 8, 156, 16, WHITE)
 end
 scr:draw_text_fast("KS1 ADD KS2 DEL KS6 CLEAR", 6, 190, 8, DIM)
 scr:draw_text_fast("enc CURSOR click JUMP KS5 SLOT KS7 MODE", 6, 202, 8, DIM)
 scr:draw_swap()
end
function M.draw(scr, eng, ctl)
 if not ctl then return end
 if ctl.frame then ctl.frame() end
 if ctl.mode == "PLAY" then
 if ctl.setup then drawSetup(scr, eng, ctl) else drawPlay(scr, eng, ctl) end
 elseif ctl.mode == "STEP" then
 drawStep(scr, eng, ctl)
 else
 if ctl.seqPage == "SLOT" then drawSeqSlot(scr, eng, ctl) else drawSeqSong(scr, eng, ctl) end
 end
end
return M

end)()
return { draw=R.draw.draw, control=R.control }
