local Engine=require("seq_engine")
local Track=require("seq_track")
local Step=require("seq_step")
local Utils=require("seq_utils")
local Performance=require("seq_performance")
local Scene=require("seq_scene")
local Probability=require("seq_probability")
function Engine.reset(engine)
    local events = Engine.allNotesOff(engine)
    engine.pulseCount = 0
    engine.swingCarry = 0
    engine.running    = true
    for i = 1, engine.trackCount do
        Track.reset(engine.tracks[i])
        engine.probSuppressed[i] = false
    end
    Engine._engineResetSceneChain(engine)
    return events
end
function Engine.stop(engine)
    local events = Engine.allNotesOff(engine)
    engine.running = false
    return events
end
function Engine.start(engine)
    engine.running = true
end
