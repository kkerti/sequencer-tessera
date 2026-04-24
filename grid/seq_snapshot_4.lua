local Snapshot=require("seq_snapshot")
local Track=require("seq_track")
local Pattern=require("seq_pattern")
local Step=require("seq_step")
function Snapshot._snapshotRestorePattern(track, patternIndex, patternData)
    local pattern = Track.addPattern(track, #patternData.steps)
    if patternData.name ~= nil then
        Pattern.setName(pattern, patternData.name)
    end

    local startFlat = Track.patternStartIndex(track, patternIndex)
    for stepIndex = 1, #patternData.steps do
        local stepData = patternData.steps[stepIndex]
        local step = Step.new(
            stepData.pitch,
            stepData.velocity,
            stepData.duration,
            stepData.gate,
            stepData.ratchet or 1,
            stepData.probability or 100
        )
        Step.setActive(step, stepData.active ~= false)
        Track.setStep(track, startFlat + stepIndex - 1, step)
    end
end
