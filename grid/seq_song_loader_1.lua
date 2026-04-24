local SongLoader=require("seq_song_loader")
local Track=require("seq_track")
local Step=require("seq_step")
function SongLoader.buildStep(desc)
    return Step.new(
        desc[1] or 60,
        desc[2] or 100,
        desc[3] or 4,
        desc[4] or 2,
        desc[5] or 1,
        desc[6] or 100
    )
end
function SongLoader.loadPatterns(track, trackDesc)
    local fi = 1
    for _, pd in ipairs(trackDesc.patterns or {}) do
        Track.addPattern(track, #(pd.steps or {}), pd.name)
        for _, sd in ipairs(pd.steps or {}) do
            Track.setStep(track, fi, SongLoader.buildStep(sd))
            fi = fi + 1
        end
    end
end
