local Track=require("seq_track")
local Pattern=require("seq_pattern")
function Track.setStep(track, index, step)
    local stepCount = Track._trackComputeStepCount(track)

    local offset = 0
    for i = 1, track.patternCount do
        local pat      = track.patterns[i]
        local patCount = Pattern.getStepCount(pat)
        if index <= offset + patCount then
            Pattern.setStep(pat, index - offset, step)
            return
        end
        offset = offset + patCount
    end
end
function Track.getCurrentStep(track)
    return Track._trackGetStepAtFlat(track, track.cursor)
end
function Track.setLoopStart(track, index)
    local stepCount = Track._trackComputeStepCount(track)
    if track.loopEnd ~= nil then
    end
    track.loopStart = index
end
function Track.setLoopEnd(track, index)
    local stepCount = Track._trackComputeStepCount(track)
    if track.loopStart ~= nil then
    end
    track.loopEnd = index
end
