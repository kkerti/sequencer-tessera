-- sequencer/engine.lua
-- The sequencer engine. Owns tracks, patterns, steps, loop points,
-- direction modes, and scene chains.
--
-- Engine.advance() is the cursor tick: called by the player once per
-- logical pulse per track (after clock div/mult has been applied by
-- the player). It returns raw step events ("NOTE_ON" / "NOTE_OFF" / nil)
-- with no MIDI and no probability logic — those are player concerns.
--
-- The player (player/player.lua) owns:
--   BPM, NOTE_ON/OFF emission, os.clock() gate timing,
--   active note tracking, probability evaluation.
-- Pitch quantization, swing, and other timing/harmony shaping are
-- intentionally not part of this engine — apply them downstream of MIDI.

local Track  = require("sequencer/track")
local Scene  = require("sequencer/scene")

local Engine = {}

-- ---------------------------------------------------------------------------
-- BPM helper (shared with player for pulse interval calculation)
-- ---------------------------------------------------------------------------

-- Converts BPM and pulsesPerBeat to a pulse interval in milliseconds.
function Engine.bpmToMs(bpm, pulsesPerBeat)
    pulsesPerBeat = pulsesPerBeat or 4
    assert(type(bpm) == "number" and bpm > 0, "engineBpmToMs: bpm must be positive")
    assert(type(pulsesPerBeat) == "number" and pulsesPerBeat > 0,
        "engineBpmToMs: pulsesPerBeat must be positive")
    return (60000 / bpm) / pulsesPerBeat
end

-- ---------------------------------------------------------------------------
-- Constructor
-- ---------------------------------------------------------------------------

local function engineInitTracks(trackCount, stepCount)
    local tracks = {}
    for i = 1, trackCount do
        local track = Track.new()
        if stepCount > 0 then
            Track.addPattern(track, stepCount)
        end
        tracks[i] = track
    end
    return tracks
end

-- Creates a new engine.
-- `bpm`           : tempo in BPM (default 120) — stored for reference; playback BPM lives on the player
-- `pulsesPerBeat` : clock resolution (default 4)
-- `trackCount`    : number of tracks (default 4, max 8)
-- `stepCount`     : initial steps per track (default 8; 0 = no initial pattern)
function Engine.new(bpm, pulsesPerBeat, trackCount, stepCount)
    bpm           = bpm or 120
    pulsesPerBeat = pulsesPerBeat or 4
    trackCount    = trackCount or 4
    stepCount     = stepCount or 8

    assert(type(bpm) == "number" and bpm > 0, "engineNew: bpm must be positive")
    assert(type(pulsesPerBeat) == "number" and pulsesPerBeat > 0,
        "engineNew: pulsesPerBeat must be positive")
    assert(type(trackCount) == "number" and trackCount > 0 and trackCount <= 8,
        "engineNew: trackCount must be 1-8")
    assert(type(stepCount) == "number" and stepCount >= 0,
        "engineNew: stepCount must be non-negative")

    return {
        bpm             = bpm,
        pulsesPerBeat   = pulsesPerBeat,
        pulseIntervalMs = Engine.bpmToMs(bpm, pulsesPerBeat),
        tracks          = engineInitTracks(trackCount, stepCount),
        trackCount      = trackCount,
        sceneChain      = nil,
    }
end

-- ---------------------------------------------------------------------------
-- Track access
-- ---------------------------------------------------------------------------

function Engine.getTrack(engine, index)
    assert(type(index) == "number" and index >= 1 and index <= engine.trackCount,
        "engineGetTrack: index out of range")
    return engine.tracks[index]
end

-- ---------------------------------------------------------------------------
-- Scene chain
-- ---------------------------------------------------------------------------

function Engine.setSceneChain(engine, chain)
    if chain ~= nil then
        assert(type(chain) == "table" and chain.scenes ~= nil,
            "engineSetSceneChain: chain must be a scene chain table or nil")
    end
    engine.sceneChain = chain
end

function Engine.getSceneChain(engine)
    return engine.sceneChain
end

function Engine.clearSceneChain(engine)
    engine.sceneChain = nil
end

function Engine.activateSceneChain(engine)
    local chain = engine.sceneChain
    assert(chain ~= nil, "engineActivateSceneChain: no scene chain attached")
    assert(Scene.chainGetCount(chain) > 0, "engineActivateSceneChain: chain is empty")
    Scene.chainSetActive(chain, true)
    Scene.chainReset(chain)
    local current = Scene.chainGetCurrent(chain)
    if current then
        Scene.applyToTracks(current, engine.tracks, engine.trackCount)
    end
end

function Engine.deactivateSceneChain(engine)
    local chain = engine.sceneChain
    if chain then
        Scene.chainSetActive(chain, false)
    end
end

-- ---------------------------------------------------------------------------
-- Advance (pure cursor tick — no MIDI, no player logic)
-- ---------------------------------------------------------------------------

-- Ticks the scene chain on beat boundaries.
-- `pulseCount` is passed in from the player (the player owns pulse counting).
local function engineTickSceneChain(engine, pulseCount)
    if engine.sceneChain == nil or not Scene.chainIsActive(engine.sceneChain) then
        return
    end
    if pulseCount % engine.pulsesPerBeat ~= 0 then
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

-- Advances a single track by one clock pulse. No return value — the caller
-- samples track outputs separately via Engine.sampleTrack.
function Engine.advanceTrack(engine, trackIndex)
    assert(type(trackIndex) == "number" and trackIndex >= 1 and trackIndex <= engine.trackCount,
        "engineAdvanceTrack: trackIndex out of range")
    Track.advance(engine.tracks[trackIndex])
end

-- Returns (cvA, cvB, gate) for the track at its current pulse.
-- Mirrors the ER-101's per-track CV-A / CV-B / GATE outputs.
function Engine.sampleTrack(engine, trackIndex)
    assert(type(trackIndex) == "number" and trackIndex >= 1 and trackIndex <= engine.trackCount,
        "engineSampleTrack: trackIndex out of range")
    return Track.sample(engine.tracks[trackIndex])
end

-- Called by the player once per logical pulse (after clock div/mult is applied).
-- Ticks the scene chain at beat boundaries using the player's pulse count.
-- The player calls Engine.advanceTrack() per track separately so it can
-- interleave its own clock accumulator logic.
function Engine.onPulse(engine, pulseCount)
    engineTickSceneChain(engine, pulseCount)
end

-- ---------------------------------------------------------------------------
-- Reset
-- ---------------------------------------------------------------------------

-- Resets all track cursors to step 1. Does not touch player state.
-- Returns nothing — note flushing is the player's responsibility.
function Engine.reset(engine)
    for i = 1, engine.trackCount do
        Track.reset(engine.tracks[i])
    end
    if engine.sceneChain and Scene.chainIsActive(engine.sceneChain) then
        Scene.chainReset(engine.sceneChain)
        local current = Scene.chainGetCurrent(engine.sceneChain)
        if current then
            Scene.applyToTracks(current, engine.tracks, engine.trackCount)
        end
    end
end

return Engine
