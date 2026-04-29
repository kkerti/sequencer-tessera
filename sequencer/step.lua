-- sequencer/step.lua
-- A single step in a sequence, packed into a Lua integer.
--
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
-- ---------------------------------------------------------------------------
-- Storage: a single Lua integer (37 bits used). Lua 5.3+ guarantees 64-bit
-- integers so this is safe. Storing as an integer means a Step is 8 bytes
-- (vs ~80 bytes for a 7-element table) and lives inline inside the parent
-- array part of `pattern.steps`. This is critical for the on-device memory
-- budget (see docs/2026-04-28-memory-diet.md).
--
-- Bit layout (LSB-first):
--   bits  0- 6  pitch       (7 bits)
--   bits  7-13  velocity    (7 bits)
--   bits 14-20  duration    (7 bits)
--   bits 21-27  gate        (7 bits)
--   bits 28-34  probability (7 bits)
--   bit  35     ratch       (1 bit)
--   bit  36     active      (1 bit)
--
-- NOTE: implementation uses arithmetic (math.floor, %, *) instead of native
-- bitwise operators (<<, >>, &, |, ~) so the bundled source can pass through
-- LuaSrcDiet, whose Lua 5.1-era parser does not understand 5.3+ operators.
-- The on-device VM (Lua 5.4) executes this just fine; no behaviour change.
--
-- API contract: `Step.setX(step, value)` is PURE — it returns a NEW packed
-- integer; the caller must rebind the returned value. Integers are passed
-- by value in Lua, so in-place mutation is impossible.
--   correct  : s = Step.setPitch(s, 60)
--   correct  : Track.setStep(t, i, Step.setPitch(Track.getStep(t, i), 60))
--   wrong    : Step.setPitch(s, 60)  -- result discarded; bug
-- ---------------------------------------------------------------------------

local Step = {}

local floor = math.floor

-- Pre-computed 2^shift constants (one per field origin).
local P_PITCH = 1                  -- 2^0
local P_VEL   = 128                -- 2^7
local P_DUR   = 16384              -- 2^14
local P_GATE  = 2097152            -- 2^21
local P_PROB  = 268435456          -- 2^28
local P_RATCH = 34359738368        -- 2^35
local P_ACT   = 68719476736        -- 2^36

-- Pre-computed (2^7) * pow constants — the "field width" in absolute terms.
-- A 7-bit field at origin P occupies values P*0..P*127; clearing it means
-- subtracting (current_field_value * P).
-- Range constants (kept for assert messages and external callers).
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

-- ---------------------------------------------------------------------------
-- Internal helpers (arithmetic in place of bitwise ops)
-- ---------------------------------------------------------------------------

local function get7(step, pow)
    -- Extract a 7-bit field whose origin is `pow` (== 2^shift).
    return floor(step / pow) % 128
end

local function getBit(step, pow)
    return floor(step / pow) % 2
end

local function pack7(step, value, pow)
    -- Replace a 7-bit field at origin `pow` with `value` (0..127).
    local cur = floor(step / pow) % 128
    return step + (value - cur) * pow
end

local function packBit(step, value, pow)
    local cur = floor(step / pow) % 2
    local newBit = value and 1 or 0
    return step + (newBit - cur) * pow
end

-- ---------------------------------------------------------------------------
-- Constructor
-- ---------------------------------------------------------------------------

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

    local s = pitch * P_PITCH
            + velocity * P_VEL
            + duration * P_DUR
            + gate * P_GATE
            + probability * P_PROB
            + P_ACT
    if ratch then s = s + P_RATCH end
    return s
end

-- ---------------------------------------------------------------------------
-- Getters
-- ---------------------------------------------------------------------------

function Step.getPitch(step)       return floor(step / P_PITCH) % 128 end
function Step.getVelocity(step)    return floor(step / P_VEL)   % 128 end
function Step.getDuration(step)    return floor(step / P_DUR)   % 128 end
function Step.getGate(step)        return floor(step / P_GATE)  % 128 end
function Step.getProbability(step) return floor(step / P_PROB)  % 128 end
function Step.getRatch(step)       return floor(step / P_RATCH) % 2 == 1 end
function Step.getActive(step)      return floor(step / P_ACT)   % 2 == 1 end

