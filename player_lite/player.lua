-- player_lite/player.lua
-- Tiny on-device player for compiled songs.
--
-- Two clock modes, same engine:
--   1. Internal (software) clock — call Player.tick(p, emit) on a timer;
--      it derives elapsed pulses from clockFn() and advances the player
--      that many pulses.
--   2. External clock (e.g. MIDI 0xF8) — call Player.externalPulse(p, emit)
--      once per player pulse.  clockFn / pulseMs / startMs are unused.
--
-- Internally the player advances one pulse at a time via externalPulse.
-- p.pulseCount is the source of truth for "where we are in the song".
--
-- The player has zero dependency on the sequencer engine — songs are
-- pre-rendered to flat parallel arrays by tools/song_compile.lua.
--
-- Emit callback signature (host-supplied):
--   emit(eventType, pitch, velocity, channel)
--     eventType: "NOTE_ON" | "NOTE_OFF"
--
-- Compiled song schema (see tools/song_compile.lua):
--   { bpm, pulsesPerBeat, durationPulses, loop, eventCount,
--     atPulse[], pitch[], velocity[], channel[], gatePulses[], probability[] }

local Player = {}

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

-- Creates a new player bound to a compiled song.
-- `song`    : compiled song table (output of tools/song_compile.lua)
-- `clockFn` : function() returning monotonic ms (used only by Player.tick)
-- `bpm`     : optional BPM override (defaults to song.bpm)
function Player.new(song, clockFn, bpm)
    bpm = bpm or song.bpm
    local pulseMs = 60000 / bpm / song.pulsesPerBeat
    return {
        song            = song,
        clockFn         = clockFn,
        bpm             = bpm,
        pulseMs         = pulseMs,
        startMs         = 0,
        pulseCount      = 0,
        cursor          = 1,
        running         = false,
        -- Active notes scheduled for NOTE_OFF, parallel arrays.
        activePitch     = {},
        activeChannel   = {},
        activeOffPulse  = {},
        activeCount     = 0,
    }
end

-- ---------------------------------------------------------------------------
-- Transport
-- ---------------------------------------------------------------------------

function Player.start(p)
    if p.clockFn then p.startMs = p.clockFn() end
    p.pulseCount  = 0
    p.cursor      = 1
    p.running     = true
    p.activeCount = 0
end

function Player.stop(p)
    p.running = false
end

-- Sets BPM at runtime, preserving current pulse position so playback
-- doesn't jump.  Only meaningful for internal-clock mode (Player.tick).
function Player.setBpm(p, bpm)
    p.bpm     = bpm
    p.pulseMs = 60000 / bpm / p.song.pulsesPerBeat
    if p.clockFn then
        p.startMs = p.clockFn() - p.pulseCount * p.pulseMs
    end
end

-- Returns NOTE_OFF events for all sounding notes; clears active list.
-- Caller must emit them via the firmware MIDI API.
function Player.allNotesOff(p)
    local n = p.activeCount
    local list = {}
    for i = 1, n do
        list[i] = {
            type     = "NOTE_OFF",
            pitch    = p.activePitch[i],
            channel  = p.activeChannel[i],
            velocity = 0,
        }
        p.activePitch[i]    = nil
        p.activeChannel[i]  = nil
        p.activeOffPulse[i] = nil
    end
    p.activeCount = 0
    return list
end

-- ---------------------------------------------------------------------------
-- Internals
-- ---------------------------------------------------------------------------

-- Flushes any active notes whose offPulse has been reached.
local function playerFlushExpired(p, currentPulse, emit)
    local i = 1
    while i <= p.activeCount do
        if p.activeOffPulse[i] <= currentPulse then
            emit("NOTE_OFF", p.activePitch[i], 0, p.activeChannel[i])
            -- swap-remove
            local last = p.activeCount
            if i ~= last then
                p.activePitch[i]    = p.activePitch[last]
                p.activeChannel[i]  = p.activeChannel[last]
                p.activeOffPulse[i] = p.activeOffPulse[last]
            end
            p.activePitch[last]    = nil
            p.activeChannel[last]  = nil
            p.activeOffPulse[last] = nil
            p.activeCount          = last - 1
        else
            i = i + 1
        end
    end
end

-- Registers a sounding note for later NOTE_OFF.
local function playerTrackNoteOn(p, pitch, channel, offPulse)
    local n = p.activeCount + 1
    p.activePitch[n]    = pitch
    p.activeChannel[n]  = channel
    p.activeOffPulse[n] = offPulse
    p.activeCount       = n
end

-- Wraps pulseCount + cursor back to song start when looping.
local function playerLoopWrap(p)
    local song = p.song
    if song.loop and p.cursor > song.eventCount
       and p.pulseCount >= song.durationPulses then
        p.pulseCount = p.pulseCount - song.durationPulses
        p.cursor     = 1
        if p.clockFn then
            p.startMs = p.startMs + song.durationPulses * p.pulseMs
        end
    end
end

-- ---------------------------------------------------------------------------
-- External-clock entry point
-- ---------------------------------------------------------------------------

-- Advances the player by exactly one pulse.  Call once per MIDI clock pulse
-- (after dividing 24 ppq down to song.pulsesPerBeat ppq).
function Player.externalPulse(p, emit)
    if not p.running then return end

    p.pulseCount = p.pulseCount + 1
    local song   = p.song
    local pc     = p.pulseCount

    playerFlushExpired(p, pc, emit)

    while p.cursor <= song.eventCount and song.atPulse[p.cursor] <= pc do
        local i    = p.cursor
        local prob = song.probability[i]
        if prob >= 100 or math.random(1, 100) <= prob then
            local pitch    = song.pitch[i]
            local channel  = song.channel[i]
            local offPulse = song.atPulse[i] + song.gatePulses[i]
            emit("NOTE_ON", pitch, song.velocity[i], channel)
            playerTrackNoteOn(p, pitch, channel, offPulse)
        end
        p.cursor = i + 1
    end

    playerLoopWrap(p)
end

-- ---------------------------------------------------------------------------
-- Internal-clock entry point
-- ---------------------------------------------------------------------------

-- Called once per firmware timer callback in software-clock mode.
-- Derives the target pulse from clockFn() and advances pulseCount up to it.
function Player.tick(p, emit)
    if not p.running then return end
    local now    = p.clockFn()
    local target = math.floor((now - p.startMs) / p.pulseMs)
    while p.pulseCount < target do
        Player.externalPulse(p, emit)
        if not p.running then return end
    end
end

return Player
