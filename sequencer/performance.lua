-- sequencer/performance.lua
-- Performance-time helpers that shape playback behaviour.

local Performance = {}

-- Decides if this pulse should be delayed by swing.
-- Returns: shouldHold, nextCarry
function Performance.nextSwingHold(pulseCount, pulsesPerBeat, swingPercent, swingCarry)
    assert(type(pulseCount) == "number" and pulseCount >= 1, "performanceNextSwingHold: pulseCount must be >= 1")
    assert(type(pulsesPerBeat) == "number" and pulsesPerBeat >= 1,
        "performanceNextSwingHold: pulsesPerBeat must be >= 1")
    assert(type(swingPercent) == "number" and swingPercent >= 50 and swingPercent <= 72,
        "performanceNextSwingHold: swingPercent out of range 50-72")

    swingCarry = swingCarry or 0

    if swingPercent <= 50 then
        return false, swingCarry
    end

    local phase = ((pulseCount - 1) % pulsesPerBeat) + 1
    if phase % 2 == 0 then
        return false, swingCarry
    end

    local intensity = (swingPercent - 50) / 22
    swingCarry = swingCarry + intensity
    if swingCarry >= 1 then
        swingCarry = swingCarry - 1
        return true, swingCarry
    end

    return false, swingCarry
end

return Performance
