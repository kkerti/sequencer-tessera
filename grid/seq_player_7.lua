local Player=require("seq_player")
function Player.new(engine, bpm, clockFn)

    bpm = bpm or engine.bpm

    local trackCount     = engine.trackCount
    local probSuppressed = {}
    for i = 1, trackCount do
        probSuppressed[i] = false
    end

    return {
        engine           = engine,
        bpm              = bpm,
        clockFn          = clockFn,
        pulseIntervalMs  = Player._playerBpmToMs(bpm, engine.pulsesPerBeat),
        pulseCount       = 0,
        swingPercent     = 50,
        swingCarry       = 0,
        scaleName        = nil,
        scaleTable       = nil,
        rootNote         = 0,
        running          = false,
        activeNoteKeys   = {},
        activeNoteOffAt  = {},
        activeNoteCount  = 0,
        probSuppressed   = probSuppressed,
    }
end
function Player.setBpm(player, bpm)
    player.bpm             = bpm
    player.pulseIntervalMs = Player._playerBpmToMs(bpm, player.engine.pulsesPerBeat)
end
