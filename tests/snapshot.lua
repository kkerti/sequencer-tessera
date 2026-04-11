-- tests/snapshot.lua
-- Behavioural tests for sequencer/snapshot.lua.

local Engine = require("sequencer/engine")
local Track = require("sequencer/track")
local Step = require("sequencer/step")
local Snapshot = require("sequencer/snapshot")

local filePath = "/tmp/sequencer_snapshot_test.lua"

do
    local e = Engine.new(123, 4, 2, 0)
    Engine.setSwing(e, 60)
    Engine.setScale(e, "major", 0)

    local t1 = Engine.getTrack(e, 1)
    Track.addPattern(t1, 2)
    Track.addPattern(t1, 2)
    Track.setStep(t1, 1, Step.new(60, 100, 4, 2, 2))
    Track.setStep(t1, 2, Step.new(62, 90, 4, 2, 1))
    Track.setStep(t1, 3, Step.new(64, 80, 4, 0, 1))
    Track.setStep(t1, 4, Step.new(65, 70, 0, 0, 1))
    Track.setLoopStart(t1, 2)
    Track.setLoopEnd(t1, 4)
    Track.setDirection(t1, "pingpong")
    Track.setMidiChannel(t1, 9)

    local t2 = Engine.getTrack(e, 2)
    Track.addPattern(t2, 1)
    Track.setStep(t2, 1, Step.new(48, 100, 4, 3, 1))

    Snapshot.saveToFile(e, filePath)
    local loaded = Snapshot.loadFromFile(filePath)

    assert(loaded.bpm == 123)
    assert(loaded.trackCount == 2)
    assert(loaded.swingPercent == 60)
    assert(loaded.scaleName == "major")

    local lt1 = Engine.getTrack(loaded, 1)
    assert(Track.getPatternCount(lt1) == 2)
    assert(Track.getLoopStart(lt1) == 2)
    assert(Track.getLoopEnd(lt1) == 4)
    assert(Track.getDirection(lt1) == "pingpong")
    assert(Track.getMidiChannel(lt1) == 9)
    assert(Track.getStep(lt1, 1).ratchet == 2)
    assert(Track.getStep(lt1, 4).duration == 0)

    local lt2 = Engine.getTrack(loaded, 2)
    assert(Track.getPatternCount(lt2) == 1)
    assert(Track.getStep(lt2, 1).pitch == 48)
end

os.remove(filePath)
print("tests/snapshot.lua OK")
