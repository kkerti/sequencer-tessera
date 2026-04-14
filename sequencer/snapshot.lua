-- sequencer/snapshot.lua
-- Save/load full engine state to disk via Lua table serialization.

local Engine = require("sequencer/engine")
local Track = require("sequencer/track")
local Pattern = require("sequencer/pattern")
local Step = require("sequencer/step")

local Snapshot = {}

local function snapshotSerializeValue(value)
    local valueType = type(value)
    if valueType == "number" then
        return tostring(value)
    end
    if valueType == "boolean" then
        return value and "true" or "false"
    end
    if valueType == "string" then
        return string.format("%q", value)
    end
    if valueType == "table" then
        local parts = { "{" }
        for k, v in pairs(value) do
            local keyPart
            if type(k) == "string" then
                keyPart = "[" .. string.format("%q", k) .. "]"
            else
                keyPart = "[" .. tostring(k) .. "]"
            end
            parts[#parts + 1] = keyPart .. "=" .. snapshotSerializeValue(v) .. ","
        end
        parts[#parts + 1] = "}"
        return table.concat(parts)
    end
    error("snapshotSerializeValue: unsupported type " .. valueType)
end

-- Serializes a single step into a plain table.
local function snapshotSerializeStep(step)
    return {
        pitch = Step.getPitch(step),
        velocity = Step.getVelocity(step),
        duration = Step.getDuration(step),
        gate = Step.getGate(step),
        ratchet = Step.getRatchet(step),
        probability = Step.getProbability(step),
        active = Step.getActive(step),
    }
end

-- Serializes a single pattern into a plain table.
local function snapshotSerializePattern(pattern)
    local p = {
        name = Pattern.getName(pattern),
        steps = {},
    }
    local stepCount = Pattern.getStepCount(pattern)
    for stepIndex = 1, stepCount do
        p.steps[stepIndex] = snapshotSerializeStep(Pattern.getStep(pattern, stepIndex))
    end
    return p
end

-- Serializes a single track into a plain table.
local function snapshotSerializeTrack(engine, trackIndex)
    local track = Engine.getTrack(engine, trackIndex)
    local t = {
        clockDiv = Track.getClockDiv(track),
        clockMult = Track.getClockMult(track),
        direction = Track.getDirection(track),
        midiChannel = Track.getMidiChannel(track),
        loopStart = Track.getLoopStart(track),
        loopEnd = Track.getLoopEnd(track),
        cursor = track.cursor,
        pulseCounter = track.pulseCounter,
        patterns = {},
    }

    local patternCount = Track.getPatternCount(track)
    for patternIndex = 1, patternCount do
        t.patterns[patternIndex] = snapshotSerializePattern(Track.getPattern(track, patternIndex))
    end

    return t
end

function Snapshot.toTable(engine)
    local data = {
        bpm = engine.bpm,
        pulsesPerBeat = engine.pulsesPerBeat,
        pulseCount = engine.pulseCount,
        swingPercent = engine.swingPercent,
        scaleName = engine.scaleName,
        rootNote = engine.rootNote,
        tracks = {},
    }

    for trackIndex = 1, engine.trackCount do
        data.tracks[trackIndex] = snapshotSerializeTrack(engine, trackIndex)
    end

    return data
end

-- Restores a single pattern's steps onto a track from serialized data.
local function snapshotRestorePattern(track, patternIndex, patternData)
    local pattern = Track.addPattern(track, #patternData.steps)
    if patternData.name ~= nil then
        Pattern.setName(pattern, patternData.name)
    end

    local startFlat = Track.patternStartIndex(track, patternIndex)
    for stepIndex = 1, #patternData.steps do
        local stepData = patternData.steps[stepIndex]
        local step = Step.new(
            stepData.pitch,
            stepData.velocity,
            stepData.duration,
            stepData.gate,
            stepData.ratchet or 1,
            stepData.probability or 100
        )
        Step.setActive(step, stepData.active ~= false)
        Track.setStep(track, startFlat + stepIndex - 1, step)
    end
end

-- Restores loop points and cursor state for a track from serialized data.
local function snapshotRestoreTrackState(track, trackData)
    if trackData.loopStart ~= nil then
        Track.setLoopStart(track, trackData.loopStart)
    end
    if trackData.loopEnd ~= nil then
        Track.setLoopEnd(track, trackData.loopEnd)
    end
    if trackData.cursor ~= nil then
        track.cursor = trackData.cursor
    end
    if trackData.pulseCounter ~= nil then
        track.pulseCounter = trackData.pulseCounter
    end
end

-- Restores a single track from serialized data.
local function snapshotRestoreTrack(engine, trackIndex, trackData)
    local track = Engine.getTrack(engine, trackIndex)

    Track.setClockDiv(track, trackData.clockDiv)
    Track.setClockMult(track, trackData.clockMult)
    Track.setDirection(track, trackData.direction or "forward")
    if trackData.midiChannel ~= nil then
        Track.setMidiChannel(track, trackData.midiChannel)
    end

    for patternIndex = 1, #trackData.patterns do
        snapshotRestorePattern(track, patternIndex, trackData.patterns[patternIndex])
    end

    snapshotRestoreTrackState(track, trackData)
end

function Snapshot.fromTable(data)
    local trackCount = #data.tracks
    local engine = Engine.new(data.bpm, data.pulsesPerBeat, trackCount, 0)

    if data.swingPercent ~= nil then
        Engine.setSwing(engine, data.swingPercent)
    end
    if data.scaleName ~= nil then
        Engine.setScale(engine, data.scaleName, data.rootNote or 0)
    end
    engine.pulseCount = data.pulseCount or 0

    for trackIndex = 1, trackCount do
        snapshotRestoreTrack(engine, trackIndex, data.tracks[trackIndex])
    end

    return engine
end

function Snapshot.saveToFile(engine, filePath)
    assert(type(filePath) == "string" and filePath ~= "", "snapshotSaveToFile: filePath must be a non-empty string")
    local data = Snapshot.toTable(engine)
    local content = "return " .. snapshotSerializeValue(data)
    local file = assert(io.open(filePath, "w"))
    file:write(content)
    file:close()
end

function Snapshot.loadFromFile(filePath)
    assert(type(filePath) == "string" and filePath ~= "", "snapshotLoadFromFile: filePath must be a non-empty string")
    local chunk = assert(loadfile(filePath))
    local data = chunk()
    return Snapshot.fromTable(data)
end

return Snapshot
