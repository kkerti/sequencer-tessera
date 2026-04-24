local Player=require("/player/seq_player")
function Player.allNotesOff(p)
    local n = p.activeCount
    local list = {}
    for i = 1, n do
        list[i] = {
            type     = "NOTE_OFF",
            pitch    = p.activePitch[i],
            channel  = p.activeChannel[i],
            velocity = 0,
        }
        p.activePitch[i]    = nil
        p.activeChannel[i]  = nil
        p.activeOffPulse[i] = nil
    end
    p.activeCount = 0
    return list
end
