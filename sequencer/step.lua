-- sequencer/step.lua
-- A single step in a sequence.
-- pitch    : MIDI note number 0-127
-- velocity : MIDI velocity 0-127
-- duration : length in clock pulses 0-99 (0 = skip this step)
-- gate     : note-on length in clock pulses 0-99
--              0              = rest (note never fires)
--              gate >= duration = legato (note held through full step)
-- ratchet  : repeat count per step (1-4, Metropolis-style)
-- probability : chance this step fires (0-100, 100 = always; Blackbox-style)
-- active   : boolean, false mutes the step without removing it

local Utils        = require("utils")

local Step         = {}

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

-- Constructor. All parameters are optional; defaults shown above.
function Step.new(pitch, velocity, duration, gate, ratchet, probability)
    pitch       = pitch or 60
    velocity    = velocity or 100
    duration    = duration or 4
    gate        = gate or 2
    ratchet     = ratchet or 1
    probability = probability or 100

    assert(type(pitch) == "number" and pitch >= PITCH_MIN and pitch <= PITCH_MAX, "stepNew: pitch out of range 0-127")
    assert(type(velocity) == "number" and velocity >= VELOCITY_MIN and velocity <= VELOCITY_MAX,
        "stepNew: velocity out of range 0-127")
    assert(type(duration) == "number" and duration >= DURATION_MIN and duration <= DURATION_MAX,
        "stepNew: duration out of range 0-99")
    assert(type(gate) == "number" and gate >= GATE_MIN and gate <= GATE_MAX, "stepNew: gate out of range 0-99")
    assert(type(ratchet) == "number" and ratchet >= RATCHET_MIN and ratchet <= RATCHET_MAX,
        "stepNew: ratchet out of range 1-4")
    assert(type(probability) == "number" and probability >= PROB_MIN and probability <= PROB_MAX,
        "stepNew: probability out of range 0-100")

    return {
        pitch       = pitch,
        velocity    = velocity,
        duration    = duration,
        gate        = gate,
        ratchet     = ratchet,
        probability = probability,
        active      = true,
    }
end

-- Pitch
function Step.getPitch(step)
    return step.pitch
end

function Step.setPitch(step, value)
    assert(type(value) == "number" and value >= PITCH_MIN and value <= PITCH_MAX,
        "stepSetPitch: value out of range 0-127")
    step.pitch = value
end

-- Velocity
function Step.getVelocity(step)
    return step.velocity
end

function Step.setVelocity(step, value)
    assert(type(value) == "number" and value >= VELOCITY_MIN and value <= VELOCITY_MAX,
        "stepSetVelocity: value out of range 0-127")
    step.velocity = value
end

-- Duration
function Step.getDuration(step)
    return step.duration
end

function Step.setDuration(step, value)
    assert(type(value) == "number" and value >= DURATION_MIN and value <= DURATION_MAX,
        "stepSetDuration: value out of range 0-99")
    step.duration = value
end

-- Gate
function Step.getGate(step)
    return step.gate
end

function Step.setGate(step, value)
    assert(type(value) == "number" and value >= GATE_MIN and value <= GATE_MAX, "stepSetGate: value out of range 0-99")
    step.gate = value
end

-- Ratchet
function Step.getRatchet(step)
    return step.ratchet
end

function Step.setRatchet(step, value)
    assert(type(value) == "number" and value >= RATCHET_MIN and value <= RATCHET_MAX,
        "stepSetRatchet: value out of range 1-4")
    step.ratchet = value
end

-- Probability
function Step.getProbability(step)
    return step.probability
end

function Step.setProbability(step, value)
    assert(type(value) == "number" and value >= PROB_MIN and value <= PROB_MAX,
        "stepSetProbability: value out of range 0-100")
    step.probability = value
end

-- Active
function Step.getActive(step)
    return step.active
end

function Step.setActive(step, value)
    assert(type(value) == "boolean", "stepSetActive: value must be boolean")
    step.active = value
end

-- Returns true if this step should fire a note-on (active and not a rest).
function Step.isPlayable(step)
    return step.active and step.duration > 0 and step.gate > 0
end

-- Checks if any ratchet sub-division starts at this pulse (NOTE_ON boundary).
local function stepIsRatchetOnPulse(step, pulseCounter)
    for i = 0, step.ratchet - 1 do
        local startPulse = math.floor((i * step.duration) / step.ratchet)
        if pulseCounter == startPulse then
            return true
        end
    end
    return false
end

-- Checks if any ratchet sub-division ends at this pulse (NOTE_OFF boundary).
local function stepIsRatchetOffPulse(step, pulseCounter)
    for i = 0, step.ratchet - 1 do
        local startPulse = math.floor((i * step.duration) / step.ratchet)
        local nextStartPulse = math.floor(((i + 1) * step.duration) / step.ratchet)
        local subDuration = nextStartPulse - startPulse
        if subDuration < 1 then
            subDuration = 1
        end

        local offPulse = startPulse + step.gate
        if offPulse > startPulse + subDuration then
            offPulse = startPulse + subDuration
        end
        if offPulse >= step.duration then
            offPulse = step.duration - 1
        end

        if pulseCounter == offPulse then
            return true
        end
    end
    return false
end

-- Returns NOTE_ON / NOTE_OFF / nil for this pulse inside the step.
-- pulseCounter is 0-based pulse index within the current step.
function Step.getPulseEvent(step, pulseCounter)
    assert(type(pulseCounter) == "number" and pulseCounter >= 0, "stepGetPulseEvent: pulseCounter must be >= 0")

    if not Step.isPlayable(step) then
        return nil
    end

    if step.ratchet == 1 then
        if pulseCounter == 0 then
            return "NOTE_ON"
        end
        if pulseCounter == step.gate then
            return "NOTE_OFF"
        end
        return nil
    end

    -- Priority rule: NOTE_ON wins if on/off boundaries collide.
    if stepIsRatchetOnPulse(step, pulseCounter) then
        return "NOTE_ON"
    end

    if stepIsRatchetOffPulse(step, pulseCounter) then
        return "NOTE_OFF"
    end

    return nil
end

-- Resolves pitch through an optional scale table.
-- If no scale table is provided, returns raw step.pitch.
function Step.resolvePitch(step, scaleTable, rootNote)
    if scaleTable == nil then
        return step.pitch
    end
    rootNote = rootNote or 0
    return Utils.quantizePitch(step.pitch, rootNote, scaleTable)
end

return Step
