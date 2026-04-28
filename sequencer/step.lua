-- sequencer/step.lua
-- A single step in a sequence.
-- pitch       : MIDI note number 0-127
-- velocity    : MIDI velocity 0-127
-- duration    : length in clock pulses 0-99 (0 = skip this step)
-- gate        : note-on length in clock pulses 0-99
--                 0              = rest (note never fires)
--                 gate >= duration = legato (note held through full step)
-- ratch       : ER-101-style boolean. When true, the gate cycles on/off
--                 inside the step. The cycle period is (2 * gate) pulses:
--                 NOTE_ON for `gate` pulses, NOTE_OFF for `gate` pulses,
--                 repeated until `duration` is reached. When false, the
--                 step fires once (ON at pulse 0, OFF at pulse `gate`).
-- probability : chance this step fires (0-100, 100 = always; Blackbox-style)
-- active      : boolean, false mutes the step without removing it
--
-- Internal storage: positional array to avoid hash-part allocation.
-- All access MUST go through the public getters/setters below.
-- Direct index access from outside this module is forbidden.
--
-- Layout: { pitch, velocity, duration, gate, ratch, probability, active }

local Step         = {}

-- Internal index constants — not exported.
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

-- Constructor. All parameters are optional; defaults shown above.
function Step.new(pitch, velocity, duration, gate, ratch, probability)
    pitch       = pitch or 60
    velocity    = velocity or 100
    duration    = duration or 4
    gate        = gate or 2
    if ratch == nil then ratch = false end
    probability = probability or 100

    assert(type(pitch) == "number" and pitch >= PITCH_MIN and pitch <= PITCH_MAX,
        "stepNew: pitch out of range 0-127")
    assert(type(velocity) == "number" and velocity >= VELOCITY_MIN and velocity <= VELOCITY_MAX,
        "stepNew: velocity out of range 0-127")
    assert(type(duration) == "number" and duration >= DURATION_MIN and duration <= DURATION_MAX,
        "stepNew: duration out of range 0-99")
    assert(type(gate) == "number" and gate >= GATE_MIN and gate <= GATE_MAX,
        "stepNew: gate out of range 0-99")
    assert(type(ratch) == "boolean", "stepNew: ratch must be boolean")
    assert(type(probability) == "number" and probability >= PROB_MIN and probability <= PROB_MAX,
        "stepNew: probability out of range 0-100")

    return { pitch, velocity, duration, gate, ratch, probability, true }
end

-- Pitch
function Step.getPitch(step)
    return step[I_PITCH]
end

function Step.setPitch(step, value)
    assert(type(value) == "number" and value >= PITCH_MIN and value <= PITCH_MAX,
        "stepSetPitch: value out of range 0-127")
    step[I_PITCH] = value
end

-- Velocity
function Step.getVelocity(step)
    return step[I_VEL]
end

function Step.setVelocity(step, value)
    assert(type(value) == "number" and value >= VELOCITY_MIN and value <= VELOCITY_MAX,
        "stepSetVelocity: value out of range 0-127")
    step[I_VEL] = value
end

-- Duration
function Step.getDuration(step)
    return step[I_DUR]
end

function Step.setDuration(step, value)
    assert(type(value) == "number" and value >= DURATION_MIN and value <= DURATION_MAX,
        "stepSetDuration: value out of range 0-99")
    step[I_DUR] = value
end

-- Gate
function Step.getGate(step)
    return step[I_GATE]
end

function Step.setGate(step, value)
    assert(type(value) == "number" and value >= GATE_MIN and value <= GATE_MAX,
        "stepSetGate: value out of range 0-99")
    step[I_GATE] = value
end

-- Ratchet (boolean)
function Step.getRatch(step)
    return step[I_RATCH]
end

function Step.setRatch(step, value)
    assert(type(value) == "boolean", "stepSetRatch: value must be boolean")
    step[I_RATCH] = value
end

-- Probability
function Step.getProbability(step)
    return step[I_PROB]
end

function Step.setProbability(step, value)
    assert(type(value) == "number" and value >= PROB_MIN and value <= PROB_MAX,
        "stepSetProbability: value out of range 0-100")
    step[I_PROB] = value
end

-- Active
function Step.getActive(step)
    return step[I_ACTIVE]
end

function Step.setActive(step, value)
    assert(type(value) == "boolean", "stepSetActive: value must be boolean")
    step[I_ACTIVE] = value
end

-- Returns true if this step should fire a note-on (active and not a rest).
function Step.isPlayable(step)
    return step[I_ACTIVE] and step[I_DUR] > 0 and step[I_GATE] > 0
end

-- Returns NOTE_ON / NOTE_OFF / nil for this pulse inside the step.
-- pulseCounter is 0-based pulse index within the current step.
--
-- Non-ratch:  ON at pulse 0, OFF at pulse `gate`.
-- Ratch=true: cycle period = 2 * gate.
--               pulse % (2*gate) == 0           → NOTE_ON
--               pulse % (2*gate) == gate        → NOTE_OFF
--             Cycles only fire while pulse < duration; the trailing OFF at
--             or beyond `duration` is suppressed (the next step's edge logic
--             takes over).
function Step.getPulseEvent(step, pulseCounter)
    assert(type(pulseCounter) == "number" and pulseCounter >= 0,
        "stepGetPulseEvent: pulseCounter must be >= 0")

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
