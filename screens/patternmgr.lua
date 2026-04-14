-- patternmgr.lua
-- Pattern Manager screen: view/create/select patterns within a track
-- Shows patterns as horizontal blocks, proportional to step count
-- 4 nav buttons move selection, slider edits values when needed

-- INIT START
n=0
TI=1
P={
{nm="Intro",sc=8,si=1},
{nm="Verse",sc=8,si=9},
{nm="Chorus",sc=4,si=17},
{nm="Break",sc=6,si=21},
{nm="Outro",sc=4,si=27}
}
NP=#P
TS=30
TC=5
LS=1
LE=20
DR="forward"
CH=1
SP=1
NS=8
MX=16
MN=1
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
print("patternmgr init ok")
-- INIT END

-- LOOP START
n=n+1

local slots=NP+1
if navButtonPressed(BTN_LEFT) then SP=navMoveIndex(SP,1,slots,-1) end
if navButtonPressed(BTN_RIGHT) then SP=navMoveIndex(SP,1,slots,1) end
if navButtonPressed(BTN_UP) then SP=navMoveIndex(SP,1,slots,-3) end
if navButtonPressed(BTN_DOWN) then SP=navMoveIndex(SP,1,slots,3) end

-- if on NEW slot, slider sub-range sets step count
-- (in real use, a second encoder would set this; for now we show default)
local onNew=(SP>NP)
if onNew then
    -- remap last portion of slider to step count 1-16
    local subRange=sliderValue-math.floor(255*(NP)/(slots))
    local subMax=255-math.floor(255*(NP)/(slots))
    if subMax<1 then subMax=1 end
    NS=math.floor(subRange/subMax*(MX-MN))+MN
    if NS<MN then NS=MN end
    if NS>MX then NS=MX end
end

-- animate cursor
if n%20==0 then
    TC=TC+1
    if TC>TS then TC=1 end
end

-- find which pattern the cursor is in
local curPat=1
local acc=0
for i=1,NP do
    acc=acc+P[i].sc
    if TC<=acc then curPat=i break end
end

-- colors
local bg={18,18,24}
local hd={30,30,42}
local tx={200,200,210}
local td={100,100,120}
local wh={255,255,255}
local cb={70,130,210}
local ch={110,180,255}
local gn={60,200,120}
local rd={200,80,70}
local rc={220,180,60}
local lc={200,100,60}
local nw={50,180,100}

-- layout
local W,H=320,240
local HH=22
local FH=18

-- clear
ggdrf(0,0,0,W,H,bg)

-- header
ggdrf(0,0,0,W,HH,hd)
ggdft(0,"PATTERNS",4,4,8,wh)
ggdft(0,"TRK"..TI,80,4,8,ch)
ggdft(0,DR,120,4,8,td)
ggdft(0,"ch"..CH,170,4,8,td)
ggdft(0,NP.." pat / "..TS.." stp",220,4,8,td)

-- === BLOCK VIEW (top section) ===
-- Patterns as horizontal blocks, proportional width
local blockY=HH+6
local blockH=50
local blockX=6
local blockW=W-12
local totalSteps=TS

-- draw pattern blocks
local bx=blockX
for i=1,NP do
    local p=P[i]
    local pw=math.max(math.floor(blockW*(p.sc/totalSteps)),16)
    local sel=(SP==i)
    local cur=(curPat==i)

    -- block fill
    local bc={38,42,58}
    if cur then bc={45,50,70} end
    if sel then bc={50,55,80} end
    ggdrf(0,bx,blockY,bx+pw-2,blockY+blockH,bc)

    -- selected outline
    if sel then
        ggdr(0,bx-1,blockY-1,bx+pw-1,blockY+blockH+1,ch)
    end

    -- playing indicator (top edge glow)
    if cur then
        ggdrf(0,bx,blockY,bx+pw-2,blockY+3,gn)
    end

    -- pattern index
    ggdft(0,tostring(i),bx+3,blockY+5,8,sel and wh or td)

    -- pattern name (truncate if needed)
    local dnm=p.nm
    if #dnm>6 then dnm=string.sub(dnm,1,6) end
    ggdft(0,dnm,bx+3,blockY+16,8,sel and tx or td)

    -- step count
    ggdft(0,p.sc.."s",bx+3,blockY+28,8,sel and rc or {70,70,85})

    -- loop region highlight
    if p.si<=LE and p.si+p.sc-1>=LS then
        ggdrf(0,bx,blockY+blockH-4,bx+pw-2,blockY+blockH,lc)
    end

    bx=bx+pw
