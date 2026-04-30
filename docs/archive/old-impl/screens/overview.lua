-- overview.lua
-- Overview screen: 8 tracks across 2 pages (4 per page)
-- Page indicator dots at bottom, JRPG tabbed-page style

-- INIT START
n=0
T={
{nm="TR1",ch=1,dr="fwd",cd=1,cm=1,mt=0,ls=1,le=8,tc=1,
s={{p=60,v=100,g=1},{p=63,v=90,g=1},{p=67,v=110,g=1},{p=70,v=80,g=0},{p=72,v=100,g=1},{p=67,v=95,g=1},{p=63,v=85,g=1},{p=60,v=100,g=1}}},
{nm="TR2",ch=2,dr="rev",cd=2,cm=1,mt=0,ls=2,le=6,tc=4,
s={{p=48,v=100,g=1},{p=48,v=100,g=1},{p=55,v=90,g=1},{p=55,v=90,g=0},{p=48,v=100,g=1},{p=48,v=100,g=1},{p=43,v=80,g=1},{p=43,v=80,g=1}}},
{nm="TR3",ch=3,dr="ppg",cd=1,cm=2,mt=1,ls=1,le=4,tc=2,
s={{p=72,v=70,g=1},{p=74,v=80,g=1},{p=76,v=90,g=1},{p=79,v=100,g=1}}},
{nm="TR4",ch=4,dr="rnd",cd=4,cm=1,mt=0,ls=1,le=8,tc=7,
s={{p=36,v=110,g=1},{p=38,v=90,g=1},{p=42,v=100,g=1},{p=36,v=100,g=0},{p=38,v=80,g=1},{p=42,v=110,g=1},{p=36,v=100,g=1},{p=46,v=90,g=1}}},
{nm="TR5",ch=5,dr="fwd",cd=1,cm=1,mt=0,ls=1,le=6,tc=3,
s={{p=64,v=90,g=1},{p=67,v=100,g=1},{p=71,v=80,g=1},{p=67,v=95,g=0},{p=64,v=100,g=1},{p=60,v=85,g=1}}},
{nm="TR6",ch=6,dr="brn",cd=1,cm=1,mt=0,ls=1,le=8,tc=5,
s={{p=50,v=100,g=1},{p=53,v=80,g=1},{p=57,v=110,g=1},{p=60,v=90,g=1},{p=57,v=100,g=0},{p=53,v=85,g=1},{p=50,v=100,g=1},{p=48,v=90,g=1}}},
{nm="TR7",ch=7,dr="ppg",cd=2,cm=1,mt=1,ls=1,le=4,tc=1,
s={{p=84,v=70,g=1},{p=86,v=80,g=1},{p=88,v=90,g=1},{p=91,v=100,g=1}}},
{nm="TR8",ch=10,dr="fwd",cd=1,cm=1,mt=0,ls=1,le=8,tc=2,
s={{p=36,v=127,g=1},{p=42,v=90,g=1},{p=36,v=110,g=1},{p=38,v=80,g=1},{p=36,v=127,g=1},{p=42,v=90,g=1},{p=36,v=110,g=0},{p=46,v=100,g=1}}}
}
NT=8
BPM=120
SW=56
SC="minPent"
SN=1
ST=1
PG=1
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
print("overview8 init ok")
-- INIT END

-- LOOP START
n=n+1

-- navigation with 4 buttons
if navButtonPressed(BTN_LEFT) then ST=navMoveIndex(ST,1,NT,-1) end
if navButtonPressed(BTN_RIGHT) then ST=navMoveIndex(ST,1,NT,1) end
if navButtonPressed(BTN_UP) then ST=navMoveIndex(ST,1,NT,-4) end
if navButtonPressed(BTN_DOWN) then ST=navMoveIndex(ST,1,NT,4) end

-- auto page based on selection
PG=math.ceil(ST/4)

-- animate cursors
if n%30==0 then
    for i=1,NT do
        local t=T[i]
        if t.mt==0 then
            t.tc=t.tc+1
            if t.tc>#t.s then t.tc=1 end
        end
    end
end

-- colors
local bg={18,18,24}
local hd={30,30,42}
local tx={200,200,210}
local td={100,100,120}
local wh={255,255,255}
local cb={70,130,210}
local ch={110,180,255}
local lc={200,100,60}
local rc={220,180,60}
local gn={60,200,120}
local mu={80,50,55}
local rs={50,45,45}

-- layout
local W,H=320,240
local HH=20
local FH=16
local PPG=4
local TH=math.floor((H-HH-FH-8)/PPG)
local LB=44
local RB=4

-- clear
ggdrf(0,0,0,W,H,bg)

