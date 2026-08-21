-- sequencer.lua
-- ER-101 / Metropolis-style step sequencer engine + driver.
--
-- One file. Loaded identically on macOS (host harness, tests) and on the
-- Grid module's Lua VM (as /sequencer.lua). Returns a single table with
-- every public class as a field:
--
--   local Seq = require("sequencer")
--   Seq.Step, Seq.Pattern, Seq.Track, Seq.Engine, Seq.Scene,
--   Seq.MidiTranslate, Seq.PatchLoader, Seq.Driver, Seq.Utils
--
-- This file holds ONLY what runs on the device at playback time:
--   * Step pack/sample (no getters/setters)
--   * Pattern construction + setStep/setName (PatchLoader)
--   * Track construction, addPattern, setters used by PatchLoader and Scene,
--     sample/advance/reset (per pulse)
--   * Scene tick + applyToTracks (per pulse, optional)
--   * Engine new + per-track sample/advance + per-pulse onPulse + reset
--   * MidiTranslate, PatchLoader, Driver
--
-- All authoring / editor / read-accessor / scene-construction methods live
-- in `authoring.lua`, which extends these tables in place when required.
-- The device never loads authoring; the host always does.
--
-- Hierarchy: Snapshot → Track → Pattern → Step (ER-101 model).
--   * Pattern is a named contiguous slice of a Track's flat step list.
--   * Loop points are per-track flat step indices.
--   * Per-track clock div/mult applied by the Driver.
--   * Per-step ratchet is boolean (ER-101); period = 2 × gate pulses.
--   * Direction modes: forward / reverse / pingpong / random / brownian.
--   * Per-step probability (Blackbox-style; rolled once per cursor entry).
--
-- Pitch is raw MIDI; scale quantization and swing are out of scope.
-- See AGENTS.md and docs/ARCHITECTURE.md for project context.

local floor = math.floor

-- ===========================================================================
-- Utils  (placeholder; populated by authoring.lua on the host)
-- ===========================================================================

local Utils = {}

-- ===========================================================================
-- Step  (packed 64-bit integer; see bit layout below)
-- ===========================================================================
--
-- Bit layout (LSB-first):
--   bits  0- 6  pitch       (7)
--   bits  7-13  velocity    (7)
--   bits 14-20  duration    (7)
--   bits 21-27  gate        (7)
--   bits 28-34  probability (7)
--   bit  35     ratch       (1)
--   bit  36     active      (1)
--
-- Arithmetic (not bitwise) so the source survives LuaSrcDiet (Lua 5.1 era).
-- The on-device VM (Lua 5.4) executes either form fine.
--
-- API contract: setters (in authoring.lua) return a NEW packed integer. Lua
-- passes integers by value, so in-place mutation is impossible. The engine
-- itself only reads via inlined arithmetic in Track.sample / Track.advance.
--
-- ---------------------------------------------------------------------------

local Step = {}

local P_PITCH = 1                  -- 2^0
local P_VEL   = 128                -- 2^7
local P_DUR   = 16384              -- 2^14
local P_GATE  = 2097152            -- 2^21
local P_PROB  = 268435456          -- 2^28
local P_RATCH = 34359738368        -- 2^35
local P_ACT   = 68719476736        -- 2^36

function Step.new(pitch, velocity, duration, gate, ratch, probability)
    pitch       = pitch or 60
    velocity    = velocity or 100
    duration    = duration or 4
    gate        = gate or 2
    if ratch == nil then ratch = false end
    probability = probability or 100

    assert(type(pitch) == "number" and pitch >= 0 and pitch <= 127,
        "stepNew: pitch out of range 0-127")
    assert(type(velocity) == "number" and velocity >= 0 and velocity <= 127,
        "stepNew: velocity out of range 0-127")
    assert(type(duration) == "number" and duration >= 0 and duration <= 99,
        "stepNew: duration out of range 0-99")
    assert(type(gate) == "number" and gate >= 0 and gate <= 99,
        "stepNew: gate out of range 0-99")
    assert(type(ratch) == "boolean", "stepNew: ratch must be boolean")
    assert(type(probability) == "number" and probability >= 0 and probability <= 100,
        "stepNew: probability out of range 0-100")

    local s = pitch * P_PITCH
            + velocity * P_VEL
            + duration * P_DUR
            + gate * P_GATE
            + probability * P_PROB
            + P_ACT
    if ratch then s = s + P_RATCH end
    return s
