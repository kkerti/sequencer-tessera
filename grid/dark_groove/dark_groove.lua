local s={}
s.bpm=118
s.pulsesPerBeat=4
s.durationPulses=64
s.loop=true
s.eventCount=86
s.atPulse=require("/dark_groove/dark_groove_atpulse_1")
s.pitch=require("/dark_groove/dark_groove_pitch_1")
s.velocity=require("/dark_groove/dark_groove_velocity_1")
s.channel={1,6,3,6,6,6,1,6,6,1,6,6,6,3,6,1,6,6,1,6,6,6,6,1,6,3,6,1,6,6,6,6,1,6,1,6,6,3,6,6,6,1,6,6,1,6,6,6,3,6,1,6,6,1,6,6,6,6,1,6,3,6,1,6,6,6,6,1,6,1,6,6,3,6,6,6,1,6,6,1,6,6,6,6,1,6}
s.gatePulses={3,1,3,1,1,1,2,1,1,3,1,1,1,3,1,2,1,1,3,1,1,1,1,2,1,3,1,3,1,1,1,1,1,1,1,1,1,2,1,1,1,2,1,1,3,1,1,1,3,1,2,1,1,3,1,1,1,1,2,1,2,1,3,1,1,1,1,1,1,1,1,1,3,1,1,1,2,1,1,3,1,1,1,1,2,1}
s.probability=require("/dark_groove/dark_groove_probability_1")
return s
