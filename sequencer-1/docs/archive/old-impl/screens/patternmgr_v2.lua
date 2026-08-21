-- patternmgr_v2.lua
-- Pattern Manager v2: equal-size grid cards + explicit safe creation flow

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

-- screen state
MODE="BROWSE"      -- BROWSE | CREATE
CUR=1              -- global cursor across cards (+ NEW slot)
PG=1
CPP=6              -- cards per page (3x2)

-- create form state
CR_MODE=1          -- 1=append, 2=insert
CR_LEN=8
CR_MIN=1
CR_MAX=16
CR_START=1
CR_FOCUS=1         -- 1=mode, 2=length, 3=start
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

print("patternmgr v2 init ok")
-- INIT END

-- LOOP START
n=n+1

-- derive slot counts
local totalSlots=NP+1
local pages=math.floor((totalSlots+CPP-1)/CPP)
if pages<1 then pages=1 end

-- playback cursor animation
if n%20==0 then
    TC=TC+1
    if TC>TS then TC=1 end
end

-- input model: 4 nav buttons for focus/selection, slider for value edits
if MODE=="BROWSE" then
    if navButtonPressed(BTN_LEFT) then CUR=navMoveIndex(CUR,1,totalSlots,-1) end
    if navButtonPressed(BTN_RIGHT) then CUR=navMoveIndex(CUR,1,totalSlots,1) end
    if navButtonPressed(BTN_UP) then CUR=navMoveIndex(CUR,1,totalSlots,-3) end
    if navButtonPressed(BTN_DOWN) then CUR=navMoveIndex(CUR,1,totalSlots,3) end
    PG=math.floor((CUR-1)/CPP)+1
    if PG<1 then PG=1 end
    if PG>pages then PG=pages end
else
    -- create mode navigation with buttons, slider edits focused value
    if navButtonPressed(BTN_LEFT) then CR_FOCUS=navMoveIndex(CR_FOCUS,1,3,-1) end
    if navButtonPressed(BTN_RIGHT) then CR_FOCUS=navMoveIndex(CR_FOCUS,1,3,1) end
    if navButtonPressed(BTN_UP) then CR_FOCUS=navMoveIndex(CR_FOCUS,1,3,-1) end
    if navButtonPressed(BTN_DOWN) then CR_FOCUS=navMoveIndex(CR_FOCUS,1,3,1) end

    if CR_FOCUS==1 then
        CR_MODE=math.floor(sliderValue/255*1)+1
    elseif CR_FOCUS==2 then
        CR_LEN=CR_MIN+math.floor(sliderValue/255*(CR_MAX-CR_MIN))
    else
        CR_START=1+math.floor(sliderValue/255*TS)
    end

    if CR_MODE<1 then CR_MODE=1 end
    if CR_MODE>2 then CR_MODE=2 end
    if CR_LEN<CR_MIN then CR_LEN=CR_MIN end
    if CR_LEN>CR_MAX then CR_LEN=CR_MAX end
    if CR_START<1 then CR_START=1 end
    if CR_START>TS+1 then CR_START=TS+1 end
end

-- helper: compute track end from patterns
local trackEnd=0
for i=1,NP do
    local e=P[i].si+P[i].sc-1
    if e>trackEnd then trackEnd=e end
end
if trackEnd<TS then trackEnd=TS end

-- create candidate placement
local candStart=CR_START
if CR_MODE==1 then
    candStart=trackEnd+1
end
local candEnd=candStart+CR_LEN-1

-- overlap detection against existing patterns
local conflict=false
local conflictIdx=0
for i=1,NP do
    local ps=P[i].si
    local pe=P[i].si+P[i].sc-1
    if not (candEnd<ps or candStart>pe) then
        conflict=true
        conflictIdx=i
        break
    end
end

-- find playing pattern
local curPat=0
for i=1,NP do
    local ps=P[i].si
    local pe=P[i].si+P[i].sc-1
    if TC>=ps and TC<=pe then
        curPat=i
        break
    end
end

-- selected slot index in browse mode
local selPat=0
local onNew=false
if MODE=="BROWSE" then
    if CUR<=NP then
        selPat=CUR
    else
        onNew=true
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
local gn={60,200,120}
local rd={200,80,70}
local rc={220,180,60}
local lc={200,100,60}
local nw={50,180,100}

-- layout
local W,H=320,240
local HH=24
local RH=16
local FH=16
local detailY=176
local detailH=48

-- grid geometry (3x2, equal cards)
local gx=8
local gy=HH+RH+8
local gapX=8
local gapY=8
local cols=3
local rows=2
local cardW=96
local cardH=64

-- helpers
local function strTrunc(text, maxLen)
    if #text<=maxLen then return text end
    return string.sub(text,1,maxLen)
end

local function drawTag(x,y,text,color)
    ggdrf(0,x,y,x+24,y+9,{30,30,40})
    ggdr(0,x,y,x+24,y+9,color)
    ggdft(0,text,x+2,y+1,8,color)
end

-- clear
ggdrf(0,0,0,W,H,bg)

-- header
ggdrf(0,0,0,W,HH,hd)
ggdft(0,"PATTERNS",8,8,8,wh)
ggdft(0,"TRK"..TI,96,8,8,ch)
ggdft(0,DR,136,8,8,td)
ggdft(0,"ch"..CH,200,8,8,td)
ggdft(0,NP.."p/"..TS.."s",248,8,8,td)

-- position ribbon
local rx=8
local ry=HH+4
local rw=W-16
local rh=8
ggdrf(0,rx,ry,rx+rw,ry+rh,{28,28,38})

-- loop region in ribbon
if LE>=LS and TS>0 then
    local lx=rx+math.floor(rw*((LS-1)/TS))
    local ex=rx+math.floor(rw*(LE/TS))
    ggdrf(0,lx,ry,ex,ry+rh,lc)
