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

local M = { mode = "PLAY", track = 1, sel = 3 }
local E, S
local NOTE = { "C","C#","D","D#","E","F","F#","G","G#","A","A#","B" }
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi else return v end end
local function noteName(m) return NOTE[m % 12 + 1] .. (m // 12 - 1) end
local function gen(t) return E.tracks[t].gen end
local function defaults(t)
 if t == 1 then
 return { scaleIndex=3, root=9, hits=7, rotate=0, seed=1,
 pitchRoot=60, pitchSpread=6, velRoot=100, velSpread=20, gateRoot=6, gateSpread=3 }
 end
 return { scaleIndex=8, root=9, hits=4, rotate=0, seed=2,
 pitchRoot=40, pitchSpread=4, velRoot=110, velSpread=15, gateRoot=18, gateSpread=6 }
end
local function regen(t)
 local tr = E.tracks[t]
 local g = tr.gen
 local sc = tr.rack.fx[3]
 sc:setScale(g.scaleIndex); sc:setRoot(g.root)
 S.generate.run(tr.pattern, g)
end
M.regen = regen
function M.bind(engine, seq)
 if E then return end
 E, S = engine, seq
 for t = 1, #E.tracks do E.tracks[t].gen = defaults(t); regen(t) end
end
local P = {}
local function add(label, show, edit, noregen) P[#P+1] = { label=label, show=show, edit=edit, regen=not noregen } end
add("SCALE", function() return S.scales.SCALES[gen(M.track).scaleIndex].name end,
 function(d) local g=gen(M.track); g.scaleIndex=clamp(g.scaleIndex+d,1,#S.scales.SCALES) end)
add("KEY", function() return noteName(gen(M.track).root):gsub("%-?%d","") end,
 function(d) local g=gen(M.track); g.root=(g.root+d)%12 end)
add("HITS", function() local g=gen(M.track); return g.hits.." / "..E.tracks[M.track].pattern.length end,
 function(d) local g=gen(M.track); g.hits=clamp(g.hits+d,1,E.tracks[M.track].pattern.length) end)
add("ROTATE", function() return tostring(gen(M.track).rotate) end,
 function(d) local g=gen(M.track); g.rotate=(g.rotate+d)%E.tracks[M.track].pattern.length end)
add("PITCH", function() return noteName(gen(M.track).pitchRoot) end,
 function(d) local g=gen(M.track); g.pitchRoot=clamp(g.pitchRoot+d,24,96) end)
add("SPREAD", function() return gen(M.track).pitchSpread.." deg" end,
 function(d) local g=gen(M.track); g.pitchSpread=clamp(g.pitchSpread+d,0,12) end)
add("VEL", function() return tostring(gen(M.track).velRoot) end,
 function(d) local g=gen(M.track); g.velRoot=clamp(g.velRoot+d,1,127) end)
add("GATE", function() return gen(M.track).gateRoot.."t" end,
 function(d) local g=gen(M.track); g.gateRoot=clamp(g.gateRoot+d,1,48) end)
add("SEED", function() return tostring(gen(M.track).seed) end,
 function(d) local g=gen(M.track); g.seed=math.max(1,g.seed+d) end)
add("LENGTH", function() return E.tracks[M.track].pattern.length.." st" end,
 function(d) local p=E.tracks[M.track].pattern; p.length=clamp(p.length+d,1,64); local g=gen(M.track); g.hits=clamp(g.hits,1,p.length) end)
add("ZOOM", function() return "z"..E.tracks[M.track].pattern.zoom end,
 function(d) local z=S.pattern.ZOOM; local p=E.tracks[M.track].pattern; local i=1 for k,v in ipairs(z) do if v.tps==p.zoom then i=k end end p.zoom=z[clamp(i+d,1,#z)].tps end)
add("CHANCE", function() return E.tracks[M.track].rack.fx[2].chance.."%" end,
 function(d) local r=E.tracks[M.track].rack.fx[2]; r.chance=clamp(r.chance+d,0,100) end, true)
add("TRACK", function() return M.track.." / "..#E.tracks end,
 function(d) M.track=clamp(M.track+d,1,#E.tracks) end, true)
M.params = P
local STEP = { [7] = 4, [12] = 5, [8] = 2 }
local KSEL = { [0]=3, [1]=2, [2]=1, [3]=6, [4]=7, [5]=12 }
function M.reroll()
 local g = gen(M.track); g.seed = g.seed + 1; regen(M.track)
end
local function toggleTrack() M.track = M.track % #E.tracks + 1 end
function M.turn(d)
 local p = P[M.sel]; if not p then return end
 p.edit((d > 0 and 1 or -1) * (STEP[M.sel] or 1))
 if p.regen then regen(M.track) end
end
function M.click(down) if down then M.reroll() end end
function M.key(n, down)
 if not down then return end
 if n == 7 then M.mode = (M.mode == "PLAY") and "SETUP" or "PLAY"; return end
 if n == 6 then toggleTrack(); return end
 if M.mode == "SETUP" then
 if n == 0 then M.sel = (M.sel - 2) % #P + 1
 elseif n == 1 then M.sel = M.sel % #P + 1
 elseif n == 5 then M.reroll() end
 elseif KSEL[n] then
 M.sel = KSEL[n]
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
local WHITE= {235, 235, 235}
local BLACK= {0, 0, 0}
local ORANGE = {249, 150, 0}
local DIMOR = {150, 95, 20}
local CYAN = {0, 200, 220}
local PLO, PHI = 40, 84
local function roll(scr, tr, y0h)
 local pat = tr.pattern
 local ev = pat.events
 local loop = Pattern.loopTicks(pat)
 local ph = (tr._gt or 0) % loop
 local rowH = (y0h - 4) / (PHI - PLO)
 local on = 0
 for i = 1, ev.n do
 local s, l, p = ev.start[i], ev.len[i], ev.pitch[i]
 local x1 = 2 + s / loop * 316
 local x2 = 2 + (s + l) / loop * 316
 if x2 - x1 < 2 then x2 = x1 + 2 end
 local y = (y0h - 2) - (p - PLO) * rowH
 local act = (ph >= s and ph < s + l)
 if act then on = on + 1 end
 scr:draw_rectangle_filled(x1, y - rowH / 2, x2, y + rowH / 2, act and ORANGE or DIMOR)
 end
 scr:draw_line(2 + ph / loop * 316, 0, 2 + ph / loop * 316, y0h - 1, CYAN)
 return on, ph, loop
end
local function drawPlay(scr, eng, ctl)
 local t = ctl and ctl.track or 1
 local tr = eng.tracks[t]
 tr._gt = (eng.gt < 0 and 0 or eng.gt)
 scr:draw_rectangle_filled(0, 0, 319, 239, BG)
 local on, ph, loop = roll(scr, tr, 120)
 scr:draw_line(0, 120, 319, 120, DIM)
 scr:draw_text_fast("T" .. t, 8, 128, 16, WHITE)
 scr:draw_text_fast(eng.playing and "PLAY" or "STOP", 232, 128, 16, eng.playing and ORANGE or DIM)
 local p = ctl and ctl.params and ctl.params[ctl.sel]
 if p then
 scr:draw_text_fast(p.label, 8, 156, 16, GREY)
 scr:draw_text_fast(p.show(), 8, 178, 24, ORANGE)
 end
 scr:draw_text_fast("KS0-5 PICK KS6 TRACK KS7 SETUP", 8, 224, 8, DIM)
 scr:draw_swap()
end
local function drawSetup(scr, eng, ctl)
 scr:draw_rectangle_filled(0, 0, 319, 239, BG)
 scr:draw_text_fast("PATTERN SETUP", 8, 6, 16, ORANGE)
 scr:draw_text_fast("T" .. ctl.track, 284, 6, 16, WHITE)
 scr:draw_line(0, 26, 319, 26, DIM)
 local rows = #ctl.params
 local leftN = math.ceil(rows / 2)
 for i = 1, rows do
 local left = (i <= leftN)
 local x = left and 16 or 176
 local row = left and (i - 1) or (i - leftN - 1)
 local y = 32 + row * 26
 local sel = (i == ctl.sel)
 if sel then scr:draw_text_fast(">", x - 12, y, 16, WHITE) end
 scr:draw_text_fast(ctl.params[i].label, x, y, 16, sel and WHITE or GREY)
 scr:draw_text_fast(ctl.params[i].show(), x + 84, y, 16, sel and WHITE or ORANGE)
 end
 scr:draw_line(0, 214, 319, 214, DIM)
 scr:draw_text_fast("ENC edit KS0/1 nav KS5 reroll KS6 track KS7 exit", 6, 224, 8, GREY)
 scr:draw_swap()
end
function M.draw(scr, eng, ctl)
 if ctl and ctl.mode == "SETUP" then drawSetup(scr, eng, ctl)
 else drawPlay(scr, eng, ctl) end
end
return M

end)()
return { draw=R.draw.draw, control=R.control }