-- header
ggdrf(0,0,0,W,HH,hd)
ggdft(0,"OVERVIEW",4,3,8,tx)
ggdft(0,tostring(BPM).."bpm",80,3,8,tx)
ggdft(0,"sw"..SW.."%",140,3,8,td)
ggdft(0,SC,195,3,8,td)

-- page indicator (right side of header)
local pgx=270
for pg=1,2 do
    local dotx=pgx+(pg-1)*22
    if pg==PG then
        ggdrf(0,dotx,6,dotx+16,14,{60,60,90})
        ggdft(0,tostring(pg),dotx+4,5,8,wh)
    else
        ggdrf(0,dotx,6,dotx+16,14,{35,35,48})
        ggdft(0,tostring(pg),dotx+4,5,8,td)
    end
end

-- 4 tracks for current page
local base=(PG-1)*PPG
for ti=1,PPG do
    local gi=base+ti
    if gi>NT then break end
    local t=T[gi]
    local ty=HH+2+(ti-1)*TH
    local sel=(gi==ST)
    local ns=#t.s

    -- selected track bg
    if sel then
        ggdrf(0,0,ty,W,ty+TH-2,{30,30,48})
    end

    -- track label area
    ggdrf(0,0,ty,LB,ty+TH-2,{25,25,35})
    local nc=tx
    if t.mt==1 then nc=mu end
    ggdft(0,t.nm,4,ty+2,8,nc)
    ggdft(0,"ch"..t.ch,4,ty+12,8,td)
    ggdft(0,t.dr,4,ty+22,8,td)

    -- clock info
    local clk=""
    if t.cd>1 then clk="/"..t.cd end
    if t.cm>1 then clk="x"..t.cm end
    if clk~="" then
        ggdft(0,clk,4,ty+32,8,rc)
    end

    -- mute indicator
    if t.mt==1 then
        ggdft(0,"MUTE",4,ty+TH-14,8,mu)
    end

    -- step area
    local sx=LB+2
    local sw=W-LB-RB-4
    local stepW=math.floor(sw/ns)
    if stepW<3 then stepW=3 end
    local stepH=TH-8

    -- find pitch range for this track
    local pMin,pMax=127,0
    for i=1,ns do
        if t.s[i].p<pMin then pMin=t.s[i].p end
        if t.s[i].p>pMax then pMax=t.s[i].p end
    end
    if pMin>=pMax then pMin=pMin-6 pMax=pMax+6 end
    pMin=pMin-2
    pMax=pMax+2
    local pRange=pMax-pMin
    if pRange<4 then pRange=4 end

    -- step blocks
    for i=1,ns do
        local s=t.s[i]
        local bx=sx+(i-1)*stepW
        local noteH=math.max(math.floor(stepH*0.35),3)
        local yNorm=(pMax-s.p)/pRange
        local ny=ty+3+math.floor(yNorm*(stepH-noteH-2))

        -- loop region background
        if i>=t.ls and i<=t.le then
            ggdrf(0,bx,ty+1,bx+stepW-1,ty+TH-3,{28,28,38})
        end

        if t.mt==1 then
            ggdrf(0,bx+1,ny,bx+stepW-2,ny+noteH,{40,35,40})
        elseif s.g==0 then
            ggdrf(0,bx+1,ny,bx+stepW-2,ny+noteH,rs)
        else
            local vb=0.5+0.5*(s.v/127)
            local clr=cb
            if sel then clr=ch end
            ggdrf(0,bx+1,ny,bx+stepW-2,ny+noteH,{
                math.floor(clr[1]*vb),
                math.floor(clr[2]*vb),
                math.floor(clr[3]*vb)
            })
        end

        -- cursor indicator
        if i==t.tc and t.mt==0 then
            ggdrf(0,bx,ty+TH-5,bx+stepW-1,ty+TH-3,wh)
        end
    end

    -- loop markers
    local lsx=sx+(t.ls-1)*stepW
    ggdrf(0,lsx,ty+1,lsx+1,ty+TH-3,lc)
    local lex=sx+t.le*stepW-1
    ggdrf(0,lex-1,ty+1,lex,ty+TH-3,lc)

    -- selected track outline
    if sel then
        ggdr(0,0,ty,W-1,ty+TH-2,{80,80,120})
    end

    -- divider
    if ti<PPG then
        ggdrf(0,0,ty+TH-2,W,ty+TH-1,{35,35,45})
    end
end

-- footer
local fy=H-FH
ggdrf(0,0,fy,W,H,hd)
local st=T[ST]
local info=st.nm.." ch"..st.ch.." "..st.dr.." "..#st.s.."stp"
if st.mt==1 then info=info.." [MUTE]" end
ggdft(0,info,4,fy+2,8,tx)
ggdft(0,"loop:"..st.ls.."-"..st.le,220,fy+2,8,lc)
ggdft(0,PG.."/2",296,fy+2,8,td)
-- LOOP END
