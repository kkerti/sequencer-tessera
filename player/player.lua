-- player/player.lua
-- MIDI playback engine. Consumes a song table produced by the sequencer engine
-- and emits MIDI events via a caller-supplied emit callback.
--
-- Responsibilities (player only):
--   - Pulse clock: BPM → interval, single tick entry point
--   - Per-track clock div/mult accumulator
--   - Swing hold (pulse skip on off-beats)
--   - Probability gate per step
--   - Scale quantization at output time
--   - NOTE_ON emission with wall-clock timestamp
--   - NOTE_OFF emission driven by wall-clock (off_at), not pulse counter
--   - Active note tracking and allNotesOff for safe shutdown
--
-- Wall-clock source:
--   The player requires a `clockFn` at construction time — a zero-argument
--   function returning a monotonic millisecond counter (integer or float).
--   On macOS dev (luv): pass `require("luv").now`  (uv.now() in ms)
--   On Grid firmware:   pass the equivalent firmware ms function
--   This keeps the player free of host-specific requires.
--
-- The engine (sequencer/engine.lua) owns cursor advancement, direction modes,
-- loop points, scene chains, and all data-shaping operations. The player only
-- reads what the engine exposes via Engine.advanceTrack().
--
-- Emitted event tables (passed to the emit callback supplied by the host):
--   { type = "NOTE_ON",  pitch = 60, velocity = 100, channel = 1 }
--   { type = "NOTE_OFF", pitch = 60, velocity = 0,   channel = 1 }

local Engine      = require("sequencer/engine")
local Performance = require("sequencer/performance")
local Probability = require("sequencer/probability")
local Step        = require("sequencer/step")
local Utils       = require("utils")

local Player = {}

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

-- Converts BPM and pulsesPerBeat to a pulse interval in milliseconds.
local function playerBpmToMs(bpm, pulsesPerBeat)
    return (60000 / bpm) / pulsesPerBeat
end

-- Converts a gate value in pulses to milliseconds.
local function playerGateToMs(gate, pulsesPerBeat, bpm)
    local pulseMs = (60000 / bpm) / pulsesPerBeat
    return gate * pulseMs
end

-- String key for the active notes table: "pitch:channel".
local function playerNoteKey(pitch, channel)
    return pitch .. ":" .. channel
end

-- Scans active notes and emits NOTE_OFF for any whose off_at time has passed.
-- Uses pre-allocated parallel arrays to avoid per-tick table allocation.
local function playerFlushExpiredNotes(player, nowMs, emit)
    local i = 1
    while i <= player.activeNoteCount do
        if nowMs >= player.activeNoteOffAt[i] then
            local key = player.activeNoteKeys[i]
            local pitch, channel = key:match("^(%d+):(%d+)$")
            emit({
                type     = "NOTE_OFF",
                pitch    = tonumber(pitch),
                velocity = 0,
                channel  = tonumber(channel),
            })
            -- O(1) removal: swap with last element and shrink.
            local last = player.activeNoteCount
            if i ~= last then
                player.activeNoteKeys[i]  = player.activeNoteKeys[last]
                player.activeNoteOffAt[i] = player.activeNoteOffAt[last]
            end
            player.activeNoteKeys[last]  = nil
            player.activeNoteOffAt[last] = nil
            player.activeNoteCount       = last - 1
            -- Do not increment i: re-check this slot (now holds the swapped element).
        else
            i = i + 1
        end
    end
end

-- Registers a new sounding note in the active note arrays.
local function playerTrackNoteOn(player, pitch, channel, offAtMs)
    local n = player.activeNoteCount + 1
    player.activeNoteKeys[n]  = playerNoteKey(pitch, channel)
    player.activeNoteOffAt[n] = offAtMs
    player.activeNoteCount    = n
end

-- Handles a NOTE_ON raw event from the engine for one track slot.
local function playerHandleNoteOn(player, trackIndex, step, nowMs, emit)
    if not Probability.shouldPlay(step) then
        player.probSuppressed[trackIndex] = true
        return
    end
    player.probSuppressed[trackIndex] = false

    local track   = player.engine.tracks[trackIndex]
    local channel = track.midiChannel or trackIndex
    local pitch   = Step.resolvePitch(step, player.scaleTable, player.rootNote)
    local offAtMs = nowMs + playerGateToMs(step.gate, player.engine.pulsesPerBeat, player.bpm)

    playerTrackNoteOn(player, pitch, channel, offAtMs)

    emit({
        type     = "NOTE_ON",
        pitch    = pitch,
        velocity = Step.getVelocity(step),
        channel  = channel,
    })
end

-- Handles a NOTE_OFF raw event from the engine.
-- Wall-clock drives actual NOTE_OFF; only the probability flag needs clearing.
local function playerHandleNoteOff(player, trackIndex)
    if player.probSuppressed[trackIndex] then
        player.probSuppressed[trackIndex] = false
    end
end

