-- ===========================================================================
-- grid_module.lua — runnable Grid module example
-- ---------------------------------------------------------------------------
-- The device-side bundle is a single file containing the lite engine,
-- MidiTranslate, PatchLoader, and Driver. Patches are pure-data Lua tables.
--
-- Required upload to the device:
--   /sequencer.lua          (grid/sequencer.lua — bundled)
--   /four_on_floor.lua      (grid/four_on_floor.lua — patch descriptor;
--                            swap for /dark_groove.lua or /empty.lua as desired)
--
-- Clock source: external MIDI clock (0xF8 at 24 ppq). The patch's
-- pulsesPerBeat (typically 4) determines how many MIDI clocks make one
-- engine pulse.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- INIT BLOCK — paste into "system event -> setup event"
-- ---------------------------------------------------------------------------
local Seq         = require("/sequencer")          -- single-file library
local Driver      = Seq.Driver
local PatchLoader = Seq.PatchLoader
local descriptor  = require("/four_on_floor")

SEQ_ENGINE         = PatchLoader.build(descriptor)
SEQ_DRIVER         = Driver.new(SEQ_ENGINE, nil, descriptor.bpm)
SEQ_MIDI_COUNT     = 0
SEQ_MIDI_PER_PULSE = 24 / SEQ_ENGINE.pulsesPerBeat   -- 24 ppq from external MIDI clock

-- Drop the descriptor from package.loaded after the engine is built. The
-- descriptor is only consumed once by PatchLoader.build; keeping it cached
-- pins ~5-7 KB of nested step tables per patch. Saves real on-device RAM.
package.loaded["/four_on_floor"] = nil
descriptor = nil
collectgarbage("collect")

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
-- with:  Driver.tick(SEQ_DRIVER, SEQ_EMIT)
-- (and supply a clockFn returning ms when constructing SEQ_DRIVER above).


-- ---------------------------------------------------------------------------
-- BUTTON 1 — paste into "button 1 -> init event"
-- ---------------------------------------------------------------------------
-- Example: Driver.start(SEQ_DRIVER)
-- Insert custom code here.


-- ---------------------------------------------------------------------------
-- BUTTON 2 — paste into "button 2 -> init event"
-- ---------------------------------------------------------------------------
-- Example: Driver.stop(SEQ_DRIVER); Driver.allNotesOff(SEQ_DRIVER, SEQ_EMIT)
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
        if SEQ_DRIVER.running then
            SEQ_MIDI_COUNT = SEQ_MIDI_COUNT + 1
            if SEQ_MIDI_COUNT >= SEQ_MIDI_PER_PULSE then
                SEQ_MIDI_COUNT = 0
                Driver.externalPulse(SEQ_DRIVER, SEQ_EMIT)
            end
        end
    elseif t == 0xFA then                          -- start
        SEQ_MIDI_COUNT = 0
        Driver.start(SEQ_DRIVER)
    elseif t == 0xFB then                          -- continue
        SEQ_MIDI_COUNT = 0
        SEQ_DRIVER.running = true
    elseif t == 0xFC then                          -- stop
        Driver.stop(SEQ_DRIVER)
        Driver.allNotesOff(SEQ_DRIVER, SEQ_EMIT)
    end
end
