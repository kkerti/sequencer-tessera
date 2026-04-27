local Player=require("/player/seq_player")
function Player.externalPulse(p, emit)
    if not p.running then return end

    p.pulseCount = p.pulseCount + 1
    local song   = p.song
    local pc     = p.pulseCount
    local atPulse = song.atPulse
    local kind    = song.kind

    while p.cursor <= song.eventCount and atPulse[p.cursor] <= pc do
        local i = p.cursor
        local k = kind[i]
        if k == 1 then
            emit("NOTE_ON",  song.pitch[i], song.velocity[i], song.channel[i])
        elseif k == 0 then
            emit("NOTE_OFF", song.pitch[i], 0,                 song.channel[i])
        end
        -- kind 2 / 3 are muted — skip silently.
        p.cursor = i + 1
    end

    if song.loop and p.cursor > song.eventCount and pc >= song.durationPulses then
        p.pulseCount = pc - song.durationPulses
        p.cursor     = 1
        p.loopIndex  = p.loopIndex + 1
        if p.clockFn then
            p.startMs = p.startMs + song.durationPulses * p.pulseMs
        end
        if song.onLoopBoundary then
            song.onLoopBoundary(song, p.loopIndex)
        end
    end
end
