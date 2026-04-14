local Track=require("seq_track")
local Pattern=require("seq_pattern")
local Step=require("seq_step")

local DIRECTION_FORWARD = "forward"
local DIRECTION_REVERSE = "reverse"
local DIRECTION_PINGPONG = "pingpong"
local DIRECTION_RANDOM = "random"
local DIRECTION_BROWNIAN = "brownian"
function Track._trackSkipZeroDuration(track, stepCount)
    local step = Track._trackGetStepAtFlat(track, track.cursor)
    local skipGuard = 0
    while step ~= nil and step.duration == 0 do
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
