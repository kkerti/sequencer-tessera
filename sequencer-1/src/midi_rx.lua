-- midi_rx.lua
-- Tiny Core-resident MIDI rx helper. Lives in dist/sequencer.lua so VSN1.lua
-- can drive transport + clock without lazy-loading the UI bundle (pure
-- playback path). UI-side concerns (EN16 playhead push) are pulled in by
-- VSN1.lua via a separate `if APP then ... end` guard, kept tiny.

local Engine = require("engine")

local M = {}

-- t: incoming status byte (0xF8 / 0xFA / 0xFB / 0xFC).
-- send: function(ch, status, p1, p2)  -- bound to `midi_send` on device.
-- Returns "tick" for 0xF8, "start" for 0xFA/0xFB, "stop" for 0xFC, nil otherwise.
function M.handle(t, send)
    if t == 0xF8 then
        local events = Engine.onPulse()
        if events then
            for i = 1, #events do
                local e = events[i]
                if e.type == 1 then send(e.ch, 0x90, e.pitch, e.vel)
                else send(e.ch, 0x80, e.pitch, 0) end
            end
        end
        return "tick"
    elseif t == 0xFA then
        Engine.onStart()
        return "start"
    elseif t == 0xFB then
        if not Engine.running then Engine.onStart() end
        return "start"
    elseif t == 0xFC then
        local off = Engine.onStop()
        if off then
            for i = 1, #off do send(off[i].ch, 0x80, off[i].pitch, 0) end
        end
        return "stop"
    end
end

return M
