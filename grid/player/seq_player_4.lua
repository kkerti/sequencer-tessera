local Player=require("/player/seq_player")
function Player.tick(p, emit)
    if not p.running then return end
    local target = math.floor((p.clockFn() - p.startMs) / p.pulseMs)
    while p.pulseCount < target do
        Player.externalPulse(p, emit)
        if not p.running then return end
    end
end
