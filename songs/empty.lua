-- songs/empty.lua
-- Smallest possible valid song. One silent track, one rest step, no looping.
-- Compiles to a song with eventCount=0 — the player loads it without error
-- and sits idle. Used as a memory-footprint baseline on device.
return{bpm=120,ppb=4,scale="chromatic",root=0,bars=1,beatsPerBar=4,loop=false,
  tracks={
    {channel=1,direction="forward",clockDiv=1,clockMult=1,
      patterns={{name="X",steps={{60,0,4,0}}}}}
  }
}
