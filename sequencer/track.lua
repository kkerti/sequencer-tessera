-- sequencer/track.lua
-- A Track owns an ordered list of Patterns, each of which owns an ordered
-- list of Steps. Playback uses a single flat cursor (1-based absolute step
-- index across all patterns) so loop points remain simple integers.
--
-- Pattern layer is purely organisational (ER-101 model):
--   - Patterns play sequentially; there is no pattern arranger.
--   - Loop points are flat step indices; RESET always goes to step 1.
--   - Clock div/mult accumulator lives here; consumed by Engine.tick.

local Pattern = require("sequencer/pattern")
local Step    = require("sequencer/step")

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

-- Returns the total number of steps across all patterns.
local function trackComputeStepCount(track)
    local total = 0
    for i = 1, track.patternCount do
        total = total + Pattern.getStepCount(track.patterns[i])
    end
    return total
end

-- Returns the Step at the given flat 1-based index, or nil if out of range.
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

-- Advances the flat cursor by one step, respecting loop points.
local function trackGetNextCursor(track, cursor)
    local stepCount = trackComputeStepCount(track)
    if stepCount == 0 then
        return 1
    end

    local rangeStart = 1
    local rangeEnd = stepCount
    if track.loopStart ~= nil then
        rangeStart = track.loopStart
    end
    if track.loopEnd ~= nil then
        rangeEnd = track.loopEnd
    end

    if cursor < rangeStart or cursor > rangeEnd then
        if track.direction == DIRECTION_REVERSE then
            return rangeEnd
        end
        if track.direction == DIRECTION_RANDOM then
            return math.random(rangeStart, rangeEnd)
        end
        return rangeStart
    end

    if track.direction == DIRECTION_FORWARD then
        if cursor >= rangeEnd then
            return rangeStart
        end
        return cursor + 1
    end

    if track.direction == DIRECTION_REVERSE then
        if cursor <= rangeStart then
            return rangeEnd
        end
        return cursor - 1
    end

    if track.direction == DIRECTION_RANDOM then
        return math.random(rangeStart, rangeEnd)
    end

    if track.direction == DIRECTION_BROWNIAN then
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

-- ---------------------------------------------------------------------------
-- Constructor
-- ---------------------------------------------------------------------------

