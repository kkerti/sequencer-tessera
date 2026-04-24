local Engine=require("seq_engine")
function Engine.bpmToMs(bpm, pulsesPerBeat)
    pulsesPerBeat = pulsesPerBeat or 4
    return (60000 / bpm) / pulsesPerBeat
end
function Engine.new(bpm, pulsesPerBeat, trackCount, stepCount)
    bpm           = bpm or 120
    pulsesPerBeat = pulsesPerBeat or 4
    trackCount    = trackCount or 4
    stepCount     = stepCount or 8


    return {
        bpm             = bpm,
        pulsesPerBeat   = pulsesPerBeat,
        pulseIntervalMs = Engine.bpmToMs(bpm, pulsesPerBeat),
        tracks          = Engine._engineInitTracks(trackCount, stepCount),
        trackCount      = trackCount,
        scaleName       = nil,
        scaleTable      = nil,
        rootNote        = 0,
        sceneChain      = nil,
    }
end
function Engine.getTrack(engine, index)
    return engine.tracks[index]
end
