-- sequencer/engine.lua
-- The sequencer engine. Owns one or more tracks and a global clock.
--
-- engineTick() is called once per clock pulse by the host timer (main.lua).
-- It advances all tracks and returns a list of MIDI events to emit.
-- The engine has no knowledge of timers, MIDI libraries, or UI.
--
-- A MIDI event table:
--   { type = "NOTE_ON",  pitch = 60, velocity = 100, channel = 1 }
--   { type = "NOTE_OFF", pitch = 60, velocity = 0,   channel = 1 }

local Track  = require("sequencer/track")
local Step   = require("sequencer/step")
local Utils  = require("utils")
local Performance = require("sequencer/performance")
local Scene  = require("sequencer/scene")
local Probability = require("sequencer/probability")

local Engine = {}

-- BPM to pulse interval in milliseconds.
-- pulsesPerBeat is how many clock pulses fit in one beat (default 4).
function Engine.bpmToMs(bpm, pulsesPerBeat)
    pulsesPerBeat = pulsesPerBeat or 4
    assert(type(bpm) == "number" and bpm > 0, "engineBpmToMs: bpm must be positive")
    assert(type(pulsesPerBeat) == "number" and pulsesPerBeat > 0, "engineBpmToMs: pulsesPerBeat must be positive")
    return (60000 / bpm) / pulsesPerBeat
end

-- Initialises the tracks and probability suppression arrays for a new engine.
-- Returns tracks, probSuppressed.
local function engineInitTracks(trackCount, stepCount)
    local tracks = {}
    local probSuppressed = {}
    for i = 1, trackCount do
        local track = Track.new()
        if stepCount > 0 then
            Track.addPattern(track, stepCount)
        end
        tracks[i] = track
        probSuppressed[i] = false
    end
    return tracks, probSuppressed
end

-- Creates a new engine.
-- `bpm`           : tempo in beats per minute (default 120)
-- `pulsesPerBeat` : clock resolution (default 4)
-- `trackCount`    : number of tracks (default 4, max 8)
-- `stepCount`     : steps per track (default 8)
function Engine.new(bpm, pulsesPerBeat, trackCount, stepCount)
    bpm           = bpm or 120
    pulsesPerBeat = pulsesPerBeat or 4
    trackCount    = trackCount or 4
    stepCount     = stepCount or 8

    assert(type(bpm) == "number" and bpm > 0, "engineNew: bpm must be positive")
    assert(type(pulsesPerBeat) == "number" and pulsesPerBeat > 0, "engineNew: pulsesPerBeat must be positive")
    assert(type(trackCount) == "number" and trackCount > 0 and trackCount <= 8, "engineNew: trackCount must be 1-8")
    assert(type(stepCount) == "number" and stepCount >= 0, "engineNew: stepCount must be non-negative")

    local tracks, probSuppressed = engineInitTracks(trackCount, stepCount)

    return {
        bpm             = bpm,
        pulsesPerBeat   = pulsesPerBeat,
        pulseIntervalMs = Engine.bpmToMs(bpm, pulsesPerBeat),
        tracks          = tracks,
        trackCount      = trackCount,
        pulseCount      = 0,
        swingPercent    = 50,
        swingCarry      = 0,
        scaleName       = nil,
        scaleTable      = nil,
        rootNote        = 0,
        running         = true,
        -- Active note tracking: keyed by "pitch:channel", value = true.
        -- Used by allNotesOff() to flush sounding notes on reset/stop.
        activeNotes     = {},
        -- Per-track probability suppression flag. When a NOTE_ON is
        -- suppressed by probability, set to true so the corresponding
        -- NOTE_OFF is also suppressed.
        probSuppressed  = probSuppressed,
        -- Optional scene chain for automated loop-point sequencing.
        sceneChain      = nil,
    }
end

-- Returns the track at 1-based `index`.
function Engine.getTrack(engine, index)
    assert(type(index) == "number" and index >= 1 and index <= engine.trackCount,
        "engineGetTrack: index out of range")
    return engine.tracks[index]
end

-- Sets the BPM and recalculates the pulse interval.
function Engine.setBpm(engine, bpm)
    assert(type(bpm) == "number" and bpm > 0, "engineSetBpm: bpm must be positive")
    engine.bpm = bpm
    engine.pulseIntervalMs = Engine.bpmToMs(bpm, engine.pulsesPerBeat)
