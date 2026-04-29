local c,i,h,l,u,p,C,t
c=(function()local e={}local n=math.floor
local l=1
local a=128
local c=16384
local t=2097152
local i=268435456
local u=34359738368
local r=68719476736
local o=0
local o=127
local o=0
local o=127
local o=0
local o=99
local o=0
local o=99
local o=0
local o=100
local function o(t,e)return n(t/e)%128
end
local function o(e,t)return n(e/t)%2
end
local function o(e,o,t)local n=n(e/t)%128
return e+(o-n)*t
end
local function p(e,o,t)local r=n(e/t)%2
local n=o and 1 or 0
return e+(n-r)*t
end
function e.new(e,d,o,n,f,s)e=e or 60
d=d or 100
o=o or 4
n=n or 2
if f==nil then f=false end
s=s or 100
local n=e*l+d*a+o*c+n*t+s*i+r
if f then n=n+u end
return n
end
function e.getPitch(e)return n(e/l)%128 end
function e.getVelocity(e)return n(e/a)%128 end
function e.getDuration(e)return n(e/c)%128 end
function e.getGate(e)return n(e/t)%128 end
function e.getProbability(e)return n(e/i)%128 end
function e.getRatch(e)return n(e/u)%2==1 end
function e.getActive(e)return n(e/r)%2==1 end
function e.setPitch(n,e)return o(n,e,l)end
function e.setVelocity(n,e)return o(n,e,a)end
function e.setDuration(e,n)return o(e,n,c)end
function e.setGate(e,n)return o(e,n,t)end
function e.setRatch(e,n)return p(e,n,u)end
function e.setProbability(n,e)return o(n,e,i)end
function e.setActive(e,n)return p(e,n,r)end
function e.isPlayable(e)return n(e/r)%2==1
and n(e/c)%128>0
and n(e/t)%128>0
end
function e.sampleCv(e)return n(e/l)%128,n(e/a)%128
end
function e.sampleGate(o,l)if n(o/r)%2==0 then return false end
local r=n(o/c)%128
if r==0 then return false end
local e=n(o/t)%128
if e==0 then return false end
if e>=r then return true end
if n(o/u)%2==0 then
return l<e
end
if l>=r then return false end
local n=l%(e*2)return n<e
end
return e
end)()i=(function()local o=(c)local n={}local e=32
function n.new(n,e)n=n or 0
e=e or""local t={}for n=1,n do
t[n]=o.new()end
return{steps=t,stepCount=n,name=e,}end
function n.getStepCount(n)return n.stepCount
end
function n.getStep(e,n)return e.steps[n]end
function n.setStep(e,t,n)e.steps[t]=n
end
function n.getName(n)return n.name
end
function n.setName(n,e)n.name=e
end
return n
end)()h=(function()local n={}local e=32
local e=32
function n.new(e,n,t,o)e=e or 1
n=n or 4
t=t or""o=o or{}return{repeats=e,lengthBeats=n,name=t,trackLoops=o,}end
function n.setTrackLoop(n,e,o,t)if o==nil and t==nil then
n.trackLoops[e]=nil
return
end
n.trackLoops[e]={loopStart=o,loopEnd=t,}end
function n.getTrackLoop(e,n)return e.trackLoops[n]end
function n.setRepeats(e,n)e.repeats=n
end
function n.getRepeats(n)return n.repeats
end
function n.setLengthBeats(n,e)n.lengthBeats=e
end
function n.getLengthBeats(n)return n.lengthBeats
end
function n.setName(e,n)e.name=n
end
function n.getName(n)return n.name
end
function n.newChain()return{scenes={},sceneCount=0,cursor=1,repeatCount=0,beatCount=0,active=false,}end
function n.chainAppend(n,e)n.sceneCount=n.sceneCount+1
n.scenes[n.sceneCount]=e
return e
end
function n.chainInsert(n,o,t)n.sceneCount=n.sceneCount+1
for e=n.sceneCount,o+1,-1 do
n.scenes[e]=n.scenes[e-1]end
n.scenes[o]=t
return t
end
function n.chainRemove(n,e)for e=e,n.sceneCount-1 do
n.scenes[e]=n.scenes[e+1]end
n.scenes[n.sceneCount]=nil
n.sceneCount=n.sceneCount-1
if n.cursor>n.sceneCount then
n.cursor=math.max(1,n.sceneCount)end
end
function n.chainGetScene(n,e)return n.scenes[e]end
function n.chainGetCount(n)return n.sceneCount
end
function n.chainGetCurrent(n)if n.sceneCount==0 then
return nil
end
return n.scenes[n.cursor]end
function n.chainReset(n)n.cursor=1
n.repeatCount=0
n.beatCount=0
end
function n.chainSetActive(n,e)n.active=e
end
function n.chainIsActive(n)return n.active
end
function n.chainCompletePass(n)if n.sceneCount==0 then
return false
end
n.repeatCount=n.repeatCount+1
local e=n.scenes[n.cursor]if n.repeatCount>=e.repeats then
n.repeatCount=0
n.beatCount=0
if n.cursor>=n.sceneCount then
n.cursor=1
else
n.cursor=n.cursor+1
end
return true
end
return false
end
function n.chainBeat(e)if e.sceneCount==0 then
return false
end
e.beatCount=e.beatCount+1
local t=e.scenes[e.cursor]if e.beatCount>=t.lengthBeats then
e.beatCount=0
return n.chainCompletePass(e)end
return false
end
function n.chainJumpTo(n,e)n.cursor=e
n.repeatCount=0
n.beatCount=0
end
function n.applyToTracks(o,e,n)local t=(l)for n=1,n do
local o=o.trackLoops[n]if o~=nil then
t.clearLoopStart(e[n])t.clearLoopEnd(e[n])t.setLoopStart(e[n],o.loopStart)t.setLoopEnd(e[n],o.loopEnd)end
end
end
return n
end)()l=(function()local e=(i)local r=(c)local n={}local l="forward"local c="reverse"local i="pingpong"local a="random"local u="brownian"local function t(n)return n==l or
n==c or
n==i or
n==a or
n==u
end
local function t(t)local n=0
for o=1,t.patternCount do
n=n+e.getStepCount(t.patterns[o])end
return n
end
local function o(o,t)local n=0
for r=1,o.patternCount do
local o=o.patterns[r]local r=e.getStepCount(o)if t<=n+r then
return e.getStep(o,t-n)end
n=n+r
end
return nil
end
local function s(n,e,t)if n>=t then
return e
end
return n+1
end
local function f(n,e,t)if n<=e then
return t
end
return n-1
end
local function d(n,e)return math.random(n,e)end
local function g(n,t,o)local e=math.random(1,4)if e==1 then
if n<=t then
return o
end
return n-1
end
if e==2 then
return n
end
if n>=o then
return t
end
return n+1
end
local function h(t,n,e,o)if e==o then
return e
end
if t.pingPongDir>0 then
if n>=o then
t.pingPongDir=-1
return n-1
end
return n+1
end
if n<=e then
t.pingPongDir=1
return n+1
end
return n-1
end
local function C(e,t,n)if e.direction==c then
return n
end
if e.direction==a then
return d(t,n)end
return t
end
local function p(e,o,n,t)if e.direction==l then
return s(o,n,t)end
if e.direction==c then
return f(o,n,t)end
if e.direction==a then
return d(n,t)end
if e.direction==u then
return g(o,n,t)end
return h(e,o,n,t)end
local function a(n,e)local t=t(n)if t==0 then
return 1
end
local o=n.loopStart or 1
local t=n.loopEnd or t
if e<o or e>t then
return C(n,o,t)end
return p(n,e,o,t)end
function n.new()return{patterns={},patternCount=0,cursor=1,pulseCounter=0,loopStart=nil,loopEnd=nil,clockDiv=1,clockMult=1,clockAccum=0,direction=l,pingPongDir=1,midiChannel=nil,currentStepGateEnabled=true,}end
function n.addPattern(n,t)t=t or 8
local e=e.new(t)n.patternCount=n.patternCount+1
n.patterns[n.patternCount]=e
return e
end
function n.getPattern(n,e)return n.patterns[e]end
function n.getPatternCount(n)return n.patternCount
end
function n.patternStartIndex(o,t)local n=0
for t=1,t-1 do
n=n+e.getStepCount(o.patterns[t])end
return n+1
end
function n.patternEndIndex(o,t)local n=0
for t=1,t do
n=n+e.getStepCount(o.patterns[t])end
return n
end
function n.copyPattern(t,n)local o=require("utils")local o=t.patterns[n]local r=e.getStepCount(o)local n=e.new(0,e.getName(o))n.steps={}n.stepCount=r
for e=1,r do
n.steps[e]=o.steps[e]end
t.patternCount=t.patternCount+1
t.patterns[t.patternCount]=n
return n
end
function n.duplicatePattern(n,t)local o=require("utils")local o=n.patterns[t]local r=e.getStepCount(o)local e=e.new(0,e.getName(o))e.steps={}e.stepCount=r
for t=1,r do
e.steps[t]=o.steps[t]end
n.patternCount=n.patternCount+1
for e=n.patternCount,t+2,-1 do
n.patterns[e]=n.patterns[e-1]end
n.patterns[t+1]=e
return e
end
local function l(n,e)for e=e,n.patternCount-1 do
n.patterns[e]=n.patterns[e+1]end
n.patterns[n.patternCount]=nil
n.patternCount=n.patternCount-1
end
local function c(n,o,e,t)if n==nil then return nil end
if n>=o and n<=e then return nil end
if n>e then return n-t end
return n
end
function n.deletePattern(e,t)local o=n.patternStartIndex(e,t)local n=n.patternEndIndex(e,t)local r=n-o+1
l(e,t)e.loopStart=c(e.loopStart,o,n,r)e.loopEnd=c(e.loopEnd,o,n,r)e.cursor=1
e.pulseCounter=0
end
local function c(e,o,t)if t<=0 then
return
end
local n=n.patternStartIndex(e,o)if e.loopStart~=nil and e.loopStart>=n then
e.loopStart=e.loopStart+t
end
if e.loopEnd~=nil and e.loopEnd>=n then
e.loopEnd=e.loopEnd+t
end
end
function n.insertPattern(n,o,t)t=t or 8
local r=e.new(t)n.patternCount=n.patternCount+1
for e=n.patternCount,o+1,-1 do
n.patterns[e]=n.patterns[e-1]end
n.patterns[o]=r
c(n,o,t)n.cursor=1
n.pulseCounter=0
return r
end
function n.swapPatterns(n,e,t)if e==t then return end
n.patterns[e],n.patterns[t]=n.patterns[t],n.patterns[e]n.loopStart=nil
n.loopEnd=nil
n.cursor=1
n.pulseCounter=0
end
function n.pastePattern(t,n,e)local o=require("utils")local n=t.patterns[n]local o=e.stepCount
n.steps={}n.stepCount=o
for t=1,o do
n.steps[t]=e.steps[t]end
n.name=e.name
t.cursor=1
t.pulseCounter=0
end
function n.getStepCount(n)return t(n)end
function n.getStep(n,e)local t=t(n)return o(n,e)end
function n.setStep(o,r,c)local n=t(o)local n=0
for t=1,o.patternCount do
local t=o.patterns[t]local o=e.getStepCount(t)if r<=n+o then
e.setStep(t,r-n,c)return
end
n=n+o
end
end
function n.getCurrentStep(n)return o(n,n.cursor)end
function n.setLoopStart(n,e)local t=t(n)if n.loopEnd~=nil then
end
n.loopStart=e
end
function n.setLoopEnd(n,e)local t=t(n)if n.loopStart~=nil then
end
n.loopEnd=e
end
function n.clearLoopStart(n)n.loopStart=nil
end
function n.clearLoopEnd(n)n.loopEnd=nil
end
function n.getLoopStart(n)return n.loopStart
end
function n.getLoopEnd(n)return n.loopEnd
end
function n.setClockDiv(n,e)n.clockDiv=e
end
function n.getClockDiv(n)return n.clockDiv
end
function n.setClockMult(n,e)n.clockMult=e
end
function n.getClockMult(n)return n.clockMult
end
function n.setMidiChannel(e,n)e.midiChannel=n
end
function n.clearMidiChannel(n)n.midiChannel=nil
end
function n.getMidiChannel(n)return n.midiChannel
end
function n.setDirection(e,n)e.direction=n
if n==i then
e.pingPongDir=1
end
end
function n.getDirection(n)return n.direction
end
local function c(e,n)if n==nil then
e.currentStepGateEnabled=false
return
end
local n=r.getProbability(n)if n==nil or n>=100 then
e.currentStepGateEnabled=true
elseif n<=0 then
e.currentStepGateEnabled=false
else
e.currentStepGateEnabled=math.random(1,100)<=n
end
end
local function l(n,l)local u=n.cursor
local e=o(n,n.cursor)local t=0
while e~=nil and r.getDuration(e)==0 do
n.cursor=a(n,n.cursor)n.pulseCounter=0
e=o(n,n.cursor)t=t+1
if t>l then
return nil
end
end
if n.cursor~=u then
c(n,e)end
return e
end
function n.sample(n)local e=t(n)if e==0 then
return 0,0,false
end
local e=l(n,e)if e==nil then
return 0,0,false
end
local o,t=r.sampleCv(e)local n=r.sampleGate(e,n.pulseCounter)and n.currentStepGateEnabled
return o,t,n
end
function n.advance(n)local e=t(n)if e==0 then
return
end
local e=l(n,e)if e==nil then
return
end
n.pulseCounter=n.pulseCounter+1
if n.pulseCounter>=r.getDuration(e)then
n.pulseCounter=0
n.cursor=a(n,n.cursor)local e=o(n,n.cursor)c(n,e)end
end
function n.reset(n)n.cursor=1
n.pulseCounter=0
n.clockAccum=0
n.pingPongDir=1
local e=o(n,1)c(n,e)end
return n
end)()u=(function()local t=(l)local e=(h)local n={}function n.bpmToMs(e,n)n=n or 4
return(60000/e)/n
end
local function c(o,e)local n={}for r=1,o do
local o=t.new()if e>0 then
t.addPattern(o,e)end
n[r]=o
end
return n
end
function n.new(e,t,o,r)e=e or 120
t=t or 4
o=o or 4
r=r or 8
return{bpm=e,pulsesPerBeat=t,pulseIntervalMs=n.bpmToMs(e,t),tracks=c(o,r),trackCount=o,sceneChain=nil,}end
function n.getTrack(n,e)return n.tracks[e]end
function n.setSceneChain(e,n)if n~=nil then
end
e.sceneChain=n
end
function n.getSceneChain(n)return n.sceneChain
end
function n.clearSceneChain(n)n.sceneChain=nil
end
function n.activateSceneChain(n)local t=n.sceneChain
e.chainSetActive(t,true)e.chainReset(t)local t=e.chainGetCurrent(t)if t then
e.applyToTracks(t,n.tracks,n.trackCount)end
end
function n.deactivateSceneChain(n)local n=n.sceneChain
if n then
e.chainSetActive(n,false)end
end
local function o(n,t)if n.sceneChain==nil or not e.chainIsActive(n.sceneChain)then
return
end
if t%n.pulsesPerBeat~=0 then
return
end
local t=e.chainBeat(n.sceneChain)if t then
local t=e.chainGetCurrent(n.sceneChain)if t then
e.applyToTracks(t,n.tracks,n.trackCount)end
end
end
function n.advanceTrack(n,e)t.advance(n.tracks[e])end
function n.sampleTrack(n,e)return t.sample(n.tracks[e])end
function n.onPulse(e,n)o(e,n)end
function n.reset(n)for e=1,n.trackCount do
t.reset(n.tracks[e])end
if n.sceneChain and e.chainIsActive(n.sceneChain)then
e.chainReset(n.sceneChain)local t=e.chainGetCurrent(n.sceneChain)if t then
e.applyToTracks(t,n.tracks,n.trackCount)end
end
end
return n
end)()p=(function()local r={}function r.new()return{prevGate=false,lastPitch=nil,}end
function r.step(n,e,a,l,o,t)local c=n.prevGate
local r=n.lastPitch
if l then
if not c then
t("NOTE_ON",e,a,o)n.lastPitch=e
elseif r~=e then
t("NOTE_OFF",r,nil,o)t("NOTE_ON",e,a,o)n.lastPitch=e
end
else
if c then
t("NOTE_OFF",r,nil,o)n.lastPitch=nil
end
end
n.prevGate=l
end
function r.panic(n,t,e)if n.prevGate and n.lastPitch~=nil then
e("NOTE_OFF",n.lastPitch,nil,t)end
n.prevGate=false
n.lastPitch=nil
end
return r
end)()C=(function()local r=(u)local e=(l)local t=(i)local c=(c)local o={}local function a(n)return c.new(n[1],n[2],n[3],n[4],n[5],n[6])end
local function l(e,n)if n.name then
t.setName(e,n.name)end
local n=n.steps or{}for o,n in ipairs(n)do
t.setStep(e,o,a(n))end
end
local function c(t,n)if n.channel then
e.setMidiChannel(t,n.channel)end
if n.direction then
e.setDirection(t,n.direction)end
if n.clockDiv then
e.setClockDiv(t,n.clockDiv)end
if n.clockMult then
e.setClockMult(t,n.clockMult)end
local o=n.patterns or{}for o,n in ipairs(o)do
local o=#(n.steps or{})local e=e.addPattern(t,o)l(e,n)end
if n.loopStart then
e.setLoopStart(t,n.loopStart)end
if n.loopEnd then
e.setLoopEnd(t,n.loopEnd)end
end
function o.build(n)local e=#n.tracks
local e=r.new(n.bpm,n.ppb,e,0)for t,n in ipairs(n.tracks)do
c(r.getTrack(e,t),n)end
return e
end
function o.load(n)local n=require(n)return o.build(n)end
return o
end)()t=(function()local t=(u)local c=(p)local n={}function n.new(e,r,n)n=n or e.bpm
local o={}for n=1,e.trackCount do
o[n]=c.new()end
return{engine=e,clockFn=r,bpm=n,pulseMs=t.bpmToMs(n,e.pulsesPerBeat),translators=o,startMs=0,pulseCount=0,running=false,}end
function n.start(n)if n.clockFn then n.startMs=n.clockFn()end
n.pulseCount=0
n.running=true
end
function n.stop(n)n.running=false
end
function n.setBpm(n,e)n.bpm=e
n.pulseMs=t.bpmToMs(e,n.engine.pulsesPerBeat)if n.clockFn then
n.startMs=n.clockFn()-n.pulseCount*n.pulseMs
end
end
function n.allNotesOff(t,o)local n=t.engine
for e=1,n.trackCount do
local n=n.tracks[e]local n=n.midiChannel or 1
c.panic(t.translators[e],n,o)end
end
function n.externalPulse(e,u)if not e.running then return end
e.pulseCount=e.pulseCount+1
local o=e.engine
for r=1,o.trackCount do
local n=o.tracks[r]local i=n.midiChannel or 1
n.clockAccum=n.clockAccum+n.clockMult
local l=math.floor(n.clockAccum/n.clockDiv)n.clockAccum=n.clockAccum%n.clockDiv
for n=1,l do
local n,l,a=t.sampleTrack(o,r)c.step(e.translators[r],n,l,a,i,u)t.advanceTrack(o,r)end
end
t.onPulse(o,e.pulseCount)end
function n.tick(e,o)if not e.running then return end
local t=math.floor((e.clockFn()-e.startMs)/e.pulseMs)while e.pulseCount<t do
n.externalPulse(e,o)if not e.running then return end
end
end
return n
end)()if t.Engine==nil then t.Engine=u end
if t.MidiTranslate==nil then t.MidiTranslate=p end
if t.PatchLoader==nil then t.PatchLoader=C end
if t.Pattern==nil then t.Pattern=i end
if t.Scene==nil then t.Scene=h end
if t.Step==nil then t.Step=c end
if t.Track==nil then t.Track=l end
return t