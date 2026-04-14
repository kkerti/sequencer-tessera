-- settings.lua
-- Global settings screen for sequencer runtime and sync behavior
-- Follows current VSN1 visual style used by existing screens

-- INIT START
n=0
PL={"CLK SRC","RUN MODE","START","STOP","CONTINUE","RESET MODE","CLK LOSS","BPM","PPQN IN","SWING","SCALE","ROOT"}
PM=#PL
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

function optionIndexFromSlider(optionCount)
    local ix=math.floor(sliderValue/255*(optionCount-1))+1
    if ix<1 then ix=1 end
    if ix>optionCount then ix=optionCount end
    return ix
end

CFG={
clkSrc={opts={"INT","USB"},ix=2},
runMode={opts={"FREE","TRANSPORT"},ix=2},
onStart={opts={"RUN","RESET+RUN"},ix=2},
onStop={opts={"PAUSE","STOP+OFF"},ix=2},
onContinue={opts={"RUN","RESET+RUN"},ix=1},
resetMode={opts={"IMMEDIATE","NEXT PULSE"},ix=1},
clockLoss={opts={"HOLD","STOP+OFF","INTERNAL"},ix=2},
bpm=120,
ppqnIn={opts={"24","12","4"},ix=1},
swing=58,
scale={opts={"OFF","MAJOR","MINOR PENT","DORIAN","CHROMATIC"},ix=3},
root={opts={"C","C#","D","Eb","E","F","F#","G","G#","A","Bb","B"},ix=1}
}

print("settings init ok")
-- INIT END

-- LOOP START
n=n+1

-- navigation with 4 buttons
if navButtonPressed(BTN_LEFT) then SP=navMoveIndex(SP,1,PM,-1) end
if navButtonPressed(BTN_RIGHT) then SP=navMoveIndex(SP,1,PM,1) end
if navButtonPressed(BTN_UP) then SP=navMoveIndex(SP,1,PM,-1) end
if navButtonPressed(BTN_DOWN) then SP=navMoveIndex(SP,1,PM,1) end

-- slider edits focused row
if SP==1 then CFG.clkSrc.ix=optionIndexFromSlider(#CFG.clkSrc.opts) end
if SP==2 then CFG.runMode.ix=optionIndexFromSlider(#CFG.runMode.opts) end
if SP==3 then CFG.onStart.ix=optionIndexFromSlider(#CFG.onStart.opts) end
if SP==4 then CFG.onStop.ix=optionIndexFromSlider(#CFG.onStop.opts) end
if SP==5 then CFG.onContinue.ix=optionIndexFromSlider(#CFG.onContinue.opts) end
if SP==6 then CFG.resetMode.ix=optionIndexFromSlider(#CFG.resetMode.opts) end
if SP==7 then CFG.clockLoss.ix=optionIndexFromSlider(#CFG.clockLoss.opts) end
if SP==8 then CFG.bpm=math.floor(sliderValue/255*270)+30 end
if SP==9 then CFG.ppqnIn.ix=optionIndexFromSlider(#CFG.ppqnIn.opts) end
if SP==10 then CFG.swing=math.floor(sliderValue/255*22)+50 end
if SP==11 then CFG.scale.ix=optionIndexFromSlider(#CFG.scale.opts) end
if SP==12 then CFG.root.ix=optionIndexFromSlider(#CFG.root.opts) end

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
local bar={45,45,60}

-- layout
local W,H=320,240
local HH=22
local FH=18
local py=HH+4
local rh=16
local lw=88
local bx=lw+4
local bw=132
local vx=bx+bw+8

-- clear
ggdrf(0,0,0,W,H,bg)

-- header
ggdrf(0,0,0,W,HH,hd)
ggdft(0,"SETTINGS",4,4,8,wh)
ggdft(0,"SEQ ENGINE",84,4,8,td)
if CFG.clkSrc.ix==2 then
    ggdft(0,"USB SYNC",248,4,8,gn)
else
    ggdft(0,"INT CLK",256,4,8,rc)
end

local function drawOptionRow(row,label,opts,ix,accent)
    local ry=py+(row-1)*rh
    local sel=(row==SP)
    if sel then
        ggdrf(0,0,ry-1,W,ry+rh-2,{30,30,50})
        ggdrf(0,0,ry-1,3,ry+rh-2,ch)
    end

    local lc=td
    if sel then lc=wh end
    ggdft(0,label,6,ry+2,8,lc)

    ggdrf(0,bx,ry+2,bx+bw,ry+10,bar)
    local count=#opts
    local segW=math.floor(bw/count)
    for i=1,count do
        local sx=bx+(i-1)*segW
        local sc={55,55,68}
        if i==ix then
            sc=accent
            if sel then
                sc={math.min(accent[1]+25,255),math.min(accent[2]+25,255),math.min(accent[3]+25,255)}
            end
        end
        ggdrf(0,sx,ry+3,sx+segW-2,ry+9,sc)
    end

    local vc=tx
    if sel then vc=wh end
    ggdft(0,opts[ix],vx,ry+2,8,vc)
end

local function drawValueRow(row,label,value,maxValue,display,accent)
    local ry=py+(row-1)*rh
    local sel=(row==SP)
    if sel then
        ggdrf(0,0,ry-1,W,ry+rh-2,{30,30,50})
        ggdrf(0,0,ry-1,3,ry+rh-2,ch)
    end

    local lc=td
    if sel then lc=wh end
    ggdft(0,label,6,ry+2,8,lc)

    ggdrf(0,bx,ry+2,bx+bw,ry+10,bar)
    local fill=math.floor(bw*(value/maxValue))
    if fill<1 then fill=1 end
    local fc=accent
    if sel then
        fc={math.min(accent[1]+25,255),math.min(accent[2]+25,255),math.min(accent[3]+25,255)}
    end
    ggdrf(0,bx,ry+2,bx+fill,ry+10,fc)

    local vc=tx
    if sel then vc=wh end
    ggdft(0,display,vx,ry+2,8,vc)
end

drawOptionRow(1,"CLK SRC",CFG.clkSrc.opts,CFG.clkSrc.ix,gn)
drawOptionRow(2,"RUN MODE",CFG.runMode.opts,CFG.runMode.ix,cb)
drawOptionRow(3,"ON START",CFG.onStart.opts,CFG.onStart.ix,cb)
drawOptionRow(4,"ON STOP",CFG.onStop.opts,CFG.onStop.ix,rd)
drawOptionRow(5,"ON CONT",CFG.onContinue.opts,CFG.onContinue.ix,cb)
drawOptionRow(6,"RESET",CFG.resetMode.opts,CFG.resetMode.ix,rc)
drawOptionRow(7,"CLK LOSS",CFG.clockLoss.opts,CFG.clockLoss.ix,rd)
drawValueRow(8,"BPM",CFG.bpm,300,tostring(CFG.bpm),cb)
drawOptionRow(9,"PPQN IN",CFG.ppqnIn.opts,CFG.ppqnIn.ix,rc)
drawValueRow(10,"SWING",CFG.swing,72,tostring(CFG.swing).."%",ch)
drawOptionRow(11,"SCALE",CFG.scale.opts,CFG.scale.ix,gn)
drawOptionRow(12,"ROOT",CFG.root.opts,CFG.root.ix,cb)

-- footer
local fy=H-FH
ggdrf(0,0,fy,W,H,hd)
ggdft(0,"SEL:"..PL[SP],4,fy+3,8,tx)
ggdft(0,"Slider edits value",176,fy+3,8,td)
-- LOOP END
