-- the below code lives on system event -> setup event
local Player = require("seq_player")
self.rtmrx_cb = function(self, t)
    if t == 0xF8 then
        if SEQ_PLAYER.running then
            SEQ_MIDI_COUNT = SEQ_MIDI_COUNT + 1
            if SEQ_MIDI_COUNT >= SEQ_MIDI_PER_PULSE then
                SEQ_MIDI_COUNT = 0
                Player.externalPulse(SEQ_PLAYER, SEQ_EMIT)
            end
        end
    elseif t == 0xFA then
        SEQ_MIDI_COUNT = 0
        Player.start(SEQ_PLAYER)
    elseif t == 0xFB then
        SEQ_MIDI_COUNT = 0
        SEQ_PLAYER.running = true
    elseif t == 0xFC then
        Player.stop(SEQ_PLAYER)
        local offs = Player.allNotesOff(SEQ_PLAYER)
        for _, e in ipairs(offs) do
            midi_send(e.channel, 0x80, e.pitch, 0)
        end
    end
end
