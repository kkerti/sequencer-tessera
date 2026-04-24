local Player=require("seq_player")
local Step=require("seq_step")
function Player._playerResolveNoteOn(player, trackIndex, step, nowMs)
    local track   = player.engine.tracks[trackIndex]
    local channel = track.midiChannel or trackIndex
    local pitch   = Step.resolvePitch(step, player.scaleTable, player.rootNote)
    local offAtMs = nowMs + Player._playerGateToMs(Step.getGate(step), player.engine.pulsesPerBeat, player.bpm)
    return channel, pitch, offAtMs
end
