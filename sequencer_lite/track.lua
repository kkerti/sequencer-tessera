-- sequencer_lite/track.lua
-- LITE BUILD: carved from sequencer/track.lua.
-- See docs/dropped-features.md for what's been removed and how to revive it.
--
-- Removed in lite:
--   - Track.copyPattern, duplicatePattern, insertPattern, deletePattern,
--     swapPatterns, pastePattern
--   - private helpers trackRemovePatternFromArray,
--     trackShiftLoopAfterDelete, trackAdjustLoopPointsAfterInsert
--
-- Kept: addPattern, getPattern(Count), patternStart/EndIndex, all step
-- access, all loop points, all clock/channel/direction setters, full
-- 5-direction-mode advance, Track.reset.

local Pattern = require("sequencer_lite/pattern")
local Step    = require("sequencer_lite/step")

local Track   = {}

local DIRECTION_FORWARD = "forward"
local DIRECTION_REVERSE = "reverse"
local DIRECTION_PINGPONG = "pingpong"
local DIRECTION_RANDOM = "random"
local DIRECTION_BROWNIAN = "brownian"

local function trackIsDirectionValid(direction)
    return direction == DIRECTION_FORWARD or
        direction == DIRECTION_REVERSE or
        direction == DIRECTION_PINGPONG or
        direction == DIRECTION_RANDOM or
        direction == DIRECTION_BROWNIAN
end

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

local function trackComputeStepCount(track)
    local total = 0
    for i = 1, track.patternCount do
        total = total + Pattern.getStepCount(track.patterns[i])
    end
    return total
end

local function trackGetStepAtFlat(track, flatIndex)
    local offset = 0
    for i = 1, track.patternCount do
        local pat      = track.patterns[i]
        local patCount = Pattern.getStepCount(pat)
        if flatIndex <= offset + patCount then
            return Pattern.getStep(pat, flatIndex - offset)
        end
        offset = offset + patCount
    end
    return nil
end

local function trackNextForward(cursor, rangeStart, rangeEnd)
    if cursor >= rangeEnd then
        return rangeStart
    end
    return cursor + 1
end

local function trackNextReverse(cursor, rangeStart, rangeEnd)
    if cursor <= rangeStart then
        return rangeEnd
    end
    return cursor - 1
end

local function trackNextRandom(rangeStart, rangeEnd)
    return math.random(rangeStart, rangeEnd)
end

local function trackNextBrownian(cursor, rangeStart, rangeEnd)
    local roll = math.random(1, 4)
    if roll == 1 then
        if cursor <= rangeStart then
            return rangeEnd
        end
        return cursor - 1
    end
    if roll == 2 then
        return cursor
    end
    if cursor >= rangeEnd then
        return rangeStart
    end
    return cursor + 1
end

local function trackNextPingPong(track, cursor, rangeStart, rangeEnd)
    if rangeStart == rangeEnd then
        return rangeStart
    end

    if track.pingPongDir > 0 then
        if cursor >= rangeEnd then
            track.pingPongDir = -1
            return cursor - 1
        end
        return cursor + 1
    end

    if cursor <= rangeStart then
        track.pingPongDir = 1
        return cursor + 1
    end
    return cursor - 1
end

local function trackResetOutOfRange(track, rangeStart, rangeEnd)
    if track.direction == DIRECTION_REVERSE then
        return rangeEnd
    end
    if track.direction == DIRECTION_RANDOM then
        return trackNextRandom(rangeStart, rangeEnd)
    end
    return rangeStart
end

local function trackDispatchDirection(track, cursor, rangeStart, rangeEnd)
    if track.direction == DIRECTION_FORWARD then
        return trackNextForward(cursor, rangeStart, rangeEnd)
    end
    if track.direction == DIRECTION_REVERSE then
        return trackNextReverse(cursor, rangeStart, rangeEnd)
    end
    if track.direction == DIRECTION_RANDOM then
        return trackNextRandom(rangeStart, rangeEnd)
    end
    if track.direction == DIRECTION_BROWNIAN then
        return trackNextBrownian(cursor, rangeStart, rangeEnd)
    end
    return trackNextPingPong(track, cursor, rangeStart, rangeEnd)
end

local function trackGetNextCursor(track, cursor)
    local stepCount = trackComputeStepCount(track)
    if stepCount == 0 then
        return 1
    end

    local rangeStart = track.loopStart or 1
    local rangeEnd = track.loopEnd or stepCount

    if cursor < rangeStart or cursor > rangeEnd then
        return trackResetOutOfRange(track, rangeStart, rangeEnd)
    end

    return trackDispatchDirection(track, cursor, rangeStart, rangeEnd)
end

-- ---------------------------------------------------------------------------
-- Constructor
-- ---------------------------------------------------------------------------

function Track.new()
    return {
        patterns     = {},
        patternCount = 0,
        cursor       = 1,
        pulseCounter = 0,
        loopStart    = nil,
        loopEnd      = nil,
        clockDiv     = 1,
        clockMult    = 1,
        clockAccum   = 0,
        direction    = DIRECTION_FORWARD,
        pingPongDir  = 1,
        midiChannel  = nil,
    }
end

-- ---------------------------------------------------------------------------
-- Pattern management (lite: append-only)
-- ---------------------------------------------------------------------------

function Track.addPattern(track, stepCount)
    stepCount = stepCount or 8
    assert(type(stepCount) == "number" and stepCount >= 0 and math.floor(stepCount) == stepCount,
        "trackAddPattern: stepCount must be a non-negative integer")

    local pat = Pattern.new(stepCount)
    track.patternCount = track.patternCount + 1
    track.patterns[track.patternCount] = pat
    return pat
end

