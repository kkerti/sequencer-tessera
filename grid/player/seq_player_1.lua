local Player=require("/player/seq_player")
function Player.new(song, clockFn, bpm)
    bpm = bpm or song.bpm
    return {
        song       = song,
        clockFn    = clockFn,
        bpm        = bpm,
        pulseMs    = 60000 / bpm / song.pulsesPerBeat,
        startMs    = 0,
        pulseCount = 0,
        cursor     = 1,
        loopIndex  = 0,
        running    = false,
    }
end
function Player.start(p)
    if p.clockFn then p.startMs = p.clockFn() end
    p.pulseCount = 0
    p.cursor     = 1
    p.loopIndex  = 0
    p.running    = true
end
function Player.stop(p)
    p.running = false
end
function Player.setBpm(p, bpm)
    p.bpm     = bpm
    p.pulseMs = 60000 / bpm / p.song.pulsesPerBeat
    if p.clockFn then
        p.startMs = p.clockFn() - p.pulseCount * p.pulseMs
    end
end
