local Track=require("seq_track")
local Pattern=require("seq_pattern")
local Step=require("seq_step")
local DIRECTION_FORWARD = "forward"
local DIRECTION_REVERSE = "reverse"
local DIRECTION_PINGPONG = "pingpong"
local DIRECTION_RANDOM = "random"
local DIRECTION_BROWNIAN = "brownian"
function Track.deletePattern(track, patternIndex)

    -- Compute the flat range of the pattern being removed.
    local delStart = Track.patternStartIndex(track, patternIndex)
    local delEnd   = Track.patternEndIndex(track, patternIndex)
    local delCount = delEnd - delStart + 1

    -- Remove from patterns array.
    for i = patternIndex, track.patternCount - 1 do
        track.patterns[i] = track.patterns[i + 1]
    end
    track.patterns[track.patternCount] = nil
    track.patternCount = track.patternCount - 1

    -- Adjust loop points.
    if track.loopStart ~= nil then
        if track.loopStart >= delStart and track.loopStart <= delEnd then
            track.loopStart = nil
        elseif track.loopStart > delEnd then
            track.loopStart = track.loopStart - delCount
        end
    end
