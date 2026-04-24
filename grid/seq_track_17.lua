local Track=require("seq_track")
local Step=require("seq_step")
function Track.setDirection(track, direction)
    track.direction = direction
    if direction == Track._DIRECTION_PINGPONG then
        track.pingPongDir = 1
    end
end
function Track.getDirection(track)
    return track.direction
end
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
    if track.pulseCounter >= Step.getDuration(step) then
        track.pulseCounter = 0
        track.cursor       = Track._trackGetNextCursor(track, track.cursor)
    end

    return event
end