end

function Engine.setSwing(engine, percent)
    assert(type(percent) == "number" and percent >= 50 and percent <= 72,
        "engineSetSwing: percent out of range 50-72")
    engine.swingPercent = percent
end

function Engine.getSwing(engine)
    return engine.swingPercent
end

function Engine.setScale(engine, scaleName, rootNote)
    assert(type(scaleName) == "string", "engineSetScale: scaleName must be a string")
    assert(Utils.SCALES[scaleName] ~= nil, "engineSetScale: unknown scale")
    rootNote = rootNote or 0
    assert(type(rootNote) == "number" and rootNote >= 0 and rootNote <= 11,
        "engineSetScale: rootNote out of range 0-11")

    engine.scaleName = scaleName
    engine.scaleTable = Utils.SCALES[scaleName]
    engine.rootNote = rootNote
end

function Engine.clearScale(engine)
    engine.scaleName = nil
    engine.scaleTable = nil
    engine.rootNote = 0
end

-- ---------------------------------------------------------------------------
-- Scene chain
-- ---------------------------------------------------------------------------

-- Attaches a scene chain to the engine. Pass nil to detach.
-- When active, the chain drives track loop points automatically.
function Engine.setSceneChain(engine, chain)
    if chain ~= nil then
        assert(type(chain) == "table" and chain.scenes ~= nil,
            "engineSetSceneChain: chain must be a scene chain table or nil")
    end
    engine.sceneChain = chain
end

-- Returns the current scene chain, or nil.
function Engine.getSceneChain(engine)
    return engine.sceneChain
end

-- Removes the scene chain.
function Engine.clearSceneChain(engine)
    engine.sceneChain = nil
end

-- Activates the scene chain and applies the first scene's loop points.
-- The chain must already be attached via setSceneChain.
function Engine.activateSceneChain(engine)
    local chain = engine.sceneChain
    assert(chain ~= nil, "engineActivateSceneChain: no scene chain attached")
    assert(Scene.chainGetCount(chain) > 0, "engineActivateSceneChain: chain is empty")

    Scene.chainSetActive(chain, true)
    Scene.chainReset(chain)

    -- Apply the first scene's loop points.
    local current = Scene.chainGetCurrent(chain)
    if current then
        Scene.applyToTracks(current, engine.tracks, engine.trackCount)
    end
end

-- Deactivates the scene chain without removing it.
function Engine.deactivateSceneChain(engine)
    local chain = engine.sceneChain
    if chain then
        Scene.chainSetActive(chain, false)
    end
end

-- Builds a string key for the activeNotes table: "pitch:channel".
local function noteKey(pitch, channel)
    return pitch .. ":" .. channel
end

-- Returns NOTE_OFF events for every note currently tracked as sounding,
-- then clears the activeNotes table.  The caller should emit these events
-- to the MIDI output to avoid hanging notes.
function Engine.allNotesOff(engine)
    local events = {}
    for key, _ in pairs(engine.activeNotes) do
        local pitch, channel = key:match("^(%d+):(%d+)$")
        pitch   = tonumber(pitch)
        channel = tonumber(channel)
        events[#events + 1] = {
            type     = "NOTE_OFF",
            pitch    = pitch,
            velocity = 0,
            channel  = channel,
        }
    end
    engine.activeNotes = {}
    return events
end

-- Handles a NOTE_ON event for a single track within a tick.
-- Checks probability, resolves pitch, tracks the active note.
local function engineHandleNoteOn(engine, trackIndex, step, events)
    if not Probability.shouldPlay(step) then
        engine.probSuppressed[trackIndex] = true
        return
    end
    engine.probSuppressed[trackIndex] = false
    local channel = engine.tracks[trackIndex].midiChannel or trackIndex
    local pitch   = Step.resolvePitch(step, engine.scaleTable, engine.rootNote)
    local key     = noteKey(pitch, channel)
    engine.activeNotes[key] = true
    events[#events + 1] = {
        type     = "NOTE_ON",
        pitch    = pitch,
        velocity = Step.getVelocity(step),
        channel  = channel,
    }
end

