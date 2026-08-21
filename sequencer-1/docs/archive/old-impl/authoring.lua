-- authoring.lua
-- Host-only extensions for Step, Pattern, Track, Scene.
--
-- The engine that ships to the Grid module (`sequencer.lua`) only contains
-- the methods needed at runtime: Step.new + sample helpers, Pattern.new /
-- setName / setStep, Track new/add/sample/advance/reset + the per-pulse
-- accessors PatchLoader needs, Scene.applyToTracks plus the chain hooks
-- Engine.tick consults. Everything else (getters, editor mutators, scene
-- chain construction, Utils helpers) is authoring surface used only by
-- mathops, snapshot, probability, tui, controls, the dev harness, and the
-- test suite.
--
-- Splitting it out keeps the device cold-boot heap below the ~130 KB
-- ceiling. Each Lua function definition costs ~1-2 KB of bytecode on the
-- ESP32 VM regardless of body size; ~50 host-only functions had been
-- accounting for ~40 KB of unnecessary device heap.
--
-- This module mutates the shared Step/Pattern/Track/Scene tables in place,
-- so existing callers continue to use the familiar `Track.copyPattern(t,1)`
-- syntax. Just `require("authoring")` once before touching the editor API.
--
-- Usage:
--      local Seq = require("sequencer")
--      require("authoring")            -- extends Seq.Step etc. in place
--      Seq.Track.copyPattern(track, 1) -- now available

local Seq = require("sequencer")

local Step    = Seq.Step
local Pattern = Seq.Pattern
local Track   = Seq.Track
local Scene   = Seq.Scene
local Utils   = Seq.Utils

local floor = math.floor

-- ---------------------------------------------------------------------------
-- Step bit-layout constants. Duplicated from sequencer.lua intentionally;
-- the bit layout is a public on-disk contract and cannot drift without a
-- coordinated migration. Keeping the numbers private to each module avoids
-- exposing a "_internals" surface from sequencer.lua.
-- ---------------------------------------------------------------------------

local P_PITCH = 1                  -- 2^0
local P_VEL   = 128                -- 2^7
local P_DUR   = 16384              -- 2^14
local P_GATE  = 2097152            -- 2^21
local P_PROB  = 268435456          -- 2^28
local P_RATCH = 34359738368        -- 2^35
local P_ACT   = 68719476736        -- 2^36

local function pack7(step, value, pow)
    local cur = floor(step / pow) % 128
    return step + (value - cur) * pow
end

local function packBit(step, value, pow)
    local cur = floor(step / pow) % 2
    local newBit = value and 1 or 0
    return step + (newBit - cur) * pow
end

-- ===========================================================================
-- Utils
-- ===========================================================================

local NOTE_NAMES = { "C","C#","D","Eb","E","F","F#","G","G#","A","Bb","B" }

function Utils.tableNew(n, default)
    assert(type(n) == "number" and n > 0, "tableNew: n must be a positive number")
    local t = {}
    for i = 1, n do t[i] = default end
    return t
end

function Utils.tableCopy(t)
    assert(type(t) == "table", "tableCopy: argument must be a table")
    local copy = {}
    for k, v in pairs(t) do copy[k] = v end
    return copy
end

function Utils.clamp(value, min, max)
    assert(type(value) == "number", "clamp: value must be a number")
    assert(type(min) == "number", "clamp: min must be a number")
    assert(type(max) == "number", "clamp: max must be a number")
    if value < min then return min end
    if value > max then return max end
    return value
end

function Utils.pitchToName(midiNote)
    assert(type(midiNote) == "number" and midiNote >= 0 and midiNote <= 127,
        "pitchToName: midiNote out of range 0-127")
    local noteIndex = (midiNote % 12) + 1
    local octave    = floor(midiNote / 12) - 1
    return NOTE_NAMES[noteIndex] .. tostring(octave)
end

-- ===========================================================================
-- Step accessors (getters and setters)
-- ===========================================================================

function Step.getPitch(step)       return floor(step / P_PITCH) % 128 end
function Step.getVelocity(step)    return floor(step / P_VEL)   % 128 end
function Step.getDuration(step)    return floor(step / P_DUR)   % 128 end
function Step.getGate(step)        return floor(step / P_GATE)  % 128 end
function Step.getProbability(step) return floor(step / P_PROB)  % 128 end
function Step.getRatch(step)       return floor(step / P_RATCH) % 2 == 1 end
function Step.getActive(step)      return floor(step / P_ACT)   % 2 == 1 end

