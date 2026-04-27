local Player=require("/player/seq_player")
function Player.allNotesOff(p, emit)
    local song    = p.song
    local kind    = song.kind
    local pairOff = song.pairOff   -- may be nil for static songs
    local atPulse = song.atPulse
    local pitch   = song.pitch
    local channel = song.channel
    local pc      = p.pulseCount
    local count   = 0

    for i = 1, p.cursor - 1 do
        local k = kind[i]
        if k == 1 then
            -- NOTE_ON was emitted; check whether its NOTE_OFF has played.
            local off
            if pairOff then
                off = pairOff[i]
            else
                -- Static song: linear-scan forward for the matching NOTE_OFF.
                -- Acceptable because allNotesOff is an emergency path.
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
