local Performance=require("seq_performance")
function Performance.swingPercentToHoldAmount(swingPercent)
    return (swingPercent - 50) / 22
end
function Performance.nextSwingHold(pulseCount, pulsesPerBeat, swingPercent, swingCarry)

    swingCarry = swingCarry or 0

    if swingPercent <= 50 then
        return false, swingCarry
    end

    local phase = ((pulseCount - 1) % pulsesPerBeat) + 1
    if phase % 2 == 1 then
        return false, swingCarry
    end

    local holdAmount = Performance.swingPercentToHoldAmount(swingPercent)
    swingCarry = swingCarry + holdAmount
    if swingCarry >= 1 then
        swingCarry = swingCarry - 1
        return true, swingCarry
    end

    return false, swingCarry
end
