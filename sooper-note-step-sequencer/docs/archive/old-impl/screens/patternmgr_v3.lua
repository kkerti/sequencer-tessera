-- patternmgr_v3.lua
-- Pattern Manager v3: hybrid timeline ribbon + scrollable list

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

-- browse state
SP=1
SO=0
VIS=7

-- mode + create form
MODE="BROWSE"      -- BROWSE | CREATE
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

print("patternmgr v3 init ok")
-- INIT END

-- LOOP START
n=n+1

local totalSlots=NP+1

-- animate playback cursor
if n%20==0 then
    TC=TC+1
    if TC>TS then TC=1 end
end

-- input model: 4 nav buttons for focus/selection, slider for value edits
if MODE=="BROWSE" then
    if navButtonPressed(BTN_LEFT) then SP=navMoveIndex(SP,1,totalSlots,-1) end
    if navButtonPressed(BTN_RIGHT) then SP=navMoveIndex(SP,1,totalSlots,1) end
    if navButtonPressed(BTN_UP) then SP=navMoveIndex(SP,1,totalSlots,-1) end
    if navButtonPressed(BTN_DOWN) then SP=navMoveIndex(SP,1,totalSlots,1) end

    if SP<SO+1 then SO=SP-1 end
    if SP>SO+VIS then SO=SP-VIS end
    if SO<0 then SO=0 end
    if SO>totalSlots-VIS then SO=totalSlots-VIS end
    if SO<0 then SO=0 end
else
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

local onNew=(SP==totalSlots)
local selPat=0
if not onNew then selPat=SP end

-- compute track end
local trackEnd=0
for i=1,NP do
    local e=P[i].si+P[i].sc-1
    if e>trackEnd then trackEnd=e end
end
if trackEnd<TS then trackEnd=TS end

-- create candidate
local candStart=CR_START
if CR_MODE==1 then candStart=trackEnd+1 end
local candEnd=candStart+CR_LEN-1

-- detect conflict
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

-- current playing pattern
local curPat=0
for i=1,NP do
    local ps=P[i].si
    local pe=P[i].si+P[i].sc-1
    if TC>=ps and TC<=pe then
        curPat=i
        break
    end
end

-- colors
local bg={18,18,24}
local hd={30,30,42}
local tx={200,200,210}
local td={100,100,120}
local wh={255,255,255}
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
local listY=HH+RH+4
local rowH=16
local detailY=listY+VIS*rowH+4

local function truncName(text, maxLen)
    if #text<=maxLen then return text end
    return string.sub(text,1,maxLen)
end

-- clear
ggdrf(0,0,0,W,H,bg)

-- header
ggdrf(0,0,0,W,HH,hd)
ggdft(0,"PATTERNS V3",8,8,8,wh)
ggdft(0,"TRK"..TI,104,8,8,ch)
ggdft(0,DR,144,8,8,td)
ggdft(0,"ch"..CH,200,8,8,td)
ggdft(0,NP.."p/"..TS.."s",248,8,8,td)

-- timeline ribbon (placement context)
local rx=8
local ry=HH+4
local rw=W-16
local rh=8
ggdrf(0,rx,ry,rx+rw,ry+rh,{28,28,38})

-- loop region
if LE>=LS and TS>0 then
    local lx=rx+math.floor(rw*((LS-1)/TS))
    local ex=rx+math.floor(rw*(LE/TS))
    ggdrf(0,lx,ry,ex,ry+rh,lc)
end

-- selected/candidate region
if MODE=="BROWSE" and selPat>0 then
    local ps=P[selPat].si
    local pe=P[selPat].si+P[selPat].sc-1
    local sx=rx+math.floor(rw*((ps-1)/TS))
    local ex=rx+math.floor(rw*(pe/TS))
    ggdrf(0,sx,ry,sx+1,ry+rh,ch)
    ggdrf(0,ex-1,ry,ex,ry+rh,ch)
