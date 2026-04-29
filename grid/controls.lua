local e=require("/sequencer")local t=e.Step
local e=e.Track
local w
w=(function()local o=(t)local n=(e)local r={}local e
local w={s="STEP",t="TRK",p="PAT",m="DIR",b="NOTE",a="VEL",d="DUR",g="GATE",l="LSTRT",e="LEND"}local g={"s","t","p","m","b","a","d","g"}local i={"forward","reverse","pingpong","random","brownian"}local m={}for t,e in ipairs(i)do m[e]=t end
r.PO=g
r.LB=w
local p,u=80,60
local f=121
local t=240-f
local _=f+4
local h=f+28
local S=40
local y=8
local function c(e,t,l)if e<t then return t end
if e>l then return l end
return e
end
local function a()return e.engine.tracks[e.tr]end
local function s()return n.getStep(a(),e.st)end
local function D()local e=e.dirty
e.b=true;e.a=true;e.d=true;e.g=true
end
function r.init(t)e={engine=t,sel="s",prev="s",tr=1,pa=1,st=1,cur=0,dirty={s=true,t=true,p=true,m=true,b=true,a=true,d=true,g=true},focusDirty=true,timelineDirty=true,}r.S=e
end
function r.value(t)if t=="s"then return e.st end
if t=="t"then return e.tr end
if t=="p"then return e.pa end
if t=="m"then return a().direction or"forward"end
if t=="l"then return a().loopStart end
if t=="e"then return a().loopEnd end
local e=s()if t=="b"then return o.getPitch(e)end
if t=="a"then return o.getVelocity(e)end
if t=="d"then return o.getDuration(e)end
if t=="g"then return o.getGate(e)end
return 0
end
function r.select(t)if e.sel==t then return end
e.prev=e.sel
e.sel=t
e.focusDirty=true
if t=="l"or t=="e"or e.prev=="l"or e.prev=="e"then
e.timelineDirty=true
end
end
function r.edit(d)local t=e.sel
local l=a()if t=="s"then
e.st=c(e.st+d,1,n.getStepCount(l))D()e.timelineDirty=true
elseif t=="t"then
e.tr=c(e.tr+d,1,e.engine.trackCount)e.pa=1;e.st=1
e.dirty.p=true;e.dirty.s=true
e.dirty.m=true
D()e.timelineDirty=true
elseif t=="p"then
e.pa=c(e.pa+d,1,n.getPatternCount(l))e.timelineDirty=true
elseif t=="m"then
local t=(m[l.direction]or 1)-1
t=(t+d)%#i
if t<0 then t=t+#i end
n.setDirection(l,i[t+1])e.timelineDirty=true
elseif t=="l"then
local t=n.getStepCount(l)local r=l.loopEnd or t
local t
if l.loopStart==nil then
t=c(e.st,1,r)else
t=c(l.loopStart+d,1,r)end
n.setLoopStart(l,t)e.timelineDirty=true
elseif t=="e"then
local r=n.getStepCount(l)local o=l.loopStart or 1
local t
if l.loopEnd==nil then
t=c(e.st,o,r)else
t=c(l.loopEnd+d,o,r)end
n.setLoopEnd(l,t)e.timelineDirty=true
elseif t=="b"or t=="a"or t=="d"or t=="g"then
local i=s()local a=(t=="d"or t=="g")and 99 or 127
local r=c(r.value(t)+d,0,a)if t=="b"then i=o.setPitch(i,r)elseif t=="a"then i=o.setVelocity(i,r)elseif t=="d"then i=o.setDuration(i,r)else i=o.setGate(i,r)end
n.setStep(l,e.st,i)e.timelineDirty=true
end
e.dirty[t]=true
end
function r.toggle()local t=e.sel
local l=a()if t=="l"then
n.clearLoopStart(l)e.dirty.l=true
e.timelineDirty=true
elseif t=="e"then
n.clearLoopEnd(l)e.dirty.e=true
e.timelineDirty=true
elseif t=="m"then
else
local t=s()t=o.setActive(t,not o.getActive(t))n.setStep(l,e.st,t)D()e.timelineDirty=true
end
end
local d={forward="FWD",reverse="REV",pingpong="P-P",random="RND",brownian="BRN"}function r.initScreen(e)e:draw_rectangle_filled(0,0,320,240,{0,0,0})for t=1,3 do
e:draw_line(t*p,0,t*p,u*2,{40,40,40})end
e:draw_line(0,u,320,u,{40,40,40})e:draw_line(0,u*2,320,u*2,{60,60,60})e:draw_swap()end
local function D(i,l,t)local n=(l-1)%4
local l=(l>4)and 1 or 0
local n=n*p
local l=l*u
local a=(t==e.sel)local c=a and{200,30,30}or{0,0,0}local o=(t=="b"or t=="a"or t=="d"or t=="g")and(not o.getActive(s()))local e
if a then e={255,255,255}elseif o then e={90,90,90}else e={200,200,200}end
i:draw_rectangle_filled(n,l,n+p,l+u,c)i:draw_text_fast(w[t],n+4,l+4,12,e)i:draw_text_fast(tostring(r.value(t)),n+4,l+22,32,e)end
local function p(e)local t=320-y*2
local e=math.floor(t/e)if e<1 then e=1 end
return e,y
end
local function m(c)local l=a()local t=n.getStepCount(l)local u=l.cursor or 0
local r=l.loopStart
local i=l.loopEnd
local s=d[l.direction]or"?"c:draw_rectangle_filled(0,f,320,240,{0,0,0})local a=""if e.sel=="l"then a=">L "elseif e.sel=="e"then a=">E "end
local f=r and tostring(r)or"--"local d=i and tostring(i)or"--"local a=a.."TRK "..e.tr.."  "..s.."  LOOP "..f..".."..d.."  "..e.st.."/"..t
c:draw_text_fast(a,y,_,12,{180,180,180})local d,a=p(t)for t=1,t do
local a=a+(t-1)*d
local l=n.getStep(l,t)local n=o.getActive(l)local r=r and i and t>=r and t<=i
local l
if t==u then
l={220,220,60}elseif t==e.st then
l={200,30,30}elseif r then
l={30,60,30}else
l={25,25,25}end
c:draw_rectangle_filled(a,h,a+d-1,h+S,l)if not n then
c:draw_line(a,h,a+d-1,h+S,{80,80,80})end
end
e.cur=u
end
function r.draw(t)local n=false
if e.focusDirty then
for r,l in ipairs(g)do
if l==e.sel or l==e.prev then
D(t,r,l)e.dirty[l]=false
n=true
end
end
e.focusDirty=false
e.prev=e.sel
end
for r,l in ipairs(g)do
if e.dirty[l]then
D(t,r,l)e.dirty[l]=false
n=true
end
end
local l=a()local l=l.cursor or 0
if l~=e.cur then e.timelineDirty=true end
if e.timelineDirty then
m(t)e.timelineDirty=false
n=true
end
if n then t:draw_swap()end
end
return r
end)()return w