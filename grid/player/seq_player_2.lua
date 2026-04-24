local Player=require("/player/seq_player")
function Player._playerLoopWrap(p)
    local song = p.song
    if song.loop and p.cursor > song.eventCount
       and p.pulseCount >= song.durationPulses then
        p.pulseCount = p.pulseCount - song.durationPulses
        p.cursor     = 1
        if p.clockFn then
            p.startMs = p.startMs + song.durationPulses * p.pulseMs
        end
    end
end
