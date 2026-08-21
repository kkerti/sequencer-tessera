-- tests/midi_translate.lua
-- Behavioural tests for sequencer/midi_translate.lua.
-- Run with: lua tests/midi_translate.lua

require("authoring")
local MidiTranslate = require("sequencer").MidiTranslate

-- Helper: collects emitted events into a flat array.
local function makeEmitter()
    local events = {}
    local function emit(kind, pitch, velocity, channel)
        events[#events + 1] = {
            kind     = kind,
            pitch    = pitch,
            velocity = velocity,
            channel  = channel,
        }
    end
    return events, emit
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

do
    local s = MidiTranslate.new()
    assert(s.prevGate == false, "fresh state should have prevGate=false")
    assert(s.lastPitch == nil, "fresh state should have lastPitch=nil")
end

-- ---------------------------------------------------------------------------
-- Rising edge → NOTE_ON
-- ---------------------------------------------------------------------------

do
    local s = MidiTranslate.new()
    local events, emit = makeEmitter()

    MidiTranslate.step(s, 60, 100, true, 1, emit)
    assert(#events == 1, "rising edge should emit one event")
    assert(events[1].kind == "NOTE_ON")
    assert(events[1].pitch == 60)
    assert(events[1].velocity == 100)
    assert(events[1].channel == 1)
    assert(s.lastPitch == 60, "lastPitch should be tracked")
    assert(s.prevGate == true)
end

-- ---------------------------------------------------------------------------
-- Held gate at same pitch emits nothing further
-- ---------------------------------------------------------------------------

do
    local s = MidiTranslate.new()
    local events, emit = makeEmitter()

    MidiTranslate.step(s, 60, 100, true, 1, emit)
    MidiTranslate.step(s, 60, 100, true, 1, emit)
    MidiTranslate.step(s, 60, 100, true, 1, emit)
    assert(#events == 1, "holding gate HIGH at same pitch should emit only the initial NOTE_ON")
end

-- ---------------------------------------------------------------------------
-- Falling edge → NOTE_OFF on the held pitch
-- ---------------------------------------------------------------------------

do
    local s = MidiTranslate.new()
    local events, emit = makeEmitter()

    MidiTranslate.step(s, 60, 100, true,  1, emit)
    MidiTranslate.step(s, 60, 100, false, 1, emit)
    assert(#events == 2, "falling edge should emit a NOTE_OFF after the NOTE_ON")
    assert(events[2].kind == "NOTE_OFF")
    assert(events[2].pitch == 60, "NOTE_OFF should target the previously held pitch")
    assert(events[2].velocity == nil)
    assert(s.lastPitch == nil)
    assert(s.prevGate == false)
end

-- ---------------------------------------------------------------------------
-- Pitch change mid-gate → retrigger (OFF old, ON new)
-- ---------------------------------------------------------------------------

do
    local s = MidiTranslate.new()
    local events, emit = makeEmitter()

    MidiTranslate.step(s, 60, 100, true, 1, emit)
    MidiTranslate.step(s, 64, 110, true, 1, emit)
    assert(#events == 3,
        "pitch change mid-gate should produce NOTE_ON + NOTE_OFF + NOTE_ON")
    assert(events[2].kind == "NOTE_OFF" and events[2].pitch == 60,
        "second event should be NOTE_OFF on the old pitch")
    assert(events[3].kind == "NOTE_ON" and events[3].pitch == 64 and events[3].velocity == 110,
        "third event should be NOTE_ON on the new pitch")
    assert(s.lastPitch == 64)
end

-- ---------------------------------------------------------------------------
-- Gate stays LOW: nothing
-- ---------------------------------------------------------------------------

do
    local s = MidiTranslate.new()
    local events, emit = makeEmitter()

    MidiTranslate.step(s, 60, 100, false, 1, emit)
    MidiTranslate.step(s, 64, 100, false, 1, emit)
    assert(#events == 0, "gate LOW with no prior NOTE_ON should emit nothing")
end

-- ---------------------------------------------------------------------------
-- Channel propagation
-- ---------------------------------------------------------------------------

do
    local s = MidiTranslate.new()
    local events, emit = makeEmitter()

    MidiTranslate.step(s, 72, 90, true,  10, emit)
    MidiTranslate.step(s, 72, 90, false, 10, emit)
    assert(events[1].channel == 10 and events[2].channel == 10,
        "channel should be passed through to both NOTE_ON and NOTE_OFF")
end

-- ---------------------------------------------------------------------------
-- Panic emits NOTE_OFF when a note is held; clears state
-- ---------------------------------------------------------------------------

do
    local s = MidiTranslate.new()
    local events, emit = makeEmitter()

    MidiTranslate.step(s, 60, 100, true, 1, emit)
    MidiTranslate.panic(s, 1, emit)
    assert(#events == 2, "panic should emit NOTE_OFF when a note is held")
    assert(events[2].kind == "NOTE_OFF" and events[2].pitch == 60)
    assert(s.prevGate == false and s.lastPitch == nil)
end

-- Panic with no held note is a no-op.
do
    local s = MidiTranslate.new()
    local events, emit = makeEmitter()
    MidiTranslate.panic(s, 1, emit)
    assert(#events == 0, "panic with no held note should emit nothing")
end

-- ---------------------------------------------------------------------------
-- Full integration: a 4-pulse step (gate=2 dur=4) drives the translator
-- ---------------------------------------------------------------------------

do
    local Step = require("sequencer").Step
    local s    = MidiTranslate.new()
    local events, emit = makeEmitter()

    local step = Step.new(60, 100, 4, 2)
    for pulse = 0, 3 do
        local cvA, cvB = Step.sampleCv(step)
        local gate     = Step.sampleGate(step, pulse)
        MidiTranslate.step(s, cvA, cvB, gate, 1, emit)
    end

    assert(#events == 2, "gate=2 dur=4 should produce NOTE_ON + NOTE_OFF (and stay quiet)")
    assert(events[1].kind == "NOTE_ON"  and events[1].pitch == 60)
    assert(events[2].kind == "NOTE_OFF" and events[2].pitch == 60)
end

print("midi_translate: all tests passed")
