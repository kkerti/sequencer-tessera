-- tests/player_lite.lua
-- Tests for player_lite/player.lua — the precompiled-song walker.
-- Covers internal-clock (Player.tick) and external-clock (Player.externalPulse)
-- modes, transport, loop wrap, NOTE_OFF flush, allNotesOff.
-- Run with: lua tests/player_lite.lua

local Player = require("player_lite/player")

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Builds a minimal compiled song.  `events` is { {atPulse, pitch, vel, ch, gate, prob}, ... }
local function makeSong(events, durationPulses, loop, ppb)
    local song = {
        bpm            = 120,
        pulsesPerBeat  = ppb or 4,
        durationPulses = durationPulses,
        loop           = (loop ~= false),
        eventCount     = #events,
        atPulse        = {},
        pitch          = {},
        velocity       = {},
        channel        = {},
        gatePulses     = {},
        probability    = {},
    }
    for i, e in ipairs(events) do
        song.atPulse[i]     = e[1]
        song.pitch[i]       = e[2]
        song.velocity[i]    = e[3]
        song.channel[i]     = e[4]
        song.gatePulses[i]  = e[5]
        song.probability[i] = e[6] or 100
    end
    return song
end

local function recordEmit()
    local events = {}
    return events, function(t, p, v, c)
        events[#events + 1] = { type = t, pitch = p, velocity = v, channel = c }
    end
end

-- ---------------------------------------------------------------------------
-- ── Construction ────────────────────────────────────────────────────────────

do
    local song = makeSong({ { 0, 60, 100, 1, 4, 100 } }, 16, true)
    local p = Player.new(song, function() return 0 end, 120)
    assert(p.bpm        == 120, "bpm")
    assert(p.pulseMs    == 125, "pulseMs = 60000/120/4 = 125")
    assert(p.pulseCount == 0,   "pulseCount starts 0")
    assert(p.cursor     == 1,   "cursor starts 1")
    assert(p.running    == false, "starts stopped")
end

-- ── externalPulse: NOTE_ON fires at atPulse, NOTE_OFF at atPulse+gate ────────

do
    -- One event: pulse 0, pitch 60, gate 4.
    local song = makeSong({ { 0, 60, 100, 1, 4, 100 } }, 16, false)
    local p = Player.new(song, nil, 120)
    Player.start(p)

    local events, emit = recordEmit()
    Player.externalPulse(p, emit)         -- pulseCount -> 1, fires event at 0
    assert(events[1].type    == "NOTE_ON", "NOTE_ON on first pulse")
    assert(events[1].pitch   == 60,        "pitch")
    assert(events[1].velocity == 100,      "velocity")
    assert(events[1].channel == 1,         "channel")
    assert(p.activeCount == 1, "one active note")

    -- Pulses 2, 3 — no NOTE_OFF yet (offPulse = 0+4 = 4).
    for _ = 2, 3 do Player.externalPulse(p, emit) end
    assert(#events == 1, "no NOTE_OFF before pulse 4")

    -- Pulse 4: pulseCount becomes 4; flush sees 4 <= 4, NOTE_OFF fires.
    Player.externalPulse(p, emit)
    assert(events[2].type    == "NOTE_OFF", "NOTE_OFF after gate")
    assert(events[2].pitch   == 60, "NOTE_OFF pitch")
    assert(events[2].channel == 1,  "NOTE_OFF channel")
    assert(p.activeCount == 0, "active list cleared")
end

-- ── externalPulse: probability 0 suppresses NOTE_ON (and no NOTE_OFF tracking) ──

do
    local song = makeSong({ { 0, 60, 100, 1, 4, 0 } }, 16, false)
    local p = Player.new(song, nil, 120)
    Player.start(p)
    local events, emit = recordEmit()
    for _ = 1, 8 do Player.externalPulse(p, emit) end
    assert(#events == 0, "probability=0 fires nothing")
    assert(p.activeCount == 0, "no active notes registered")
end

-- ── externalPulse: loop wrap rewinds cursor and pulseCount ───────────────────

do
    -- Two events at pulses 0 and 4, durationPulses 8.
    local song = makeSong({
        { 0, 60, 100, 1, 2, 100 },
        { 4, 62, 100, 1, 2, 100 },
    }, 8, true)
    local p = Player.new(song, nil, 120)
    Player.start(p)
    local events, emit = recordEmit()

    -- Advance through the loop.  After 8 pulses, both events should have fired
    -- and we should have wrapped.
    for _ = 1, 8 do Player.externalPulse(p, emit) end

    local noteOns = 0
    for _, e in ipairs(events) do
        if e.type == "NOTE_ON" then noteOns = noteOns + 1 end
    end
    assert(noteOns == 2, "two NOTE_ONs in first loop, got " .. noteOns)
    assert(p.cursor     == 1, "cursor wrapped to 1")
    assert(p.pulseCount == 0, "pulseCount wrapped to 0, got " .. p.pulseCount)

    -- Second loop should fire events again.
    for _ = 1, 8 do Player.externalPulse(p, emit) end
    local noteOns2 = 0
    for _, e in ipairs(events) do
        if e.type == "NOTE_ON" then noteOns2 = noteOns2 + 1 end
    end
    assert(noteOns2 == 4, "four total NOTE_ONs after two loops, got " .. noteOns2)
end

-- ── externalPulse: stopped player is a no-op ─────────────────────────────────

do
    local song = makeSong({ { 0, 60, 100, 1, 4, 100 } }, 16, true)
    local p = Player.new(song, nil, 120)
    -- Note: not started.
    local events, emit = recordEmit()
    Player.externalPulse(p, emit)
    assert(#events == 0, "stopped player emits nothing")
    assert(p.pulseCount == 0, "stopped player does not advance")
end

-- ── Player.start resets pulseCount and cursor ────────────────────────────────

do
    local song = makeSong({
        { 0, 60, 100, 1, 2, 100 },
        { 4, 62, 100, 1, 2, 100 },
    }, 8, true)
    local p = Player.new(song, nil, 120)
    Player.start(p)
    local events, emit = recordEmit()
    for _ = 1, 5 do Player.externalPulse(p, emit) end
    assert(p.pulseCount > 0, "advanced before restart")
    Player.start(p)
    assert(p.pulseCount == 0, "pulseCount reset")
    assert(p.cursor     == 1, "cursor reset")
    assert(p.activeCount == 0, "active notes cleared")
end

-- ── Player.tick (internal clock) drives pulses from clockFn ──────────────────

do
    local song = makeSong({
        { 0, 60, 100, 1, 2, 100 },
        { 4, 62, 100, 1, 2, 100 },
    }, 8, true)

    local nowMs = 0
    local clock = function() return nowMs end
    local p = Player.new(song, clock, 120)   -- pulseMs = 125
    Player.start(p)                          -- startMs = 0

    -- Advance wall clock by 4 pulses worth of ms = 500.
    nowMs = 500
    local events, emit = recordEmit()
    Player.tick(p, emit)
    assert(p.pulseCount == 4, "tick advanced pulseCount to 4, got " .. p.pulseCount)

    -- Both events at pulses 0 and 4 should have fired.
    local noteOns = 0
    for _, e in ipairs(events) do
        if e.type == "NOTE_ON" then noteOns = noteOns + 1 end
    end
    assert(noteOns == 2, "tick fired both events, got " .. noteOns)
end

-- ── Player.tick is a no-op when no time has passed ───────────────────────────

do
    local song = makeSong({ { 0, 60, 100, 1, 2, 100 } }, 8, true)
    local nowMs = 0
    local p = Player.new(song, function() return nowMs end, 120)
    Player.start(p)
    local events, emit = recordEmit()
    Player.tick(p, emit)
    assert(p.pulseCount == 0, "no time elapsed -> no advance")
    assert(#events == 0, "no time elapsed -> no events")
end

-- ── allNotesOff returns sounding notes and clears active list ────────────────

do
    local song = makeSong({ { 0, 60, 100, 5, 8, 100 } }, 16, true)
    local p = Player.new(song, nil, 120)
    Player.start(p)
    local _, emit = recordEmit()
    Player.externalPulse(p, emit)
    assert(p.activeCount == 1, "one active note")

    local offs = Player.allNotesOff(p)
    assert(#offs == 1, "one NOTE_OFF returned")
    assert(offs[1].type    == "NOTE_OFF", "type")
    assert(offs[1].pitch   == 60, "pitch")
    assert(offs[1].channel == 5,  "channel")
    assert(p.activeCount == 0, "active list cleared")
end

-- ── allNotesOff on idle player returns empty list ────────────────────────────

do
    local song = makeSong({ { 0, 60, 100, 1, 4, 100 } }, 16, true)
    local p = Player.new(song, nil, 120)
    local offs = Player.allNotesOff(p)
    assert(#offs == 0, "idle player -> empty NOTE_OFF list")
end

-- ── setBpm preserves pulse position (internal-clock mode) ────────────────────

do
    local song = makeSong({ { 0, 60, 100, 1, 4, 100 } }, 16, true)
    local nowMs = 0
    local p = Player.new(song, function() return nowMs end, 120)
    Player.start(p)
    nowMs = 500
    local _, emit = recordEmit()
    Player.tick(p, emit)
    assert(p.pulseCount == 4, "advanced 4 pulses")

    -- Halve BPM; pulseMs doubles to 250.  pulseCount must not jump.
    Player.setBpm(p, 60)
    assert(p.pulseMs == 250, "pulseMs recalculated")

    -- No further time elapses; tick must not advance.
    Player.tick(p, emit)
    assert(p.pulseCount == 4, "setBpm did not jump pulseCount")
end

print("player_lite: all tests passed")
