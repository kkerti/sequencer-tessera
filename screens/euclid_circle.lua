-- euclid_circle.lua -- Single-track Euclidean rhythm visualizer.
-- One large circle, N step-slots evenly spaced around it. Filled dots = hits,
-- empty rings = rests. A polygon connects the hits (the iconic Euclidean shape).
-- A radial playhead sweeps with the mocked tick.
--
-- Controls:
--   Encoder         -> k (pulses), 0..n
--   SHIFT+Encoder   -> rotate (offset) the pattern
--   B9 / B10        -> n--, n++  (4..32)
--   B11             -> rotate--  (alt to SHIFT+enc)
--   B12             -> rotate++
--   K0..K3          -> select track 1..4 (color preset)
--   K4              -> toggle pause
--   K5              -> toggle polygon connector
--
-- Pure mock: no engine state, no persistence. Polygon math precomputed each frame
-- (cheap at n<=32) using draw_polygon + draw_line + draw_pixel rings to fake circles
-- (the VSN1 API has no native circle/arc primitive).

-- INIT START
W,H=320,240
n=n or 16
k=k or 5
rot=rot or 0
selT=selT or 1
paused=paused or false
showPoly=(showPoly==nil) and true or showPoly
tick=tick or 0
shift=(uiControlDown[7]==1)

-- handle encoder: edits k (or rot when SHIFT)
if uiLastEventIndex==8 and uiEncoderDelta~=0 then
  if shift then
    rot=(rot+uiEncoderDelta)%n
  else
    k=k+uiEncoderDelta
    if k<0 then k=0 end
    if k>n then k=n end
  end
end

-- n adjust
if uiControlPressed[9]==1 then
  n=n-1
  if n<4 then n=4 end
  if k>n then k=n end
  if rot>=n then rot=0 end
end
if uiControlPressed[10]==1 then
  n=n+1
  if n>32 then n=32 end
end
-- rotation buttons
if uiControlPressed[11]==1 then rot=(rot-1)%n end
if uiControlPressed[12]==1 then rot=(rot+1)%n end

-- track select via keyswitches 0..3
for i=0,3 do
  if uiControlPressed[i]==1 then selT=i+1 end
end
if uiControlPressed[4]==1 then paused=not paused end
if uiControlPressed[5]==1 then showPoly=not showPoly end

print('euclid n='..n..' k='..k..' rot='..rot..' trk='..selT)
-- INIT END

-- LOOP START
BG={14,14,18}
HD={30,30,42}
FG={235,235,240}
DIM={120,120,140}
RING={70,70,84}
HIT_COLORS={
  {80,180,255},   -- track 1 cyan
  {120,220,140},  -- track 2 green
  {250,200,80},   -- track 3 amber
  {240,110,160},  -- track 4 magenta
}
HIT=HIT_COLORS[selT]
PLY={250,90,90}
ACC={80,180,255}
SHIFTC={210,140,80}

if not paused then tick=tick+1 end

ggdrf(0,0,0,W,H,BG)

-- header
ggdrf(0,0,0,W,18,HD)
ggdft(0,'EUCLIDEAN  E('..k..','..n..')',6,5,8,FG)
ggdft(0,'TRK '..selT,150,5,8,HIT)
ggdft(0,'rot '..rot,200,5,8,DIM)
if shift then ggdft(0,'SHIFT',250,5,8,SHIFTC) end
if paused then ggdft(0,'PAUSE',285,5,8,PLY) end

-- circle geometry
local cx,cy=130,128
local R=88        -- main radius (slot centers)
local rDot=8      -- hit dot radius
local rRest=4     -- rest dot radius

-- compute hit table: e[i]=true if step i (1..n) is a hit, with rotation
-- E(k,n) via the integer-bucket method (close to Bjorklund for most params).
local hits={}
local hitX,hitY={},{}
local nHits=0
for i=0,n-1 do
  local idx=(i-rot)%n
  local was=(idx*k)//n
  local now=((idx+1)*k)//n
  hits[i+1]=(now~=was)
end

-- 12 o'clock = step 1, going clockwise. angle = -pi/2 + 2*pi*(i-1)/n
-- Use integer-friendly precomputed sines? Just call math.sin/cos; cheap at n<=32 and
-- this is mock UI only — engine never touches sin/cos.
local TAU=6.2831853
for i=1,n do
  local a=-1.5707963+TAU*(i-1)/n
  local x=cx+math.floor(R*math.cos(a)+0.5)
  local y=cy+math.floor(R*math.sin(a)+0.5)
  -- draw the slot ring as a small filled circle (approx via 4 pixels + plus shape)
  -- VSN1 has no circle primitive; use draw_rectangle_filled as fallback square
  if hits[i] then
    nHits=nHits+1
    hitX[nHits]=x
    hitY[nHits]=y
    -- filled square stand-in for hit dot
    ggdrf(0,x-rDot,y-rDot,x+rDot,y+rDot,HIT)
  else
    -- rest: outline only
    ggdr(0,x-rRest,y-rRest,x+rRest,y+rRest,RING)
  end
end

-- connecting polygon between hits
if showPoly and nHits>=2 then
  -- close the polygon by appending first vertex
  hitX[nHits+1]=hitX[1]
  hitY[nHits+1]=hitY[1]
  for i=1,nHits do
    ggdl(0,hitX[i],hitY[i],hitX[i+1],hitY[i+1],HIT)
  end
end

-- playhead: which step is "now"? scrubs through 1..n
local pStep=((tick//6)%n)+1
do
  local a=-1.5707963+TAU*(pStep-1)/n
  -- radial line from center to slot
  local x2=cx+math.floor((R+12)*math.cos(a)+0.5)
  local y2=cy+math.floor((R+12)*math.sin(a)+0.5)
  ggdl(0,cx,cy,x2,y2,PLY)
  -- small diamond at slot
  local px=cx+math.floor(R*math.cos(a)+0.5)
  local py=cy+math.floor(R*math.sin(a)+0.5)
  ggdpof(0,{px,px+5,px,px-5},{py-5,py,py+5,py},PLY)
end

-- center info
ggdft(0,tostring(k),cx-6,cy-12,16,FG)
ggdft(0,'/'..n,cx-10,cy+6,8,DIM)

-- side panel
local px=240
local py=28
ggdft(0,'PARAMS',px,py,8,DIM)
ggdft(0,'pulses  '..k,px,py+18,8,FG)
ggdft(0,'steps   '..n,px,py+30,8,FG)
ggdft(0,'rotate  '..rot,px,py+42,8,FG)
ggdft(0,'density '..((k*100)//n)..'%',px,py+54,8,FG)

ggdft(0,'PATTERN',px,py+78,8,DIM)
-- print the pattern as . and X (max 16 chars per row)
local row1,row2='',''
for i=1,n do
  local ch=hits[i] and 'X' or '.'
  if i<=16 then row1=row1..ch else row2=row2..ch end
end
ggdft(0,row1,px,py+92,8,HIT)
if #row2>0 then ggdft(0,row2,px,py+104,8,HIT) end

ggdft(0,'now '..pStep,px,py+124,8,PLY)

-- footer
ggdrf(0,0,H-16,W,H,HD)
ggdft(0,'Enc=k SHIFT+Enc=rot B9/10=n B11/12=rot K0-3=trk K4=pause K5=poly',4,H-12,8,DIM)
ggdsw()
-- LOOP END
