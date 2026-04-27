-- player/player.lua
-- Tiny on-device player for compiled songs. Pure tape-deck: walks the song's
-- pre-rendered event arrays and emits MIDI. No probability, no scale, no
-- swing, no gate math, no active-note bookkeeping.
--
-- All live decisions (probability rolls, future jitter, scene moves) belong
-- in the song writer (sequencer/song_writer.lua), which mutates the song
-- in place at every loop boundary via `song.onLoopBoundary(song, loopIndex)`.
-- A static song leaves `onLoopBoundary` nil and pays zero cost per loop.
--
-- Two clock modes:
--   1. Internal (software) clock — call Player.tick(p, emit) on a timer;
--      derives elapsed pulses from clockFn() and advances accordingly.
--   2. External clock (e.g. MIDI 0xF8) — call Player.externalPulse(p, emit)
--      once per player pulse. clockFn / pulseMs / startMs are unused.
--
-- The only mutable runtime knob is BPM (Player.setBpm).
--
-- Emit callback signature:
--   emit(eventType, pitch, velocity, channel)
--     eventType: "NOTE_ON" | "NOTE_OFF"
--
-- Compiled song schema (see tools/song_compile.lua):
--   { bpm, pulsesPerBeat, durationPulses, loop, eventCount,
--     atPulse[], kind[], pitch[], velocity[], channel[],
--     -- writer-only (present iff hasProbability):
--     hasProbability, pairOff[], srcStepProb[], srcVelocity[],
--     onLoopBoundary = function(song, loopIndex) end | nil }
--
-- kind[] values:
--   1 = NOTE_ON  (emit)
--   0 = NOTE_OFF (emit)
--   2 = NOTE_ON  muted by writer this loop (skip)
--   3 = NOTE_OFF muted by writer this loop (skip)

local Player = {}

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

function Player.new(song, clockFn, bpm)
    bpm = bpm or song.bpm
    return {
        song       = song,
        clockFn    = clockFn,
        bpm        = bpm,
        pulseMs    = 60000 / bpm / song.pulsesPerBeat,
        startMs    = 0,
        pulseCount = 0,
        cursor     = 1,
        loopIndex  = 0,
        running    = false,
    }
end

-- ---------------------------------------------------------------------------
-- Transport
-- ---------------------------------------------------------------------------

function Player.start(p)
    if p.clockFn then p.startMs = p.clockFn() end
    p.pulseCount = 0
    p.cursor     = 1
    p.loopIndex  = 0
    p.running    = true
end

function Player.stop(p)
    p.running = false
end

-- Sets BPM at runtime, preserving current pulse position so playback doesn't
-- jump. Only meaningful for internal-clock mode (Player.tick).
function Player.setBpm(p, bpm)
    p.bpm     = bpm
    p.pulseMs = 60000 / bpm / p.song.pulsesPerBeat
    if p.clockFn then
        p.startMs = p.clockFn() - p.pulseCount * p.pulseMs
    end
end

-- Emergency drain: scans events [1..cursor] and returns a list of
-- NOTE_OFF descriptors for every NOTE_ON that hasn't been paired yet.
-- Caller is responsible for sending the MIDI (via midi_send / emit fn).
-- Returns: { { pitch=int, channel=int }, ... }  (possibly empty)
-- O(cursor); call only on stop/panic.
function Player.allNotesOff(p)
    local song    = p.song
    local kind    = song.kind
    local pairOff = song.pairOff   -- may be nil for static songs
    local atPulse = song.atPulse
    local pitch   = song.pitch
    local channel = song.channel
    local pc      = p.pulseCount
    local offs    = {}

    for i = 1, p.cursor - 1 do
        local k = kind[i]
        if k == 1 then
            -- NOTE_ON was emitted; check whether its NOTE_OFF has played.
            local off
            if pairOff then
                off = pairOff[i]
            else
                -- Static song: linear-scan forward for the matching NOTE_OFF.
                -- Acceptable because allNotesOff is an emergency path.
                for j = i + 1, song.eventCount do
                    if kind[j] == 0 and pitch[j] == pitch[i]
                       and channel[j] == channel[i] then
                        off = j
                        break
                    end
                end
            end
            if not off or off == 0 or atPulse[off] > pc then
                offs[#offs + 1] = { pitch = pitch[i], channel = channel[i] }
            end
        end
    end
    return offs
end

-- ---------------------------------------------------------------------------
-- External-clock entry point
-- ---------------------------------------------------------------------------

-- Advances the player by exactly one pulse. Call once per MIDI clock pulse
-- (after dividing 24 ppq down to song.pulsesPerBeat ppq).
function Player.externalPulse(p, emit)
    if not p.running then return end

    p.pulseCount = p.pulseCount + 1
    local song   = p.song
    local pc     = p.pulseCount
    local atPulse = song.atPulse
    local kind    = song.kind

    while p.cursor <= song.eventCount and atPulse[p.cursor] <= pc do
        local i = p.cursor
        local k = kind[i]
        if k == 1 then
            emit("NOTE_ON",  song.pitch[i], song.velocity[i], song.channel[i])
        elseif k == 0 then
            emit("NOTE_OFF", song.pitch[i], 0,                 song.channel[i])
        end
        -- kind 2 / 3 are muted — skip silently.
        p.cursor = i + 1
    end

    if song.loop and p.cursor > song.eventCount and pc >= song.durationPulses then
        p.pulseCount = pc - song.durationPulses
        p.cursor     = 1
        p.loopIndex  = p.loopIndex + 1
        if p.clockFn then
            p.startMs = p.startMs + song.durationPulses * p.pulseMs
        end
        if song.onLoopBoundary then
            song.onLoopBoundary(song, p.loopIndex)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Internal-clock entry point
-- ---------------------------------------------------------------------------

-- Called once per firmware timer callback in software-clock mode.
-- Derives the target pulse from clockFn() and advances pulseCount up to it.
function Player.tick(p, emit)
    if not p.running then return end
    local target = math.floor((p.clockFn() - p.startMs) / p.pulseMs)
    while p.pulseCount < target do
        Player.externalPulse(p, emit)
        if not p.running then return end
    end
end

return Player