function Step.setPitch(step, value)
    assert(type(value) == "number" and value >= 0 and value <= 127,
        "stepSetPitch: value out of range 0-127")
    return pack7(step, value, P_PITCH)
end
function Step.setVelocity(step, value)
    assert(type(value) == "number" and value >= 0 and value <= 127,
        "stepSetVelocity: value out of range 0-127")
    return pack7(step, value, P_VEL)
end
function Step.setDuration(step, value)
    assert(type(value) == "number" and value >= 0 and value <= 99,
        "stepSetDuration: value out of range 0-99")
    return pack7(step, value, P_DUR)
end
function Step.setGate(step, value)
    assert(type(value) == "number" and value >= 0 and value <= 99,
        "stepSetGate: value out of range 0-99")
    return pack7(step, value, P_GATE)
end
function Step.setRatch(step, value)
    assert(type(value) == "boolean", "stepSetRatch: value must be boolean")
    return packBit(step, value, P_RATCH)
end
function Step.setProbability(step, value)
    assert(type(value) == "number" and value >= 0 and value <= 100,
        "stepSetProbability: value out of range 0-100")
    return pack7(step, value, P_PROB)
end
function Step.setActive(step, value)
    assert(type(value) == "boolean", "stepSetActive: value must be boolean")
    return packBit(step, value, P_ACT)
end

function Step.isPlayable(step)
    return floor(step / P_ACT) % 2 == 1
        and floor(step / P_DUR) % 128 > 0
        and floor(step / P_GATE) % 128 > 0
end

-- ===========================================================================
-- Pattern accessors
-- ===========================================================================

function Pattern.getStepCount(pattern) return pattern.stepCount end

function Pattern.getStep(pattern, index)
    assert(type(index) == "number" and index >= 1 and index <= pattern.stepCount,
        "patternGetStep: index out of range 1-" .. pattern.stepCount)
    return pattern.steps[index]
end

function Pattern.getName(pattern) return pattern.name end

-- ===========================================================================
-- Track editor / pattern manipulation
-- ===========================================================================

local function trackComputeStepCount(track)
    local total = 0
    for i = 1, track.patternCount do
        total = total + track.patterns[i].stepCount
    end
    return total
end

local function trackGetStepAtFlat(track, flatIndex)
    local offset = 0
    for i = 1, track.patternCount do
        local pat      = track.patterns[i]
        local patCount = pat.stepCount
        if flatIndex <= offset + patCount then
            return pat.steps[flatIndex - offset]
        end
        offset = offset + patCount
    end
    return nil
end

function Track.getPattern(track, patternIndex)
    assert(type(patternIndex) == "number" and patternIndex >= 1 and patternIndex <= track.patternCount,
        "trackGetPattern: patternIndex out of range 1-" .. track.patternCount)
    return track.patterns[patternIndex]
end

function Track.getPatternCount(track) return track.patternCount end

function Track.patternStartIndex(track, patternIndex)
    assert(type(patternIndex) == "number" and patternIndex >= 1 and patternIndex <= track.patternCount,
        "trackPatternStartIndex: patternIndex out of range 1-" .. track.patternCount)
    local offset = 0
    for i = 1, patternIndex - 1 do
        offset = offset + track.patterns[i].stepCount
    end
    return offset + 1
end

function Track.patternEndIndex(track, patternIndex)
    assert(type(patternIndex) == "number" and patternIndex >= 1 and patternIndex <= track.patternCount,
        "trackPatternEndIndex: patternIndex out of range 1-" .. track.patternCount)
    local offset = 0
    for i = 1, patternIndex do
        offset = offset + track.patterns[i].stepCount
    end
    return offset
end

-- Copy steps from pattern at srcIndex into a new pattern appended to track.
function Track.copyPattern(track, srcIndex)
    assert(type(srcIndex) == "number" and srcIndex >= 1 and srcIndex <= track.patternCount,
        "trackCopyPattern: srcIndex out of range 1-" .. track.patternCount)
    local src    = track.patterns[srcIndex]
    local count  = src.stepCount
    local newPat = Pattern.new(0, src.name)
    newPat.stepCount = count
    for i = 1, count do newPat.steps[i] = src.steps[i] end
    track.patternCount = track.patternCount + 1
    track.patterns[track.patternCount] = newPat
    return newPat
end

