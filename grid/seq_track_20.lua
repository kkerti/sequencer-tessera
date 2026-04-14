local Track=require("seq_track")
local Pattern=require("seq_pattern")
local Step=require("seq_step")
local DIRECTION_FORWARD = "forward"
local DIRECTION_REVERSE = "reverse"
local DIRECTION_PINGPONG = "pingpong"
local DIRECTION_RANDOM = "random"
local DIRECTION_BROWNIAN = "brownian"
function Track.advance(track)
    local stepCount = Track._trackComputeStepCount(track)
    if stepCount == 0 then
        return nil
    end

    local step = Track._trackSkipZeroDuration(track, stepCount)

    if step == nil then
        return nil
    end

    local event = Step.getPulseEvent(step, track.pulseCounter)

    track.pulseCounter = track.pulseCounter + 1

    -- Step duration elapsed: move to next step (respecting loop points).
    if track.pulseCounter >= step.duration then
        track.pulseCounter = 0
        track.cursor       = Track._trackGetNextCursor(track, track.cursor)
    end

    return event
end
function Track.reset(track)
    track.cursor       = 1
    track.pulseCounter = 0
    track.clockAccum   = 0
    track.pingPongDir  = 1
end
