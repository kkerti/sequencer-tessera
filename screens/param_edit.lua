-- param_edit.lua -- Mirrors src/controls.lua top half: 4x2 cells.
--   Row 1: NOTE VEL DUR GATE
--   Row 2: MUTE RATCH PROB SHIFT
-- Keyswitches 0..6 select edit MODE. Key 7 = SHIFT.
-- Encoder edits selected step's value in current mode.
-- Small btns 9-12 select track (no shift) or queue region (shift).

-- INIT START
W,H=320,240
selT=selT or 1
selS=selS or 1
focus=focus or 1
queR=queR or 0
-- mock per-step params: pitch vel dur gate mute ratch prob
sp=sp or {}
if not sp[1] then
  for t=1,4 do sp[t]={} for s=1,64 do
    sp[t][s]={60,100,12,8,0,0,100}
  end end
end
shift=(uiControlDown[7]==1)

-- mode select 1..7 from K0..K6
for k=0,6 do if uiControlPressed[k]==1 then focus=k+1 end end
-- track / region from small buttons
if uiControlPressed[9]==1 then if shift then queR=1 else selT=1 end end
if uiControlPressed[10]==1 then if shift then queR=2 else selT=2 end end
if uiControlPressed[11]==1 then if shift then queR=3 else selT=3 end end
if uiControlPressed[12]==1 then if shift then queR=4 else selT=4 end end

-- encoder edits the selected step's current-mode value
if uiLastEventIndex==8 and uiEncoderDelta~=0 then
  local v=sp[selT][selS]
  if focus==5 or focus==6 then
    -- toggle on any nonzero delta
    v[focus]=(v[focus]==0) and 1 or 0
  else
    local nv=v[focus]+uiEncoderDelta
    if nv<0 then nv=0 end
    if nv>127 then nv=127 end
    v[focus]=nv
  end
end
print('param_edit t='..selT..' s='..selS..' focus='..focus)
-- INIT END

-- LOOP START
W,H=320,240
BG={16,16,20}
HD={32,32,46}
FG={235,235,240}
DIM={120,120,140}
ACTIVE={200,30,30}
INACTIVE={40,40,40}
SHIFTC={100,100,200}
NAMES={'NOTE','VEL','DUR','GATE','MUTE','RATCH','PROB','SHIFT'}

ggdrf(0,0,0,W,H,BG)
local v=sp[selT][selS]

-- 4x2 cells, each 80x60, occupying y=0..119
local cw,ch=80,60
for i=1,8 do
  local col=(i-1)%4
  local row=(i-1)>=4 and 1 or 0
  local x=col*cw
  local y=row*ch
  local bg
  if i==8 then
    bg=shift and SHIFTC or INACTIVE
  else
    bg=(i==focus) and ACTIVE or INACTIVE
  end
  ggdrf(0,x,y,x+cw-1,y+ch-1,bg)
  ggdft(0,NAMES[i],x+4,y+4,8,FG)
  local val=''
  if i<=4 or i==7 then val=tostring(v[i])
  elseif i==5 then val=(v[5]==1) and 'M' or '-'
  elseif i==6 then val=(v[6]==1) and 'R' or '-'
  elseif i==8 then val=shift and '*' or '' end
  ggdt(0,val,x+4,y+18,16,FG)
end

-- bottom half: track tabs + step nav
ggdrf(0,0,120,W,H,HD)
for t=1,4 do
  local x=8+(t-1)*78
  local sel=(t==selT)
  ggdrf(0,x,128,x+72,148,sel and ACTIVE or INACTIVE)
  ggdft(0,'TRK '..t,x+8,134,8,FG)
end
-- step strip: show 16 steps centered around selS
local center=selS
local first=center-8
if first<1 then first=1 end
if first>49 then first=49 end
local sw=18
for i=0,15 do
  local s=first+i
  local x=8+i*(sw+1)
  local y=158
  local on=true -- mock all on
  ggdrf(0,x,y,x+sw,y+24,(s==selS) and ACTIVE or INACTIVE)
  ggdft(0,tostring(s),x+2,y+2,8,FG)
end
ggdft(0,'sel step '..selS,8,190,8,DIM)
ggdft(0,'queue R '..queR,120,190,8,queR>0 and ACTIVE or DIM)
ggdft(0,'TRK '..selT..'  STEP '..selS..'  MODE '..NAMES[focus],8,212,8,FG)

ggdrf(0,0,H-14,W,H,HD)
ggdft(0,'K0-6 mode  K7 SHIFT  Encoder edit  B9-12 trk',6,H-11,8,DIM)
ggdsw()
-- LOOP END
