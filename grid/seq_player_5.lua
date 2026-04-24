local Player=require("seq_player")
local Probability=require("seq_probability")
local Step=require("seq_step")
function Player._playerHandleNoteOn(player, trackIndex, step, nowMs, emit)
    if not Probability.shouldPlay(step) then
        player.probSuppressed[trackIndex] = true
        return
    end
    player.probSuppressed[trackIndex] = false
    local channel, pitch, offAtMs = Player._playerResolveNoteOn(player, trackIndex, step, nowMs)
    Player._playerTrackNoteOn(player, pitch, channel, offAtMs)
    emit({ type="NOTE_ON", pitch=pitch, velocity=Step.getVelocity(step), channel=channel })
end
function Player._playerHandleNoteOff(player, trackIndex)
    if player.probSuppressed[trackIndex] then
        player.probSuppressed[trackIndex] = false
    end
end
