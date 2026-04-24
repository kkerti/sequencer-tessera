local Track=require("seq_track")
local Step=require("seq_step")
function Track._trackSkipZeroDuration(track, stepCount)
    local step = Track._trackGetStepAtFlat(track, track.cursor)
    local skipGuard = 0
    while step ~= nil and Step.getDuration(step) == 0 do
        track.cursor       = Track._trackGetNextCursor(track, track.cursor)
        track.pulseCounter = 0
        step               = Track._trackGetStepAtFlat(track, track.cursor)
        skipGuard = skipGuard + 1
        if skipGuard > stepCount then
            return nil
        end
    end
    return step
end
