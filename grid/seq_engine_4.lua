local Engine=require("seq_engine")
local Track=require("seq_track")
local Step=require("seq_step")
local Utils=require("seq_utils")
local Performance=require("seq_performance")
local Scene=require("seq_scene")
local Probability=require("seq_probability")
function Engine._engineProcessTrackEvent(engine, trackIndex, step, event, events)
    if event == "NOTE_ON" then
        Engine._engineHandleNoteOn(engine, trackIndex, step, events)
    elseif event == "NOTE_OFF" then
        Engine._engineHandleNoteOff(engine, trackIndex, step, events)
    end