end

function Step.sampleCv(step)
    return floor(step / P_PITCH) % 128, floor(step / P_VEL) % 128
end

-- Returns gate level (boolean) at `pulseCounter` pulses into the step.
-- Rules: inactive→low, dur=0→low, gate=0→low, gate>=dur→high (legato),
-- ratch=false→high on [0,gate), ratch=true→period 2*gate, suppressed
-- once pulseCounter >= dur.
function Step.sampleGate(step, pulseCounter)
    assert(type(pulseCounter) == "number" and pulseCounter >= 0,
        "stepSampleGate: pulseCounter must be >= 0")
    if floor(step / P_ACT) % 2 == 0 then return false end
    local dur  = floor(step / P_DUR)  % 128
    if dur == 0 then return false end
    local gate = floor(step / P_GATE) % 128
    if gate == 0 then return false end
    if gate >= dur then return true end
    if floor(step / P_RATCH) % 2 == 0 then
        return pulseCounter < gate
    end
    if pulseCounter >= dur then return false end
    return (pulseCounter % (gate * 2)) < gate
end

-- ===========================================================================
-- Pattern  (named contiguous slice of a track's flat step list)
-- ===========================================================================

local Pattern = {}

local PATTERN_NAME_MAX = 32

function Pattern.new(stepCount, name)
    stepCount = stepCount or 0
    name      = name or ""
    assert(type(stepCount) == "number" and stepCount >= 0 and floor(stepCount) == stepCount,
        "patternNew: stepCount must be a non-negative integer")
    assert(type(name) == "string" and #name <= PATTERN_NAME_MAX,
        "patternNew: name must be a string of max " .. PATTERN_NAME_MAX .. " chars")
    local steps = {}
    for i = 1, stepCount do steps[i] = Step.new() end
    return { steps = steps, stepCount = stepCount, name = name }
end

function Pattern.setStep(pattern, index, step)
    assert(type(index) == "number" and index >= 1 and index <= pattern.stepCount,
        "patternSetStep: index out of range 1-" .. pattern.stepCount)
    assert(type(step) == "number", "patternSetStep: step must be a packed integer")
    pattern.steps[index] = step
end

function Pattern.setName(pattern, name)
    assert(type(name) == "string" and #name <= PATTERN_NAME_MAX,
        "patternSetName: name must be a string of max " .. PATTERN_NAME_MAX .. " chars")
    pattern.name = name
end

-- ===========================================================================
-- Track  (owns Patterns, flat cursor, loop points, direction, clock state)
-- ===========================================================================
--
-- Per pulse the engine performs:
--      Track.sample(t) → cvA, cvB, gate
--      Track.advance(t)
-- SAMPLE first (read present), then ADVANCE (move time forward by one pulse).
-- Probability is rolled once per cursor entry (Blackbox-style).
--
-- ---------------------------------------------------------------------------

local Track = {}

local DIR_FORWARD  = "forward"
local DIR_REVERSE  = "reverse"
local DIR_PINGPONG = "pingpong"
local DIR_RANDOM   = "random"
local DIR_BROWNIAN = "brownian"

local function trackIsDirectionValid(d)
    return d == DIR_FORWARD or d == DIR_REVERSE or d == DIR_PINGPONG
        or d == DIR_RANDOM  or d == DIR_BROWNIAN
end

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

-- Direction handlers ---------------------------------------------------------

local function trackNextForward(cursor, lo, hi)
    if cursor >= hi then return lo end
    return cursor + 1
end

local function trackNextReverse(cursor, lo, hi)
    if cursor <= lo then return hi end
    return cursor - 1
end

local function trackNextRandom(lo, hi) return math.random(lo, hi) end

local function trackNextBrownian(cursor, lo, hi)
    local roll = math.random(1, 4)
    if roll == 1 then
        if cursor <= lo then return hi end
        return cursor - 1
    end
    if roll == 2 then return cursor end
    if cursor >= hi then return lo end
    return cursor + 1
end

local function trackNextPingPong(track, cursor, lo, hi)
    if lo == hi then return lo end
    if track.pingPongDir > 0 then
        if cursor >= hi then track.pingPongDir = -1; return cursor - 1 end
        return cursor + 1
    end
    if cursor <= lo then track.pingPongDir = 1; return cursor + 1 end
    return cursor - 1
end

local function trackResetOutOfRange(track, lo, hi)
    if track.direction == DIR_REVERSE then return hi end
    if track.direction == DIR_RANDOM  then return trackNextRandom(lo, hi) end
    return lo
end

local function trackDispatchDirection(track, cursor, lo, hi)
    local d = track.direction
    if d == DIR_FORWARD  then return trackNextForward(cursor, lo, hi) end
    if d == DIR_REVERSE  then return trackNextReverse(cursor, lo, hi) end
    if d == DIR_RANDOM   then return trackNextRandom(lo, hi) end
    if d == DIR_BROWNIAN then return trackNextBrownian(cursor, lo, hi) end
    return trackNextPingPong(track, cursor, lo, hi)
end

local function trackGetNextCursor(track, cursor)
    local stepCount = trackComputeStepCount(track)
    if stepCount == 0 then return 1 end
    local lo = track.loopStart or 1
    local hi = track.loopEnd   or stepCount
    if cursor < lo or cursor > hi then
        return trackResetOutOfRange(track, lo, hi)
    end
    return trackDispatchDirection(track, cursor, lo, hi)
end

-- Constructor ----------------------------------------------------------------

function Track.new()
    return {
        patterns               = {},
        patternCount           = 0,
        cursor                 = 1,
        pulseCounter           = 0,
        loopStart              = nil,
        loopEnd                = nil,
        clockDiv               = 1,
        clockMult              = 1,
        clockAccum             = 0,
        direction              = DIR_FORWARD,
        pingPongDir            = 1,
        midiChannel            = nil,
        currentStepGateEnabled = true,
    }
end

function Track.addPattern(track, stepCount)
    stepCount = stepCount or 8
    assert(type(stepCount) == "number" and stepCount >= 0 and floor(stepCount) == stepCount,
        "trackAddPattern: stepCount must be a non-negative integer")
    local pat = Pattern.new(stepCount)
    track.patternCount = track.patternCount + 1
    track.patterns[track.patternCount] = pat
    return pat
end

-- Loop points ----------------------------------------------------------------

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

-- Clock / channel / direction setters ---------------------------------------

function Track.setClockDiv(track, value)
    assert(type(value) == "number" and value >= 1 and value <= 99,
        "trackSetClockDiv: value out of range 1-99")
    track.clockDiv = value
end

function Track.setClockMult(track, value)
    assert(type(value) == "number" and value >= 1 and value <= 99,
        "trackSetClockMult: value out of range 1-99")
    track.clockMult = value
end

function Track.setMidiChannel(track, channel)
    assert(type(channel) == "number" and channel >= 1 and channel <= 16,
        "trackSetMidiChannel: channel out of range 1-16")
    track.midiChannel = channel
end

function Track.clearMidiChannel(track) track.midiChannel = nil end

function Track.setDirection(track, direction)
    assert(type(direction) == "string" and trackIsDirectionValid(direction),
        "trackSetDirection: direction must be forward|reverse|pingpong|random|brownian")
    track.direction = direction
    if direction == DIR_PINGPONG then track.pingPongDir = 1 end
end

-- Playback (sampled-state) ---------------------------------------------------

local function trackRollEntryProbability(track, step)
    if step == nil then track.currentStepGateEnabled = false; return end
    local prob = floor(step / P_PROB) % 128
    if prob >= 100 then
        track.currentStepGateEnabled = true
    elseif prob <= 0 then
        track.currentStepGateEnabled = false
    else
        track.currentStepGateEnabled = math.random(1, 100) <= prob
    end
end

local function trackSkipZeroDuration(track, stepCount)
    local startCursor = track.cursor
    local step = trackGetStepAtFlat(track, track.cursor)
    local skipGuard = 0
    while step ~= nil and (floor(step / P_DUR) % 128) == 0 do
        track.cursor       = trackGetNextCursor(track, track.cursor)
        track.pulseCounter = 0
        step               = trackGetStepAtFlat(track, track.cursor)
        skipGuard = skipGuard + 1
        if skipGuard > stepCount then return nil end
    end
    if track.cursor ~= startCursor then trackRollEntryProbability(track, step) end
    return step
end

function Track.sample(track)
    local stepCount = trackComputeStepCount(track)
    if stepCount == 0 then return 0, 0, false end
    local step = trackSkipZeroDuration(track, stepCount)
    if step == nil then return 0, 0, false end
    local cvA, cvB = Step.sampleCv(step)
    local gate     = Step.sampleGate(step, track.pulseCounter)
                     and track.currentStepGateEnabled
    return cvA, cvB, gate
end

function Track.advance(track)
    local stepCount = trackComputeStepCount(track)
    if stepCount == 0 then return end
    local step = trackSkipZeroDuration(track, stepCount)
    if step == nil then return end
    track.pulseCounter = track.pulseCounter + 1
    if track.pulseCounter >= (floor(step / P_DUR) % 128) then
        track.pulseCounter = 0
        track.cursor       = trackGetNextCursor(track, track.cursor)
        trackRollEntryProbability(track, trackGetStepAtFlat(track, track.cursor))
    end
end

function Track.reset(track)
    track.cursor       = 1
    track.pulseCounter = 0
    track.clockAccum   = 0
    track.pingPongDir  = 1
    trackRollEntryProbability(track, trackGetStepAtFlat(track, 1))
end

-- ===========================================================================
-- Scene  (loop-point automation; per-pulse tick + applyToTracks only)
-- ===========================================================================
--
-- Construction (Scene.new, newChain, chainAppend, ...) lives in authoring.lua.
-- The engine only needs to read an attached chain, beat it, and apply scene
-- loop overrides to tracks.

local Scene = {}

function Scene.chainGetCount(chain) return chain.sceneCount end

function Scene.chainGetCurrent(chain)
    if chain.sceneCount == 0 then return nil end
    return chain.scenes[chain.cursor]
end

function Scene.chainReset(chain)
    chain.cursor      = 1
    chain.repeatCount = 0
    chain.beatCount   = 0
end

function Scene.chainSetActive(chain, active)
    assert(type(active) == "boolean", "sceneChainSetActive: active must be boolean")
    chain.active = active
end

function Scene.chainIsActive(chain) return chain.active end

function Scene.chainCompletePass(chain)
    if chain.sceneCount == 0 then return false end
    chain.repeatCount = chain.repeatCount + 1
    local current = chain.scenes[chain.cursor]
    if chain.repeatCount >= current.repeats then
        chain.repeatCount = 0
        chain.beatCount   = 0
        if chain.cursor >= chain.sceneCount then
            chain.cursor = 1
        else
            chain.cursor = chain.cursor + 1
        end
        return true
    end
    return false
end

function Scene.chainBeat(chain)
    if chain.sceneCount == 0 then return false end
    chain.beatCount = chain.beatCount + 1
    local current = chain.scenes[chain.cursor]
    if chain.beatCount >= current.lengthBeats then
        chain.beatCount = 0
        return Scene.chainCompletePass(chain)
    end
    return false
end

function Scene.applyToTracks(scene, tracks, trackCount)
    assert(type(tracks) == "table", "sceneApplyToTracks: tracks must be a table")
    assert(type(trackCount) == "number" and trackCount >= 1,
        "sceneApplyToTracks: trackCount must be >= 1")
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

-- ===========================================================================
-- Engine  (top-level: BPM, multi-track sample/advance, scene hook)
-- ===========================================================================

local Engine = {}

function Engine.bpmToMs(bpm, pulsesPerBeat)
    pulsesPerBeat = pulsesPerBeat or 4
    assert(type(bpm) == "number" and bpm > 0, "engineBpmToMs: bpm must be positive")
    assert(type(pulsesPerBeat) == "number" and pulsesPerBeat > 0,
        "engineBpmToMs: pulsesPerBeat must be positive")
    return (60000 / bpm) / pulsesPerBeat
end

local function engineInitTracks(trackCount, stepCount)
    local tracks = {}
    for i = 1, trackCount do
        local track = Track.new()
        if stepCount > 0 then Track.addPattern(track, stepCount) end
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
        sceneChain      = nil,
    }
