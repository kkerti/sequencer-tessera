local Player=require("seq_player")
function Player._playerExpireNote(player, i, emit)
    local key = player.activeNoteKeys[i]
    local pitch, channel = key:match("^(%d+):(%d+)$")
    emit({ type="NOTE_OFF", pitch=tonumber(pitch), velocity=0, channel=tonumber(channel) })
    local last = player.activeNoteCount
    if i ~= last then
        player.activeNoteKeys[i]  = player.activeNoteKeys[last]
        player.activeNoteOffAt[i] = player.activeNoteOffAt[last]
    end
    player.activeNoteKeys[last]  = nil
    player.activeNoteOffAt[last] = nil
    player.activeNoteCount       = last - 1
    return i
end