-- Creates a new Track with zero patterns and zero steps.
-- Patterns are added after construction via Track.addPattern.
function Track.new()
    return {
        patterns     = {},
        patternCount = 0,
        cursor       = 1,  -- flat 1-based step index
        pulseCounter = 0,  -- pulses elapsed within the current step
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
-- Pattern management
-- ---------------------------------------------------------------------------

-- Appends a new Pattern with `stepCount` default steps and returns it.
-- stepCount defaults to 8.
function Track.addPattern(track, stepCount)
    stepCount = stepCount or 8
    assert(type(stepCount) == "number" and stepCount >= 0 and math.floor(stepCount) == stepCount,
        "trackAddPattern: stepCount must be a non-negative integer")

    local pat = Pattern.new(stepCount)
    track.patternCount = track.patternCount + 1
    track.patterns[track.patternCount] = pat
    return pat
end

-- Returns the Pattern at 1-based patternIndex, or nil.
function Track.getPattern(track, patternIndex)
    assert(type(patternIndex) == "number" and patternIndex >= 1 and patternIndex <= track.patternCount,
        "trackGetPattern: patternIndex out of range 1-" .. track.patternCount)
    return track.patterns[patternIndex]
end

-- Returns the number of patterns on this track.
function Track.getPatternCount(track)
    return track.patternCount
end

-- Returns the flat step index of the first step of a pattern (1-based).
-- Useful for setting loop points at pattern boundaries.
function Track.patternStartIndex(track, patternIndex)
    assert(type(patternIndex) == "number" and patternIndex >= 1 and patternIndex <= track.patternCount,
        "trackPatternStartIndex: patternIndex out of range 1-" .. track.patternCount)
    local offset = 0
    for i = 1, patternIndex - 1 do
        offset = offset + Pattern.getStepCount(track.patterns[i])
    end
    return offset + 1
end

-- Returns the flat step index of the last step of a pattern (1-based).
-- Useful for setting loop points at pattern boundaries.
function Track.patternEndIndex(track, patternIndex)
    assert(type(patternIndex) == "number" and patternIndex >= 1 and patternIndex <= track.patternCount,
        "trackPatternEndIndex: patternIndex out of range 1-" .. track.patternCount)
    local offset = 0
    for i = 1, patternIndex do
        offset = offset + Pattern.getStepCount(track.patterns[i])
    end
    return offset
end

-- ---------------------------------------------------------------------------
-- Step access (flat index API — used by engine and tests)
-- ---------------------------------------------------------------------------

-- Returns the total step count across all patterns (computed on demand).
function Track.getStepCount(track)
    return trackComputeStepCount(track)
end

-- Returns the Step at flat 1-based index.
function Track.getStep(track, index)
    local stepCount = trackComputeStepCount(track)
    assert(type(index) == "number" and index >= 1 and index <= stepCount,
        "trackGetStep: index out of range 1-" .. stepCount)
    return trackGetStepAtFlat(track, index)
end

-- Replaces the Step at flat 1-based index.
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

-- Returns the Step at the current play cursor.
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

function Track.clearLoopStart(track)
    track.loopStart = nil
end

function Track.clearLoopEnd(track)
    track.loopEnd = nil
end

function Track.getLoopStart(track)
    return track.loopStart
end

function Track.getLoopEnd(track)
    return track.loopEnd
end

-- ---------------------------------------------------------------------------
-- Clock
-- ---------------------------------------------------------------------------

function Track.setClockDiv(track, value)
    assert(type(value) == "number" and value >= 1 and value <= 99,
        "trackSetClockDiv: value out of range 1-99")
    track.clockDiv = value
end

function Track.getClockDiv(track)
    return track.clockDiv
end

function Track.setClockMult(track, value)
    assert(type(value) == "number" and value >= 1 and value <= 99,
        "trackSetClockMult: value out of range 1-99")
    track.clockMult = value
end

function Track.getClockMult(track)
    return track.clockMult
end

function Track.setMidiChannel(track, channel)
    assert(type(channel) == "number" and channel >= 1 and channel <= 16,
        "trackSetMidiChannel: channel out of range 1-16")
    track.midiChannel = channel
end

function Track.clearMidiChannel(track)
    track.midiChannel = nil
end

function Track.getMidiChannel(track)
    return track.midiChannel
end

function Track.setDirection(track, direction)
    assert(type(direction) == "string" and trackIsDirectionValid(direction),
        "trackSetDirection: direction must be forward|reverse|pingpong|random|brownian")
    track.direction = direction
    if direction == DIRECTION_PINGPONG then
        track.pingPongDir = 1
    end
end

function Track.getDirection(track)
    return track.direction
end

-- ---------------------------------------------------------------------------
-- Playback
-- ---------------------------------------------------------------------------

-- Advances the track by one clock pulse.
-- Returns "NOTE_ON", "NOTE_OFF", or nil.
-- Returns nil immediately if the track has no steps.
function Track.advance(track)
    local stepCount = trackComputeStepCount(track)
    if stepCount == 0 then
        return nil
    end

    local step      = trackGetStepAtFlat(track, track.cursor)
    local skipGuard = 0

    -- Skip steps with zero duration entirely.
    while step ~= nil and step.duration == 0 do
        track.cursor       = trackGetNextCursor(track, track.cursor)
        track.pulseCounter = 0
        step               = trackGetStepAtFlat(track, track.cursor)

        skipGuard = skipGuard + 1
        if skipGuard > stepCount then
            return nil
        end
    end

    if step == nil then
        return nil
    end

    local event = Step.getPulseEvent(step, track.pulseCounter)

    track.pulseCounter = track.pulseCounter + 1

    -- Step duration elapsed: move to next step (respecting loop points).
    if track.pulseCounter >= step.duration then
        track.pulseCounter = 0
        track.cursor       = trackGetNextCursor(track, track.cursor)
    end

    return event
end

-- Resets the play cursor to step 1 of pattern 1 (flat index 1).
-- Ignores loop points — matches ER-101 RESET behaviour.
function Track.reset(track)
    track.cursor       = 1
    track.pulseCounter = 0
    track.clockAccum   = 0
    track.pingPongDir  = 1
end

return Track
