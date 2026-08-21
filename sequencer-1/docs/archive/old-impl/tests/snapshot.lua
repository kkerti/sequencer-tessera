-- tests/snapshot.lua
-- Behavioural tests for sequencer/snapshot.lua.

require("authoring")
local Engine = require("sequencer").Engine
local Track = require("sequencer").Track
local Step = require("sequencer").Step
local Snapshot = require("snapshot")

local filePath = "/tmp/sequencer_snapshot_test.lua"

do
    local e = Engine.new(123, 4, 2, 0)

    local t1 = Engine.getTrack(e, 1)
    Track.addPattern(t1, 2)
    Track.addPattern(t1, 2)
    Track.setStep(t1, 1, Step.new(60, 100, 4, 2, true))
    Track.setStep(t1, 2, Step.new(62, 90, 4, 2, false))
    Track.setStep(t1, 3, Step.new(64, 80, 4, 0, false, 50))  -- probability = 50
    Track.setStep(t1, 4, Step.new(65, 70, 0, 0, false, 0))   -- probability = 0
    Track.setLoopStart(t1, 2)
    Track.setLoopEnd(t1, 4)
    Track.setDirection(t1, "pingpong")
    Track.setMidiChannel(t1, 9)

    local t2 = Engine.getTrack(e, 2)
    Track.addPattern(t2, 1)
    Track.setStep(t2, 1, Step.new(48, 100, 4, 3, false))

    Snapshot.saveToFile(e, filePath)
    local loaded = Snapshot.loadFromFile(filePath)

    assert(loaded.bpm == 123)
    assert(loaded.trackCount == 2)

    local lt1 = Engine.getTrack(loaded, 1)
    assert(Track.getPatternCount(lt1) == 2)
    assert(Track.getLoopStart(lt1) == 2)
    assert(Track.getLoopEnd(lt1) == 4)
    assert(Track.getDirection(lt1) == "pingpong")
    assert(Track.getMidiChannel(lt1) == 9)
    assert(Step.getRatch(Track.getStep(lt1, 1)) == true)
    assert(Step.getProbability(Track.getStep(lt1, 1)) == 100)  -- default
    assert(Step.getProbability(Track.getStep(lt1, 3)) == 50)    -- explicit 50
    assert(Step.getProbability(Track.getStep(lt1, 4)) == 0)     -- explicit 0
    assert(Step.getDuration(Track.getStep(lt1, 4)) == 0)

    local lt2 = Engine.getTrack(loaded, 2)
    assert(Track.getPatternCount(lt2) == 1)
    assert(Step.getPitch(Track.getStep(lt2, 1)) == 48)
    assert(Step.getProbability(Track.getStep(lt2, 1)) == 100)   -- default
end

os.remove(filePath)
print("tests/snapshot.lua OK")