end

-- "NEW" block at end
if bx<blockX+blockW-20 then
    local nww=blockX+blockW-bx
    local sel=onNew
    local nc={30,40,35}
    if sel then nc={35,55,45} end
    ggdrf(0,bx,blockY,bx+nww-2,blockY+blockH,nc)
    if sel then
        ggdr(0,bx-1,blockY-1,bx+nww-1,blockY+blockH+1,nw)
    end
    ggdft(0,"+NEW",bx+4,blockY+10,8,sel and nw or {60,80,70})
    if sel then
        ggdft(0,NS.." steps",bx+4,blockY+24,8,wh)
    end
end

-- === DETAIL SECTION (below blocks) ===
local detY=blockY+blockH+8

if onNew then
    -- NEW pattern creator
    ggdrf(0,6,detY,W-6,detY+60,{25,30,28})
    ggdr(0,6,detY,W-6,detY+60,nw)
    ggdft(0,"CREATE NEW PATTERN",12,detY+4,8,nw)

    -- step count selector bar
    local barX=12
    local barY=detY+18
    local barW=W-24
    local barH=14
    ggdrf(0,barX,barY,barX+barW,barY+barH,{40,45,42})

    -- discrete step count blocks
    for s=MN,MX do
        local sx=barX+math.floor(barW*(s-MN)/(MX-MN))
        local sw2=math.floor(barW/(MX-MN))-1
        if sw2<2 then sw2=2 end
        local sc2={40,50,45}
        if s<=NS then sc2=nw end
        ggdrf(0,sx,barY+1,sx+sw2,barY+barH-1,sc2)
    end

    ggdft(0,"Steps: "..NS,12,barY+barH+4,8,wh)
    ggdft(0,"Use slider to set steps",12,barY+barH+16,8,td)

    -- preview: show what the new pattern slot would look like
    ggdft(0,"Pattern "..(NP+1).." \""..NS.." new steps\"",12,detY+52,8,td)
else
    -- selected pattern detail
    local p=P[SP]
    ggdrf(0,6,detY,W-6,detY+70,{25,25,35})
    ggdr(0,6,detY,W-6,detY+70,{50,50,70})

    -- pattern info
    ggdft(0,"Pattern "..SP,12,detY+4,8,ch)
    ggdft(0,"\""..p.nm.."\"",90,detY+4,8,tx)

    -- stats row
    ggdft(0,"Steps: "..p.sc,12,detY+18,8,tx)
    ggdft(0,"Start: "..p.si,110,detY+18,8,td)
    ggdft(0,"End: "..(p.si+p.sc-1),200,detY+18,8,td)

    -- step mini-view: tiny blocks representing steps
    local mvY=detY+34
    local mvH=12
    local mvX=12
    local mvW=W-24
    local stepPx=math.floor(mvW/p.sc)
    if stepPx<4 then stepPx=4 end
    for si=1,p.sc do
        local sx=mvX+(si-1)*stepPx
        local inLoop=(p.si+si-1>=LS and p.si+si-1<=LE)
        local clr={50,60,80}
        if inLoop then clr=cb end
        if p.si+si-1==TC then clr=gn end
        ggdrf(0,sx,mvY,sx+stepPx-1,mvY+mvH,clr)
    end

    -- loop info
    ggdft(0,"Loop: "..LS.."-"..LE,12,mvY+mvH+4,8,lc)

    -- cursor position within pattern
    if TC>=p.si and TC<p.si+p.sc then
        local ci=TC-p.si+1
        ggdft(0,"Cursor: step "..ci.."/"..p.sc,140,mvY+mvH+4,8,gn)
    end

    -- actions hint
    ggdft(0,"Press: edit | Hold: rename",12,detY+62,8,td)
end

-- footer
local fy=H-FH
ggdrf(0,0,fy,W,H,hd)
if onNew then
    ggdft(0,"New pattern: "..NS.." steps",4,fy+3,8,nw)
else
    local p=P[SP]
    ggdft(0,"Pat "..SP..": \""..p.nm.."\" "..p.sc.."stp",4,fy+3,8,tx)
end
ggdft(0,"loop:"..LS.."-"..LE,240,fy+3,8,lc)
-- LOOP END
