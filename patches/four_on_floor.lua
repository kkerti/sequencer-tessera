-- patches/four_on_floor.lua
-- Mid-size baseline: a single drum-channel kick on every beat for 4 bars.
-- 16 NOTE_ON / NOTE_OFF pairs total. Roughly one third the event count of
-- dark_groove. Useful as a middle data point for on-device footprint sweeps.
return{bpm=120,ppb=4,bars=4,beatsPerBar=4,
  tracks={
    {channel=10,direction="forward",clockDiv=1,clockMult=1,
      patterns={{name="K",steps={
        {36,110,4,2},{36,110,4,2},{36,110,4,2},{36,110,4,2}
      }}}}
  }
}
