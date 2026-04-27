local s={}
local R=require
s.bpm=118
s.pulsesPerBeat=4
s.durationPulses=64
s.loop=true
s.eventCount=172
s.atPulse=R("dark_groove_atpulse_1")
do local x=R("dark_groove_atpulse_2")table.move(x,1,#x,#s.atPulse+1,s.atPulse)end
s.kind=R("dark_groove_kind_1")
do local x=R("dark_groove_kind_2")table.move(x,1,#x,#s.kind+1,s.kind)end
s.pitch=R("dark_groove_pitch_1")
do local x=R("dark_groove_pitch_2")table.move(x,1,#x,#s.pitch+1,s.pitch)end
s.velocity=R("dark_groove_velocity_1")
do local x=R("dark_groove_velocity_2")table.move(x,1,#x,#s.velocity+1,s.velocity)end
s.channel=R("dark_groove_channel_1")
do local x=R("dark_groove_channel_2")table.move(x,1,#x,#s.channel+1,s.channel)end
return s