function Track.getPattern(track, patternIndex)
    assert(type(patternIndex) == "number" and patternIndex >= 1 and patternIndex <= track.patternCount,
        "trackGetPattern: patternIndex out of range 1-" .. track.patternCount)
    return track.patterns[patternIndex]
end

function Track.getPatternCount(track)
    return track.patternCount
end

function Track.patternStartIndex(track, patternIndex)
    assert(type(patternIndex) == "number" and patternIndex >= 1 and patternIndex <= track.patternCount,
        "trackPatternStartIndex: patternIndex out of range 1-" .. track.patternCount)
    local offset = 0
    for i = 1, patternIndex - 1 do
        offset = offset + Pattern.getStepCount(track.patterns[i])
    end
    return offset + 1
end

function Track.patternEndIndex(track, patternIndex)
    assert(type(patternIndex) == "number" and patternIndex >= 1 and patternIndex <= track.patternCount,
        "trackPatternEndIndex: patternIndex out of range 1-" .. track.patternCount)
    local offset = 0
    for i = 1, patternIndex do
        offset = offset + Pattern.getStepCount(track.patterns[i])
    end
    return offset
end

-- NOTE: copyPattern, duplicatePattern, insertPattern, deletePattern,
-- swapPatterns, pastePattern are intentionally absent.
-- See docs/dropped-features.md tier 2.

-- ---------------------------------------------------------------------------
-- Step access (flat index API)
-- ---------------------------------------------------------------------------

function Track.getStepCount(track)
    return trackComputeStepCount(track)
end

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
    assert(type(step) == "table", "trackSetStep: step must be a table")

    local offset = 0
    for i = 1, track.patternCount do
        local pat      = track.patterns[i]
        local patCount = Pattern.getStepCount(pat)
        if index <= offset + patCount then
            Pattern.setStep(pat, index - offset, step)
            return
        end
        offset = offset + patCount
    end
end

function Track.getCurrentStep(track)
    return trackGetStepAtFlat(track, track.cursor)
end

-- ---------------------------------------------------------------------------
-- Loop points
-- ---------------------------------------------------------------------------

function Track.setLoopStart(track, index)
    local stepCount = trackComputeStepCount(track)
    assert(type(index) == "number" and index >= 1 and index <= stepCount,
        "trackSetLoopStart: index out of range 1-" .. stepCount)
    if track.loopEnd ~= nil then
        assert(index <= track.loopEnd, "trackSetLoopStart: loopStart must be <= loopEnd")
    end
    track.loopStart = index
end

function Track.setLoopEnd(track, index)
    local stepCount = trackComputeStepCount(track)
    assert(type(index) == "number" and index >= 1 and index <= stepCount,
        "trackSetLoopEnd: index out of range 1-" .. stepCount)
    if track.loopStart ~= nil then
        assert(track.loopStart <= index, "trackSetLoopEnd: loopEnd must be >= loopStart")
    end
    track.loopEnd = index
end

function Track.clearLoopStart(track) track.loopStart = nil end
function Track.clearLoopEnd(track)   track.loopEnd   = nil end
function Track.getLoopStart(track)   return track.loopStart end
function Track.getLoopEnd(track)     return track.loopEnd end

-- ---------------------------------------------------------------------------
-- Clock / channel / direction
-- ---------------------------------------------------------------------------

function Track.setClockDiv(track, value)
    assert(type(value) == "number" and value >= 1 and value <= 99,
        "trackSetClockDiv: value out of range 1-99")
    track.clockDiv = value
end

function Track.getClockDiv(track) return track.clockDiv end

function Track.setClockMult(track, value)
    assert(type(value) == "number" and value >= 1 and value <= 99,
        "trackSetClockMult: value out of range 1-99")
    track.clockMult = value
end

function Track.getClockMult(track) return track.clockMult end

function Track.setMidiChannel(track, channel)
    assert(type(channel) == "number" and channel >= 1 and channel <= 16,
        "trackSetMidiChannel: channel out of range 1-16")
    track.midiChannel = channel
end

function Track.clearMidiChannel(track) track.midiChannel = nil end
function Track.getMidiChannel(track)   return track.midiChannel end

function Track.setDirection(track, direction)
    assert(type(direction) == "string" and trackIsDirectionValid(direction),
        "trackSetDirection: direction must be forward|reverse|pingpong|random|brownian")
    track.direction = direction
    if direction == DIRECTION_PINGPONG then
        track.pingPongDir = 1
    end
end

function Track.getDirection(track) return track.direction end

-- ---------------------------------------------------------------------------
-- Playback
-- ---------------------------------------------------------------------------

local function trackSkipZeroDuration(track, stepCount)
    local step = trackGetStepAtFlat(track, track.cursor)
    local skipGuard = 0
    while step ~= nil and Step.getDuration(step) == 0 do
        track.cursor       = trackGetNextCursor(track, track.cursor)
        track.pulseCounter = 0
        step               = trackGetStepAtFlat(track, track.cursor)
        skipGuard = skipGuard + 1
        if skipGuard > stepCount then
            return nil
        end
    end
    return step
end

function Track.advance(track)
    local stepCount = trackComputeStepCount(track)
    if stepCount == 0 then
        return nil
    end

    local step = trackSkipZeroDuration(track, stepCount)

    if step == nil then
        return nil
    end

    local event = Step.getPulseEvent(step, track.pulseCounter)

    track.pulseCounter = track.pulseCounter + 1

    if track.pulseCounter >= Step.getDuration(step) then
        track.pulseCounter = 0
        track.cursor       = trackGetNextCursor(track, track.cursor)
    end

    return event
end

function Track.reset(track)
    track.cursor       = 1
    track.pulseCounter = 0
    track.clockAccum   = 0
    track.pingPongDir  = 1
end

return Track
