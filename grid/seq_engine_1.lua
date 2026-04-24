local Engine=require("seq_engine")
local Track=require("seq_track")
local Scene=require("seq_scene")
function Engine._engineInitTracks(trackCount, stepCount)
    local tracks = {}
    for i = 1, trackCount do
        local track = Track.new()
        if stepCount > 0 then
            Track.addPattern(track, stepCount)
        end
        tracks[i] = track
    end
    return tracks
end
function Engine._engineTickSceneChain(engine, pulseCount)
    if engine.sceneChain == nil or not Scene.chainIsActive(engine.sceneChain) then
        return
    end
    if pulseCount % engine.pulsesPerBeat ~= 0 then
        return
    end
    local advanced = Scene.chainBeat(engine.sceneChain)
    if advanced then
        local current = Scene.chainGetCurrent(engine.sceneChain)
        if current then
            Scene.applyToTracks(current, engine.tracks, engine.trackCount)
        end
    end
end
