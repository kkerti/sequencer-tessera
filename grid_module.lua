-- grid_module.lua
-- Grid firmware entry point for the sequencer + player stack.
--
-- This file is designed to run on the Grid ESP32 Lua VM.  It loads a song
-- via SongLoader, wires up MIDI emit to the Grid midi_send() API, and
-- drives the clock from the Grid element timer (self-restarting).
--
-- ── Firmware API assumed ──────────────────────────────────────────────────
--   midi_send(channel, status_byte, note, velocity)
--     e.g. midi_send(1, 0x90, 60, 100)  → NOTE_ON ch1 C4
--          midi_send(1, 0x80, 60, 0)    → NOTE_OFF ch1 C4
--
--   element_timer_start(element_index, delay_ms)
--     Restarts the named element's timer after delay_ms milliseconds.
--     Call from within that element's timer event to create a loop.
--
--   self:element_index()
--     Returns the index of the currently executing element.
--
-- ── Files to upload ───────────────────────────────────────────────────────
-- All files in grid/  (82 split modules: seq_engine.lua, seq_engine_1.lua,
--                      seq_player.lua, seq_song_loader.lua, …)
-- Plus your song file as flat name: dark_groove.lua  (copied from songs/)
--
-- ── Usage ─────────────────────────────────────────────────────────────────
-- Paste the INIT BLOCK into element 0's init event.
-- Paste the TIMER BLOCK into element 0's timer event.
-- To start playback from a button: element_timer_start(0, 0)
-- To stop:  Player.stop(SEQ_PLAYER)
-- To reset: Engine.reset(SEQ_ENGINE)  (then restart timer)
--
-- ── Clock source ──────────────────────────────────────────────────────────
-- Grid firmware does not expose uv.now().  We maintain SEQ_CLOCK_MS, a
-- simple integer that increments by the pulse interval on every timer
-- callback.  Monotonic and accurate enough for NOTE_OFF gate timing
-- because all timing is relative to the same counter.

-- ═══════════════════════════════════════════════════════════════════════════
-- INIT BLOCK  (paste into element 0 init event — runs once on config load)
-- ═══════════════════════════════════════════════════════════════════════════

local SongLoader = require("seq_song_loader")
local Player     = require("seq_player")
local Engine     = require("seq_engine")

-- Monotonic ms counter — incremented each timer tick by the pulse interval.
SEQ_CLOCK_MS = 0
local function gridClockFn() return SEQ_CLOCK_MS end

local result = SongLoader.load(require("dark_groove"), gridClockFn)
SEQ_ENGINE   = result.engine
SEQ_PLAYER   = result.player
SEQ_INTERVAL = math.floor(SEQ_PLAYER.pulseIntervalMs)

-- MIDI emit: route player events to the Grid firmware MIDI API.
function SEQ_EMIT(event)
    if event.type == "NOTE_ON" then
        midi_send(event.channel, 0x90, event.pitch, event.velocity)
    elseif event.type == "NOTE_OFF" then
        midi_send(event.channel, 0x80, event.pitch, 0)
    end
end

Player.start(SEQ_PLAYER)
-- Start the timer loop. Replace 0 with the element index this code lives in.
element_timer_start(0, SEQ_INTERVAL)

-- ═══════════════════════════════════════════════════════════════════════════
-- TIMER BLOCK  (paste into element 0 timer event — self-restarting loop)
-- ═══════════════════════════════════════════════════════════════════════════

local Player = require("seq_player")

-- Advance the software clock by one pulse interval.
SEQ_CLOCK_MS = SEQ_CLOCK_MS + SEQ_INTERVAL

-- Tick the player: advances engine cursors, emits MIDI events, flushes
-- any NOTE_OFFs whose wall-clock gate has expired.
Player.tick(SEQ_PLAYER, SEQ_EMIT)

-- Restart this element's timer for the next pulse.
element_timer_start(self:element_index(), SEQ_INTERVAL)

-- ═══════════════════════════════════════════════════════════════════════════
-- BUTTON CONTROLS  (example — paste into any button element's press event)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Start playback:
--   local Player = require("seq_player")
--   Player.start(SEQ_PLAYER)
--   element_timer_start(0, 0)
--
-- Stop playback and silence all notes:
--   local Player = require("seq_player")
--   Player.stop(SEQ_PLAYER)
--   local offs = Player.allNotesOff(SEQ_PLAYER)
--   for _, e in ipairs(offs) do
--       midi_send(e.channel, 0x80, e.pitch, 0)
--   end
--
-- Reset to beginning:
--   local Engine = require("seq_engine")
--   Engine.reset(SEQ_ENGINE)
