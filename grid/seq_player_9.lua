local Player=require("seq_player")
function Player.allNotesOff(player)
    local events = {}
    for i = 1, player.activeNoteCount do
        local key = player.activeNoteKeys[i]
        local pitch, channel = key:match("^(%d+):(%d+)$")
        events[#events + 1] = {
            type     = "NOTE_OFF",
            pitch    = tonumber(pitch),
            velocity = 0,
            channel  = tonumber(channel),
        }
        player.activeNoteKeys[i]  = nil
        player.activeNoteOffAt[i] = nil
    end
    player.activeNoteCount = 0
    return events
end
