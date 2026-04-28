-- ===========================================================================
-- grid_module.lua — runnable Grid module example
-- ---------------------------------------------------------------------------
-- Each block below is meant to be pasted into the matching Grid editor slot.
-- Required upload to the device:
--   /player.lua            (grid/player.lua)
--   /four_on_floor.lua     (grid/four_on_floor.lua)   -- or another song
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- INIT BLOCK — paste into "system event -> setup event"
-- ---------------------------------------------------------------------------
local Player = require("/player")
local song   = require("/four_on_floor")

SEQ_PLAYER         = Player.new(song)
SEQ_MIDI_COUNT     = 0
SEQ_MIDI_PER_PULSE = 24 / song.pulsesPerBeat   -- 24 ppq from external MIDI clock

SEQ_EMIT = function(event, pitch, velocity, channel)
    if event == "NOTE_ON" then
        midi_send(channel, 0x90, pitch, velocity)
    else
        midi_send(channel, 0x80, pitch, 0)
    end
end


-- ---------------------------------------------------------------------------
-- TIMER BLOCK — paste into the timer event
-- ---------------------------------------------------------------------------
-- External MIDI clock drives playback through rtmrx_cb below; the timer is
-- unused in that mode. For internal-clock playback instead, replace the body
-- with:  Player.tick(SEQ_PLAYER, SEQ_EMIT)


-- ---------------------------------------------------------------------------
-- BUTTON 1 — paste into "button 1 -> init event"
-- ---------------------------------------------------------------------------
-- Insert custom code here, e.g. Player.start(SEQ_PLAYER) / Player.stop(SEQ_PLAYER).


-- ---------------------------------------------------------------------------
-- BUTTON 2 — paste into "button 2 -> init event"
-- ---------------------------------------------------------------------------
-- Insert custom code here.


-- ---------------------------------------------------------------------------
-- BUTTON 3 — paste into "button 3 -> init event"
-- ---------------------------------------------------------------------------
-- Insert custom code here.


-- ---------------------------------------------------------------------------
-- BUTTON 4 — paste into "button 4 -> init event"
-- ---------------------------------------------------------------------------
-- Insert custom code here.


-- ---------------------------------------------------------------------------
-- RTMIDI CALLBACK — paste into the rtmidi receive callback
-- ---------------------------------------------------------------------------
self.rtmrx_cb = function(self, t)
    if t == 0xF8 then                              -- clock pulse (24 ppq)
        if SEQ_PLAYER.running then
            SEQ_MIDI_COUNT = SEQ_MIDI_COUNT + 1
            if SEQ_MIDI_COUNT >= SEQ_MIDI_PER_PULSE then
                SEQ_MIDI_COUNT = 0
                Player.externalPulse(SEQ_PLAYER, SEQ_EMIT)
            end
        end
    elseif t == 0xFA then                          -- start
        SEQ_MIDI_COUNT = 0
        Player.start(SEQ_PLAYER)
    elseif t == 0xFB then                          -- continue
        SEQ_MIDI_COUNT = 0
        SEQ_PLAYER.running = true
    elseif t == 0xFC then                          -- stop
        Player.stop(SEQ_PLAYER)
        local offs = Player.allNotesOff(SEQ_PLAYER)
        for _, e in ipairs(offs) do
            midi_send(e.channel, 0x80, e.pitch, 0)
        end
    end
end
