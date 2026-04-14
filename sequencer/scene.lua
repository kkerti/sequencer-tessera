-- sequencer/scene.lua
-- Scene chain system.
--
-- A Scene is a lightweight snapshot of per-track loop points + a repeat count
-- + a length in beats that defines one "pass" through the scene.
-- A SceneChain is an ordered list of Scenes that the engine steps through.
--
-- Scenes automate loop-point moves — they sit on top of the existing
-- Track loop-point architecture rather than replacing it.
--
-- The scene chain is consumed by Engine.tick(): when the current scene's
-- repeat count is exhausted (repeats * lengthBeats), the engine advances
-- to the next scene and applies its loop points to all tracks.
--
-- Terminology:
--   scene.trackLoops[trackIndex] = { loopStart = N, loopEnd = M } | nil
--     - nil means "leave this track's loop points unchanged"
--     - An explicit table overwrites the track's loop start/end
--   scene.repeats     = integer >= 1 (how many passes before advancing)
--   scene.lengthBeats = integer >= 1 (beats per pass; one pass = lengthBeats beats)
--   scene.name        = optional string label

local Scene = {}

local NAME_MAX_LEN = 32
local MAX_SCENES   = 32

-- ---------------------------------------------------------------------------
-- Scene (single)
-- ---------------------------------------------------------------------------

-- Creates a single Scene.
-- `repeats`     : how many times the loop plays before the chain advances (default 1)
-- `lengthBeats` : beats per pass (default 4, i.e. one bar in 4/4)
-- `name`        : optional string label (default "")
-- `trackLoops`  : optional table of per-track loop overrides
function Scene.new(repeats, lengthBeats, name, trackLoops)
    repeats     = repeats or 1
    lengthBeats = lengthBeats or 4
    name        = name or ""
    trackLoops  = trackLoops or {}

    assert(type(repeats) == "number" and repeats >= 1 and math.floor(repeats) == repeats,
        "sceneNew: repeats must be a positive integer")
    assert(type(lengthBeats) == "number" and lengthBeats >= 1 and math.floor(lengthBeats) == lengthBeats,
        "sceneNew: lengthBeats must be a positive integer")
    assert(type(name) == "string" and #name <= NAME_MAX_LEN,
        "sceneNew: name must be a string of max " .. NAME_MAX_LEN .. " characters")
    assert(type(trackLoops) == "table", "sceneNew: trackLoops must be a table")

    return {
        repeats     = repeats,
        lengthBeats = lengthBeats,
        name        = name,
        trackLoops  = trackLoops,
    }
end

-- Sets the loop points for a specific track within a scene.
-- Pass `loopStart` and `loopEnd` as flat step indices (1-based).
-- Pass nil for both to clear the override (leave track unchanged).
function Scene.setTrackLoop(scene, trackIndex, loopStart, loopEnd)
    assert(type(trackIndex) == "number" and trackIndex >= 1,
        "sceneSetTrackLoop: trackIndex must be >= 1")

    if loopStart == nil and loopEnd == nil then
        scene.trackLoops[trackIndex] = nil
        return
    end

    assert(type(loopStart) == "number" and loopStart >= 1,
        "sceneSetTrackLoop: loopStart must be >= 1")
    assert(type(loopEnd) == "number" and loopEnd >= 1,
        "sceneSetTrackLoop: loopEnd must be >= 1")
    assert(loopStart <= loopEnd,
        "sceneSetTrackLoop: loopStart must be <= loopEnd")

    scene.trackLoops[trackIndex] = {
        loopStart = loopStart,
        loopEnd   = loopEnd,
    }
end

-- Returns the loop override for a track, or nil if not set.
function Scene.getTrackLoop(scene, trackIndex)
    return scene.trackLoops[trackIndex]
end

-- Sets the repeat count.
function Scene.setRepeats(scene, repeats)
    assert(type(repeats) == "number" and repeats >= 1 and math.floor(repeats) == repeats,
        "sceneSetRepeats: repeats must be a positive integer")
    scene.repeats = repeats
end

-- Returns the repeat count.
function Scene.getRepeats(scene)
    return scene.repeats
end

-- Sets the length in beats per pass.
function Scene.setLengthBeats(scene, lengthBeats)
    assert(type(lengthBeats) == "number" and lengthBeats >= 1 and math.floor(lengthBeats) == lengthBeats,
        "sceneSetLengthBeats: lengthBeats must be a positive integer")
    scene.lengthBeats = lengthBeats
end

-- Returns the length in beats per pass.
function Scene.getLengthBeats(scene)
    return scene.lengthBeats
end

-- Sets the scene name.
function Scene.setName(scene, name)
    assert(type(name) == "string" and #name <= NAME_MAX_LEN,
        "sceneSetName: name must be a string of max " .. NAME_MAX_LEN .. " characters")
    scene.name = name
end

-- Returns the scene name.
function Scene.getName(scene)
    return scene.name
end

-- ---------------------------------------------------------------------------
-- SceneChain
-- ---------------------------------------------------------------------------

-- Creates a new empty SceneChain.
-- The chain holds an ordered list of scenes and a cursor + repeat counter.
function Scene.newChain()
    return {
        scenes       = {},
        sceneCount   = 0,
        cursor       = 1,     -- 1-based index into scenes
        repeatCount  = 0,     -- how many full passes have completed for current scene
        beatCount    = 0,     -- beats elapsed within the current pass
        active       = false, -- whether the chain is driving loop points
    }
end

