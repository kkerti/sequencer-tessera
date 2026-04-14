local Engine=require("seq_engine")
local Track=require("seq_track")
local Step=require("seq_step")
local Utils=require("seq_utils")
local Performance=require("seq_performance")
local Scene=require("seq_scene")
local Probability=require("seq_probability")
function Engine.tick(engine)
    if not engine.running then
        return {}
    end

    engine.pulseCount = engine.pulseCount + 1

    local shouldHoldSwing
    shouldHoldSwing, engine.swingCarry = Performance.nextSwingHold(
        engine.pulseCount,
        engine.pulsesPerBeat,
        engine.swingPercent,
        engine.swingCarry
    )

    if shouldHoldSwing then
        return {}
    end

    local events = {}

    for trackIndex = 1, engine.trackCount do
        Engine._engineAdvanceTrack(engine, trackIndex, events)
    end

    Engine._engineTickSceneChain(engine)

    return events
end
