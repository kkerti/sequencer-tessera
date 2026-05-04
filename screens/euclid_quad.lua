-- euclid_quad.lua -- Four Euclidean circles, one per track. Overview style.
-- Each track shows a small circle with its own (k,n,rot) and an independent
-- playhead so you can see polyrhythmic relationships between tracks at a glance.
--
-- Controls:
--   B9..B12        -> select track 1..4 (whichever is selected becomes editable)
--   Encoder        -> selected track: k++/--
--   SHIFT+Encoder  -> selected track: n++/--
--   K0             -> selected track: rot--
--   K1             -> selected track: rot++
--   K2             -> selected track: random preset (cycle through musical defaults)
--   K3             -> reset selected track to E(3,8)
--   K4             -> toggle global pause
--   K5             -> toggle polygon connectors
--
-- Mock only. Per-track tick advance speeds differ slightly to fake polyrhythm.

-- INIT START
W,H=320,240
selT=selT or 1
paused=paused or false
showPoly=(showPoly==nil) and true or showPoly
tick=tick or 0
shift=(uiControlDown[7]==1)

-- per-track state: k, n, rot, speed (pulses-per-frame divisor)
trk=trk or {
  {k=3,n=8, rot=0,sp=8},   -- classic tresillo
  {k=5,n=8, rot=0,sp=8},   -- cinquillo
  {k=4,n=16,rot=0,sp=4},   -- four-on-floor on 16
  {k=7,n=12,rot=0,sp=6},   -- 7-against-12
}

-- preset cycle for K2
presets=presets or {
  {3,8},{5,8},{2,5},{3,7},{4,9},{5,12},{7,16},{9,16},{4,11},{5,13},
}
presetIdx=presetIdx or 1

for i=0,3 do
  if uiControlPressed[9+i]==1 then selT=i+1 end
end

-- encoder edits selected track
if uiLastEventIndex==8 and uiEncoderDelta~=0 then
  local t=trk[selT]
  if shift then
    t.n=t.n+uiEncoderDelta
    if t.n<3 then t.n=3 end
    if t.n>32 then t.n=32 end
    if t.k>t.n then t.k=t.n end
    if t.rot>=t.n then t.rot=0 end
  else
    t.k=t.k+uiEncoderDelta
    if t.k<0 then t.k=0 end
    if t.k>t.n then t.k=t.n end
  end
end

if uiControlPressed[0]==1 then trk[selT].rot=(trk[selT].rot-1)%trk[selT].n end
if uiControlPressed[1]==1 then trk[selT].rot=(trk[selT].rot+1)%trk[selT].n end
if uiControlPressed[2]==1 then
  presetIdx=(presetIdx%#presets)+1
  trk[selT].k=presets[presetIdx][1]
  trk[selT].n=presets[presetIdx][2]
  trk[selT].rot=0
end
if uiControlPressed[3]==1 then
  trk[selT].k=3; trk[selT].n=8; trk[selT].rot=0
end
if uiControlPressed[4]==1 then paused=not paused end
if uiControlPressed[5]==1 then showPoly=not showPoly end

print('quad sel='..selT..' E('..trk[selT].k..','..trk[selT].n..')')
-- INIT END

-- LOOP START
BG={14,14,18}
HD={30,30,42}
FG={235,235,240}
DIM={120,120,140}
RING={62,62,76}
COLORS={
  {80,180,255},
  {120,220,140},
  {250,200,80},
  {240,110,160},
}
SEL={255,255,255}
PLY={250,90,90}
SHIFTC={210,140,80}

if not paused then tick=tick+1 end

ggdrf(0,0,0,W,H,BG)
ggdrf(0,0,0,W,18,HD)
ggdft(0,'EUCLIDEAN  4-TRACK',6,5,8,FG)
ggdft(0,'sel TRK '..selT,140,5,8,COLORS[selT])
if shift then ggdft(0,'SHIFT',210,5,8,SHIFTC) end
if paused then ggdft(0,'PAUSE',250,5,8,PLY) end

local TAU=6.2831853

-- 2x2 layout of small circles
local layout={
  {x= 80, y= 78},
  {x=240, y= 78},
  {x= 80, y=170},
  {x=240, y=170},
}
local R=44
local rDot=5
local rRest=2

for ti=1,4 do
  local L=layout[ti]
  local cx,cy=L.x,L.y
  local t=trk[ti]
  local C=COLORS[ti]

  -- selection halo
  if ti==selT then
    ggdr(0,cx-R-10,cy-R-10,cx+R+10,cy+R+10,SEL)
  end

  -- label box
  ggdft(0,'T'..ti,cx-R-6,cy-R-22,8,C)
  ggdft(0,'E('..t.k..','..t.n..')',cx-R+12,cy-R-22,8,FG)
  if t.rot>0 then ggdft(0,'r'..t.rot,cx+R-14,cy-R-22,8,DIM) end

  -- compute and draw slots
  local hitsX,hitsY={},{}
  local nh=0
  for i=0,t.n-1 do
    local idx=(i-t.rot)%t.n
    local was=(idx*t.k)//t.n
    local now=((idx+1)*t.k)//t.n
    local hit=(now~=was)
    local a=-1.5707963+TAU*i/t.n
    local x=cx+math.floor(R*math.cos(a)+0.5)
    local y=cy+math.floor(R*math.sin(a)+0.5)
    if hit then
      nh=nh+1; hitsX[nh]=x; hitsY[nh]=y
      ggdrf(0,x-rDot,y-rDot,x+rDot,y+rDot,C)
    else
      ggdpx(0,x,y,RING)
      ggdpx(0,x+1,y,RING)
      ggdpx(0,x,y+1,RING)
      ggdpx(0,x+1,y+1,RING)
    end
  end

  -- polygon connector
  if showPoly and nh>=2 then
    hitsX[nh+1]=hitsX[1]; hitsY[nh+1]=hitsY[1]
    for i=1,nh do
      ggdl(0,hitsX[i],hitsY[i],hitsX[i+1],hitsY[i+1],C)
    end
  end

  -- per-track playhead (different speed per track for polyrhythm illusion)
  local pStep=((tick//t.sp)%t.n)
  local a=-1.5707963+TAU*pStep/t.n
  local x2=cx+math.floor((R+8)*math.cos(a)+0.5)
  local y2=cy+math.floor((R+8)*math.sin(a)+0.5)
  ggdl(0,cx,cy,x2,y2,PLY)
end

ggdrf(0,0,H-16,W,H,HD)
ggdft(0,'B9-12 sel  Enc=k SHIFT+Enc=n  K0/1=rot K2=preset K3=reset K4=pause K5=poly',4,H-12,8,DIM)
ggdsw()
-- LOOP END