end

-- selected pattern / candidate region
if MODE=="BROWSE" and selPat>0 then
    local ps=P[selPat].si
    local pe=P[selPat].si+P[selPat].sc-1
    local sx=rx+math.floor(rw*((ps-1)/TS))
    local ex=rx+math.floor(rw*(pe/TS))
    ggdrf(0,sx,ry,sx+1,ry+rh,ch)
    ggdrf(0,ex-1,ry,ex,ry+rh,ch)
elseif MODE=="CREATE" then
    local sx=rx+math.floor(rw*((candStart-1)/math.max(trackEnd+CR_LEN,1)))
    local ex=rx+math.floor(rw*(candEnd/math.max(trackEnd+CR_LEN,1)))
    local cc=nw
    if conflict then cc=rd end
    ggdrf(0,sx,ry,ex,ry+rh,cc)
end

-- playhead in ribbon
local px=rx+math.floor(rw*(TC/math.max(TS,1)))
ggdrf(0,px,ry-2,px+1,ry+rh+2,wh)

-- grid page slice
local pageStart=(PG-1)*CPP+1
local pageEnd=pageStart+CPP-1
if pageEnd>totalSlots then pageEnd=totalSlots end

for row=1,rows do
    for col=1,cols do
        local slot=(row-1)*cols+col
        local gi=pageStart+slot-1
        local x=gx+(col-1)*(cardW+gapX)
        local y=gy+(row-1)*(cardH+gapY)
        if gi<=pageEnd then
            local isNew=(gi==NP+1)
            local isSel=(MODE=="BROWSE" and gi==CUR)

            local fill={32,36,48}
            if isNew then fill={28,40,34} end
            if isSel then fill={40,46,64} end
            ggdrf(0,x,y,x+cardW,y+cardH,fill)

            local out={46,52,72}
            if isNew then out={40,90,60} end
            if isSel then out=ch end
            ggdr(0,x,y,x+cardW,y+cardH,out)

            if isNew then
                ggdft(0,"+ NEW",x+8,y+8,8,nw)
                ggdft(0,"Create",x+8,y+24,8,tx)
                ggdft(0,"pattern",x+8,y+32,8,tx)
                ggdft(0,"slot",x+8,y+40,8,td)
            else
                local p=P[gi]
                local ps=p.si
                local pe=p.si+p.sc-1

                ggdft(0,"P"..gi,x+8,y+8,8,wh)
                ggdft(0,strTrunc(p.nm,9),x+32,y+8,8,tx)
                ggdft(0,ps.."-"..pe,x+8,y+24,8,td)
                ggdft(0,p.sc.." steps",x+8,y+40,8,rc)

                if gi==curPat then
                    drawTag(x+64,y+8,"PLAY",gn)
                end
                if LS<=pe and LE>=ps then
                    drawTag(x+64,y+20,"LOOP",lc)
                end
                if isSel then
                    drawTag(x+64,y+32,"SEL",ch)
                end
            end
        end
    end
end

-- detail strip
ggdrf(0,8,detailY,W-8,detailY+detailH,{24,24,34})
ggdr(0,8,detailY,W-8,detailY+detailH,{45,45,65})

if MODE=="BROWSE" then
    if onNew then
        ggdft(0,"NEW PATTERN",16,detailY+8,8,nw)
        ggdft(0,"Press to enter create flow",16,detailY+24,8,tx)
        ggdft(0,"Safe placement checks enabled",16,detailY+32,8,td)
    else
        local p=P[selPat]
        local ps=p.si
        local pe=p.si+p.sc-1
        ggdft(0,"P"..selPat.." \""..strTrunc(p.nm,14).."\"",16,detailY+8,8,ch)
        ggdft(0,"Range: "..ps.."-"..pe.."  Len: "..p.sc,16,detailY+24,8,tx)
        if TC>=ps and TC<=pe then
            ggdft(0,"Playhead: step "..(TC-ps+1).."/"..p.sc,16,detailY+32,8,gn)
        else
            ggdft(0,"Playhead outside selected pattern",16,detailY+32,8,td)
        end
    end
else
    local modeText="Append"
    if CR_MODE==2 then modeText="Insert" end
    local okText="OK"
    local okColor=gn
    if conflict then
        okText="CONFLICT P"..conflictIdx
        okColor=rd
    end

    ggdft(0,"CREATE PATTERN",16,detailY+8,8,nw)
    ggdft(0,"Mode:"..modeText.."  Len:"..CR_LEN.."  Start:"..candStart,16,detailY+24,8,tx)
    ggdft(0,"Range:"..candStart.."-"..candEnd.."  "..okText,16,detailY+32,8,okColor)

    if CR_FOCUS==1 then
        ggdrf(0,14,detailY+23,54,detailY+24,ch)
    elseif CR_FOCUS==2 then
        ggdrf(0,78,detailY+23,108,detailY+24,ch)
    else
        ggdrf(0,130,detailY+23,176,detailY+24,ch)
    end
end

-- footer
local fy=H-FH
ggdrf(0,0,fy,W,H,hd)
if MODE=="BROWSE" then
    ggdft(0,"Buttons navigate  Slider edits",8,fy+4,8,tx)
else
    ggdft(0,"Create mode: validate then confirm",8,fy+4,8,tx)
end
ggdft(0,PG.."/"..pages,288,fy+4,8,td)

-- demo transition trigger into create mode when NEW is selected
if MODE=="BROWSE" and onNew and n%180==0 then
    MODE="CREATE"
end
if MODE=="CREATE" and n%360==0 then
    MODE="BROWSE"
end
-- LOOP END