-- Insert a copy of pattern srcIndex immediately after srcIndex.
function Track.duplicatePattern(track, srcIndex)
    assert(type(srcIndex) == "number" and srcIndex >= 1 and srcIndex <= track.patternCount,
        "trackDuplicatePattern: srcIndex out of range 1-" .. track.patternCount)
    local src    = track.patterns[srcIndex]
    local count  = src.stepCount
    local newPat = Pattern.new(0, src.name)
    newPat.stepCount = count
    for i = 1, count do newPat.steps[i] = src.steps[i] end
    track.patternCount = track.patternCount + 1
    for i = track.patternCount, srcIndex + 2, -1 do
        track.patterns[i] = track.patterns[i - 1]
    end
    track.patterns[srcIndex + 1] = newPat
    return newPat
end

local function trackRemovePatternFromArray(track, patternIndex)
    for i = patternIndex, track.patternCount - 1 do
        track.patterns[i] = track.patterns[i + 1]
    end
    track.patterns[track.patternCount] = nil
    track.patternCount = track.patternCount - 1
end

local function trackShiftLoopAfterDelete(value, delStart, delEnd, delCount)
    if value == nil then return nil end
    if value >= delStart and value <= delEnd then return nil end
    if value > delEnd then return value - delCount end
    return value
end

function Track.deletePattern(track, patternIndex)
    assert(type(patternIndex) == "number" and patternIndex >= 1 and patternIndex <= track.patternCount,
        "trackDeletePattern: patternIndex out of range 1-" .. track.patternCount)
    assert(track.patternCount > 1, "trackDeletePattern: cannot delete the last remaining pattern")
    local delStart = Track.patternStartIndex(track, patternIndex)
    local delEnd   = Track.patternEndIndex(track, patternIndex)
    local delCount = delEnd - delStart + 1
    trackRemovePatternFromArray(track, patternIndex)
    track.loopStart = trackShiftLoopAfterDelete(track.loopStart, delStart, delEnd, delCount)
    track.loopEnd   = trackShiftLoopAfterDelete(track.loopEnd,   delStart, delEnd, delCount)
    track.cursor       = 1
    track.pulseCounter = 0
end

local function trackAdjustLoopPointsAfterInsert(track, patternIndex, stepCount)
    if stepCount <= 0 then return end
    local insertStart = Track.patternStartIndex(track, patternIndex)
    if track.loopStart ~= nil and track.loopStart >= insertStart then
        track.loopStart = track.loopStart + stepCount
    end
    if track.loopEnd ~= nil and track.loopEnd >= insertStart then
        track.loopEnd = track.loopEnd + stepCount
    end
end

function Track.insertPattern(track, patternIndex, stepCount)
    stepCount = stepCount or 8
    assert(type(patternIndex) == "number" and patternIndex >= 1 and patternIndex <= track.patternCount + 1,
        "trackInsertPattern: patternIndex out of range 1-" .. (track.patternCount + 1))
    assert(type(stepCount) == "number" and stepCount >= 0 and floor(stepCount) == stepCount,
        "trackInsertPattern: stepCount must be a non-negative integer")
    local newPat = Pattern.new(stepCount)
    track.patternCount = track.patternCount + 1
    for i = track.patternCount, patternIndex + 1, -1 do
        track.patterns[i] = track.patterns[i - 1]
    end
    track.patterns[patternIndex] = newPat
    trackAdjustLoopPointsAfterInsert(track, patternIndex, stepCount)
    track.cursor       = 1
    track.pulseCounter = 0
    return newPat
end

function Track.swapPatterns(track, indexA, indexB)
    assert(type(indexA) == "number" and indexA >= 1 and indexA <= track.patternCount,
        "trackSwapPatterns: indexA out of range 1-" .. track.patternCount)
    assert(type(indexB) == "number" and indexB >= 1 and indexB <= track.patternCount,
        "trackSwapPatterns: indexB out of range 1-" .. track.patternCount)
    if indexA == indexB then return end
    track.patterns[indexA], track.patterns[indexB] = track.patterns[indexB], track.patterns[indexA]
    track.loopStart    = nil
    track.loopEnd      = nil
    track.cursor       = 1
    track.pulseCounter = 0
end

