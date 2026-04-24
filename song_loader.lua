-- song_loader.lua
-- Constructs and returns a configured { engine, player } pair from a song table.
-- Split into three public functions so gridsplit can chunk it under 800 chars.
--
-- Usage:
--   local SongLoader = require("song_loader")
--   local result = SongLoader.load(require("songs/dark_groove"), clockFn)

local Engine = require("sequencer/engine")
local Track  = require("sequencer/track")
local Step   = require("sequencer/step")
local Player = require("player/player")

local SongLoader = {}

-- Build one Step from a packed descriptor { pitch, vel, dur, gate [,ratch [,prob]] }.
function SongLoader.buildStep(desc)
    return Step.new(
        desc[1] or 60,
        desc[2] or 100,
        desc[3] or 4,
        desc[4] or 2,
        desc[5] or 1,
        desc[6] or 100
    )
end

-- Add all patterns and steps from one track descriptor into a track.
function SongLoader.loadPatterns(track, trackDesc)
    local fi = 1
    for _, pd in ipairs(trackDesc.patterns or {}) do
        Track.addPattern(track, #(pd.steps or {}), pd.name)
        for _, sd in ipairs(pd.steps or {}) do
            Track.setStep(track, fi, SongLoader.buildStep(sd))
            fi = fi + 1
        end
    end
end

-- Configure all tracks on the engine from the song descriptor.
function SongLoader.loadTracks(engine, song)
    for ti, td in ipairs(song.tracks or {}) do
        local tr = Engine.getTrack(engine, ti)
        if td.channel   then Track.setMidiChannel(tr, td.channel)   end
        if td.direction then Track.setDirection(tr, td.direction)    end
        if td.clockDiv  then Track.setClockDiv(tr, td.clockDiv)      end
        if td.clockMult then Track.setClockMult(tr, td.clockMult)    end
        SongLoader.loadPatterns(tr, td)
        if td.loopStart then Track.setLoopStart(tr, td.loopStart)    end
        if td.loopEnd   then Track.setLoopEnd(tr, td.loopEnd)        end
    end
end

-- Load a song table and return { engine, player }.
-- `song`    : song descriptor table (see songs/dark_groove.lua)
-- `clockFn` : zero-argument function returning monotonic ms
function SongLoader.load(song, clockFn)
    assert(type(song)    == "table",    "SongLoader.load: song must be a table")
    assert(type(clockFn) == "function", "SongLoader.load: clockFn must be a function")

    local bpm = song.bpm or 120
    local eng = Engine.new(bpm, song.ppb or 4, #(song.tracks or {}), 0)
    SongLoader.loadTracks(eng, song)
    local pl = Player.new(eng, bpm, clockFn)
    if song.swing then Player.setSwing(pl, song.swing) end
    if song.scale then Player.setScale(pl, song.scale, song.root or 0) end
    return { engine = eng, player = pl }
end

return SongLoader
