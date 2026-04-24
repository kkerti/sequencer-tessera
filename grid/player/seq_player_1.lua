local Player=require("/player/seq_player")
function Player._playerFlushExpired(p, currentPulse, emit)
    local i = 1
    while i <= p.activeCount do
        if p.activeOffPulse[i] <= currentPulse then
            emit("NOTE_OFF", p.activePitch[i], 0, p.activeChannel[i])
            -- swap-remove
            local last = p.activeCount
            if i ~= last then
                p.activePitch[i]    = p.activePitch[last]
                p.activeChannel[i]  = p.activeChannel[last]
                p.activeOffPulse[i] = p.activeOffPulse[last]
            end
            p.activePitch[last]    = nil
            p.activeChannel[last]  = nil
            p.activeOffPulse[last] = nil
            p.activeCount          = last - 1
        else
            i = i + 1
        end
    end
end
function Player._playerTrackNoteOn(p, pitch, channel, offPulse)
    local n = p.activeCount + 1
    p.activePitch[n]    = pitch
    p.activeChannel[n]  = channel
    p.activeOffPulse[n] = offPulse
    p.activeCount       = n
end