function Track.pastePattern(track, destIndex, srcPattern)
    assert(type(destIndex) == "number" and destIndex >= 1 and destIndex <= track.patternCount,
        "trackPastePattern: destIndex out of range 1-" .. track.patternCount)
    assert(type(srcPattern) == "table" and srcPattern.steps ~= nil,
        "trackPastePattern: srcPattern must be a pattern table")
    local dest  = track.patterns[destIndex]
    local count = srcPattern.stepCount
    dest.steps     = {}
    dest.stepCount = count
    for i = 1, count do dest.steps[i] = srcPattern.steps[i] end
    dest.name = srcPattern.name
    track.cursor       = 1
    track.pulseCounter = 0
end

-- Step access (flat index API) -----------------------------------------------

function Track.getStepCount(track) return trackComputeStepCount(track) end

function Track.getStep(track, index)
    local stepCount = trackComputeStepCount(track)
    assert(type(index) == "number" and index >= 1 and index <= stepCount,
        "trackGetStep: index out of range 1-" .. stepCount)
    return trackGetStepAtFlat(track, index)
end

function Track.setStep(track, index, step)
    local stepCount = trackComputeStepCount(track)
    assert(type(index) == "number" and index >= 1 and index <= stepCount,
        "trackSetStep: index out of range 1-" .. stepCount)
    assert(type(step) == "number", "trackSetStep: step must be a packed integer")
    local offset = 0
    for i = 1, track.patternCount do
        local pat      = track.patterns[i]
        local patCount = pat.stepCount
        if index <= offset + patCount then
            pat.steps[index - offset] = step
            return
        end
        offset = offset + patCount
    end
end

function Track.getCurrentStep(track) return trackGetStepAtFlat(track, track.cursor) end

-- Loop point getters / clear (the engine path only needs setLoopStart /
-- setLoopEnd / clearLoopStart / clearLoopEnd, which Scene.applyToTracks
-- and PatchLoader call). Editor reads live here.

function Track.getLoopStart(track) return track.loopStart end
function Track.getLoopEnd(track)   return track.loopEnd end

-- Clock / channel / direction read accessors --------------------------------

function Track.getClockDiv(track)    return track.clockDiv end
function Track.getClockMult(track)   return track.clockMult end
function Track.getMidiChannel(track) return track.midiChannel end
function Track.getDirection(track)   return track.direction end

-- ===========================================================================
-- Scene editor / chain construction
-- ===========================================================================

local SCENE_NAME_MAX = 32
local SCENE_MAX      = 32

function Scene.new(repeats, lengthBeats, name, trackLoops)
    repeats     = repeats or 1
    lengthBeats = lengthBeats or 4
    name        = name or ""
    trackLoops  = trackLoops or {}
    assert(type(repeats) == "number" and repeats >= 1 and floor(repeats) == repeats,
        "sceneNew: repeats must be a positive integer")
    assert(type(lengthBeats) == "number" and lengthBeats >= 1 and floor(lengthBeats) == lengthBeats,
        "sceneNew: lengthBeats must be a positive integer")
    assert(type(name) == "string" and #name <= SCENE_NAME_MAX,
        "sceneNew: name must be a string of max " .. SCENE_NAME_MAX .. " chars")
    assert(type(trackLoops) == "table", "sceneNew: trackLoops must be a table")
    return { repeats = repeats, lengthBeats = lengthBeats, name = name, trackLoops = trackLoops }
end

function Scene.setTrackLoop(scene, trackIndex, loopStart, loopEnd)
    assert(type(trackIndex) == "number" and trackIndex >= 1, "sceneSetTrackLoop: trackIndex must be >= 1")
    if loopStart == nil and loopEnd == nil then
        scene.trackLoops[trackIndex] = nil
        return
    end
    assert(type(loopStart) == "number" and loopStart >= 1, "sceneSetTrackLoop: loopStart must be >= 1")
    assert(type(loopEnd)   == "number" and loopEnd   >= 1, "sceneSetTrackLoop: loopEnd must be >= 1")
    assert(loopStart <= loopEnd, "sceneSetTrackLoop: loopStart must be <= loopEnd")
    scene.trackLoops[trackIndex] = { loopStart = loopStart, loopEnd = loopEnd }
end

function Scene.getTrackLoop(scene, trackIndex) return scene.trackLoops[trackIndex] end

function Scene.setRepeats(scene, repeats)
    assert(type(repeats) == "number" and repeats >= 1 and floor(repeats) == repeats,
        "sceneSetRepeats: repeats must be a positive integer")
    scene.repeats = repeats
end
function Scene.getRepeats(scene) return scene.repeats end