end

function Engine.getTrack(engine, index)
    assert(type(index) == "number" and index >= 1 and index <= engine.trackCount,
        "engineGetTrack: index out of range")
    return engine.tracks[index]
end

local function engineTickSceneChain(engine, pulseCount)
    if engine.sceneChain == nil or not Scene.chainIsActive(engine.sceneChain) then return end
    if pulseCount % engine.pulsesPerBeat ~= 0 then return end
    local advanced = Scene.chainBeat(engine.sceneChain)
    if advanced then
        local current = Scene.chainGetCurrent(engine.sceneChain)
        if current then Scene.applyToTracks(current, engine.tracks, engine.trackCount) end
    end
end

function Engine.advanceTrack(engine, trackIndex)
    assert(type(trackIndex) == "number" and trackIndex >= 1 and trackIndex <= engine.trackCount,
        "engineAdvanceTrack: trackIndex out of range")
    Track.advance(engine.tracks[trackIndex])
end

function Engine.sampleTrack(engine, trackIndex)
    assert(type(trackIndex) == "number" and trackIndex >= 1 and trackIndex <= engine.trackCount,
        "engineSampleTrack: trackIndex out of range")
    return Track.sample(engine.tracks[trackIndex])
end

function Engine.onPulse(engine, pulseCount) engineTickSceneChain(engine, pulseCount) end