else
    local den=math.max(trackEnd+CR_LEN,1)
    local sx=rx+math.floor(rw*((candStart-1)/den))
    local ex=rx+math.floor(rw*(candEnd/den))
    ggdrf(0,sx,ry,ex,ry+rh,conflict and rd or nw)
end

-- playhead
local px=rx+math.floor(rw*(TC/math.max(TS,1)))
ggdrf(0,px,ry-2,px+1,ry+rh+2,wh)

-- list panel
ggdrf(0,8,listY,W-8,listY+VIS*rowH,{24,24,34})
ggdr(0,8,listY,W-8,listY+VIS*rowH,{45,45,65})

for i=1,VIS do
    local gi=SO+i
    local y=listY+(i-1)*rowH
    if gi<=totalSlots then
        local rowSel=(MODE=="BROWSE" and gi==SP)
        if rowSel then
            ggdrf(0,9,y+1,W-9,y+rowH-1,{34,40,58})
            ggdrf(0,8,y+1,10,y+rowH-1,ch)
        end

        if gi==totalSlots then
            ggdft(0,"+ NEW",16,y+4,8,nw)
            ggdft(0,"Create pattern",72,y+4,8,tx)
        else
            local p=P[gi]
            local ps=p.si
            local pe=p.si+p.sc-1
            local nm=truncName(p.nm,10)

            ggdft(0,"P"..gi,16,y+4,8,rowSel and wh or td)
            ggdft(0,nm,48,y+4,8,rowSel and tx or tx)
            ggdft(0,ps.."-"..pe,144,y+4,8,td)
            ggdft(0,p.sc.."s",208,y+4,8,rc)

            if gi==curPat then
                ggdft(0,"PLAY",240,y+4,8,gn)
            elseif LS<=pe and LE>=ps then
                ggdft(0,"LOOP",240,y+4,8,lc)
            end
        end

        if gi<totalSlots then
            ggdrf(0,12,y+rowH-1,W-12,y+rowH,{35,35,46})
        end
    end
end

-- scrollbar for long list
if totalSlots>VIS then
    local sx=W-5
    local sy=listY
    local sh=VIS*rowH
    local th=math.floor(sh*(VIS/totalSlots))
    if th<8 then th=8 end
    local ty=sy+math.floor((sh-th)*(SO/math.max(totalSlots-VIS,1)))
    ggdrf(0,sx,sy,sx+2,sy+sh,{32,32,40})
    ggdrf(0,sx,ty,sx+2,ty+th,td)
end

-- detail / create panel
ggdrf(0,8,detailY,W-8,H-FH-2,{24,24,34})
ggdr(0,8,detailY,W-8,H-FH-2,{45,45,65})

if MODE=="BROWSE" then
    if onNew then
        ggdft(0,"NEW PATTERN",16,detailY+8,8,nw)
        ggdft(0,"Press to enter create flow",16,detailY+24,8,tx)
    else
        local p=P[selPat]
        local ps=p.si
        local pe=p.si+p.sc-1
        ggdft(0,"P"..selPat.." \""..truncName(p.nm,14).."\"",16,detailY+8,8,ch)
        ggdft(0,"Range:"..ps.."-"..pe.."  Len:"..p.sc,16,detailY+24,8,tx)
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
    ggdft(0,"Mode:"..modeText.." Len:"..CR_LEN.." Start:"..candStart,16,detailY+24,8,tx)
    ggdft(0,"Range:"..candStart.."-"..candEnd.." "..okText,16,detailY+32,8,okColor)
end

-- footer
local fy=H-FH
ggdrf(0,0,fy,W,H,hd)
if MODE=="BROWSE" then
    ggdft(0,"Buttons navigate  Slider edits",8,fy+4,8,tx)
else
    ggdft(0,"Create mode: validate then confirm",8,fy+4,8,tx)
end

-- demo mode transitions for web preview
if MODE=="BROWSE" and onNew and n%180==0 then
    MODE="CREATE"
end
if MODE=="CREATE" and n%360==0 then
    MODE="BROWSE"
end
-- LOOP END
