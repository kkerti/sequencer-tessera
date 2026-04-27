


































local Player = {}





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




function Player.allNotesOff(p, emit)
    local song    = p.song
    local kind    = song.kind
    local pairOff = song.pairOff   
    local atPulse = song.atPulse
    local pitch   = song.pitch
    local channel = song.channel
    local pc      = p.pulseCount
    local count   = 0

    for i = 1, p.cursor - 1 do
        local k = kind[i]
        if k == 1 then
            
            local off
            if pairOff then
                off = pairOff[i]
            else
                
                
                for j = i + 1, song.eventCount do
                    if kind[j] == 0 and pitch[j] == pitch[i]
                       and channel[j] == channel[i] then
                        off = j
                        break
                    end
                end
            end
            if not off or off == 0 or atPulse[off] > pc then
                emit("NOTE_OFF", pitch[i], 0, channel[i])
                count = count + 1
            end
        end
    end
    return count
end







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







function Player.tick(p, emit)
    if not p.running then return end
    local target = math.floor((p.clockFn() - p.startMs) / p.pulseMs)
    while p.pulseCount < target do
        Player.externalPulse(p, emit)
        if not p.running then return end
    end
end

return Player
