local Player=require("/player/seq_player")
function Player.externalPulse(p, emit)
    if not p.running then return end

    p.pulseCount = p.pulseCount + 1
    local song   = p.song
    local pc     = p.pulseCount

    Player._playerFlushExpired(p, pc, emit)

    while p.cursor <= song.eventCount and song.atPulse[p.cursor] <= pc do
        local i    = p.cursor
        local prob = song.probability[i]
        if prob >= 100 or math.random(1, 100) <= prob then
            local pitch    = song.pitch[i]
            local channel  = song.channel[i]
            local offPulse = song.atPulse[i] + song.gatePulses[i]
            emit("NOTE_ON", pitch, song.velocity[i], channel)
            Player._playerTrackNoteOn(p, pitch, channel, offPulse)
        end
        p.cursor = i + 1
    end

    Player._playerLoopWrap(p)
end
