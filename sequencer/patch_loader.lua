-- sequencer/patch_loader.lua
-- Builds an Engine from a terse patch descriptor.
--
-- Descriptor schema (see patches/*.lua):
--   {
--     bpm           = number,
--     ppb           = number,            -- pulsesPerBeat
--     bars          = number,            -- optional, advisory only (loop length hint)
--     beatsPerBar   = number,            -- optional, advisory only
--     tracks = {
--       { channel     = number,          -- MIDI channel (1-based)
--         direction   = "forward" | "reverse" | "pingpong" | "random" | "brownian",
--         clockDiv    = number,
--         clockMult   = number,
--         loopStart   = number,          -- optional flat step index
--         loopEnd     = number,          -- optional flat step index
--         patterns = {
--           { name  = string,
--             steps = {
--               -- positional Step args: {pitch, velocity, duration, gate, ratch?, prob?}
--               { 60, 100, 4, 2 },
--               { 62, 100, 4, 2, true },
--               ...
--             },
--           },
--           ...
--         },
--       },
--       ...
--     },
--   }
--
-- The loader is shared by the host (main.lua) and the device (grid_module.lua).
-- It is the single bridge between authoring patches and the live engine.

local Engine  = require("sequencer/engine")
local Track   = require("sequencer/track")
local Pattern = require("sequencer/pattern")
local Step    = require("sequencer/step")

local PatchLoader = {}

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

local function patchLoaderBuildStep(descriptor)
    -- descriptor is a positional array {pitch, velocity, duration, gate, ratch?, prob?}
    -- Construct directly via Step.new (single allocation, single return).
    return Step.new(
        descriptor[1],
        descriptor[2],
        descriptor[3],
        descriptor[4],
        descriptor[5],
        descriptor[6])
end

local function patchLoaderApplyPattern(pattern, patternDescriptor)
    if patternDescriptor.name then
        Pattern.setName(pattern, patternDescriptor.name)
    end

    local steps = patternDescriptor.steps or {}
    assert(#steps == Pattern.getStepCount(pattern),
        "patchLoaderApplyPattern: pattern step count mismatch")
    for i, stepDescriptor in ipairs(steps) do
        Pattern.setStep(pattern, i, patchLoaderBuildStep(stepDescriptor))
    end
end

local function patchLoaderApplyTrack(track, trackDescriptor)
    if trackDescriptor.channel then
        Track.setMidiChannel(track, trackDescriptor.channel)
    end
    if trackDescriptor.direction then
        Track.setDirection(track, trackDescriptor.direction)
    end
    if trackDescriptor.clockDiv then
        Track.setClockDiv(track, trackDescriptor.clockDiv)
    end
    if trackDescriptor.clockMult then
        Track.setClockMult(track, trackDescriptor.clockMult)
    end

    local patterns = trackDescriptor.patterns or {}
    for _, patternDescriptor in ipairs(patterns) do
        local stepCount = #(patternDescriptor.steps or {})
        local pattern   = Track.addPattern(track, stepCount)
        patchLoaderApplyPattern(pattern, patternDescriptor)
    end

    -- Loop points are applied last so they reference final flat indices.
    if trackDescriptor.loopStart then
        Track.setLoopStart(track, trackDescriptor.loopStart)
    end
    if trackDescriptor.loopEnd then
        Track.setLoopEnd(track, trackDescriptor.loopEnd)
    end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- Builds and returns an Engine populated from the descriptor.
function PatchLoader.build(descriptor)
    assert(type(descriptor) == "table", "patchLoaderBuild: descriptor must be a table")
    assert(type(descriptor.bpm) == "number", "patchLoaderBuild: descriptor.bpm required")
    assert(type(descriptor.ppb) == "number", "patchLoaderBuild: descriptor.ppb required")
    assert(type(descriptor.tracks) == "table" and #descriptor.tracks > 0,
        "patchLoaderBuild: descriptor.tracks must be non-empty")

    local trackCount = #descriptor.tracks
    -- Build engine with zero pre-allocated steps; patterns are added per track.
    local engine = Engine.new(descriptor.bpm, descriptor.ppb, trackCount, 0)

    for i, trackDescriptor in ipairs(descriptor.tracks) do
        patchLoaderApplyTrack(Engine.getTrack(engine, i), trackDescriptor)
    end

    return engine
end

-- Loads a patch by module path (e.g. "patches/dark_groove") and returns the
-- engine. Convenience wrapper for callers that don't already have the
-- descriptor table in memory.
function PatchLoader.load(modulePath)
    assert(type(modulePath) == "string", "patchLoaderLoad: modulePath must be a string")
    local descriptor = require(modulePath)
    return PatchLoader.build(descriptor)
end

return PatchLoader
