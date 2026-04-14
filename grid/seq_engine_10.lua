local Engine=require("seq_engine")
local Track=require("seq_track")
local Step=require("seq_step")
local Utils=require("seq_utils")
local Performance=require("seq_performance")
local Scene=require("seq_scene")
local Probability=require("seq_probability")
function Engine.setBpm(engine, bpm)
    engine.bpm = bpm
    engine.pulseIntervalMs = Engine.bpmToMs(bpm, engine.pulsesPerBeat)
end
function Engine.setSwing(engine, percent)
    engine.swingPercent = percent
end
function Engine.getSwing(engine)
    return engine.swingPercent
end
function Engine.setScale(engine, scaleName, rootNote)
    rootNote = rootNote or 0

    engine.scaleName = scaleName
    engine.scaleTable = Utils.SCALES[scaleName]
    engine.rootNote = rootNote
end
function Engine.clearScale(engine)
    engine.scaleName = nil
    engine.scaleTable = nil
    engine.rootNote = 0
end
