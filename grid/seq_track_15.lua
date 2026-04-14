local Track=require("seq_track")
local Pattern=require("seq_pattern")
local Step=require("seq_step")
local DIRECTION_FORWARD = "forward"
local DIRECTION_REVERSE = "reverse"
local DIRECTION_PINGPONG = "pingpong"
local DIRECTION_RANDOM = "random"
local DIRECTION_BROWNIAN = "brownian"
function Track.swapPatterns(track, indexA, indexB)

    if indexA == indexB then return end

    track.patterns[indexA], track.patterns[indexB] = track.patterns[indexB], track.patterns[indexA]

    -- Clear loop points since flat indices are now different.
    track.loopStart    = nil
    track.loopEnd      = nil
    track.cursor       = 1
    track.pulseCounter = 0
end
function Track.pastePattern(track, destIndex, srcPattern)

    local Utils   = require("utils")
    local dest    = track.patterns[destIndex]
    local count   = srcPattern.stepCount

    -- Replace steps.
    dest.steps     = {}
    dest.stepCount = count
    for i = 1, count do
        dest.steps[i] = Utils.tableCopy(srcPattern.steps[i])
    end
    dest.name = srcPattern.name

    -- Cursor reset for safety — step count may have changed.
    track.cursor       = 1
    track.pulseCounter = 0
end
