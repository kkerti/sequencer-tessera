-- track_select.lua -- 4 vertical track lanes.
-- Small btns 9-12 select track. Encoder edits the selected track's
-- "channel" parameter (mock). K0..K6 cycle a per-track parameter mode.

-- INIT START
W,H=320,240
selT=selT or 1
mode=mode or 1   -- 1..7 NOTE VEL DUR GATE MUTE RATCH PROB
ch=ch or {1,2,3,10}
vals=vals or {{60,100,12,8,0,0,100},{64,90,8,6,0,1,80},{67,110,16,10,0,0,90},{72,80,4,4,1,0,60}}
shift=(uiControlDown[7]==1)

if uiControlPressed[9]==1 then selT=1 end
if uiControlPressed[10]==1 then selT=2 end
if uiControlPressed[11]==1 then selT=3 end
if uiControlPressed[12]==1 then selT=4 end
for k=0,6 do if uiControlPressed[k]==1 then mode=k+1 end end
if uiLastEventIndex==8 and uiEncoderDelta~=0 then
  vals[selT][mode]=vals[selT][mode]+uiEncoderDelta
end
print('track_select t='..selT..' mode='..mode)
-- INIT END

-- LOOP START
BG={16,16,20}
HD={32,32,46}
FG={235,235,240}
DIM={120,120,140}
ACC={80,180,255}
SEL={250,90,90}
LANE={28,28,38}
NAMES={'NOTE','VEL','DUR','GATE','MUTE','RATCH','PROB'}
TCOL={{220,90,90},{220,180,80},{90,200,140},{120,160,240}}

ggdrf(0,0,0,W,H,BG)
ggdrf(0,0,0,W,18,HD)
ggdft(0,'TRACK SELECT',6,5,8,FG)
ggdft(0,'mode '..NAMES[mode],110,5,8,ACC)
ggdft(0,'edit '..vals[selT][mode],220,5,8,SEL)

-- 4 lanes
local lw=72
for t=1,4 do
  local x=8+(t-1)*(lw+4)
  local sel=(t==selT)
  ggdrf(0,x,26,x+lw,H-22,sel and HD or LANE)
  if sel then ggdr(0,x,26,x+lw,H-22,SEL) end
  -- header strip per track colour
  ggdrf(0,x,26,x+lw,42,TCOL[t])
  ggdft(0,'TRK '..t,x+8,30,8,BG)
  ggdft(0,'ch'..ch[t],x+44,30,8,BG)
  -- list params
  for i=1,7 do
    local y=48+(i-1)*22
    local m=(i==mode)
    ggdft(0,NAMES[i],x+6,y,8,m and FG or DIM)
    ggdft(0,tostring(vals[t][i]),x+44,y,8,m and (sel and SEL or ACC) or FG)
  end
end

ggdrf(0,0,H-18,W,H,HD)
ggdft(0,'B9-12 sel trk  K0-6 sel param  Encoder edit',6,H-13,8,DIM)
ggdsw()
-- LOOP END
