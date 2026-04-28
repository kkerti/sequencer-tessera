-- ---------------------------------------------------------------------------
-- INIT BLOCK — paste into the Grid module's "system event -> setup event"
-- ---------------------------------------------------------------------------
--
-- Default: minimal player + a compiled song.
--
local Player = require("/player")
local song   = require("/four_on_floor")
SEQ_PLAYER          = Player.new(song)
SEQ_MIDI_COUNT      = 0
SEQ_MIDI_PER_PULSE  = 24 / song.pulsesPerBeat   -- 24 ppq from the MIDI clock
SEQ_EMIT = function(event, pitch, velocity, channel)
    if event == "NOTE_ON" then
        midi_send(channel, 0x90, pitch, velocity)
    else
        midi_send(channel, 0x80, pitch, 0)
    end
end

-- ---------------------------------------------------------------------------
-- LITE-ENGINE MEASUREMENT HOOK (uncomment ONE tier at a time)
-- ---------------------------------------------------------------------------
--
-- The lite authoring engine (`/sequencer_lite.lua`, single bundled file) is
-- NOT used by the player and does NOT participate in playback. These hooks
-- measure the RAM cost of having the bundle + a representative authoring
-- object graph resident.
--
-- The bundle returns the Engine module table; Step / Pattern / Track / Utils
-- are exposed as fields on it (Engine.Step etc.).
--
-- Three tiers, each strictly more expensive than the last. Boot with each
-- in turn and note free RAM after each:
--
--   TIER A — module only (require cost, no instances)
--   TIER B — module + empty Engine.new() default = 4 tracks × 1 pat × 8 steps
--   TIER C — module + realistic 4-track / 16-step-per-track authoring graph
--
-- Expected stripped source size: ~17.8 KB. The interesting numbers are how
-- much additional heap each tier costs on top of the player baseline.
--

-- ---- TIER A — module only ----
-- local Engine = require("/sequencer_lite")

-- ---- TIER B — module + default empty engine (4 × 1 × 8 = 32 steps) ----
-- local Engine = require("/sequencer_lite")
-- SEQ_LITE_ENGINE = Engine.new()

-- ---- TIER C — realistic authoring graph (4 tracks × 16 steps = 64 steps) ----
-- local Engine = require("/sequencer_lite")
-- local Track  = Engine.Track
-- local Step   = Engine.Step
-- SEQ_LITE_ENGINE = Engine.new(120, 4, 4, 16)
-- for trackIdx = 1, 4 do
--     local track = Engine.getTrack(SEQ_LITE_ENGINE, trackIdx)
--     Track.setMidiChannel(track, trackIdx)
--     for stepIdx = 1, 16 do
--         local step = Track.getStep(track, stepIdx)
--         Step.setPitch(step, 60 + ((stepIdx - 1) % 12))
--         Step.setVelocity(step, 100)
--         Step.setDuration(step, 4)
--         Step.setGate(step, 2)
--     end
-- end

-- ---------------------------------------------------------------------------
-- LIVE-EDIT MEASUREMENT HOOK (uncomment ONE tier at a time)
-- ---------------------------------------------------------------------------
--
-- live/edit.lua mutates the compiled song in place (pitch / velocity / mute
-- as O(1) ops). Small footprint. One tier:
--
--   TIER A — module loaded
--

-- ---- TIER A — module loaded ----
-- local Edit = require("/edit")

-- ---------------------------------------------------------------------------
-- LIVE-EDIT AUDIBLE DEMO (uncomment to hear the editor working)
-- ---------------------------------------------------------------------------
--
-- Designed for the four_on_floor song: 4 bars × 4 kick beats = 16 NOTE_ONs.
-- Event indices are 1-based and interleaved (ON/OFF/ON/OFF...). Beat N is
-- ON at idx (2N - 1), OFF at idx 2N.
--
-- This block REQUIRES Tier A above (Edit loaded). Uncomment Tier A first,
-- then this block.
--
-- After boot you should hear:
--   Bar 1: kick / kick / SILENCE / kick      (beat 3 muted)
--   Bar 2: SNARE / kick / silence / kick     (beat 5 = note 38)
--   Bar 3: kick / quiet kick / silence / kick (beat 7 vel = 30)
--
-- O(1) edits — apply immediately, audible from the very first bar:
-- Edit.mutePair(song, 5)                  -- beat 3 (idx 5 = ON, 6 = OFF)
-- Edit.setPitch(song, 9, 38)              -- beat 5 → snare (note 38)
-- Edit.setVelocity(song, 13, 30)          -- beat 7 → quiet (vel 30)

-- ---------------------------------------------------------------------------
-- TIMER BLOCK — paste into the Grid module's timer event (10 ms tick is fine
-- when slaved to external MIDI clock; the timer is unused there).
-- ---------------------------------------------------------------------------
--
-- For external-clock playback, leave the timer empty — `rtmrx_cb` below drives
-- everything. For internal-clock playback, replace the body with:
--
-- Player.tick(SEQ_PLAYER, SEQ_EMIT)

-- ---------------------------------------------------------------------------
-- RTMIDI CALLBACK — paste into the rtmidi receive callback
-- ---------------------------------------------------------------------------
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
