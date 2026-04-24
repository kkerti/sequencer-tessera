local Player=require("/player/seq_player")
function Player.new(song, clockFn, bpm)
    bpm = bpm or song.bpm
    local pulseMs = 60000 / bpm / song.pulsesPerBeat
    return {
        song            = song,
        clockFn         = clockFn,
        bpm             = bpm,
        pulseMs         = pulseMs,
        startMs         = 0,
        pulseCount      = 0,
        cursor          = 1,
        running         = false,
        -- Active notes scheduled for NOTE_OFF, parallel arrays.
        activePitch     = {},
        activeChannel   = {},
        activeOffPulse  = {},
        activeCount     = 0,
    }
end
function Player.start(p)
    if p.clockFn then p.startMs = p.clockFn() end
    p.pulseCount  = 0
    p.cursor      = 1
    p.running     = true
    p.activeCount = 0
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
