-- stepedit.lua
-- Step Edit screen: detailed view of a single step's parameters
-- Shows pitch, velocity, duration, gate, ratchet, active with visual bars

-- INIT START
n=0
SI=5
S={{p=60,v=100,d=4,g=2,r=1,a=1},{p=63,v=90,d=4,g=3,r=1,a=1},{p=67,v=110,d=4,g=2,r=2,a=1},{p=70,v=80,d=4,g=0,r=1,a=1},{p=72,v=100,d=4,g=4,r=1,a=1},{p=67,v=95,d=4,g=2,r=3,a=1},{p=63,v=85,d=0,g=2,r=1,a=1},{p=60,v=100,d=4,g=2,r=1,a=0}}
NT=#S
NN={"C","C#","D","Eb","E","F","F#","G","G#","A","Bb","B"}
PL={"PITCH","VEL","DUR","GATE","RATCH","ACTIV"}
PM=6
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
print("stepedit init ok")
-- INIT END

-- LOOP START
n=n+1

-- navigation with 4 buttons
if navButtonPressed(BTN_LEFT) then SP=navMoveIndex(SP,1,PM,-1) end
if navButtonPressed(BTN_RIGHT) then SP=navMoveIndex(SP,1,PM,1) end
if navButtonPressed(BTN_UP) then SP=navMoveIndex(SP,1,PM,-1) end
if navButtonPressed(BTN_DOWN) then SP=navMoveIndex(SP,1,PM,1) end

local s=S[SI]

-- slider edits value of focused parameter
if SP==1 then s.p=math.floor(sliderValue/255*127) end
if SP==2 then s.v=math.floor(sliderValue/255*127) end
if SP==3 then s.d=math.floor(sliderValue/255*99) end
if SP==4 then s.g=math.floor(sliderValue/255*99) end
if SP==5 then s.r=math.floor(sliderValue/255*3)+1 end
if SP==6 then
    if sliderValue>=128 then s.a=1 else s.a=0 end
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
local HH=22
local FH=18

-- clear
ggdrf(0,0,0,W,H,bg)

-- header
ggdrf(0,0,0,W,HH,hd)
ggdft(0,"STEP "..SI.."/"..NT,4,4,8,tx)
local pn=NN[(s.p%12)+1]..tostring(math.floor(s.p/12)-1)
ggdft(0,pn,90,4,8,ch)
if s.a==0 then
    ggdft(0,"[MUTED]",140,4,8,rd)
end
if s.d==0 then
    ggdft(0,"[SKIP]",210,4,8,rd)
elseif s.g==0 then
    ggdft(0,"[REST]",210,4,8,rc)
end

-- parameter rows
local py=HH+4
local rh=26
local lw=50
local bx=lw+4
local vw=56
local bw=W-bx-vw-4
local brh=14

-- param data: {label, value, max, display, color}
local params={}
params[1]={l="PITCH",v=s.p,mx=127,c=ch}
params[2]={l="VEL",v=s.v,mx=127,c=gn}
params[3]={l="DUR",v=s.d,mx=99,c=cb}
params[4]={l="GATE",v=s.g,mx=99,c=cb}
params[5]={l="RATCH",v=s.r,mx=4,c=rc}
params[6]={l="ACTIVE",v=s.a,mx=1,c=gn}

for i=1,PM do
    local pr=params[i]
    local ry=py+(i-1)*rh
    local sel=(i==SP)

    -- selected row highlight
    if sel then
        ggdrf(0,0,ry-2,W,ry+rh-4,{30,30,50})
        ggdrf(0,0,ry-2,3,ry+rh-4,ch)
    end

    -- label
    local lc2=td
    if sel then lc2=wh end
    ggdft(0,pr.l,8,ry+2,8,lc2)

    -- value display
    local vt=""
    if i==1 then
        -- pitch: show note name + number
        vt=NN[(s.p%12)+1]..tostring(math.floor(s.p/12)-1).." ("..s.p..")"
    elseif i==6 then
        -- active: ON/OFF
        if s.a==1 then vt="ON" else vt="OFF" end
    elseif i==5 then
        -- ratchet: show count with dots
        vt=tostring(pr.v).."x"
    else
        vt=tostring(pr.v)
    end

    -- bar background
    ggdrf(0,bx,ry+2,bx+bw,ry+2+brh,bar)

    if i==5 then
        -- ratchet: discrete blocks
        local blockW=math.floor(bw/4)-2
        for r=1,4 do
            local rx=bx+2+(r-1)*(blockW+2)
            local clr=bar
            if r<=pr.v then
                clr=pr.c
                if sel then clr={255,220,80} end
            end
            ggdrf(0,rx,ry+4,rx+blockW,ry+brh,clr)
        end
    elseif i==6 then
        -- active: on/off toggle
        if s.a==1 then
            ggdrf(0,bx+2,ry+4,bx+bw-2,ry+brh,pr.c)
            if sel then ggdrf(0,bx+2,ry+4,bx+bw-2,ry+brh,{80,255,140}) end
        else
            ggdrf(0,bx+2,ry+4,bx+bw-2,ry+brh,rd)
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

    -- value text after bar
    local vtc=tx
    if sel then vtc=wh end
    ggdft(0,vt,bx+bw+6,ry+4,8,vtc)
end

-- piano keyboard visualization (bottom area)
local ky=py+PM*rh+4
local kh=H-ky-FH-4
if kh>20 then
    local kw=math.floor(W/24)
    local startOct=math.floor(s.p/12)-1
    local startNote=startOct*12
    -- draw 2 octaves of keys
    for i=0,23 do
        local note=startNote+i
        local kx=4+i*kw
        local isBlack=false
        local m=note%12
        if m==1 or m==3 or m==6 or m==8 or m==10 then isBlack=true end

        local kc={55,55,65}
        if isBlack then kc={30,30,38} end
        if note==s.p then
            kc=ch
        end
        ggdrf(0,kx,ky,kx+kw-1,ky+kh,kc)

        -- note name on current note
        if note==s.p then
            local nm=NN[(note%12)+1]
            ggdft(0,nm,kx+1,ky+kh-10,8,{20,20,30})
        end

        -- C markers
        if m==0 then
            ggdft(0,"C"..tostring(math.floor(note/12)-1),kx+1,ky+1,8,td)
        end
    end
end

-- footer
local fy=H-FH
ggdrf(0,0,fy,W,H,hd)
ggdft(0,"Step "..SI..": "..pn.." v"..s.v.." d"..s.d.." g"..s.g.." r"..s.r,4,fy+3,8,tx)
if s.a==0 then ggdft(0,"MUTED",260,fy+3,8,rd) end
-- LOOP END
