-- pattern.lua
-- Pattern screen: piano-roll style note blocks on a pitch grid
-- Compact rectangular blocks at pitch height, not full bars

-- INIT START
n=0
S={{p=60,v=100,d=4,g=2,r=1,a=1},{p=63,v=90,d=4,g=3,r=1,a=1},{p=67,v=110,d=4,g=2,r=2,a=1},{p=70,v=80,d=4,g=0,r=1,a=1},{p=72,v=100,d=4,g=4,r=1,a=1},{p=67,v=95,d=4,g=2,r=3,a=1},{p=63,v=85,d=0,g=2,r=1,a=1},{p=60,v=100,d=4,g=2,r=1,a=0},{p=55,v=100,d=4,g=2,r=1,a=1},{p=58,v=90,d=4,g=3,r=1,a=1},{p=62,v=100,d=4,g=2,r=4,a=1},{p=65,v=85,d=4,g=1,r=1,a=1},{p=67,v=100,d=4,g=2,r=1,a=1},{p=70,v=95,d=4,g=4,r=2,a=1},{p=72,v=110,d=4,g=2,r=1,a=1},{p=74,v=100,d=4,g=3,r=1,a=1}}
NT=#S
NN={"C","C#","D","Eb","E","F","F#","G","G#","A","Bb","B"}
LS=3
LE=14
TC=1
DR="forward"
BPM=120
SW=56
SC="minPent"
VO=0
SS=1
BTN_LEFT=9
BTN_UP=10
BTN_DOWN=11
BTN_RIGHT=12

function navButtonPressed(index)
    return uiControlPressed and uiControlPressed[index]==1
end

function navMoveIndex(current,minValue,maxValue,delta)
    local nextValue=current+delta
    if nextValue<minValue then nextValue=minValue end
    if nextValue>maxValue then nextValue=maxValue end
    return nextValue
end
print("init ok "..NT)
-- INIT END

-- LOOP START
n=n+1

-- navigation with 4 buttons
if navButtonPressed(BTN_LEFT) then SS=navMoveIndex(SS,1,NT,-1) end
if navButtonPressed(BTN_RIGHT) then SS=navMoveIndex(SS,1,NT,1) end
if navButtonPressed(BTN_UP) then SS=navMoveIndex(SS,1,NT,-8) end
if navButtonPressed(BTN_DOWN) then SS=navMoveIndex(SS,1,NT,8) end

if SS<VO+1 then VO=SS-1 end
if SS>VO+8 then VO=SS-8 end
if VO<0 then VO=0 end
if VO>NT-8 then VO=NT-8 end
if n%30==0 then TC=TC+1 end
if TC>NT then TC=1 end

-- colors
local bg={18,18,24}
local hd={30,30,42}
local gd={32,32,40}
local cb={70,130,210}
local ch={110,180,255}
local gn={60,200,120}
local gf={45,40,40}
local mu={60,50,55}
local rc={220,180,60}
local lc={200,100,60}
local tx={200,200,210}
local td={100,100,120}
local wh={255,255,255}

-- layout
local W,H=320,240
local HH=22
local FH=18
local VIS=8
local CW=38
local CG=2
local CX=6
local PY=HH+2
local PH=H-HH-FH-4
local NH=10

-- find pitch range of visible steps
local pMin,pMax=127,0
for i=1,VIS do
    local si=VO+i
    if si<=NT and S[si].d>0 then
        if S[si].p<pMin then pMin=S[si].p end
        if S[si].p>pMax then pMax=S[si].p end
    end
end
if pMin>pMax then pMin=60 pMax=72 end
-- pad range by 2 semitones each side
pMin=pMin-2
pMax=pMax+2
local pRange=pMax-pMin
if pRange<12 then
    local mid=math.floor((pMin+pMax)/2)
    pMin=mid-6
    pMax=mid+6
    pRange=12
end

-- clear
ggdrf(0,0,0,W,H,bg)

-- header
ggdrf(0,0,0,W,HH,hd)
ggdft(0,"TRK1",4,3,8,tx)
ggdft(0,DR,40,3,8,td)
ggdft(0,tostring(BPM).."bpm",130,3,8,tx)
ggdft(0,"sw"..tostring(SW).."%",200,3,8,td)
ggdft(0,SC,265,3,8,td)
ggdft(0,tostring(SS).."/"..tostring(NT),4,12,8,td)

