local Player=require("seq_player")
function Player._playerFlushExpiredNotes(player, nowMs, emit)
    local i = 1
    while i <= player.activeNoteCount do
        if nowMs >= player.activeNoteOffAt[i] then
            i = Player._playerExpireNote(player, i, emit)
        else
            i = i + 1
        end
    end
end
function Player._playerTrackNoteOn(player, pitch, channel, offAtMs)
    local n = player.activeNoteCount + 1
    player.activeNoteKeys[n]  = Player._playerNoteKey(pitch, channel)
    player.activeNoteOffAt[n] = offAtMs
    player.activeNoteCount    = n
end
