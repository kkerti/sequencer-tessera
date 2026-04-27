-- song_loader.lua
-- Builds an Engine + lightweight playback context from a song descriptor.
-- Used by tools/song_compile.lua to walk the engine pulse-by-pulse and
-- record events. The returned `player` is a stub table holding only the
-- fields the compiler reads (engine, swingPercent, scaleTable, rootNote);
-- there is no on-device player wrapper any more.
--
-- Usage:
--   local SongLoader = require("song_loader")
--   local result = SongLoader.load(require("songs/dark_groove"), clockFn)

local Engine = require("sequencer/engine")
local Track  = require("sequencer/track")
local Step   = require("sequencer/step")
local Utils  = require("utils")

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

-- Load a song table and return { engine, player } where `player` is a
-- lightweight stub holding the fields the compiler walker reads.
-- `song`    : song descriptor table (see songs/dark_groove.lua)
-- `clockFn` : kept for API compatibility; not consulted by the loader
function SongLoader.load(song, clockFn)
    assert(type(song)    == "table",    "SongLoader.load: song must be a table")
    assert(type(clockFn) == "function", "SongLoader.load: clockFn must be a function")

    local bpm = song.bpm or 120
    local eng = Engine.new(bpm, song.ppb or 4, #(song.tracks or {}), 0)
    SongLoader.loadTracks(eng, song)

    local scaleTable = nil
    if song.scale then
        scaleTable = Utils.SCALES and Utils.SCALES[song.scale] or nil
    end

    local pl = {
        engine        = eng,
        swingPercent  = song.swing or 50,
        scaleTable    = scaleTable,
        rootNote      = song.root or 0,
    }

    return { engine = eng, player = pl }
end

return SongLoader