-- pitch grid lines (every C and every visible semitone reference)
local gridArea=PH-NH-8
for semi=pMin,pMax do
    local yNorm=(pMax-semi)/pRange
    local y=PY+4+math.floor(yNorm*gridArea)
    -- draw faint line at every octave C
    if semi%12==0 then
        ggdrf(0,CX,y,CX+VIS*(CW+CG)-CG,y+1,{40,40,55})
        -- C label on left? too tight, skip
    end
end

-- step columns
for i=1,VIS do
    local si=VO+i
    if si<=NT then
        local s=S[si]
        local x=CX+(i-1)*(CW+CG)
        local sel=(si==SS)
        local cur=(si==TC)

        -- column separator (faint vertical)
        if i>1 then
            ggdrf(0,x-1,PY,x,PY+PH,{28,28,36})
        end

        -- selected column highlight
        if sel then
            ggdrf(0,x,PY,x+CW,PY+PH-NH-4,{35,35,50})
        end

        if s.d>0 and s.a==1 then
            -- note block position
            local yNorm=(pMax-s.p)/pRange
            local ny=PY+4+math.floor(yNorm*gridArea)

            -- gate width: proportion of column width
            local gateRatio=s.g/math.max(s.d,1)
            if gateRatio>1 then gateRatio=1 end
            local nw=math.floor((CW-4)*gateRatio)
            if nw<6 then nw=6 end

            -- note block
            local nc=cb
            if sel then nc=ch end
            -- velocity -> brightness
            local vb=0.5+0.5*(s.v/127)
            local nvColor={
                math.floor(nc[1]*vb),
                math.floor(nc[2]*vb),
                math.floor(nc[3]*vb)
            }
            ggdrf(0,x+2,ny,x+2+nw,ny+NH,nvColor)

            -- note outline if selected
            if sel then
                ggdr(0,x+1,ny-1,x+3+nw,ny+NH+1,wh)
            end

            -- pitch label below the note block
            local pn=NN[(s.p%12)+1]..tostring(math.floor(s.p/12)-1)
            ggdft(0,pn,x+3,ny+NH+2,8,tx)

            -- ratchet dots above note
            if s.r>1 then
                for r=1,s.r do
                    local dx=x+3+(r-1)*8
                    ggdrf(0,dx,ny-6,dx+4,ny-2,rc)
                end
            end
        elseif s.d==0 then
            -- skip marker
            local midY=PY+math.floor(PH/2)-4
            ggdft(0,"--",x+12,midY,8,td)
        elseif s.g==0 then
            -- rest marker
            local yNorm=(pMax-s.p)/pRange
            local ny=PY+4+math.floor(yNorm*gridArea)
            ggdrf(0,x+2,ny,x+CW-2,ny+NH,gf)
            local pn=NN[(s.p%12)+1]..tostring(math.floor(s.p/12)-1)
            ggdft(0,pn,x+3,ny+NH+2,8,td)
        elseif s.a==0 then
            -- muted
            local yNorm=(pMax-s.p)/pRange
            local ny=PY+4+math.floor(yNorm*gridArea)
            ggdrf(0,x+2,ny,x+CW-2,ny+NH,mu)
            local pn=NN[(s.p%12)+1]..tostring(math.floor(s.p/12)-1)
            ggdft(0,pn,x+3,ny+NH+2,8,td)
        end

        -- loop markers
        if si==LS then
            ggdrf(0,x,PY,x+2,PY+PH,lc)
        end
        if si==LE then
            ggdrf(0,x+CW-2,PY,x+CW,PY+PH,lc)
        end

        -- playback cursor (bottom indicator)
        local botY=PY+PH-NH
        if cur then
            ggdrf(0,x,botY,x+CW,botY+3,wh)
        end

        -- step number
        ggdft(0,tostring(si),x+14,botY+4,8,td)
    end
end

-- footer
local fy=H-FH
ggdrf(0,0,fy,W,H,hd)
local ss=S[SS]
if ss then
    local pn=NN[(ss.p%12)+1]..tostring(math.floor(ss.p/12)-1)
    local dt=pn.." v"..ss.v.." d"..ss.d.." g"..ss.g.." r"..ss.r
    if ss.a==0 then dt=dt.." [MUTE]" end
    ggdft(0,dt,4,fy+3,8,tx)
    ggdft(0,"loop:"..LS.."-"..LE,230,fy+3,8,lc)
end

-- scrollbar
if NT>8 then
    local sth=PH
    local th=math.floor(sth*8/NT)
    if th<8 then th=8 end
    local ty=PY+math.floor((sth-th)*VO/(NT-8))
    ggdrf(0,W-4,PY,W-1,PY+sth,{32,32,40})
    ggdrf(0,W-4,ty,W-1,ty+th,td)
end
-- LOOP END
