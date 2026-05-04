-- region_picker.lua -- 4 region tiles. Shows active vs queued.
-- SHIFT (key 7) + small btn 9-12 -> queue region.
-- Without SHIFT, small btn 9-12 selects display track (does not affect engine).
-- K0..K3 force-set active region (debug).
-- Mocked "boundary tick" auto-promotes queued -> active every ~24 frames.

-- INIT START
W,H=320,240
selT=selT or 1
actR=actR or 1
queR=queR or 0
ftick=ftick or 0
shift=(uiControlDown[7]==1)

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
  if uiControlPressed[k]==1 then actR=k+1; queR=0; ftick=0 end
end
print('region act='..actR..' que='..queR)
-- INIT END

-- LOOP START
BG={16,16,20}
HD={32,32,46}
FG={235,235,240}
DIM={120,120,140}
ACC={80,180,255}
ACT={90,200,120}
QUE={250,200,80}
TILE={36,36,48}
SEL={250,90,90}

-- promote queued -> active periodically
ftick=ftick+1
if queR>0 and ftick>40 then
  actR=queR; queR=0; ftick=0
end

ggdrf(0,0,0,W,H,BG)
ggdrf(0,0,0,W,18,HD)
ggdft(0,'REGION PICKER',6,5,8,FG)
ggdft(0,'TRK '..selT,110,5,8,ACC)
ggdft(0,'ACT '..actR,160,5,8,ACT)
ggdft(0,queR>0 and ('QUE '..queR) or 'no queue',210,5,8,queR>0 and QUE or DIM)
ggdft(0,shift and 'SHIFT' or '',280,5,8,SEL)

-- 4 region tiles 2x2
local tw,th=140,90
for r=1,4 do
  local col=(r-1)%2
  local row=(r-1)//2
  local x=14+col*(tw+12)
  local y=28+row*(th+8)
  local active=(r==actR)
  local queued=(r==queR)
  local bg=TILE
  if active then bg=ACT elseif queued then bg=QUE end
  ggdrf(0,x,y,x+tw,y+th,bg)
  if queued and not active then
    -- pulsing border based on ftick
    local p=(ftick//4)%2
    if p==1 then ggdr(0,x,y,x+tw,y+th,FG) end
  end
  local txt=active and {255,255,255} or FG
  ggdft(0,'REGION '..r,x+8,y+6,8,txt)
  ggdt(0,tostring(r),x+tw-26,y+th-30,24,txt)
  -- step range label
  local s1=(r-1)*16+1
  local s2=r*16
  ggdft(0,'steps '..s1..'-'..s2,x+8,y+th-14,8,txt)
end

-- progress bar to next promotion
if queR>0 then
  local bw=W-20
  local fill=(ftick*bw)//40
  ggdrf(0,10,H-30,10+bw,H-22,HD)
  ggdrf(0,10,H-30,10+fill,H-22,QUE)
end

ggdrf(0,0,H-18,W,H,HD)
ggdft(0,'B9-12 sel trk  SHIFT+B queue  K0-3 force active',6,H-13,8,DIM)
ggdsw()
-- LOOP END
