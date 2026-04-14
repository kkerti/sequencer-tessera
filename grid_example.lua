-- grid_example.lua
-- Pseudo-code: how the sequencer engine runs on Grid hardware.
--
-- Grid's timer event is a self-restarting callback on a control element.
-- One element (e.g. element 0) owns the sequencer clock. Its timer event
-- calls Engine.tick(), emits MIDI, and restarts itself at the pulse interval.
--
-- This file is NOT part of the split grid/ output — it shows the integration
-- pattern that a Grid user config script would follow.

-- ═══════════════════════════════════════════════════════════════════════════
-- ELEMENT 0 — INIT EVENT (runs once when config loads)
-- ═══════════════════════════════════════════════════════════════════════════

-- All split chunk files live on Grid's filesystem. Grid's require() searches
-- the local script path. The naming scheme is:
--
--   seq_utils.lua        (root: creates Utils table, requires chunks)
--   seq_utils_1.lua      (chunk: attaches tableNew, tableCopy, clamp, pitchToName)
--   seq_utils_2.lua      (chunk: attaches quantizePitch)
--   seq_step.lua         (root)
--   seq_step_1.lua       (chunk: new, getPitch, setPitch, ...)
--   ...
--   seq_engine.lua       (root: creates Engine table)
--   seq_engine_1.lua     (chunk: bpmToMs)
--   seq_engine_2.lua     (chunk: Engine.new)
--   ...
--
-- require("seq_engine") loads seq_engine.lua, which cascades all chunk requires.

local Engine = require("seq_engine")
local Track  = require("seq_track")
local Step   = require("seq_step")

-- ── Build the sequence ────────────────────────────────────────────────────
-- These calls are identical to the desktop version. The split files expose
-- the exact same API — Step.new, Track.addPattern, Engine.tick etc.

local BPM = 120
local PULSES_PER_BEAT = 4

local engine = Engine.new(BPM, PULSES_PER_BEAT, 1, 0)  -- 1 track, 0 initial steps
local track  = Engine.getTrack(engine, 1)

Track.setMidiChannel(track, 1)
Track.addPattern(track, 4)

Track.setStep(track, 1, Step.new(48, 100, 4, 2))   -- C3
Track.setStep(track, 2, Step.new(51,  90, 4, 2))   -- Eb3
Track.setStep(track, 3, Step.new(55,  95, 4, 3))   -- G3
Track.setStep(track, 4, Step.new(53,  85, 4, 2))   -- F3

Engine.setScale(engine, "minorPentatonic", 0)

-- Store engine in a global so the timer event can access it.
-- Grid element events share globals within the same config.
SEQ_ENGINE = engine
SEQ_INTERVAL = math.floor(Engine.bpmToMs(BPM, PULSES_PER_BEAT))

-- ═══════════════════════════════════════════════════════════════════════════
-- ELEMENT 0 — TIMER EVENT (self-restarting loop)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- On Grid, each element has a timer event that fires after a configured delay.
-- The timer can restart itself with element_timer_start(element_index, delay_ms).
-- This creates the sequencer's clock loop.
--
-- Pseudo-API (Grid firmware):
--   element_timer_start(element_index, delay_ms)  -- start/restart timer
--   midi_send(channel, type, note, velocity)      -- send MIDI
--
-- The timer event script below would be pasted into Grid Editor for element 0.

-- TIMER EVENT BODY (runs every pulse)
local events = Engine.tick(SEQ_ENGINE)

for i = 1, #events do
    local e = events[i]
    if e.type == "NOTE_ON" then
        -- Grid MIDI send: channel, status, note, velocity
        midi_send(e.channel, 0x90, e.pitch, e.velocity)
    elseif e.type == "NOTE_OFF" then
        midi_send(e.channel, 0x80, e.pitch, 0)
    end
end

-- Restart the timer to fire again after one pulse interval.
-- This creates the sequencer clock loop.
element_timer_start(self:element_index(), SEQ_INTERVAL)


-- ═══════════════════════════════════════════════════════════════════════════
-- STARTING THE CLOCK
-- ═══════════════════════════════════════════════════════════════════════════
--
-- From any element's event (e.g. a button press), kick off the timer:
--
--   element_timer_start(0, 0)   -- start element 0's timer immediately
--
-- To stop:
--
--   Engine.stop(SEQ_ENGINE)     -- engine ignores ticks, emits NOTE_OFFs
--
-- To reset:
--
--   Engine.reset(SEQ_ENGINE)    -- rewind all tracks to step 1


-- ═══════════════════════════════════════════════════════════════════════════
-- MIDI CLOCK SYNC (external clock source)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- If Grid receives MIDI clock (0xF8) from an external device, the timer
-- event is not needed. Instead, hook the MIDI RX event:
--
--   -- MIDI RX EVENT on any element
--   if midi_rx_type == 0xF8 then          -- timing clock
--       local events = Engine.tick(SEQ_ENGINE)
--       for i = 1, #events do
--           local e = events[i]
--           if e.type == "NOTE_ON" then
--               midi_send(e.channel, 0x90, e.pitch, e.velocity)
--           elseif e.type == "NOTE_OFF" then
--               midi_send(e.channel, 0x80, e.pitch, 0)
--           end
--       end
--   elseif midi_rx_type == 0xFA then      -- start
--       Engine.reset(SEQ_ENGINE)
--   elseif midi_rx_type == 0xFC then      -- stop
--       Engine.stop(SEQ_ENGINE)
--   end
--
-- In this mode, BPM is irrelevant — the external clock drives the pulse rate.
