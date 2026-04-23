-- tests/player.lua
-- Static analysis tests for player/player.lua.
-- No audio, no timer, no bridge — all assertions are deterministic.
-- Run with: lua tests/player.lua

local Engine = require("sequencer/engine")
local Player = require("player/player")
local Track  = require("sequencer/track")
local Step   = require("sequencer/step")

-- ---------------------------------------------------------------------------
-- Helper: run N ticks collecting all emitted events into a flat list.
-- Returns the event list.
local function runTicks(player, n)
    local events = {}
    for _ = 1, n do
        Player.tick(player, function(ev)
            events[#events + 1] = ev
        end)
    end
    return events
end

-- Fake clock: always returns 0. Tests that need expiry force off_at manually.
local function fakeClock() return 0 end

-- Helper: build a fresh engine + player with a single track and given steps.
-- steps is an array of Step tables (index 1..n).
local function makePlayer(steps, bpm)
    bpm = bpm or 120
    local engine = Engine.new(bpm, 4, 1, #steps)
    local track  = Engine.getTrack(engine, 1)
    for i, s in ipairs(steps) do
        Track.setStep(track, i, s)
    end
    local player = Player.new(engine, bpm, fakeClock)
    Player.start(player)
    return player, engine
end

-- ---------------------------------------------------------------------------
-- ── Construction ────────────────────────────────────────────────────────────

do
    local engine = Engine.new(120, 4, 1, 1)
    local player = Player.new(engine, 120, fakeClock)
    assert(player.bpm            == 120,  "bpm should be 120")
    assert(player.pulseIntervalMs == 125, "interval should be 125ms")
    assert(player.swingPercent   == 50,   "default swing 50")
    assert(player.running        == false, "player starts stopped")
    assert(player.activeNoteCount == 0,   "no active notes at start")
end

-- ── setBpm ───────────────────────────────────────────────────────────────────

do
    local engine = Engine.new(120, 4, 1, 1)
    local player = Player.new(engine, 120, fakeClock)
    Player.setBpm(player, 60)
    assert(player.bpm             == 60,  "bpm updated")
    assert(player.pulseIntervalMs == 250, "interval recalculated")
end

-- ── NOTE_ON emitted on pulse 0 of a playable step ────────────────────────────

do
    local player = makePlayer({ Step.new(60, 100, 4, 2) })
    local events = runTicks(player, 1)
    assert(#events == 1,                   "one event on pulse 0")
    assert(events[1].type    == "NOTE_ON", "should be NOTE_ON")
    assert(events[1].pitch   == 60,        "pitch 60")
    assert(events[1].velocity == 100,      "velocity 100")
    assert(events[1].channel == 1,         "default channel = trackIndex = 1")
end

-- ── NOTE_OFF emitted via wall-clock (off_at) not pulse counter ───────────────
-- We cannot truly test wall-clock expiry in a synchronous test, but we can
-- verify that after enough ticks for the gate to expire in real time,
-- a NOTE_OFF is emitted.  We force this by manipulating off_at directly.

do
    local player = makePlayer({ Step.new(60, 100, 4, 2) })

    -- Tick once: NOTE_ON registered.
    local ev1 = {}
    Player.tick(player, function(ev) ev1[#ev1 + 1] = ev end)
    assert(#ev1 == 1 and ev1[1].type == "NOTE_ON", "NOTE_ON on tick 1")
    assert(player.activeNoteCount == 1, "note registered in active arrays")

    -- Force off_at to the past so the next tick flushes it.
    player.activeNoteOffAt[1] = -1

    local ev2 = {}
    Player.tick(player, function(ev) ev2[#ev2 + 1] = ev end)

    -- The flush happens at the start of the tick; there may also be a new
    -- NOTE_ON from advancing the cursor (step loops). Filter by type.
    local noteOffs = {}
    for _, ev in ipairs(ev2) do
        if ev.type == "NOTE_OFF" then noteOffs[#noteOffs + 1] = ev end
    end
    assert(#noteOffs == 1,                    "one NOTE_OFF emitted after off_at expires")
    assert(noteOffs[1].pitch   == 60,         "NOTE_OFF pitch 60")
    assert(noteOffs[1].channel == 1,          "NOTE_OFF channel 1")
    assert(player.activeNoteCount == 0 or
        player.activeNoteCount == 1,          -- re-registered if cursor looped
        "active note count consistent")
end

-- ── activeNoteCount tracks multiple simultaneous notes ───────────────────────

do
    local engine = Engine.new(120, 4, 2, 1)
    local t1 = Engine.getTrack(engine, 1)
    local t2 = Engine.getTrack(engine, 2)
    Track.setStep(t1, 1, Step.new(60, 100, 4, 3))
    Track.setStep(t2, 1, Step.new(72, 100, 4, 3))
    Track.setMidiChannel(t1, 1)
    Track.setMidiChannel(t2, 2)

    local player = Player.new(engine, 120, fakeClock)
    Player.start(player)

    runTicks(player, 1)
    assert(player.activeNoteCount == 2, "two notes should be active after tick 1")
end

-- ── allNotesOff clears active arrays and returns NOTE_OFF events ──────────────

do
    local player = makePlayer({ Step.new(60, 100, 4, 3) })
    runTicks(player, 1)
    assert(player.activeNoteCount == 1, "one active note before allNotesOff")

    local offEvents = Player.allNotesOff(player)
    assert(#offEvents == 1,                     "one NOTE_OFF returned")
    assert(offEvents[1].type  == "NOTE_OFF",    "event type")
    assert(offEvents[1].pitch == 60,            "event pitch")
    assert(player.activeNoteCount == 0,         "active arrays cleared")
    assert(player.activeNoteKeys[1]  == nil,    "key slot nil")
    assert(player.activeNoteOffAt[1] == nil,    "offAt slot nil")
end

-- ── allNotesOff on empty player returns empty list ────────────────────────────

do
    local engine = Engine.new(120, 4, 1, 1)
    local player = Player.new(engine, 120, fakeClock)
    local evs = Player.allNotesOff(player)
    assert(#evs == 0, "allNotesOff on empty player returns nothing")
end

-- ── Player.stop halts cursor advancement ─────────────────────────────────────

do
    local player, engine = makePlayer({ Step.new(60, 100, 4, 2) })
    runTicks(player, 1)               -- NOTE_ON
    Player.stop(player)
    local evs = runTicks(player, 4)  -- should produce nothing (player halted)
    local noteOns = {}
    for _, ev in ipairs(evs) do
        if ev.type == "NOTE_ON" then noteOns[#noteOns + 1] = ev end
    end
    assert(#noteOns == 0, "no new NOTE_ONs after stop")
end

-- ── Player.start resumes after stop ──────────────────────────────────────────

do
    local player = makePlayer({ Step.new(60, 100, 4, 2) })
    Player.stop(player)
    Player.start(player)
    assert(player.running == true, "running after start")
    local evs = runTicks(player, 1)
    assert(#evs >= 1, "events produced after start")
end

-- ── Probability suppression: 0% never fires ──────────────────────────────────

do
    local s = Step.new(60, 100, 4, 2)
    Step.setProbability(s, 0)
    local player = makePlayer({ s })
    local evs = runTicks(player, 4)
    local noteOns = {}
    for _, ev in ipairs(evs) do
        if ev.type == "NOTE_ON" then noteOns[#noteOns + 1] = ev end
    end
    assert(#noteOns == 0, "probability=0 should suppress all NOTE_ONs")
end

-- ── Scale quantization applied at player output ───────────────────────────────
-- Pitch 61 (C#4) should quantize to 60 (C4) in C major.

do
    local engine = Engine.new(120, 4, 1, 1)
    local track  = Engine.getTrack(engine, 1)
    Track.setStep(track, 1, Step.new(61, 100, 1, 1))

    local player = Player.new(engine, 120, fakeClock)
    Player.setScale(player, "major", 0)
    Player.start(player)

    local events = {}
    Player.tick(player, function(ev) events[#events + 1] = ev end)
    local noteOns = {}
    for _, ev in ipairs(events) do
        if ev.type == "NOTE_ON" then noteOns[#noteOns + 1] = ev end
    end
    assert(#noteOns == 1,          "one NOTE_ON")
    assert(noteOns[1].pitch == 60, "61 quantized to 60 in C major")
end

-- ── MIDI channel: track override takes priority over trackIndex ───────────────

do
    local engine = Engine.new(120, 4, 1, 1)
    local track  = Engine.getTrack(engine, 1)
    Track.setStep(track, 1, Step.new(60, 100, 1, 1))
    Track.setMidiChannel(track, 10)

    local player = Player.new(engine, 120, fakeClock)
    Player.start(player)

    local events = {}
    Player.tick(player, function(ev) events[#events + 1] = ev end)
    assert(events[1].channel == 10, "midiChannel override should be 10")
end

-- ── Clock division: div=2 advances once every 2 ticks ────────────────────────

do
    local engine = Engine.new(120, 4, 1, 2)
    local track  = Engine.getTrack(engine, 1)
    Track.setStep(track, 1, Step.new(60, 100, 1, 1))
    Track.setStep(track, 2, Step.new(62, 100, 1, 1))
    Track.setClockDiv(track, 2)

    local player = Player.new(engine, 120, fakeClock)
    Player.start(player)

    local ev1 = {}
    Player.tick(player, function(ev) ev1[#ev1 + 1] = ev end)
    assert(#ev1 == 0, "div=2: no event on first tick")

    local ev2 = {}
    Player.tick(player, function(ev) ev2[#ev2 + 1] = ev end)
    local noteOns = {}
    for _, ev in ipairs(ev2) do
        if ev.type == "NOTE_ON" then noteOns[#noteOns + 1] = ev end
    end
    assert(#noteOns == 1 and noteOns[1].pitch == 60,
        "div=2: NOTE_ON on second tick")
end

-- ── Clock multiplication: mult=2 advances twice per tick ─────────────────────

do
    local engine = Engine.new(120, 4, 1, 2)
    local track  = Engine.getTrack(engine, 1)
    Track.setStep(track, 1, Step.new(60, 100, 1, 1))
    Track.setStep(track, 2, Step.new(62, 100, 1, 1))
    Track.setClockMult(track, 2)

    local player = Player.new(engine, 120, fakeClock)
    Player.start(player)

    local evs = {}
    Player.tick(player, function(ev) evs[#evs + 1] = ev end)
    local noteOns = {}
    for _, ev in ipairs(evs) do
        if ev.type == "NOTE_ON" then noteOns[#noteOns + 1] = ev end
    end
    assert(#noteOns == 2, "mult=2: two NOTE_ONs in one tick")
    assert(noteOns[1].pitch == 60 and noteOns[2].pitch == 62,
        "mult=2: both steps advanced")
end

-- ── Swing holds off-beat pulses ───────────────────────────────────────────────

do
    local player = makePlayer({ Step.new(60, 100, 1, 1) })
    Player.setSwing(player, 72)

    local ev1 = {}
    Player.tick(player, function(ev) ev1[#ev1 + 1] = ev end)
    local ev1noteOns = {}
    for _, ev in ipairs(ev1) do
        if ev.type == "NOTE_ON" then ev1noteOns[#ev1noteOns + 1] = ev end
    end
    assert(#ev1noteOns == 1, "swing: beat-1 (downbeat) fires normally")

    local ev2 = {}
    Player.tick(player, function(ev) ev2[#ev2 + 1] = ev end)
    local ev2noteOns = {}
    for _, ev in ipairs(ev2) do
        if ev.type == "NOTE_ON" then ev2noteOns[#ev2noteOns + 1] = ev end
    end
    assert(#ev2noteOns == 0, "swing: off-beat pulse held (no NOTE_ON)")
end

-- ── No per-tick table allocation: emit callback pattern ──────────────────────
-- Verify tick accepts a callback (not returning a table).

do
    local player = makePlayer({ Step.new(60, 100, 4, 2) })
    local called = 0
    Player.tick(player, function(_) called = called + 1 end)
    assert(called >= 1, "emit callback should be called at least once")
end

print("player: all tests passed")
