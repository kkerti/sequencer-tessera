-- midi_rx.lua — device MIDI-clock receiver. Lives in the Core bundle so the
-- pure-playback path (clock in -> notes out) never loads the UI bundle.
--
-- On the Grid module, the system element's setup event arms MIDI rx (grxm) and
-- routes each incoming realtime byte here:
--     self.rtmrx_cb = function(self,h,t) MIDIRX.handle(t, gms) end
-- where `gms(ch, status, p1, p2)` is Grid's MIDI-send. This mirrors the proven
-- "Note Step Sequencer" profile, adapted to seq-2's engine.out buffer.
--
--   handle(t, send):
--     0xF8 clock  -> Engine.onPulse(); emit engine.out via send; returns "tick"
--     0xFA start  -> Engine.onStart();                           returns "start"
--     0xFB cont   -> onStart if not playing;                     returns "start"
--     0xFC stop   -> Engine.onStop(); emit note-offs;            returns "stop"

local Engine = require("engine")

local M = {}

function M.handle(t, send)
    if t == 0xF8 then
        local o = Engine.onPulse()
        for i = 1, o.n do
            if o.typ[i] == 1 then send(o.ch[i], 0x90, o.pitch[i], o.vel[i])
            else send(o.ch[i], 0x80, o.pitch[i], 0) end
        end
        return "tick"
    elseif t == 0xFA then
        Engine.onStart()
        return "start"
    elseif t == 0xFB then
        if not Engine.playing then Engine.onStart() end
        return "start"
    elseif t == 0xFC then
        local o = Engine.onStop()
        for i = 1, o.n do send(o.ch[i], 0x80, o.pitch[i], 0) end
        return "stop"
    end
end

return M
