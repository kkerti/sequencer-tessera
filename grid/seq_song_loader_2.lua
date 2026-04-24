local SongLoader=require("seq_song_loader")
local Engine=require("seq_engine")
local Track=require("seq_track")
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
