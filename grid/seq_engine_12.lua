local Engine=require("seq_engine")
local Track=require("seq_track")
local Step=require("seq_step")
local Utils=require("seq_utils")
local Performance=require("seq_performance")
local Scene=require("seq_scene")
local Probability=require("seq_probability")
function Engine.deactivateSceneChain(engine)
    local chain = engine.sceneChain
    if chain then
        Scene.chainSetActive(chain, false)
    end
end
function Engine.allNotesOff(engine)
    local events = {}
    for key, _ in pairs(engine.activeNotes) do
        local pitch, channel = key:match("^(%d+):(%d+)$")
        pitch   = tonumber(pitch)
        channel = tonumber(channel)
        events[#events + 1] = {
            type     = "NOTE_OFF",
            pitch    = pitch,
            velocity = 0,
            channel  = channel,
        }
    end
    engine.activeNotes = {}
    return events
end
