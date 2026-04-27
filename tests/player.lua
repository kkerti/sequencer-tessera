-- tests/player.lua
-- Tests for player/player.lua — the precompiled-song walker.
-- Schema v2: interleaved NOTE_ON+NOTE_OFF events, kind[] field, no in-player
-- probability or gate math.
-- Run with: lua tests/player.lua

local Player = require("player/player")

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Builds a minimal compiled song from a NOTE_ON spec list.
-- `notes` is { {atPulse, pitch, vel, ch, gate}, ... }. The helper auto-pairs
-- a NOTE_OFF at atPulse+gate for each note and sorts the result.
local function makeSong(notes, durationPulses, loop, ppb)
    local interleaved = {}
    for _, n in ipairs(notes) do
        interleaved[#interleaved + 1] = { at = n[1],         k = 1, pitch = n[2], vel = n[3], ch = n[4] }
        local off = n[1] + n[5]
        if off > durationPulses then off = durationPulses end
        interleaved[#interleaved + 1] = { at = off,           k = 0, pitch = n[2], vel = 0,    ch = n[4] }
    end
    table.sort(interleaved, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        return a.k < b.k
    end)

    local song = {
        bpm            = 120,
        pulsesPerBeat  = ppb or 4,
        durationPulses = durationPulses,
        loop           = (loop ~= false),
        eventCount     = #interleaved,
        atPulse        = {},
        kind           = {},
        pitch          = {},
        velocity       = {},
        channel        = {},
    }
    for i, e in ipairs(interleaved) do
        song.atPulse[i]  = e.at
        song.kind[i]     = e.k
        song.pitch[i]    = e.pitch
        song.velocity[i] = e.vel
        song.channel[i]  = e.ch
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
    local song = makeSong({ { 0, 60, 100, 1, 4 } }, 16, true)
    local p = Player.new(song, function() return 0 end, 120)
    assert(p.bpm        == 120, "bpm")
    assert(p.pulseMs    == 125, "pulseMs = 60000/120/4 = 125")
    assert(p.pulseCount == 0,   "pulseCount starts 0")
    assert(p.cursor     == 1,   "cursor starts 1")
    assert(p.running    == false, "starts stopped")
    assert(p.loopIndex  == 0,   "loopIndex starts 0")
end

-- ── externalPulse: NOTE_ON fires at atPulse, NOTE_OFF at atPulse+gate ────────

do
    -- One note: atPulse 0, gate 4.
    local song = makeSong({ { 0, 60, 100, 1, 4 } }, 16, false)
    local p = Player.new(song, nil, 120)
    Player.start(p)

    local events, emit = recordEmit()
    Player.externalPulse(p, emit)         -- pulseCount -> 1, fires NOTE_ON at 0
    assert(events[1].type    == "NOTE_ON", "NOTE_ON on first pulse")
    assert(events[1].pitch   == 60,        "pitch")
    assert(events[1].velocity == 100,      "velocity")
    assert(events[1].channel == 1,         "channel")

    -- Pulses 2, 3 — no NOTE_OFF yet (NOTE_OFF is at pulse 4).
    for _ = 2, 3 do Player.externalPulse(p, emit) end
    assert(#events == 1, "no NOTE_OFF before pulse 4")

    -- Pulse 4: NOTE_OFF fires.
    Player.externalPulse(p, emit)
    assert(events[2].type    == "NOTE_OFF", "NOTE_OFF after gate")
    assert(events[2].pitch   == 60, "NOTE_OFF pitch")
    assert(events[2].channel == 1,  "NOTE_OFF channel")
end

-- ── kind=2/3 (muted by writer) skip silently ─────────────────────────────────

do
    local song = makeSong({ { 0, 60, 100, 1, 4 } }, 16, false)
    -- Manually mute as the writer would: flip kind 1->2 and 0->3.
    song.kind[1] = 2
    song.kind[2] = 3

    local p = Player.new(song, nil, 120)
    Player.start(p)
    local events, emit = recordEmit()
    for _ = 1, 8 do Player.externalPulse(p, emit) end
    assert(#events == 0, "muted events emit nothing")
    assert(p.cursor == song.eventCount + 1, "cursor still advanced past muted")
end

-- ── externalPulse: loop wrap rewinds cursor and pulseCount ───────────────────

do
    local song = makeSong({
        { 0, 60, 100, 1, 2 },
        { 4, 62, 100, 1, 2 },
    }, 8, true)
    local p = Player.new(song, nil, 120)
    Player.start(p)
    local events, emit = recordEmit()

    for _ = 1, 8 do Player.externalPulse(p, emit) end

    local noteOns = 0
    for _, e in ipairs(events) do
        if e.type == "NOTE_ON" then noteOns = noteOns + 1 end
    end
    assert(noteOns == 2, "two NOTE_ONs in first loop, got " .. noteOns)
    assert(p.cursor     == 1, "cursor wrapped to 1")
    assert(p.pulseCount == 0, "pulseCount wrapped to 0, got " .. p.pulseCount)
    assert(p.loopIndex  == 1, "loopIndex incremented to 1")

    -- Second loop fires events again.
    for _ = 1, 8 do Player.externalPulse(p, emit) end
    local noteOns2 = 0
    for _, e in ipairs(events) do
        if e.type == "NOTE_ON" then noteOns2 = noteOns2 + 1 end
    end
    assert(noteOns2 == 4, "four total NOTE_ONs after two loops, got " .. noteOns2)
    assert(p.loopIndex == 2, "loopIndex incremented to 2")
end

-- ── onLoopBoundary callback fires at loop wrap ───────────────────────────────

do
    local song = makeSong({ { 0, 60, 100, 1, 2 } }, 4, true)
    local calls = {}
    song.onLoopBoundary = function(s, idx) calls[#calls + 1] = idx end

    local p = Player.new(song, nil, 120)
    Player.start(p)
    local _, emit = recordEmit()
    -- Two full loops.
    for _ = 1, 8 do Player.externalPulse(p, emit) end
    assert(#calls == 2, "callback fired twice, got " .. #calls)
    assert(calls[1] == 1 and calls[2] == 2, "loopIndex passed to callback")
end

-- ── externalPulse: stopped player is a no-op ─────────────────────────────────

do
    local song = makeSong({ { 0, 60, 100, 1, 4 } }, 16, true)
    local p = Player.new(song, nil, 120)
    local events, emit = recordEmit()
    Player.externalPulse(p, emit)
    assert(#events == 0, "stopped player emits nothing")
    assert(p.pulseCount == 0, "stopped player does not advance")
end

-- ── Player.start resets pulseCount, cursor, loopIndex ────────────────────────

do
    local song = makeSong({
        { 0, 60, 100, 1, 2 },
        { 4, 62, 100, 1, 2 },
    }, 8, true)
    local p = Player.new(song, nil, 120)
    Player.start(p)
    local _, emit = recordEmit()
    for _ = 1, 12 do Player.externalPulse(p, emit) end
    assert(p.loopIndex >= 1, "advanced through a loop")
    Player.start(p)
    assert(p.pulseCount == 0, "pulseCount reset")
    assert(p.cursor     == 1, "cursor reset")
    assert(p.loopIndex  == 0, "loopIndex reset")
end

-- ── Player.tick (internal clock) drives pulses from clockFn ──────────────────

do
    local song = makeSong({
        { 0, 60, 100, 1, 2 },
        { 4, 62, 100, 1, 2 },
    }, 8, true)

    local nowMs = 0
    local clock = function() return nowMs end
    local p = Player.new(song, clock, 120)   -- pulseMs = 125
    Player.start(p)                          -- startMs = 0

    nowMs = 500
    local events, emit = recordEmit()
    Player.tick(p, emit)
    assert(p.pulseCount == 4, "tick advanced pulseCount to 4, got " .. p.pulseCount)

    local noteOns = 0
    for _, e in ipairs(events) do
        if e.type == "NOTE_ON" then noteOns = noteOns + 1 end
    end
    assert(noteOns == 2, "tick fired both events, got " .. noteOns)
end

-- ── Player.tick is a no-op when no time has passed ───────────────────────────

do
    local song = makeSong({ { 0, 60, 100, 1, 2 } }, 8, true)
    local nowMs = 0
    local p = Player.new(song, function() return nowMs end, 120)
    Player.start(p)
    local events, emit = recordEmit()
    Player.tick(p, emit)
    assert(p.pulseCount == 0, "no time elapsed -> no advance")
    assert(#events == 0, "no time elapsed -> no events")
end

-- ── allNotesOff drains in-flight notes via callback ─────────────────────────

do
    local song = makeSong({ { 0, 60, 100, 5, 8 } }, 16, true)
    local p = Player.new(song, nil, 120)
    Player.start(p)
    local _, emit = recordEmit()
    Player.externalPulse(p, emit)            -- emits NOTE_ON only (gate=8)

    local offs = {}
    local count = Player.allNotesOff(p, function(t, pitch, vel, ch)
        offs[#offs + 1] = { type = t, pitch = pitch, channel = ch }
    end)
    assert(count == 1, "one NOTE_OFF returned, got " .. count)
    assert(offs[1].type    == "NOTE_OFF", "type")
    assert(offs[1].pitch   == 60, "pitch")
    assert(offs[1].channel == 5,  "channel")
end

-- ── allNotesOff on idle player emits nothing ────────────────────────────────

do
    local song = makeSong({ { 0, 60, 100, 1, 4 } }, 16, true)
    local p = Player.new(song, nil, 120)
    local count = Player.allNotesOff(p, function() error("should not emit") end)
    assert(count == 0, "idle player -> zero NOTE_OFFs")
end

-- ── setBpm preserves pulse position (internal-clock mode) ────────────────────

do
    local song = makeSong({ { 0, 60, 100, 1, 4 } }, 16, true)
    local nowMs = 0
    local p = Player.new(song, function() return nowMs end, 120)
    Player.start(p)
    nowMs = 500
    local _, emit = recordEmit()
    Player.tick(p, emit)
    assert(p.pulseCount == 4, "advanced 4 pulses")

    Player.setBpm(p, 60)
    assert(p.pulseMs == 250, "pulseMs recalculated")

    Player.tick(p, emit)
    assert(p.pulseCount == 4, "setBpm did not jump pulseCount")
end

print("player: all tests passed")
