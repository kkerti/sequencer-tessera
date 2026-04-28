local Utils, Step, Pattern, Track, Engine

Utils = (function()

local Utils = {}

local NOTE_NAMES = {
    "C", "C#", "D", "Eb", "E", "F", "F#", "G", "G#", "A", "Bb", "B"
}

function Utils.tableNew(n, default)
    local t = {}
    for i = 1, n do
        t[i] = default
    end
    return t
end

function Utils.tableCopy(t)
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = v
    end
    return copy
end

function Utils.clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

function Utils.pitchToName(midiNote)

    local noteIndex = (midiNote % 12) + 1
    local octave = math.floor(midiNote / 12) - 1
    return NOTE_NAMES[noteIndex] .. tostring(octave)
end

    return Utils
end)()

Step = (function()

local Step         = {}

local I_PITCH    = 1
local I_VEL      = 2
local I_DUR      = 3
local I_GATE     = 4
local I_RATCH    = 5
local I_PROB     = 6
local I_ACTIVE   = 7

local PITCH_MIN    = 0
local PITCH_MAX    = 127
local VELOCITY_MIN = 0
local VELOCITY_MAX = 127
local DURATION_MIN = 0
local DURATION_MAX = 99
local GATE_MIN     = 0
local GATE_MAX     = 99
local PROB_MIN     = 0
local PROB_MAX     = 100

function Step.new(pitch, velocity, duration, gate, ratch, probability)
    pitch       = pitch or 60
    velocity    = velocity or 100
    duration    = duration or 4
    gate        = gate or 2
    if ratch == nil then ratch = false end
    probability = probability or 100

    return { pitch, velocity, duration, gate, ratch, probability, true }
end

function Step.getPitch(step)       return step[I_PITCH] end
function Step.setPitch(step, value)
    step[I_PITCH] = value
end

function Step.getVelocity(step)    return step[I_VEL] end
function Step.setVelocity(step, value)
    step[I_VEL] = value
end

function Step.getDuration(step)    return step[I_DUR] end
function Step.setDuration(step, value)
    step[I_DUR] = value
end

function Step.getGate(step)        return step[I_GATE] end
function Step.setGate(step, value)
    step[I_GATE] = value
end

function Step.getRatch(step)       return step[I_RATCH] end
function Step.setRatch(step, value)
    step[I_RATCH] = value
end

function Step.getProbability(step) return step[I_PROB] end
function Step.setProbability(step, value)
    step[I_PROB] = value
end

function Step.getActive(step)      return step[I_ACTIVE] end
function Step.setActive(step, value)
    step[I_ACTIVE] = value
end

function Step.isPlayable(step)
    return step[I_ACTIVE] and step[I_DUR] > 0 and step[I_GATE] > 0
end

function Step.getPulseEvent(step, pulseCounter)

    if not Step.isPlayable(step) then
        return nil
    end

    local gate = step[I_GATE]
    local dur  = step[I_DUR]

    if not step[I_RATCH] then
        if pulseCounter == 0 then
            return "NOTE_ON"
        end
        if pulseCounter == gate then
            return "NOTE_OFF"
        end
        return nil
    end

    if pulseCounter >= dur then
        return nil
    end

    local period = gate * 2
    local phase  = pulseCounter % period
    if phase == 0 then
        return "NOTE_ON"
    end
    if phase == gate then
        return "NOTE_OFF"
    end
    return nil
end

    return Step
end)()

Pattern = (function()

local Step    = (Step)

local Pattern = {}

local NAME_MAX_LEN = 32

function Pattern.new(stepCount, name)
    stepCount = stepCount or 0
    name      = name or ""

    local steps = {}
    for i = 1, stepCount do
        steps[i] = Step.new()
    end

    return {
        steps     = steps,
        stepCount = stepCount,
        name      = name,
    }
end

function Pattern.getStepCount(pattern)
    return pattern.stepCount
end

function Pattern.getStep(pattern, index)
    return pattern.steps[index]
end

function Pattern.setStep(pattern, index, step)
    pattern.steps[index] = step
end

function Pattern.getName(pattern)
    return pattern.name
end

function Pattern.setName(pattern, name)
    pattern.name = name
end

    return Pattern
end)()

