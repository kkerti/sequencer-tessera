-- seq2_screen.lua -- sequencer-2 VSN1 screen, for the grid-wasm harness.
--
-- Flat Grid screen script (no require, global state, ggd* primitives) so it
-- runs on the real Grid VM. Two panes: top = piano roll + playhead + ghosted
-- 2nd track; bottom = mode tabs + status + params. The encoder (sliderValue
-- 0..255) sweeps the playhead so a screenshot at any slider value shows the
-- notes lighting as the head crosses them.
--
-- Render (from grid-wasm/, with `python3 -m http.server 8080` in the parent):
--   node screenshot.mjs ../sequencer-2/screens/seq2_screen.lua 128 shot.png

-- INIT START
W,H=320,240
BG={12,12,16} DIM={60,60,60} GREY={130,130,130} WHITE={235,235,235}
ORANGE={249,150,0} DIMOR={150,95,20} CYAN={0,200,220} GHOST={40,40,46} BLACK={0,0,0}
LOOPT=96 PLO=43 PHI=74
-- track 1 (selected): A-minor melody + triad on beat 1
T1P={57,60,64,67,71,60,64} T1S={0,0,0,18,36,54,72} T1L={18,18,18,12,12,12,18} N1=7
-- track 2 (ghost): pentatonic bass, quarter notes
T2P={45,52,45,52} T2S={0,24,48,72} T2L={24,24,24,24} N2=4
print('seq2 screen init')
-- INIT END

-- LOOP START
ggdrf(0,0,0,W,H,BG)
local rowH=116/(PHI-PLO)
local ph=math.floor((sliderValue or 0)/255*LOOPT)

-- ghost track 2
for i=1,N2 do
  local x1=2+T2S[i]/LOOPT*316
  local x2=2+(T2S[i]+T2L[i])/LOOPT*316
  local y=118-(T2P[i]-PLO)*rowH
  ggdrf(0,x1,y-rowH/2,x2,y+rowH/2,GHOST)
end
-- selected track 1
for i=1,N1 do
  local s,l,p=T1S[i],T1L[i],T1P[i]
  local x1=2+s/LOOPT*316
  local x2=2+(s+l)/LOOPT*316
  if x2-x1<2 then x2=x1+2 end
  local y=118-(p-PLO)*rowH
  local act=(ph>=s and ph<s+l)
  ggdrf(0,x1,y-rowH/2,x2,y+rowH/2,act and ORANGE or DIMOR)
end
-- playhead
local px=2+ph/LOOPT*316
ggdl(0,px,0,px,119,CYAN)

-- bottom pane
ggdl(0,0,120,W,120,DIM)
ggdrf(0,4,126,44,142,ORANGE)
ggdft(0,'STEP',8,128,8,BLACK)
ggdft(0,'FX',54,128,8,GREY)
ggdft(0,'TRACK',80,128,8,GREY)
ggdft(0,'T1 ch1 Amin 120 PLAY',150,128,8,WHITE)

local cnt=0
for i=1,N1 do if ph>=T1S[i] and ph<T1S[i]+T1L[i] then cnt=cnt+1 end end
ggdft(0,'PLAYHEAD',8,156,8,GREY)
ggdft(0,ph..' / '..LOOPT,170,156,8,ORANGE)
ggdft(0,'NOTES ON',8,174,8,GREY)
ggdft(0,tostring(cnt),170,174,8,ORANGE)
ggdft(0,'SCALE',8,192,8,GREY)
ggdft(0,'A minor',170,192,8,ORANGE)

ggdsw()
-- LOOP END