function Scene.setLengthBeats(scene, lengthBeats)
    assert(type(lengthBeats) == "number" and lengthBeats >= 1 and floor(lengthBeats) == lengthBeats,
        "sceneSetLengthBeats: lengthBeats must be a positive integer")
    scene.lengthBeats = lengthBeats
end
function Scene.getLengthBeats(scene) return scene.lengthBeats end

function Scene.setName(scene, name)
    assert(type(name) == "string" and #name <= SCENE_NAME_MAX,
        "sceneSetName: name must be a string of max " .. SCENE_NAME_MAX .. " chars")
    scene.name = name
end
function Scene.getName(scene) return scene.name end

function Scene.newChain()
    return {
        scenes      = {},
        sceneCount  = 0,
        cursor      = 1,
        repeatCount = 0,
        beatCount   = 0,
        active      = false,
    }
end

function Scene.chainAppend(chain, scene)
    assert(type(scene) == "table" and scene.repeats ~= nil,
        "sceneChainAppend: scene must be a scene table")
    assert(chain.sceneCount < SCENE_MAX, "sceneChainAppend: max " .. SCENE_MAX .. " scenes")
    chain.sceneCount = chain.sceneCount + 1
    chain.scenes[chain.sceneCount] = scene
    return scene
end

function Scene.chainInsert(chain, index, scene)
    assert(type(index) == "number" and index >= 1 and index <= chain.sceneCount + 1,
        "sceneChainInsert: index out of range 1-" .. (chain.sceneCount + 1))
    assert(type(scene) == "table" and scene.repeats ~= nil,
        "sceneChainInsert: scene must be a scene table")
    assert(chain.sceneCount < SCENE_MAX, "sceneChainInsert: max " .. SCENE_MAX .. " scenes")
    chain.sceneCount = chain.sceneCount + 1
    for i = chain.sceneCount, index + 1, -1 do
        chain.scenes[i] = chain.scenes[i - 1]
    end
    chain.scenes[index] = scene
    return scene
end

function Scene.chainRemove(chain, index)
    assert(type(index) == "number" and index >= 1 and index <= chain.sceneCount,
        "sceneChainRemove: index out of range 1-" .. chain.sceneCount)
    for i = index, chain.sceneCount - 1 do
        chain.scenes[i] = chain.scenes[i + 1]
    end
    chain.scenes[chain.sceneCount] = nil
    chain.sceneCount = chain.sceneCount - 1
    if chain.cursor > chain.sceneCount then
        chain.cursor = math.max(1, chain.sceneCount)
    end
end

function Scene.chainGetScene(chain, index)
    assert(type(index) == "number" and index >= 1 and index <= chain.sceneCount,
        "sceneChainGetScene: index out of range 1-" .. chain.sceneCount)
    return chain.scenes[index]
end

function Scene.chainJumpTo(chain, index)
    assert(type(index) == "number" and index >= 1 and index <= chain.sceneCount,
        "sceneChainJumpTo: index out of range 1-" .. chain.sceneCount)
    chain.cursor      = index
    chain.repeatCount = 0
    chain.beatCount   = 0
end

-- ===========================================================================
-- Engine scene-chain wiring
-- ===========================================================================
--
-- The engine itself only needs to TICK an attached chain (per-pulse) and to
-- re-apply the current scene on Engine.reset(). Construction, attachment,
-- activation/deactivation, and read access are all authoring concerns.

local Engine = Seq.Engine

function Engine.setSceneChain(engine, chain)
    if chain ~= nil then
        assert(type(chain) == "table" and chain.scenes ~= nil,
            "engineSetSceneChain: chain must be a scene chain table or nil")
    end
    engine.sceneChain = chain
end

function Engine.getSceneChain(engine)   return engine.sceneChain end
function Engine.clearSceneChain(engine) engine.sceneChain = nil end

function Engine.activateSceneChain(engine)
    local chain = engine.sceneChain
    assert(chain ~= nil, "engineActivateSceneChain: no scene chain attached")
    assert(Scene.chainGetCount(chain) > 0, "engineActivateSceneChain: chain is empty")
    Scene.chainSetActive(chain, true)
    Scene.chainReset(chain)
    local current = Scene.chainGetCurrent(chain)
    if current then Scene.applyToTracks(current, engine.tracks, engine.trackCount) end
end

function Engine.deactivateSceneChain(engine)
    if engine.sceneChain then Scene.chainSetActive(engine.sceneChain, false) end
end
