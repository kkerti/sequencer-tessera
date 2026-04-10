-- sequencer/step.lua
-- A single step in a sequence.
-- pitch    : MIDI note number 0-127
-- velocity : MIDI velocity 0-127
-- duration : length in clock pulses 0-99 (0 = skip this step)
-- gate     : note-on length in clock pulses 0-99
--              0              = rest (note never fires)
--              gate >= duration = legato (note held through full step)
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

-- Constructor. All parameters are optional; defaults shown above.
function Step.new(pitch, velocity, duration, gate)
    pitch    = pitch or 60
    velocity = velocity or 100
    duration = duration or 4
    gate     = gate or 2

    assert(type(pitch) == "number" and pitch >= PITCH_MIN and pitch <= PITCH_MAX, "stepNew: pitch out of range 0-127")
    assert(type(velocity) == "number" and velocity >= VELOCITY_MIN and velocity <= VELOCITY_MAX,
        "stepNew: velocity out of range 0-127")
    assert(type(duration) == "number" and duration >= DURATION_MIN and duration <= DURATION_MAX,
        "stepNew: duration out of range 0-99")
    assert(type(gate) == "number" and gate >= GATE_MIN and gate <= GATE_MAX, "stepNew: gate out of range 0-99")

    return {
        pitch    = pitch,
        velocity = velocity,
        duration = duration,
        gate     = gate,
        active   = true,
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

return Step
