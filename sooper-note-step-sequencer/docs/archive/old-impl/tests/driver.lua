-- tests/driver.lua
-- Behavioural tests for driver/driver.lua.
-- Run with: lua tests/driver.lua

local Driver        = require("sequencer").Driver
local PatchLoader   = require("sequencer").PatchLoader
local Engine        = require("sequencer").Engine
local Track         = require("sequencer").Track
local Step          = require("sequencer").Step

-- Helper: collects emitted events.
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
    local descriptor = {
        bpm = 120, ppb = 4,
        tracks = {
            { channel = 1, direction = "forward", clockDiv = 1, clockMult = 1,
              patterns = { { name = "A", steps = { {60,100,4,2} } } } },
        },
    }
    local engine = PatchLoader.build(descriptor)
    local d      = Driver.new(engine)
    assert(d.bpm == 120, "bpm should default from engine")
    assert(d.pulseMs == 125, "pulseMs at 120 bpm / 4 ppb should be 125")
    assert(d.running == false, "driver should start stopped")
    assert(#d.translators == 1, "one translator per track")
end

-- ---------------------------------------------------------------------------
-- externalPulse drives the engine and emits NOTE_ON / NOTE_OFF
-- ---------------------------------------------------------------------------

do
    -- Single track, single 4-step pattern, every step dur=4 gate=2 → HIGH HIGH LOW LOW.
    local descriptor = {
        bpm = 120, ppb = 4,
        tracks = {
            { channel = 5, direction = "forward", clockDiv = 1, clockMult = 1,
              patterns = { { name = "A", steps = {
                {60, 100, 4, 2},
                {62, 110, 4, 2},
                {64, 120, 4, 2},
                {65,  90, 4, 2},
              } } },
            },
        },
    }
    local engine = PatchLoader.build(descriptor)
    local d      = Driver.new(engine)
    local events, emit = makeEmitter()

    -- externalPulse without start should be a no-op.
    Driver.externalPulse(d, emit)
    assert(#events == 0, "externalPulse before start should emit nothing")

    Driver.start(d)
    -- 16 pulses = 4 steps × dur 4 → 4 NOTE_ON + 4 NOTE_OFF
    for _ = 1, 16 do Driver.externalPulse(d, emit) end

    assert(#events == 8, "expected 8 events across 16 pulses, got " .. #events)
    assert(events[1].kind == "NOTE_ON"  and events[1].pitch == 60 and events[1].velocity == 100 and events[1].channel == 5)
    assert(events[2].kind == "NOTE_OFF" and events[2].pitch == 60 and events[2].channel == 5)
    assert(events[3].kind == "NOTE_ON"  and events[3].pitch == 62 and events[3].velocity == 110)
    assert(events[4].kind == "NOTE_OFF" and events[4].pitch == 62)
    assert(events[5].kind == "NOTE_ON"  and events[5].pitch == 64)
    assert(events[7].kind == "NOTE_ON"  and events[7].pitch == 65)
    assert(events[8].kind == "NOTE_OFF" and events[8].pitch == 65)
end

-- ---------------------------------------------------------------------------
-- Multi-track: each track emits on its own channel
-- ---------------------------------------------------------------------------

do
    local descriptor = {
        bpm = 120, ppb = 4,
        tracks = {
            { channel = 1, direction = "forward", clockDiv = 1, clockMult = 1,
              patterns = { { name = "A", steps = { {60,100,2,1} } } } },
            { channel = 10, direction = "forward", clockDiv = 1, clockMult = 1,
              patterns = { { name = "B", steps = { {36,110,2,1} } } } },
        },
    }
    local engine = PatchLoader.build(descriptor)
    local d      = Driver.new(engine)
    local events, emit = makeEmitter()

    Driver.start(d)
    -- 2 pulses: pulse 0 of each track sees rising edge; pulse 1 sees falling edge.
    Driver.externalPulse(d, emit)
    Driver.externalPulse(d, emit)

    -- Expect 4 events: t1 ON ch1, t2 ON ch10, t1 OFF ch1, t2 OFF ch10.
    assert(#events == 4, "expected 4 events across 2 pulses, got " .. #events)
    -- Track 1 fires before track 2 in driver loop order.
    assert(events[1].channel == 1  and events[1].pitch == 60 and events[1].kind == "NOTE_ON")
    assert(events[2].channel == 10 and events[2].pitch == 36 and events[2].kind == "NOTE_ON")
    assert(events[3].channel == 1  and events[3].pitch == 60 and events[3].kind == "NOTE_OFF")
    assert(events[4].channel == 10 and events[4].pitch == 36 and events[4].kind == "NOTE_OFF")
end

-- ---------------------------------------------------------------------------
-- allNotesOff emits NOTE_OFF for held notes per track
-- ---------------------------------------------------------------------------

do
    local descriptor = {
        bpm = 120, ppb = 4,
        tracks = {
            { channel = 1, direction = "forward", clockDiv = 1, clockMult = 1,
              patterns = { { name = "A", steps = { {60,100,8,8} } } } },
            { channel = 2, direction = "forward", clockDiv = 1, clockMult = 1,
              patterns = { { name = "B", steps = { {72,90,8,8} } } } },
        },
    }
    local engine = PatchLoader.build(descriptor)
    local d      = Driver.new(engine)
    local events, emit = makeEmitter()

    Driver.start(d)
    Driver.externalPulse(d, emit)  -- both tracks: NOTE_ON, gate stays HIGH
    assert(#events == 2)

    local panicEvents, panicEmit = makeEmitter()
    Driver.allNotesOff(d, panicEmit)
    assert(#panicEvents == 2, "panic should emit NOTE_OFF for both held tracks")
    assert(panicEvents[1].kind == "NOTE_OFF" and panicEvents[1].pitch == 60 and panicEvents[1].channel == 1)
    assert(panicEvents[2].kind == "NOTE_OFF" and panicEvents[2].pitch == 72 and panicEvents[2].channel == 2)
end

-- ---------------------------------------------------------------------------
-- Internal-clock tick fires the right number of pulses
-- ---------------------------------------------------------------------------

do
    local descriptor = {
        bpm = 120, ppb = 4,  -- pulseMs = 125
        tracks = {
            { channel = 1, direction = "forward", clockDiv = 1, clockMult = 1,
              patterns = { { name = "A", steps = { {60,100,4,2} } } } },
        },
    }
    local engine = PatchLoader.build(descriptor)
    local now    = 0
    local d      = Driver.new(engine, function() return now end)
    local events, emit = makeEmitter()

    Driver.start(d)
    -- 0 ms elapsed: no pulses.
    Driver.tick(d, emit)
    assert(d.pulseCount == 0)

    -- 250 ms elapsed → 2 pulses (target = floor(250 / 125) = 2).
    now = 250
    Driver.tick(d, emit)
    assert(d.pulseCount == 2, "expected 2 pulses at 250ms, got " .. d.pulseCount)

    -- Single 1-step dur=4 gate=2 pattern: pulse 0 NOTE_ON, pulse 1 still HIGH (no event),
    -- so we expect exactly 1 event after 2 pulses.
    assert(#events == 1 and events[1].kind == "NOTE_ON" and events[1].pitch == 60,
        "expected exactly NOTE_ON 60 after 2 pulses")
end

-- ---------------------------------------------------------------------------
-- setBpm preserves position and updates pulseMs
-- ---------------------------------------------------------------------------

do
    local descriptor = {
        bpm = 120, ppb = 4,
        tracks = {
            { channel = 1, direction = "forward", clockDiv = 1, clockMult = 1,
              patterns = { { name = "A", steps = { {60,100,4,2} } } } },
        },
    }
    local engine = PatchLoader.build(descriptor)
    local now    = 0
    local d      = Driver.new(engine, function() return now end)

    Driver.start(d)
    now = 250
    local _, emit = makeEmitter()
    Driver.tick(d, emit)
    assert(d.pulseCount == 2, "should be 2 pulses in")

    -- Switch to 60 bpm: pulseMs becomes 250.
    Driver.setBpm(d, 60)
    assert(d.pulseMs == 250)
    -- pulseCount preserved.
    assert(d.pulseCount == 2)
end

print("driver: all tests passed")
