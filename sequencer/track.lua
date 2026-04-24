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

-- Direction handler: forward mode.
local function trackNextForward(cursor, rangeStart, rangeEnd)
    if cursor >= rangeEnd then
        return rangeStart
    end
    return cursor + 1
end

-- Direction handler: reverse mode.
local function trackNextReverse(cursor, rangeStart, rangeEnd)
    if cursor <= rangeStart then
        return rangeEnd
    end
    return cursor - 1
end

-- Direction handler: random mode.
local function trackNextRandom(rangeStart, rangeEnd)
    return math.random(rangeStart, rangeEnd)
end

-- Direction handler: brownian mode (75% forward, 25% backward or hold).
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

-- Direction handler: ping-pong mode.
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

-- Resolves the cursor when it's outside the current loop range.
-- Returns the appropriate reset position based on direction.
local function trackResetOutOfRange(track, rangeStart, rangeEnd)
    if track.direction == DIRECTION_REVERSE then
        return rangeEnd
    end
    if track.direction == DIRECTION_RANDOM then
        return trackNextRandom(rangeStart, rangeEnd)
    end
    return rangeStart
end

-- Dispatches to the appropriate direction handler for in-range cursors.
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

-- Advances the flat cursor by one step, respecting loop points.
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

-- Copies all steps from pattern at `srcIndex` into a new pattern appended
-- to the track. Returns the new pattern. Step data is deep-copied so edits
-- to the copy do not affect the source.
function Track.copyPattern(track, srcIndex)
    assert(type(srcIndex) == "number" and srcIndex >= 1 and srcIndex <= track.patternCount,
        "trackCopyPattern: srcIndex out of range 1-" .. track.patternCount)

    local Utils  = require("utils")
    local src    = track.patterns[srcIndex]
    local count  = Pattern.getStepCount(src)
    local newPat = Pattern.new(0, Pattern.getName(src))

    newPat.steps     = {}
    newPat.stepCount = count
    for i = 1, count do
        newPat.steps[i] = Utils.tableCopy(src.steps[i])
    end

    track.patternCount = track.patternCount + 1
    track.patterns[track.patternCount] = newPat
    return newPat
end

-- Copies all steps from pattern at `srcIndex` and inserts the new pattern
-- immediately after `srcIndex`. Returns the new pattern.
function Track.duplicatePattern(track, srcIndex)
    assert(type(srcIndex) == "number" and srcIndex >= 1 and srcIndex <= track.patternCount,
        "trackDuplicatePattern: srcIndex out of range 1-" .. track.patternCount)

    local Utils  = require("utils")
    local src    = track.patterns[srcIndex]
    local count  = Pattern.getStepCount(src)
    local newPat = Pattern.new(0, Pattern.getName(src))

    newPat.steps     = {}
    newPat.stepCount = count
    for i = 1, count do
        newPat.steps[i] = Utils.tableCopy(src.steps[i])
    end

    -- Shift patterns after srcIndex forward by one slot.
    track.patternCount = track.patternCount + 1
    for i = track.patternCount, srcIndex + 2, -1 do
        track.patterns[i] = track.patterns[i - 1]
    end
    track.patterns[srcIndex + 1] = newPat
    return newPat
end

-- Removes the pattern at `patternIndex` and its steps from the track.
-- Adjusts loop points: clears any that fall inside the deleted range,
-- shifts any that fall after it. Resets cursor to 1 to avoid stale state.
-- Removes pattern at `patternIndex` from the patterns array (in place).
local function trackRemovePatternFromArray(track, patternIndex)
    for i = patternIndex, track.patternCount - 1 do
        track.patterns[i] = track.patterns[i + 1]
    end
    track.patterns[track.patternCount] = nil
    track.patternCount = track.patternCount - 1
end

-- Shifts a single loop endpoint after a pattern delete spanning [delStart, delEnd].
-- Returns the new value (nil if the endpoint fell inside the deleted range).
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

-- Adjusts loop points after a pattern insert at `patternIndex`.
-- Any loop point at or after the insert boundary shifts forward by `stepCount`.
local function trackAdjustLoopPointsAfterInsert(track, patternIndex, stepCount)
    if stepCount <= 0 then
        return
    end
    local insertStart = Track.patternStartIndex(track, patternIndex)
    if track.loopStart ~= nil and track.loopStart >= insertStart then
        track.loopStart = track.loopStart + stepCount
    end
    if track.loopEnd ~= nil and track.loopEnd >= insertStart then
        track.loopEnd = track.loopEnd + stepCount
    end
end

-- Inserts a new empty pattern with `stepCount` steps at `patternIndex`.
-- Existing patterns at and after that index shift forward.
-- Resets cursor to 1.
function Track.insertPattern(track, patternIndex, stepCount)
    stepCount = stepCount or 8
    assert(type(patternIndex) == "number" and patternIndex >= 1 and patternIndex <= track.patternCount + 1,
        "trackInsertPattern: patternIndex out of range 1-" .. (track.patternCount + 1))
    assert(type(stepCount) == "number" and stepCount >= 0 and math.floor(stepCount) == stepCount,
        "trackInsertPattern: stepCount must be a non-negative integer")

    local newPat = Pattern.new(stepCount)

    -- Shift patterns forward.
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

-- Swaps the positions of two patterns in the track.
-- Does not adjust loop points (they refer to flat step indices which change).
-- Resets cursor to 1.
function Track.swapPatterns(track, indexA, indexB)
    assert(type(indexA) == "number" and indexA >= 1 and indexA <= track.patternCount,
        "trackSwapPatterns: indexA out of range 1-" .. track.patternCount)
    assert(type(indexB) == "number" and indexB >= 1 and indexB <= track.patternCount,
        "trackSwapPatterns: indexB out of range 1-" .. track.patternCount)

    if indexA == indexB then return end

    track.patterns[indexA], track.patterns[indexB] = track.patterns[indexB], track.patterns[indexA]

    -- Clear loop points since flat indices are now different.
    track.loopStart    = nil
    track.loopEnd      = nil
    track.cursor       = 1
    track.pulseCounter = 0
end

-- Pastes steps from a source pattern table (e.g. from a clipboard) over
-- the pattern at `destIndex`, replacing all its steps. The source pattern
-- is deep-copied so subsequent edits are independent.
function Track.pastePattern(track, destIndex, srcPattern)
    assert(type(destIndex) == "number" and destIndex >= 1 and destIndex <= track.patternCount,
        "trackPastePattern: destIndex out of range 1-" .. track.patternCount)
    assert(type(srcPattern) == "table" and srcPattern.steps ~= nil,
        "trackPastePattern: srcPattern must be a pattern table")

    local Utils   = require("utils")
    local dest    = track.patterns[destIndex]
    local count   = srcPattern.stepCount

    -- Replace steps.
    dest.steps     = {}
    dest.stepCount = count
    for i = 1, count do
        dest.steps[i] = Utils.tableCopy(srcPattern.steps[i])
    end
    dest.name = srcPattern.name

    -- Cursor reset for safety — step count may have changed.
    track.cursor       = 1
    track.pulseCounter = 0
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

-- Skips over steps with zero duration, advancing the cursor past them.
-- Returns the step at the final cursor position, or nil if all steps
-- have zero duration (degenerate track).
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

-- Advances the track by one clock pulse.
-- Returns "NOTE_ON", "NOTE_OFF", or nil.
-- Returns nil immediately if the track has no steps.
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

    -- Step duration elapsed: move to next step (respecting loop points).
    if track.pulseCounter >= Step.getDuration(step) then
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
