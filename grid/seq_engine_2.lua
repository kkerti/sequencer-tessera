local Engine=require("seq_engine")
local Track=require("seq_track")
local Step=require("seq_step")
local Utils=require("seq_utils")
local Performance=require("seq_performance")
local Scene=require("seq_scene")
local Probability=require("seq_probability")
function Engine._engineHandleNoteOn(engine, trackIndex, step, events)
    if not Probability.shouldPlay(step) then
        engine.probSuppressed[trackIndex] = true
        return
    end
    engine.probSuppressed[trackIndex] = false
    local channel = engine.tracks[trackIndex].midiChannel or trackIndex
    local pitch   = Step.resolvePitch(step, engine.scaleTable, engine.rootNote)
    local key     = Engine._noteKey(pitch, channel)
    engine.activeNotes[key] = true
    events[#events + 1] = {
        type     = "NOTE_ON",
        pitch    = pitch,
        velocity = Step.getVelocity(step),
        channel  = channel,
    }
end
