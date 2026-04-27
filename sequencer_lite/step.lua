-- sequencer_lite/step.lua
-- LITE BUILD: byte-for-byte copy of sequencer/step.lua, kept as a separate
-- file so the on-device engine has no dependency on sequencer/.
-- See docs/dropped-features.md for the carve rationale.
--
-- A single step in a sequence.
-- pitch       : MIDI note number 0-127
-- velocity    : MIDI velocity 0-127
-- duration    : length in clock pulses 0-99 (0 = skip this step)
-- gate        : note-on length in clock pulses 0-99
--                 0              = rest (note never fires)
--                 gate >= duration = legato (note held through full step)
-- ratchet     : repeat count per step (1-4, Metropolis-style)
-- probability : chance this step fires (0-100, 100 = always; Blackbox-style)
-- active      : boolean, false mutes the step without removing it
--
-- Layout: { pitch, velocity, duration, gate, ratchet, probability, active }

local Utils        = require("utils")

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
local RATCHET_MIN  = 1
local RATCHET_MAX  = 4
local PROB_MIN     = 0
local PROB_MAX     = 100

function Step.new(pitch, velocity, duration, gate, ratchet, probability)
    pitch       = pitch or 60
    velocity    = velocity or 100
    duration    = duration or 4
    gate        = gate or 2
    ratchet     = ratchet or 1
    probability = probability or 100

    assert(type(pitch) == "number" and pitch >= PITCH_MIN and pitch <= PITCH_MAX,
        "stepNew: pitch out of range 0-127")
    assert(type(velocity) == "number" and velocity >= VELOCITY_MIN and velocity <= VELOCITY_MAX,
        "stepNew: velocity out of range 0-127")
    assert(type(duration) == "number" and duration >= DURATION_MIN and duration <= DURATION_MAX,
        "stepNew: duration out of range 0-99")
    assert(type(gate) == "number" and gate >= GATE_MIN and gate <= GATE_MAX,
        "stepNew: gate out of range 0-99")
    assert(type(ratchet) == "number" and ratchet >= RATCHET_MIN and ratchet <= RATCHET_MAX,
        "stepNew: ratchet out of range 1-4")
    assert(type(probability) == "number" and probability >= PROB_MIN and probability <= PROB_MAX,
        "stepNew: probability out of range 0-100")

    return { pitch, velocity, duration, gate, ratchet, probability, true }
end

function Step.getPitch(step)       return step[I_PITCH] end
function Step.setPitch(step, value)
    assert(type(value) == "number" and value >= PITCH_MIN and value <= PITCH_MAX,
        "stepSetPitch: value out of range 0-127")
    step[I_PITCH] = value
end

function Step.getVelocity(step)    return step[I_VEL] end
function Step.setVelocity(step, value)
    assert(type(value) == "number" and value >= VELOCITY_MIN and value <= VELOCITY_MAX,
        "stepSetVelocity: value out of range 0-127")
    step[I_VEL] = value
end

function Step.getDuration(step)    return step[I_DUR] end
function Step.setDuration(step, value)
    assert(type(value) == "number" and value >= DURATION_MIN and value <= DURATION_MAX,
        "stepSetDuration: value out of range 0-99")
    step[I_DUR] = value
end

function Step.getGate(step)        return step[I_GATE] end
function Step.setGate(step, value)
    assert(type(value) == "number" and value >= GATE_MIN and value <= GATE_MAX,
        "stepSetGate: value out of range 0-99")
    step[I_GATE] = value
end

function Step.getRatchet(step)     return step[I_RATCH] end
function Step.setRatchet(step, value)
    assert(type(value) == "number" and value >= RATCHET_MIN and value <= RATCHET_MAX,
        "stepSetRatchet: value out of range 1-4")
    step[I_RATCH] = value
end

function Step.getProbability(step) return step[I_PROB] end
function Step.setProbability(step, value)
    assert(type(value) == "number" and value >= PROB_MIN and value <= PROB_MAX,
        "stepSetProbability: value out of range 0-100")
    step[I_PROB] = value
end

function Step.getActive(step)      return step[I_ACTIVE] end
function Step.setActive(step, value)
    assert(type(value) == "boolean", "stepSetActive: value must be boolean")
    step[I_ACTIVE] = value
end

function Step.isPlayable(step)
    return step[I_ACTIVE] and step[I_DUR] > 0 and step[I_GATE] > 0
end

local function stepIsRatchetOnPulse(step, pulseCounter)
    local ratch = step[I_RATCH]
    local dur   = step[I_DUR]
    for i = 0, ratch - 1 do
        local startPulse = math.floor((i * dur) / ratch)
        if pulseCounter == startPulse then
            return true
        end
    end
    return false
end

local function stepIsRatchetOffPulse(step, pulseCounter)
    local ratch = step[I_RATCH]
    local dur   = step[I_DUR]
    local gate  = step[I_GATE]
    for i = 0, ratch - 1 do
        local startPulse    = math.floor((i * dur) / ratch)
        local nextStartPulse = math.floor(((i + 1) * dur) / ratch)
        local subDuration   = nextStartPulse - startPulse
        if subDuration < 1 then
            subDuration = 1
        end

        local offPulse = startPulse + gate
        if offPulse > startPulse + subDuration then
            offPulse = startPulse + subDuration
        end
        if offPulse >= dur then
            offPulse = dur - 1
        end

        if pulseCounter == offPulse then
            return true
        end
    end
    return false
end

function Step.getPulseEvent(step, pulseCounter)
    assert(type(pulseCounter) == "number" and pulseCounter >= 0,
        "stepGetPulseEvent: pulseCounter must be >= 0")

    if not Step.isPlayable(step) then
        return nil
    end

    if step[I_RATCH] == 1 then
        if pulseCounter == 0 then
            return "NOTE_ON"
        end
        if pulseCounter == step[I_GATE] then
            return "NOTE_OFF"
        end
        return nil
    end

    if stepIsRatchetOnPulse(step, pulseCounter) then
        return "NOTE_ON"
    end

    if stepIsRatchetOffPulse(step, pulseCounter) then
        return "NOTE_OFF"
    end

    return nil
end

function Step.resolvePitch(step, scaleTable, rootNote)
    if scaleTable == nil then
        return step[I_PITCH]
    end
    rootNote = rootNote or 0
    return Utils.quantizePitch(step[I_PITCH], rootNote, scaleTable)
end

return Step
