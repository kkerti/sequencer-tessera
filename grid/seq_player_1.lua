local Player=require("seq_player")
function Player._playerBpmToMs(bpm, pulsesPerBeat)
    return (60000 / bpm) / pulsesPerBeat
end
function Player._playerGateToMs(gate, pulsesPerBeat, bpm)
    local pulseMs = (60000 / bpm) / pulsesPerBeat
    return gate * pulseMs
end
function Player._playerNoteKey(pitch, channel)
    return pitch .. ":" .. channel
end
