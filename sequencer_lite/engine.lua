-- sequencer_lite/engine.lua
-- LITE BUILD: carved from sequencer/engine.lua.
-- See docs/dropped-features.md.
--
-- Removed in lite:
--   - Scene chain hooks (setSceneChain/getSceneChain/clearSceneChain,
--     activateSceneChain/deactivateSceneChain, engineTickSceneChain helper,
--     scene.* import, sceneChain field, scene block in Engine.reset)
--
-- Engine.onPulse remains as a stable hook (now a no-op) so callers do not
-- need to special-case lite-vs-full.

local Track  = require("sequencer_lite/track")

local Engine = {}

-- ---------------------------------------------------------------------------
-- BPM helper (shared with player for pulse interval calculation)
-- ---------------------------------------------------------------------------

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
    }
end

function Engine.getTrack(engine, index)
    assert(type(index) == "number" and index >= 1 and index <= engine.trackCount,
        "engineGetTrack: index out of range")
    return engine.tracks[index]
end

-- ---------------------------------------------------------------------------
-- Advance (pure cursor tick — no MIDI, no player logic)
-- ---------------------------------------------------------------------------

function Engine.advanceTrack(engine, trackIndex)
    assert(type(trackIndex) == "number" and trackIndex >= 1 and trackIndex <= engine.trackCount,
        "engineAdvanceTrack: trackIndex out of range")
    local track = engine.tracks[trackIndex]
    local step  = Track.getCurrentStep(track)
    local event = Track.advance(track)
    return step, event
end

-- onPulse remains as a stable hook so the player code path is identical
-- between lite and full engines. Lite has nothing to do per pulse.
function Engine.onPulse(engine, pulseCount)
    -- intentionally empty in lite
end

-- ---------------------------------------------------------------------------
-- Reset
-- ---------------------------------------------------------------------------

function Engine.reset(engine)
    for i = 1, engine.trackCount do
        Track.reset(engine.tracks[i])
    end
end

return Engine
