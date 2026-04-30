-- trackconfig.lua
-- Track Config screen: per-track settings editor
-- Direction, clock, loop points, MIDI channel

-- INIT START
n=0
TI=1
T={
{nm="TRK1",ch=1,dr="forward",cd=1,cm=1,ls=1,le=8,mt=0,ns=8},
{nm="TRK2",ch=2,dr="reverse",cd=2,cm=1,ls=2,le=6,mt=0,ns=8},
{nm="TRK3",ch=3,dr="pingpong",cd=1,cm=2,ls=1,le=4,mt=1,ns=4},
{nm="TRK4",ch=10,dr="random",cd=4,cm=1,ls=1,le=8,mt=0,ns=8}
}
NT=4
BPM=120
DR={"forward","reverse","pingpong","random","brownian"}
PL={"DIR","CLK/","CLKx","LOOP S","LOOP E","MIDI CH","MUTE"}
PM=7
SP=1
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
print("trackconfig init ok")
-- INIT END

-- LOOP START
n=n+1

-- navigation with 4 buttons
if navButtonPressed(BTN_LEFT) then SP=navMoveIndex(SP,1,PM,-1) end
if navButtonPressed(BTN_RIGHT) then SP=navMoveIndex(SP,1,PM,1) end
if navButtonPressed(BTN_UP) then SP=navMoveIndex(SP,1,PM,-1) end
if navButtonPressed(BTN_DOWN) then SP=navMoveIndex(SP,1,PM,1) end

local t=T[TI]

-- slider edits value of focused parameter
if SP==1 then
    local dirIndex=math.floor(sliderValue/255*(#DR-1))+1
    if dirIndex<1 then dirIndex=1 end
    if dirIndex>#DR then dirIndex=#DR end
    t.dr=DR[dirIndex]
elseif SP==2 then
    t.cd=math.floor(sliderValue/255*15)+1
elseif SP==3 then
    t.cm=math.floor(sliderValue/255*7)+1
elseif SP==4 then
    t.ls=math.floor(sliderValue/255*(t.ns-1))+1
    if t.ls>t.le then t.ls=t.le end
elseif SP==5 then
    t.le=math.floor(sliderValue/255*(t.ns-1))+1
    if t.le<t.ls then t.le=t.ls end
elseif SP==6 then
    t.ch=math.floor(sliderValue/255*15)+1
elseif SP==7 then
    if sliderValue>=128 then t.mt=1 else t.mt=0 end
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
local bar={45,45,60}

-- layout
local W,H=320,240
local HH=24
local FH=18

-- clear
ggdrf(0,0,0,W,H,bg)

-- header
ggdrf(0,0,0,W,HH,hd)
ggdft(0,t.nm.." CONFIG",4,4,8,wh)
ggdft(0,tostring(BPM).."bpm",140,4,8,tx)
ggdft(0,t.ns.." steps",270,4,8,td)

-- track selector tabs
local tabY=HH+2
local tabH=16
local tabW=math.floor(W/NT)
for i=1,NT do
    local tx2=T[i]
    local x=(i-1)*tabW
    local sel=(i==TI)
    if sel then
        ggdrf(0,x,tabY,x+tabW-2,tabY+tabH,{40,40,60})
    else
        ggdrf(0,x,tabY,x+tabW-2,tabY+tabH,{28,28,38})
    end
    local tc=td
    if sel then tc=wh end
    if tx2.mt==1 then tc={80,50,55} end
    ggdft(0,tx2.nm,x+12,tabY+3,8,tc)
end

-- parameter rows
local py=tabY+tabH+6
local rh=24
local lw=62
local bx=lw+4
local vw=80
local bw=W-bx-vw-8
local brh=12

-- direction -> index for bar
local dirIdx=1
for di=1,#DR do
    if DR[di]==t.dr then dirIdx=di end
end

-- param definitions
local params={}
params[1]={l="DIR",v=dirIdx,mx=#DR,ds=t.dr,c=ch}
params[2]={l="CLK /",v=t.cd,mx=16,ds="/"..t.cd,c=rc}
params[3]={l="CLK x",v=t.cm,mx=8,ds="x"..t.cm,c=rc}
params[4]={l="LOOP S",v=t.ls,mx=t.ns,ds=tostring(t.ls),c=lc}
params[5]={l="LOOP E",v=t.le,mx=t.ns,ds=tostring(t.le),c=lc}
params[6]={l="MIDI CH",v=t.ch,mx=16,ds=tostring(t.ch),c=gn}
params[7]={l="MUTE",v=t.mt,mx=1,ds="",c=gn}

for i=1,PM do
    local pr=params[i]
    local ry=py+(i-1)*rh
    local sel=(i==SP)

    -- selected row highlight
    if sel then
        ggdrf(0,0,ry-1,W,ry+rh-3,{30,30,50})
        ggdrf(0,0,ry-1,3,ry+rh-3,ch)
    end

    -- label
    local lclr=td
    if sel then lclr=wh end
    ggdft(0,pr.l,8,ry+2,8,lclr)

    -- bar background
    ggdrf(0,bx,ry+2,bx+bw,ry+2+brh,bar)

    if i==7 then
        -- mute: toggle
        if t.mt==0 then
            ggdrf(0,bx+2,ry+3,bx+bw-2,ry+1+brh,gn)
            pr.ds="OFF"
        else
            ggdrf(0,bx+2,ry+3,bx+bw-2,ry+1+brh,rd)
            pr.ds="MUTED"
        end
    elseif i==1 then
        -- direction: discrete blocks
        local blockW=math.floor(bw/#DR)-2
        for d=1,#DR do
            local dx=bx+2+(d-1)*(blockW+2)
            local clr=bar
            if d==dirIdx then
                clr=pr.c
                if sel then clr={140,200,255} end
            end
            ggdrf(0,dx,ry+3,dx+blockW,ry+1+brh,clr)
        end
    elseif i==4 or i==5 then
        -- loop: show position within step range
        local fill=math.floor(bw*(pr.v/pr.mx))
        if fill<2 then fill=2 end
        ggdrf(0,bx,ry+2,bx+fill,ry+2+brh,pr.c)
        -- show loop region
        if i==4 then
            local ls=math.floor(bw*(t.ls/t.ns))
            local le=math.floor(bw*(t.le/t.ns))
            ggdrf(0,bx+ls,ry+brh+1,bx+le,ry+brh+3,{lc[1],lc[2],lc[3]})
        end
    else
        -- continuous bar
        local fill=math.floor(bw*(pr.v/pr.mx))
        if fill<1 then fill=1 end
        local fc=pr.c
        if sel then
            fc={math.min(fc[1]+40,255),math.min(fc[2]+40,255),math.min(fc[3]+40,255)}
        end
        ggdrf(0,bx,ry+2,bx+fill,ry+2+brh,fc)
    end

    -- value text
    local vtc=tx
    if sel then vtc=wh end
    ggdft(0,pr.ds,bx+bw+6,ry+3,8,vtc)
end

-- footer
local fy=H-FH
ggdrf(0,0,fy,W,H,hd)
local info=t.nm.." "..t.dr.." /"..t.cd.." x"..t.cm.." ch"..t.ch
ggdft(0,info,4,fy+3,8,tx)
ggdft(0,"loop:"..t.ls.."-"..t.le,240,fy+3,8,lc)
-- LOOP END