-- Handles a NOTE_OFF event for a single track within a tick.
-- Suppresses if the preceding NOTE_ON was suppressed by probability.
local function engineHandleNoteOff(engine, trackIndex, step, events)
    if engine.probSuppressed[trackIndex] then
        engine.probSuppressed[trackIndex] = false
        return
    end
    local channel = engine.tracks[trackIndex].midiChannel or trackIndex
    local pitch   = Step.resolvePitch(step, engine.scaleTable, engine.rootNote)
    local key     = noteKey(pitch, channel)
    engine.activeNotes[key] = nil
    events[#events + 1] = {
        type     = "NOTE_OFF",
        pitch    = pitch,
        velocity = 0,
        channel  = channel,
    }
end

-- Processes a single track event (NOTE_ON or NOTE_OFF) within a tick.
-- Dispatches to the appropriate handler.
local function engineProcessTrackEvent(engine, trackIndex, step, event, events)
    if event == "NOTE_ON" then
        engineHandleNoteOn(engine, trackIndex, step, events)
    elseif event == "NOTE_OFF" then
        engineHandleNoteOff(engine, trackIndex, step, events)
    end
end

-- Scene chain beat check: on each beat boundary, tick the chain.
-- If the chain advances to a new scene, apply its loop points.
local function engineTickSceneChain(engine)
    if engine.sceneChain == nil or not Scene.chainIsActive(engine.sceneChain) then
        return
    end
    if engine.pulseCount % engine.pulsesPerBeat ~= 0 then
        return
    end
    local advanced = Scene.chainBeat(engine.sceneChain)
    if advanced then
        local current = Scene.chainGetCurrent(engine.sceneChain)
        if current then
            Scene.applyToTracks(current, engine.tracks, engine.trackCount)
        end
    end
end

-- Advances a single track by its clock accumulator and collects MIDI events.
local function engineAdvanceTrack(engine, trackIndex, events)
    local track = engine.tracks[trackIndex]
    track.clockAccum = track.clockAccum + track.clockMult
    local advanceCount = math.floor(track.clockAccum / track.clockDiv)
    track.clockAccum = track.clockAccum % track.clockDiv

    for _ = 1, advanceCount do
        local step = Track.getCurrentStep(track)
        local event = Track.advance(track)
        engineProcessTrackEvent(engine, trackIndex, step, event, events)
    end
end

-- Advances all tracks by one pulse.
-- Returns a list (possibly empty) of MIDI event tables.
-- Tracks active (sounding) notes so they can be flushed on reset/stop.
function Engine.tick(engine)
    if not engine.running then
        return {}
    end

    engine.pulseCount = engine.pulseCount + 1

    local shouldHoldSwing
    shouldHoldSwing, engine.swingCarry = Performance.nextSwingHold(
        engine.pulseCount,
        engine.pulsesPerBeat,
        engine.swingPercent,
        engine.swingCarry
    )

    if shouldHoldSwing then
        return {}
    end

    local events = {}

    for trackIndex = 1, engine.trackCount do
        engineAdvanceTrack(engine, trackIndex, events)
    end

    engineTickSceneChain(engine)

    return events
end

-- Resets the scene chain cursor and re-applies the first scene's loop points.
-- Called by Engine.reset when a scene chain is active.
local function engineResetSceneChain(engine)
    if engine.sceneChain == nil or not Scene.chainIsActive(engine.sceneChain) then
        return
    end
    Scene.chainReset(engine.sceneChain)
    local current = Scene.chainGetCurrent(engine.sceneChain)
    if current then
        Scene.applyToTracks(current, engine.tracks, engine.trackCount)
    end
end

-- Resets all tracks to the start.
-- Returns a list of NOTE_OFF events for any notes that were sounding,
-- so the caller can flush them to MIDI output before restarting.
-- Also resets the scene chain cursor if one is attached and active.
function Engine.reset(engine)
    local events = Engine.allNotesOff(engine)
    engine.pulseCount = 0
    engine.swingCarry = 0
    engine.running    = true
    for i = 1, engine.trackCount do
        Track.reset(engine.tracks[i])
        engine.probSuppressed[i] = false
    end
    engineResetSceneChain(engine)
    return events
end

-- Stops playback and returns NOTE_OFF events for all sounding notes.
-- After calling stop, Engine.tick() becomes a no-op until reset/start.
function Engine.stop(engine)
    local events = Engine.allNotesOff(engine)
    engine.running = false
    return events
end

-- Resumes playback after a stop.
-- Does not reset cursors — playback continues from where it was halted.
function Engine.start(engine)
    engine.running = true
end

return Engine
