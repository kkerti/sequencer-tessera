-- tests/tui.lua
-- Behavioural tests for tui.lua.

require("authoring")
local Engine = require("sequencer").Engine
local Track  = require("sequencer").Track
local Step   = require("sequencer").Step
local Tui    = require("tui")

local engine = Engine.new(120, 4, 1, 0)
local track = Engine.getTrack(engine, 1)

Track.addPattern(track, 4)
Track.setStep(track, 1, Step.new(60, 100, 4, 3))
Track.setStep(track, 2, Step.new(51, 90, 2, 1))
Track.setStep(track, 3, Step.new(48, 80, 4, 0))
Track.setStep(track, 4, Step.new(55, 100, 0, 0))
Track.setLoopStart(track, 1)
Track.setLoopEnd(track, 4)

local events = {
    { type = "NOTE_ON", pitch = 60, velocity = 100, channel = 1 },
    { type = "NOTE_OFF", pitch = 60, velocity = 0, channel = 1 },
}

local frame = Tui.render(engine, 4, events)

assert(type(frame) == "string" and #frame > 0, "tuiRender should return non-empty string")
assert(frame:find("%[BEAT:1 PULSE:4 BPM:120 PPB:4%]"), "header should include beat/pulse/bpm/ppb")
assert(frame:find("EVENTS total:2"), "frame should contain event total")
assert(frame:find("EVT TRK 1 NOTE_ON C4 v100 %| NOTE_OFF C4"), "frame should contain per-track event trace")
assert(frame:find("TRK 1"), "frame should contain track row")
assert(frame:find("ch:1"), "frame should contain MIDI channel")
assert(frame:find("dir:forward"), "frame should contain direction info")
assert(frame:find("loop:%[1%.%.4%]"), "frame should contain loop range")
assert(frame:find("%*C4"), "active step marker should be present on first step")
assert(frame:find("Eb3"), "render should include pitch names")
assert(frame:find("C3"), "render should include lower octave pitch names")
assert(frame:find("SKIP"), "render should include skip step marker")

local tickLine = Tui.renderTickTrace(engine, 4, events)
assert(tickLine:find("%[TICK pulse:4%]"), "tick trace should include pulse marker")
assert(tickLine:find("T1@1/p0"), "tick trace should include cursor token")
assert(tickLine:find("NOTE_ON:C4"), "tick trace should include event token")

print("tests/tui.lua OK")
