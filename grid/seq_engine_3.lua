local Engine=require("seq_engine")
local Track=require("seq_track")
local Step=require("seq_step")
local Utils=require("seq_utils")
local Performance=require("seq_performance")
local Scene=require("seq_scene")
local Probability=require("seq_probability")
function Engine._engineHandleNoteOff(engine, trackIndex, step, events)
    if engine.probSuppressed[trackIndex] then
        engine.probSuppressed[trackIndex] = false
        return
    end
    local channel = engine.tracks[trackIndex].midiChannel or trackIndex
    local pitch   = Step.resolvePitch(step, engine.scaleTable, engine.rootNote)
    local key     = Engine._noteKey(pitch, channel)
    engine.activeNotes[key] = nil
    events[#events + 1] = {
        type     = "NOTE_OFF",
        pitch    = pitch,
        velocity = 0,
        channel  = channel,
    }
end
