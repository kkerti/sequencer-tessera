-- sequencer/track.lua
-- A single track: a flat ordered list of steps with a play cursor.
-- At this stage there are no patterns; that layer comes later.
--
-- pulseCounter tracks the current pulse within the active step.
-- When pulseCounter reaches the step's duration, the track advances.

local Step = require("sequencer/step")

local Track = {}

-- Creates a new track with `stepCount` default steps.
-- `stepCount` defaults to 8.
function Track.new(stepCount)
    stepCount = stepCount or 8
    assert(type(stepCount) == "number" and stepCount > 0, "trackNew: stepCount must be a positive number")

    local steps = {}
    for i = 1, stepCount do
        steps[i] = Step.new()
    end

    return {
        steps        = steps,
        stepCount    = stepCount,
        cursor       = 1, -- 1-based index of the current step
        pulseCounter = 0, -- pulses elapsed within the current step
    }
end

-- Returns the step at the current play cursor.
function Track.getCurrentStep(track)
    return track.steps[track.cursor]
end

-- Returns the step at a specific 1-based index.
function Track.getStep(track, index)
    assert(type(index) == "number" and index >= 1 and index <= track.stepCount,
        "trackGetStep: index out of range")
    return track.steps[index]
end

-- Replaces the step at a specific 1-based index.
function Track.setStep(track, index, step)
    assert(type(index) == "number" and index >= 1 and index <= track.stepCount,
        "trackSetStep: index out of range")
    assert(type(step) == "table", "trackSetStep: step must be a table")
    track.steps[index] = step
end

-- Advances the track by one clock pulse.
-- Returns an event string: "NOTE_ON", "NOTE_OFF", or nil.
-- The engine uses this to know what MIDI to emit.
function Track.advance(track)
    local step = Track.getCurrentStep(track)

    -- Skip steps with zero duration entirely.
    while step.duration == 0 do
        track.cursor = (track.cursor % track.stepCount) + 1
        track.pulseCounter = 0
        step = Track.getCurrentStep(track)
    end

    local event = nil

    if track.pulseCounter == 0 then
        -- First pulse of this step: fire NOTE_ON if step is playable.
        if Step.isPlayable(step) then
            event = "NOTE_ON"
        end
    elseif track.pulseCounter == step.gate then
        -- Gate length elapsed: fire NOTE_OFF.
        if Step.isPlayable(step) then
            event = "NOTE_OFF"
        end
    end

    track.pulseCounter = track.pulseCounter + 1

    -- Step duration elapsed: move to next step.
    if track.pulseCounter >= step.duration then
        track.pulseCounter = 0
        track.cursor = (track.cursor % track.stepCount) + 1
    end

    return event
end

-- Resets the play cursor to the first step.
function Track.reset(track)
    track.cursor = 1
    track.pulseCounter = 0
end

return Track
