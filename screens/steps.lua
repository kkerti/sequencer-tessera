-- steps.lua -- 16-step region view (one of 4 regions in a 64-step track).
-- Endless turn  -> move selected step (1..16 within active region).
-- Endless click (btn 8 in our harness ~ none; use small btn 12) -> toggle mute.
-- Small btns 9-12 -> select track 1..4.
-- Keyswitch 7 (SHIFT) + small btn -> queue region.
-- Keyswitches 0..3 -> jump active region 1..4 (debug shortcut).
-- Mocked playhead advances every loop tick.

-- INIT START
W,H=320,240
selT=selT or 1
selS=selS or 1
actR=actR or 1
queR=queR or 0
play=play or 1
tick=tick or 0
-- mock track contents: per (track,step) packed flags 0=off 1=on 2=accent 3=ratch
trk=trk or {}
if not trk[1] then
  for t=1,4 do
    trk[t]={}
    for s=1,64 do trk[t][s]=((s+t)%4==0) and 2 or ((s%2==0) and 1 or 0) end
  end
end
-- shift state from key 7
shift=(uiControlDown[7]==1)
-- handle inputs (run only on this load)
if uiLastEventIndex==8 and uiEncoderDelta~=0 then
  selS=selS+uiEncoderDelta
  if selS<1 then selS=1 end
  if selS>16 then selS=16 end
end
if uiControlPressed[9]==1 then
  if shift then queR=1 else selT=1 end
end
if uiControlPressed[10]==1 then
  if shift then queR=2 else selT=2 end
end
if uiControlPressed[11]==1 then
  if shift then queR=3 else selT=3 end
end
if uiControlPressed[12]==1 then
  if shift then queR=4 else selT=4 end
end
for k=0,3 do
  if uiControlPressed[k]==1 then actR=k+1; queR=0 end
end
print('steps init t='..selT..' s='..selS..' r='..actR)
-- INIT END

-- LOOP START
BG={16,16,20}
HD={32,32,46}
FG={235,235,240}
DIM={120,120,140}
ACC={80,180,255}
PLY={250,200,80}
SEL={250,90,90}
ON={70,160,90}
ACT={210,140,80}
MUTE={50,50,60}

ggdrf(0,0,0,W,H,BG)
-- header
ggdrf(0,0,0,W,18,HD)
ggdft(0,'STEP GRID',6,5,8,FG)
ggdft(0,'TRK '..selT,90,5,8,ACC)
ggdft(0,'REG '..actR..(queR>0 and ('>'..queR) or ''),140,5,8,queR>0 and PLY or FG)
ggdft(0,'SEL '..selS,210,5,8,SEL)
ggdft(0,shift and 'SHIFT' or '',270,5,8,ACT)

-- track tabs
for t=1,4 do
  local x=8+(t-1)*78
  local sel=(t==selT)
  ggdrf(0,x,22,x+72,40,sel and ACC or HD)
  ggdft(0,'TRK '..t,x+8,28,8,sel and BG or DIM)
end

-- 16-step grid (4x4)
local gx,gy=8,52
local cw,ch=74,38
local base=(actR-1)*16
for i=1,16 do
  local col=(i-1)%4
  local row=(i-1)//4
  local x=gx+col*(cw+2)
  local y=gy+row*(ch+2)
  local sIdx=base+i
  local v=trk[selT][sIdx]
  local bg=MUTE
  if v==1 then bg=ON elseif v==2 then bg=ACT elseif v==3 then bg=PLY end
  ggdrf(0,x,y,x+cw,y+ch,bg)
  -- selection ring
  if i==selS then
    ggdr(0,x-1,y-1,x+cw+1,y+ch+1,SEL)
    ggdr(0,x,y,x+cw,y+ch,SEL)
  end
  -- playhead (mocked: advances every tick within active region)
  if (actR==1 or actR==2 or actR==3 or actR==4) and i==(((tick)%16)+1) then
    ggdrf(0,x,y+ch-3,x+cw,y+ch,PLY)
  end
  ggdft(0,tostring(sIdx),x+4,y+4,8,FG)
end
tick=(tick or 0)+1

-- footer hint
ggdrf(0,0,H-16,W,H,HD)
ggdft(0,'Encoder=sel  B9-12=trk  SHIFT+B=queue R  K0-3=jump R',6,H-12,8,DIM)
ggdsw()
-- LOOP END