-- ---------------------------------------------------------------------------
-- Setters — return a new packed integer; the caller must rebind.
-- ---------------------------------------------------------------------------

function Step.setPitch(step, value)
    assert(type(value) == "number" and value >= PITCH_MIN and value <= PITCH_MAX,
        "stepSetPitch: value out of range 0-127")
    return pack7(step, value, P_PITCH)
end

function Step.setVelocity(step, value)
    assert(type(value) == "number" and value >= VELOCITY_MIN and value <= VELOCITY_MAX,
        "stepSetVelocity: value out of range 0-127")
    return pack7(step, value, P_VEL)
end

function Step.setDuration(step, value)
    assert(type(value) == "number" and value >= DURATION_MIN and value <= DURATION_MAX,
        "stepSetDuration: value out of range 0-99")
    return pack7(step, value, P_DUR)
end

function Step.setGate(step, value)
    assert(type(value) == "number" and value >= GATE_MIN and value <= GATE_MAX,
        "stepSetGate: value out of range 0-99")
    return pack7(step, value, P_GATE)
end

function Step.setRatch(step, value)
    assert(type(value) == "boolean", "stepSetRatch: value must be boolean")
    return packBit(step, value, P_RATCH)
end

function Step.setProbability(step, value)
    assert(type(value) == "number" and value >= PROB_MIN and value <= PROB_MAX,
        "stepSetProbability: value out of range 0-100")
    return pack7(step, value, P_PROB)
end

function Step.setActive(step, value)
    assert(type(value) == "boolean", "stepSetActive: value must be boolean")
    return packBit(step, value, P_ACT)
end

-- ---------------------------------------------------------------------------
-- Convenience predicates
-- ---------------------------------------------------------------------------

function Step.isPlayable(step)
    return floor(step / P_ACT) % 2 == 1
        and floor(step / P_DUR) % 128 > 0
        and floor(step / P_GATE) % 128 > 0
end

-- ---------------------------------------------------------------------------
-- ER-101 sampled-state model
-- ---------------------------------------------------------------------------
-- Each clock pulse the engine asks "what is the current value of CV-A,
-- CV-B and GATE for this track?". Step.sampleCv answers the constant CV
-- pair; Step.sampleGate answers the boolean gate level for a given pulse
-- index inside the step. MIDI emission is downstream of the gate stream's
-- rising and falling edges (see sequencer/midi_translate.lua).
-- ---------------------------------------------------------------------------

function Step.sampleCv(step)
    return floor(step / P_PITCH) % 128, floor(step / P_VEL) % 128
end

-- Returns the gate level (boolean) at `pulseCounter` pulses into the step.
-- pulseCounter is 0-based.
--
-- Rules (from the ER-101 manual, §"Ratcheting"):
--   active==false                  : low (mute)
--   duration == 0                  : low (skip step)
--   gate == 0                      : low (rest)
--   gate >= duration               : high (legato)
--   ratch==false                   : high on [0, gate); low otherwise
--   ratch==true                    : period = 2*gate; high on [0, gate);
--                                    suppressed once pulseCounter >= duration
function Step.sampleGate(step, pulseCounter)
    assert(type(pulseCounter) == "number" and pulseCounter >= 0,
        "stepSampleGate: pulseCounter must be >= 0")

    if floor(step / P_ACT) % 2 == 0 then return false end

    local dur = floor(step / P_DUR) % 128
    if dur == 0 then return false end

    local gate = floor(step / P_GATE) % 128
    if gate == 0 then return false end

    if gate >= dur then return true end

    if floor(step / P_RATCH) % 2 == 0 then
        return pulseCounter < gate
    end

    if pulseCounter >= dur then return false end
    local phase = pulseCounter % (gate * 2)
    return phase < gate
end

return Step