-- Appends a scene to the chain. Returns the scene.
function Scene.chainAppend(chain, scene)
    assert(type(scene) == "table" and scene.repeats ~= nil,
        "sceneChainAppend: scene must be a scene table")
    assert(chain.sceneCount < MAX_SCENES,
        "sceneChainAppend: max " .. MAX_SCENES .. " scenes")

    chain.sceneCount = chain.sceneCount + 1
    chain.scenes[chain.sceneCount] = scene
    return scene
end

-- Inserts a scene at a specific 1-based position.
function Scene.chainInsert(chain, index, scene)
    assert(type(index) == "number" and index >= 1 and index <= chain.sceneCount + 1,
        "sceneChainInsert: index out of range 1-" .. (chain.sceneCount + 1))
    assert(type(scene) == "table" and scene.repeats ~= nil,
        "sceneChainInsert: scene must be a scene table")
    assert(chain.sceneCount < MAX_SCENES,
        "sceneChainInsert: max " .. MAX_SCENES .. " scenes")

    chain.sceneCount = chain.sceneCount + 1
    for i = chain.sceneCount, index + 1, -1 do
        chain.scenes[i] = chain.scenes[i - 1]
    end
    chain.scenes[index] = scene
    return scene
end

-- Removes a scene at a specific 1-based position.
function Scene.chainRemove(chain, index)
    assert(type(index) == "number" and index >= 1 and index <= chain.sceneCount,
        "sceneChainRemove: index out of range 1-" .. chain.sceneCount)

    for i = index, chain.sceneCount - 1 do
        chain.scenes[i] = chain.scenes[i + 1]
    end
    chain.scenes[chain.sceneCount] = nil
    chain.sceneCount = chain.sceneCount - 1

    -- Adjust cursor if needed.
    if chain.cursor > chain.sceneCount then
        chain.cursor = math.max(1, chain.sceneCount)
    end
end

-- Returns the scene at 1-based index.
function Scene.chainGetScene(chain, index)
    assert(type(index) == "number" and index >= 1 and index <= chain.sceneCount,
        "sceneChainGetScene: index out of range 1-" .. chain.sceneCount)
    return chain.scenes[index]
end

-- Returns the number of scenes in the chain.
function Scene.chainGetCount(chain)
    return chain.sceneCount
end

-- Returns the current scene (at the cursor), or nil if the chain is empty.
function Scene.chainGetCurrent(chain)
    if chain.sceneCount == 0 then
        return nil
    end
    return chain.scenes[chain.cursor]
end

-- Resets the chain cursor to scene 1 with zero repeats completed.
function Scene.chainReset(chain)
    chain.cursor      = 1
    chain.repeatCount = 0
    chain.beatCount   = 0
end

-- Activates the chain — the engine should start applying scene loop points.
function Scene.chainSetActive(chain, active)
    assert(type(active) == "boolean", "sceneChainSetActive: active must be boolean")
    chain.active = active
end

-- Returns whether the chain is active.
function Scene.chainIsActive(chain)
    return chain.active
end

-- Signals that one full loop pass has completed for the current scene.
-- Returns true if the chain advanced to a new scene, false otherwise.
-- When the chain reaches the end, it wraps to scene 1.
function Scene.chainCompletePass(chain)
    if chain.sceneCount == 0 then
        return false
    end

    chain.repeatCount = chain.repeatCount + 1
    local current = chain.scenes[chain.cursor]

    if chain.repeatCount >= current.repeats then
        -- Advance to next scene.
        chain.repeatCount = 0
        chain.beatCount   = 0
        if chain.cursor >= chain.sceneCount then
            chain.cursor = 1 -- wrap
        else
            chain.cursor = chain.cursor + 1
        end
        return true
    end

    return false
end

-- Called once per beat by the engine. Increments the beat counter and
-- automatically completes a pass when `lengthBeats` is reached.
-- Returns true if the chain advanced to a new scene, false otherwise.
function Scene.chainBeat(chain)
    if chain.sceneCount == 0 then
        return false
    end

    chain.beatCount = chain.beatCount + 1
    local current = chain.scenes[chain.cursor]

    if chain.beatCount >= current.lengthBeats then
        chain.beatCount = 0
        return Scene.chainCompletePass(chain)
    end

    return false
end

-- Manually jumps to a specific scene index (1-based).
-- Resets the repeat counter and beat counter.
function Scene.chainJumpTo(chain, index)
    assert(type(index) == "number" and index >= 1 and index <= chain.sceneCount,
        "sceneChainJumpTo: index out of range 1-" .. chain.sceneCount)
    chain.cursor      = index
    chain.repeatCount = 0
    chain.beatCount   = 0
end

-- Applies the current scene's loop points to the given tracks array.
-- `tracks` is the engine's tracks table, `trackCount` is the number of tracks.
-- Only overrides tracks that have explicit loop settings in the scene.
-- Clears existing loop points before setting new ones to avoid validation
-- conflicts (e.g. new loopStart > old loopEnd).
function Scene.applyToTracks(scene, tracks, trackCount)
    assert(type(tracks) == "table", "sceneApplyToTracks: tracks must be a table")
    assert(type(trackCount) == "number" and trackCount >= 1,
        "sceneApplyToTracks: trackCount must be >= 1")

    local Track = require("sequencer/track")

    for trackIndex = 1, trackCount do
        local loopOverride = scene.trackLoops[trackIndex]
        if loopOverride ~= nil then
            -- Clear first to avoid validation order issues.
            Track.clearLoopStart(tracks[trackIndex])
            Track.clearLoopEnd(tracks[trackIndex])
            Track.setLoopStart(tracks[trackIndex], loopOverride.loopStart)
            Track.setLoopEnd(tracks[trackIndex], loopOverride.loopEnd)
        end
    end
end

return Scene
