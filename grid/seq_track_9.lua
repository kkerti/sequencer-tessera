local Track=require("seq_track")
local Pattern=require("seq_pattern")
local Step=require("seq_step")
local DIRECTION_FORWARD = "forward"
local DIRECTION_REVERSE = "reverse"
local DIRECTION_PINGPONG = "pingpong"
local DIRECTION_RANDOM = "random"
local DIRECTION_BROWNIAN = "brownian"
function Track.new()
    return {
        patterns     = {},
        patternCount = 0,
        cursor       = 1,  -- flat 1-based step index
        pulseCounter = 0,  -- pulses elapsed within the current step
        loopStart    = nil,
        loopEnd      = nil,
        clockDiv     = 1,
        clockMult    = 1,
        clockAccum   = 0,
        direction    = DIRECTION_FORWARD,
        pingPongDir  = 1,
        midiChannel  = nil,
    }
end
function Track.addPattern(track, stepCount)
    stepCount = stepCount or 8

    local pat = Pattern.new(stepCount)
    track.patternCount = track.patternCount + 1
    track.patterns[track.patternCount] = pat
    return pat
end
function Track.getPattern(track, patternIndex)
    return track.patterns[patternIndex]
end
function Track.getPatternCount(track)
    return track.patternCount
end