function Engine.reset(engine)
    for i = 1, engine.trackCount do Track.reset(engine.tracks[i]) end
    if engine.sceneChain and Scene.chainIsActive(engine.sceneChain) then
        Scene.chainReset(engine.sceneChain)
        local current = Scene.chainGetCurrent(engine.sceneChain)
        if current then Scene.applyToTracks(current, engine.tracks, engine.trackCount) end
    end
end

-- ===========================================================================
-- MidiTranslate  (per-track edge detector: cv+gate stream → NOTE_ON / NOTE_OFF)
-- ===========================================================================
--
-- emit(kind, pitch, velocityOrNil, channel)
--   kind = "NOTE_ON" | "NOTE_OFF"; velocity is nil for NOTE_OFF.

local MidiTranslate = {}

function MidiTranslate.new()
    return { prevGate = false, lastPitch = nil }
end

function MidiTranslate.step(state, cvA, cvB, gate, channel, emit)
    local prevGate  = state.prevGate
    local lastPitch = state.lastPitch
    if gate then
        if not prevGate then
            emit("NOTE_ON", cvA, cvB, channel)
            state.lastPitch = cvA
        elseif lastPitch ~= cvA then
            emit("NOTE_OFF", lastPitch, nil, channel)
            emit("NOTE_ON",  cvA, cvB, channel)
            state.lastPitch = cvA
        end
    else
        if prevGate then
            emit("NOTE_OFF", lastPitch, nil, channel)
            state.lastPitch = nil
        end
    end
    state.prevGate = gate
