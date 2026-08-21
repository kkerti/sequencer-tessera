-- overview.lua -- Live control-state inspector for VSN1.
-- Shows every value the harness injects: encoder, small btns 9-12,
-- keyswitches 0-7, last event, plus a SHIFT (key 7) indicator.
-- Pure diagnostic: no engine state, no persistence.

-- INIT START
W,H=320,240
BG={18,18,22}
HD={32,32,44}
FG={230,230,230}
DIM={120,120,140}
ACC={80,180,255}
ON={90,200,120}
OFF={60,60,70}
SHIFTC={210,140,80}
print('overview init')
-- INIT END

-- LOOP START
ggdrf(0,0,0,W,H,BG)
-- header
ggdrf(0,0,0,W,18,HD)
ggdft(0,'CONTROL STATE OVERVIEW',6,5,8,FG)
ggdft(0,'evt:'..uiLastEventIndex..' d'..uiLastEventDelta,210,5,8,DIM)

-- Encoder panel
ggdft(0,'ENDLESS [8]',8,24,8,DIM)
-- knob ring
local cx,cy,r=44,68,22
ggdrf(0,cx-r-2,cy-r-2,cx+r+2,cy+r+2,HD)
-- value bar (sliderValue 0-255)
local bw=200
ggdft(0,'val',cx+r+18,52,8,DIM)
ggdrf(0,cx+r+18,62,cx+r+18+bw,72,OFF)
local fill=(sliderValue or 0)*bw//255
if fill>0 then ggdrf(0,cx+r+18,62,cx+r+18+fill,72,ACC) end
ggdft(0,tostring(sliderValue or 0),cx+r+18+bw+6,62,8,FG)
ggdft(0,'delta '..uiEncoderDelta..'  ticks '..uiEncoderTicks,cx+r+18,80,8,DIM)
ggdt(0,'O',cx-4,cy-8,16,FG)

-- Small buttons 9..12
ggdft(0,'SMALL BUTTONS [9-12]',8,108,8,DIM)
for i=0,3 do
  local idx=9+i
  local x=8+i*58
  local down=uiControlDown[idx]==1
  ggdrf(0,x,120,x+50,150,down and ACC or OFF)
  ggdft(0,'B'..idx,x+6,124,8,FG)
  ggdft(0,down and 'DOWN' or '----',x+6,136,8,down and BG or DIM)
end

-- Keyswitches 0..7
ggdft(0,'KEYSWITCHES [0-7]',8,160,8,DIM)
for i=0,7 do
  local col=i%4
  local row=i//4
  local x=8+col*58
  local y=172+row*30
  local down=uiControlDown[i]==1
  local label='K'..i
  if i==7 then label='SHFT' end
  local c=down and (i==7 and SHIFTC or ON) or OFF
  ggdrf(0,x,y,x+50,y+24,c)
  ggdft(0,label,x+6,y+4,8,FG)
  ggdft(0,down and 'on' or 'off',x+6,y+14,8,down and BG or DIM)
end

ggdsw()
-- LOOP END