-- Advances a single track by its clock accumulator, dispatching events.
local function playerAdvanceTrack(player, trackIndex, nowMs, emit)
    local engine = player.engine
    local track  = engine.tracks[trackIndex]

    track.clockAccum = track.clockAccum + track.clockMult
    local advanceCount = math.floor(track.clockAccum / track.clockDiv)
    track.clockAccum   = track.clockAccum % track.clockDiv

    for _ = 1, advanceCount do
        local step, event = Engine.advanceTrack(engine, trackIndex)
        if event == "NOTE_ON" then
            playerHandleNoteOn(player, trackIndex, step, nowMs, emit)
        elseif event == "NOTE_OFF" then
            playerHandleNoteOff(player, trackIndex)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Constructor
-- ---------------------------------------------------------------------------

-- Creates a new Player bound to an engine.
-- `engine`  : Engine table (sequencer/engine.lua instance)
-- `bpm`     : tempo in BPM (default: engine.bpm)
-- `clockFn` : function() → millisecond wall-clock counter (monotonic)
--             On macOS/luv: pass `require("luv").now`
--             On Grid:      pass the firmware ms clock function
function Player.new(engine, bpm, clockFn)
    assert(type(engine) == "table" and engine.tracks ~= nil,
        "playerNew: engine must be an engine table")

    bpm = bpm or engine.bpm
    assert(type(bpm) == "number" and bpm > 0, "playerNew: bpm must be positive")
    assert(type(clockFn) == "function", "playerNew: clockFn must be a function returning ms")

    local trackCount     = engine.trackCount
    local probSuppressed = {}
    for i = 1, trackCount do
        probSuppressed[i] = false
    end

    return {
        engine           = engine,
        bpm              = bpm,
        clockFn          = clockFn,
        pulseIntervalMs  = playerBpmToMs(bpm, engine.pulsesPerBeat),
        pulseCount       = 0,
        swingPercent     = 50,
        swingCarry       = 0,
        scaleName        = nil,
        scaleTable       = nil,
        rootNote         = 0,
        running          = false,
        activeNoteKeys   = {},
        activeNoteOffAt  = {},
        activeNoteCount  = 0,
        probSuppressed   = probSuppressed,
    }
end

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

function Player.setBpm(player, bpm)
    assert(type(bpm) == "number" and bpm > 0, "playerSetBpm: bpm must be positive")
    player.bpm             = bpm
    player.pulseIntervalMs = playerBpmToMs(bpm, player.engine.pulsesPerBeat)
end

function Player.getBpm(player)
    return player.bpm
end

function Player.setSwing(player, percent)
    assert(type(percent) == "number" and percent >= 50 and percent <= 72,
        "playerSetSwing: percent out of range 50-72")
    player.swingPercent = percent
end

function Player.getSwing(player)
    return player.swingPercent
end

function Player.setScale(player, scaleName, rootNote)
    assert(type(scaleName) == "string", "playerSetScale: scaleName must be a string")
    assert(Utils.SCALES[scaleName] ~= nil, "playerSetScale: unknown scale")
    rootNote = rootNote or 0
    assert(type(rootNote) == "number" and rootNote >= 0 and rootNote <= 11,
        "playerSetScale: rootNote out of range 0-11")
    player.scaleName  = scaleName
    player.scaleTable = Utils.SCALES[scaleName]
    player.rootNote   = rootNote
end

function Player.clearScale(player)
    player.scaleName  = nil
    player.scaleTable = nil
    player.rootNote   = 0
end

-- ---------------------------------------------------------------------------
-- Transport
-- ---------------------------------------------------------------------------

function Player.start(player)
    player.running = true
end

function Player.stop(player)
    player.running = false
end

-- Returns NOTE_OFF events for all currently sounding notes and clears arrays.
function Player.allNotesOff(player)
    local events = {}
    for i = 1, player.activeNoteCount do
        local key = player.activeNoteKeys[i]
        local pitch, channel = key:match("^(%d+):(%d+)$")
        events[#events + 1] = {
            type     = "NOTE_OFF",
            pitch    = tonumber(pitch),
            velocity = 0,
            channel  = tonumber(channel),
        }
        player.activeNoteKeys[i]  = nil
        player.activeNoteOffAt[i] = nil
    end
    player.activeNoteCount = 0
    return events
end

-- ---------------------------------------------------------------------------
-- Tick
-- ---------------------------------------------------------------------------

-- Called once per firmware timer callback (one clock pulse).
-- `emit` : function(event) — host-supplied callback, called for each MIDI event.
--
-- Per tick:
--   1. Sample wall-clock via clockFn() once — used for both flush and NOTE_ON timestamps.
--   2. Flush expired active notes (NOTE_OFFs).
--   3. Advance cursors (unless swing-held), emitting NOTE_ONs.
function Player.tick(player, emit)
    if not player.running then
        return
    end

    local nowMs = player.clockFn()

    playerFlushExpiredNotes(player, nowMs, emit)

    player.pulseCount = player.pulseCount + 1

    local shouldHold
    shouldHold, player.swingCarry = Performance.nextSwingHold(
        player.pulseCount,
        player.engine.pulsesPerBeat,
        player.swingPercent,
        player.swingCarry
    )

    if shouldHold then
        return
    end

    for trackIndex = 1, player.engine.trackCount do
        playerAdvanceTrack(player, trackIndex, nowMs, emit)
    end

    Engine.onPulse(player.engine, player.pulseCount)
end

return Player
