local Player=require("seq_player")
local Engine=require("seq_engine")
function Player._playerAdvanceTrack(player, trackIndex, nowMs, emit)
    local engine = player.engine
    local track  = engine.tracks[trackIndex]

    track.clockAccum = track.clockAccum + track.clockMult
    local advanceCount = math.floor(track.clockAccum / track.clockDiv)
    track.clockAccum   = track.clockAccum % track.clockDiv

    for _ = 1, advanceCount do
        local step, event = Engine.advanceTrack(engine, trackIndex)
        if event == "NOTE_ON" then
            Player._playerHandleNoteOn(player, trackIndex, step, nowMs, emit)
        elseif event == "NOTE_OFF" then
            Player._playerHandleNoteOff(player, trackIndex)
        end
    end
end
