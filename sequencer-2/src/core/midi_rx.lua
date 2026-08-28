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

-- Emit an engine.out buffer via a Grid `send` (gms). Shared by the clock
-- handler and the App layer (which flushes note-offs after sequence/mute
-- switches off the hot path).
function M.emit(out, send)
    for i = 1, out.n do
        if out.typ[i] == 1 then send(out.ch[i], 0x90, out.pitch[i], out.vel[i])
        else send(out.ch[i], 0x80, out.pitch[i], 0) end
    end
end

function M.handle(t, send)
    if t == 0xF8 then
        local o = Engine.onPulse()
        M.emit(o, send)
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
