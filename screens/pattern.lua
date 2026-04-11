-- pattern.lua
-- Pattern screen for Grid VSN1 320x240 LCD
-- CONSTRAINT: init must be under 2KB (WASM loadScript limit)
-- All heavy code goes in the loop section.

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
print("init ok "..NT)
-- INIT END

-- LOOP START
n=n+1

-- slider -> selected step
SS=math.floor(sliderValue/255*(NT-1))+1
if SS<1 then SS=1 end
if SS>NT then SS=NT end
-- auto-scroll
if SS<VO+1 then VO=SS-1 end
if SS>VO+8 then VO=SS-8 end
if VO<0 then VO=0 end
if VO>NT-8 then VO=NT-8 end
-- advance cursor every 30 frames
if n%30==0 then TC=TC+1 end
if TC>NT then TC=1 end

-- colors
local bg={18,18,24}
local hd={30,30,42}
local sb={28,28,38}
local sa={50,50,70}
local cb={80,140,220}
local ch={100,180,255}
local gn={60,200,120}
local gf={60,50,50}
local mu={80,60,60}
local rc={220,180,60}
local lc={200,100,60}
local tx={200,200,210}
local td={100,100,120}
local wh={255,255,255}
local bk={0,0,0}

-- layout
local W,H=320,240
local HH=24
local FH=20
local SW2=38
local SG=2
local SX=6
local SY=HH+4
local SH=H-HH-FH-8
local BB=SY+SH-22
local BT=SY+14
local BM=BB-BT
local GY=BB+4
local GH2=8
local RY=GY+GH2+3

-- clear
ggdrf(0,0,0,W,H,bg)

-- header
ggdrf(0,0,0,W,HH,hd)
ggdft(0,"TRK1",4,4,8,tx)
ggdft(0,DR,40,4,8,td)
ggdft(0,tostring(BPM).."bpm",130,4,8,tx)
ggdft(0,"sw"..tostring(SW).."%",195,4,8,td)
ggdft(0,SC,260,4,8,td)
ggdft(0,tostring(SS).."/"..tostring(NT),4,14,8,td)

-- step columns
for i=1,8 do
    local si=VO+i
    if si<=NT then
        local s=S[si]
        local x=SX+(i-1)*(SW2+SG)
        local sel=(si==SS)
        local cur=(si==TC)

        -- background
        local c=sb
        if sel then c=sa end
        if s.a==0 then c=mu end
        ggdrf(0,x,SY,x+SW2,BB+2,c)

        -- pitch bar
        if s.d>0 then
            local np=(s.p-36)/60
            if np<0 then np=0 end
            if np>1 then np=1 end
            local bh=math.floor(np*BM)
            if bh<3 then bh=3 end
            local by=BB-bh
            local bc=cb
            if sel then bc=ch end
            if s.a==0 then bc=mu end
            ggdrf(0,x+2,by,x+SW2-2,BB,bc)

            -- velocity highlight
            local vh=math.floor(bh*s.v/127*0.3)
            if vh>1 then
                local vc={
                    math.floor(bc[1]+(wh[1]-bc[1])*0.3),
                    math.floor(bc[2]+(wh[2]-bc[2])*0.3),
                    math.floor(bc[3]+(wh[3]-bc[3])*0.3)
                }
                ggdrf(0,x+2,by,x+SW2-2,by+vh,vc)
            end

            -- pitch name
            local pn=NN[(s.p%12)+1]..tostring(math.floor(s.p/12)-1)
            local ly=by-10
            if ly<SY+2 then ly=by+2 end
            ggdft(0,pn,x+3,ly,8,tx)
        else
            ggdft(0,"SKIP",x+4,BB-30,8,td)
        end

        -- gate bar
        if s.g>0 and s.d>0 then
            local gr=s.g/math.max(s.d,1)
            if gr>1 then gr=1 end
            local gw=math.floor((SW2-4)*gr)
            ggdrf(0,x+2,GY,x+2+gw,GY+GH2,gn)
            if gw<SW2-4 then
                ggdrf(0,x+2+gw,GY,x+SW2-2,GY+GH2,gf)
            end
        else
            ggdrf(0,x+2,GY,x+SW2-2,GY+GH2,gf)
        end

        -- ratchet dots
        if s.r>1 then
            for r=1,s.r do
                local dx=x+4+(r-1)*9
                ggdrf(0,dx,RY,dx+5,RY+5,rc)
            end
        end

        -- loop markers
        if si==LS then
            ggdrf(0,x,SY,x+2,BB+2,lc)
        end
        if si==LE then
            ggdrf(0,x+SW2-2,SY,x+SW2,BB+2,lc)
        end

        -- playback cursor
        if cur then
            ggdrf(0,x,RY+8,x+SW2,RY+12,wh)
        end

        -- step number
        ggdft(0,tostring(si),x+14,RY+14,8,td)
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
    ggdft(0,dt,4,fy+4,8,tx)
    ggdft(0,"loop:"..LS.."-"..LE,230,fy+4,8,lc)
end

-- scrollbar
if NT>8 then
    local sth=SH
    local th=math.floor(sth*8/NT)
    if th<8 then th=8 end
    local ty=SY+math.floor((sth-th)*VO/(NT-8))
    ggdrf(0,W-4,SY,W-1,SY+sth,{40,40,52})
    ggdrf(0,W-4,ty,W-1,ty+th,td)
end
-- LOOP END
