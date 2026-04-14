local Engine=require("seq_engine")
local Track=require("seq_track")
local Step=require("seq_step")
local Utils=require("seq_utils")
local Performance=require("seq_performance")
local Scene=require("seq_scene")
local Probability=require("seq_probability")
function Engine.new(bpm, pulsesPerBeat, trackCount, stepCount)
    bpm           = bpm or 120
    pulsesPerBeat = pulsesPerBeat or 4
    trackCount    = trackCount or 4
    stepCount     = stepCount or 8


    local tracks, probSuppressed = Engine._engineInitTracks(trackCount, stepCount)

    return {
        bpm             = bpm,
        pulsesPerBeat   = pulsesPerBeat,
        pulseIntervalMs = Engine.bpmToMs(bpm, pulsesPerBeat),
        tracks          = tracks,
        trackCount      = trackCount,
        pulseCount      = 0,
        swingPercent    = 50,
        swingCarry      = 0,
        scaleName       = nil,
        scaleTable      = nil,
        rootNote        = 0,
        running         = true,
        -- Active note tracking: keyed by "pitch:channel", value = true.
        -- Used by allNotesOff() to flush sounding notes on reset/stop.
        activeNotes     = {},
        -- Per-track probability suppression flag. When a NOTE_ON is
        -- suppressed by probability, set to true so the corresponding
        -- NOTE_OFF is also suppressed.
        probSuppressed  = probSuppressed,
        -- Optional scene chain for automated loop-point sequencing.
        sceneChain      = nil,
    }
end
function Engine.getTrack(engine, index)
    return engine.tracks[index]
end
