local Player=require("seq_player")
local Engine=require("seq_engine")
local Performance=require("seq_performance")
function Player.tick(player, emit)
    if not player.running then
        return
    end

    local nowMs = player.clockFn()

    Player._playerFlushExpiredNotes(player, nowMs, emit)

    player.pulseCount = player.pulseCount + 1

    local shouldHold
    shouldHold, player.swingCarry = Performance.nextSwingHold(
        player.pulseCount,
        player.engine.pulsesPerBeat,
        player.swingPercent,
        player.swingCarry
    )

    if shouldHold then
        return
    end

    for trackIndex = 1, player.engine.trackCount do
        Player._playerAdvanceTrack(player, trackIndex, nowMs, emit)
    end

    Engine.onPulse(player.engine, player.pulseCount)
end