end

function MidiTranslate.panic(state, channel, emit)
    if state.prevGate and state.lastPitch ~= nil then
        emit("NOTE_OFF", state.lastPitch, nil, channel)
    end
    state.prevGate  = false
    state.lastPitch = nil
end

-- ===========================================================================
-- PatchLoader  (descriptor table → populated Engine)
-- ===========================================================================

local PatchLoader = {}

local function patchLoaderApplyPattern(pattern, patternDescriptor)
    if patternDescriptor.name then Pattern.setName(pattern, patternDescriptor.name) end
    local steps = patternDescriptor.steps or {}
    assert(#steps == pattern.stepCount,
        "patchLoaderApplyPattern: pattern step count mismatch")
    for i, sd in ipairs(steps) do
        Pattern.setStep(pattern, i, Step.new(sd[1], sd[2], sd[3], sd[4], sd[5], sd[6]))
    end
end

local function patchLoaderApplyTrack(track, trackDescriptor)
    if trackDescriptor.channel   then Track.setMidiChannel(track, trackDescriptor.channel)   end
    if trackDescriptor.direction then Track.setDirection(track,   trackDescriptor.direction) end
    if trackDescriptor.clockDiv  then Track.setClockDiv(track,    trackDescriptor.clockDiv)  end
    if trackDescriptor.clockMult then Track.setClockMult(track,   trackDescriptor.clockMult) end
    local patterns = trackDescriptor.patterns or {}
    for _, pd in ipairs(patterns) do
        local pat = Track.addPattern(track, #(pd.steps or {}))
        patchLoaderApplyPattern(pat, pd)
    end
    if trackDescriptor.loopStart then Track.setLoopStart(track, trackDescriptor.loopStart) end
    if trackDescriptor.loopEnd   then Track.setLoopEnd(track,   trackDescriptor.loopEnd)   end
end

function PatchLoader.build(descriptor)
    assert(type(descriptor) == "table", "patchLoaderBuild: descriptor must be a table")
    assert(type(descriptor.bpm) == "number", "patchLoaderBuild: descriptor.bpm required")
    assert(type(descriptor.ppb) == "number", "patchLoaderBuild: descriptor.ppb required")
    assert(type(descriptor.tracks) == "table" and #descriptor.tracks > 0,
        "patchLoaderBuild: descriptor.tracks must be non-empty")
    local trackCount = #descriptor.tracks
    local engine = Engine.new(descriptor.bpm, descriptor.ppb, trackCount, 0)
    for i, td in ipairs(descriptor.tracks) do
        patchLoaderApplyTrack(Engine.getTrack(engine, i), td)
    end
    return engine
end

function PatchLoader.load(modulePath)
    assert(type(modulePath) == "string", "patchLoaderLoad: modulePath must be a string")
    return PatchLoader.build(require(modulePath))
end

-- ===========================================================================
-- Driver  (per-pulse: sample → translate → advance, per track)
-- ===========================================================================
--
-- Two clock modes (mutually exclusive):
--   1. Internal:  Driver.tick(d, emit)         -- needs clockFn() returning ms
--   2. External:  Driver.externalPulse(d, emit) -- one master pulse per call
--
-- Per pulse, for each track:
--   1. clockAccum += clockMult; advanceCount = floor(clockAccum / clockDiv)
--   2. repeat advanceCount times:
--        cvA, cvB, gate = Engine.sampleTrack(eng, i)
--        MidiTranslate.step(state, cvA, cvB, gate, ch, emit)
--        Engine.advanceTrack(eng, i)
--   3. clockAccum = clockAccum % clockDiv

local Driver = {}

function Driver.new(engine, clockFn, bpm)
    bpm = bpm or engine.bpm
    local translators = {}
    for i = 1, engine.trackCount do translators[i] = MidiTranslate.new() end
    return {
        engine      = engine,
        clockFn     = clockFn,
        bpm         = bpm,
        pulseMs     = Engine.bpmToMs(bpm, engine.pulsesPerBeat),
        translators = translators,
        startMs     = 0,
        pulseCount  = 0,
        running     = false,
    }
end

function Driver.start(d)
    if d.clockFn then d.startMs = d.clockFn() end
    d.pulseCount = 0
    d.running    = true
end

function Driver.stop(d) d.running = false end

function Driver.setBpm(d, bpm)
    d.bpm     = bpm
    d.pulseMs = Engine.bpmToMs(bpm, d.engine.pulsesPerBeat)
    if d.clockFn then d.startMs = d.clockFn() - d.pulseCount * d.pulseMs end
end

function Driver.allNotesOff(d, emit)
    local engine = d.engine
    for i = 1, engine.trackCount do
        local channel = engine.tracks[i].midiChannel or 1
        MidiTranslate.panic(d.translators[i], channel, emit)
    end
end

function Driver.externalPulse(d, emit)
    if not d.running then return end
    d.pulseCount = d.pulseCount + 1
    local engine = d.engine
    for i = 1, engine.trackCount do
        local track   = engine.tracks[i]
        local channel = track.midiChannel or 1
        track.clockAccum = track.clockAccum + track.clockMult
        local advanceCount = floor(track.clockAccum / track.clockDiv)
        track.clockAccum   = track.clockAccum % track.clockDiv
        for _ = 1, advanceCount do
            local cvA, cvB, gate = Engine.sampleTrack(engine, i)
            MidiTranslate.step(d.translators[i], cvA, cvB, gate, channel, emit)
            Engine.advanceTrack(engine, i)
        end
    end
    Engine.onPulse(engine, d.pulseCount)
end

function Driver.tick(d, emit)
    if not d.running then return end
    local target = floor((d.clockFn() - d.startMs) / d.pulseMs)
    while d.pulseCount < target do
        Driver.externalPulse(d, emit)
        if not d.running then return end
    end
end

-- ===========================================================================
-- Module export
-- ===========================================================================

return {
    Utils         = Utils,
    Step          = Step,
    Pattern       = Pattern,
    Track         = Track,
    Scene         = Scene,
    Engine        = Engine,
    MidiTranslate = MidiTranslate,
    PatchLoader   = PatchLoader,
    Driver        = Driver,
}
