-- grid_module_test.lua
--
-- Minimal Grid module config: play four_on_floor with 4 live edits applied,
-- driven by external MIDI clock (DAW transport).
--
-- Required files on device (flat layout):
--   /player.lua   /edit.lua   /four_on_floor.lua
--
-- Edits applied at INIT (four_on_floor = 16 kicks, ON at idx 2N-1):
--   mutePair(5)     → bar 1 beat 3 silenced
--   setPitch(9,38)  → bar 2 beat 1 becomes a snare
--   setVelocity(13,30) → bar 2 beat 3 quiet
--   queueRatchetEdit(17,...) → bar 3 beat 1 becomes a 4-hit roll
--                              (queued: audible from loop 2 onward)
--
-- Two event slots to fill. Paste each block (without its delimiter line)
-- into the matching slot in the Grid module editor.

-- ============================== INIT EVENT ==============================
local Player = require("/player")
local Edit   = require("/edit")
local song   = require("/four_on_floor")
SEQ_PLAYER         = Player.new(song)
SEQ_MIDI_COUNT     = 0
SEQ_MIDI_PER_PULSE = 24 / song.pulsesPerBeat
SEQ_EMIT = function(ev, p, v, c)
    if ev == "NOTE_ON" then midi_send(c, 0x90, p, v)
    else midi_send(c, 0x80, p, 0) end
end
SEQ_QUEUE = Edit.newQueue()
song.onLoopBoundary = function(s, i) Edit.applyQueue(s, SEQ_QUEUE) end
Edit.mutePair(song, 5)
Edit.setPitch(song, 9, 38)
Edit.setVelocity(song, 13, 30)
Edit.queueRatchetEdit(SEQ_QUEUE, {
    firstOnIdx=17, currentCount=1, currentSubPulses=0, currentGate=2,
    newCount=4,    newSubPulses=1, newGate=1,
})

-- ============================ RTMIDI CALLBACK ===========================
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
        for _, e in ipairs(Player.allNotesOff(SEQ_PLAYER)) do
            midi_send(e.channel, 0x80, e.pitch, 0)
        end
    end
end