Track = (function()

local Pattern = (Pattern)
local Step    = (Step)

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

function Track.addPattern(track, stepCount)
    stepCount = stepCount or 8

    local pat = Pattern.new(stepCount)
    track.patternCount = track.patternCount + 1
    track.patterns[track.patternCount] = pat
    return pat
end

function Track.getPattern(track, patternIndex)
    return track.patterns[patternIndex]
end

function Track.getPatternCount(track)
    return track.patternCount
end

function Track.patternStartIndex(track, patternIndex)
    local offset = 0
    for i = 1, patternIndex - 1 do
        offset = offset + Pattern.getStepCount(track.patterns[i])
    end
    return offset + 1
end

function Track.patternEndIndex(track, patternIndex)
    local offset = 0
    for i = 1, patternIndex do
        offset = offset + Pattern.getStepCount(track.patterns[i])
    end
    return offset
end

function Track.getStepCount(track)
    return trackComputeStepCount(track)
end

function Track.getStep(track, index)
    local stepCount = trackComputeStepCount(track)
    return trackGetStepAtFlat(track, index)
end

function Track.setStep(track, index, step)
    local stepCount = trackComputeStepCount(track)

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

function Track.setLoopStart(track, index)
    local stepCount = trackComputeStepCount(track)
    if track.loopEnd ~= nil then
    end
    track.loopStart = index
end

function Track.setLoopEnd(track, index)
    local stepCount = trackComputeStepCount(track)
    if track.loopStart ~= nil then
    end
    track.loopEnd = index
end

function Track.clearLoopStart(track) track.loopStart = nil end
function Track.clearLoopEnd(track)   track.loopEnd   = nil end
function Track.getLoopStart(track)   return track.loopStart end
function Track.getLoopEnd(track)     return track.loopEnd end

function Track.setClockDiv(track, value)
    track.clockDiv = value
end

function Track.getClockDiv(track) return track.clockDiv end

function Track.setClockMult(track, value)
    track.clockMult = value
end

function Track.getClockMult(track) return track.clockMult end

function Track.setMidiChannel(track, channel)
    track.midiChannel = channel
end

function Track.clearMidiChannel(track) track.midiChannel = nil end
function Track.getMidiChannel(track)   return track.midiChannel end

function Track.setDirection(track, direction)
    track.direction = direction
    if direction == DIRECTION_PINGPONG then
        track.pingPongDir = 1
    end
end

function Track.getDirection(track) return track.direction end

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
end)()

Engine = (function()

local Track  = (Track)

local Engine = {}

function Engine.bpmToMs(bpm, pulsesPerBeat)
    pulsesPerBeat = pulsesPerBeat or 4
    return (60000 / bpm) / pulsesPerBeat
end

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

    return {
        bpm             = bpm,
        pulsesPerBeat   = pulsesPerBeat,
        pulseIntervalMs = Engine.bpmToMs(bpm, pulsesPerBeat),
        tracks          = engineInitTracks(trackCount, stepCount),
        trackCount      = trackCount,
    }
end

function Engine.getTrack(engine, index)
    return engine.tracks[index]
end

function Engine.advanceTrack(engine, trackIndex)
    local track = engine.tracks[trackIndex]
    local step  = Track.getCurrentStep(track)
    local event = Track.advance(track)
    return step, event
end

function Engine.onPulse(engine, pulseCount)

end

function Engine.reset(engine)
    for i = 1, engine.trackCount do
        Track.reset(engine.tracks[i])
    end
end

    return Engine
end)()

if Engine.Pattern == nil then Engine.Pattern = Pattern end
if Engine.Step == nil then Engine.Step = Step end
if Engine.Track == nil then Engine.Track = Track end
if Engine.Utils == nil then Engine.Utils = Utils end

return Engine
