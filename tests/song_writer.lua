-- tests/song_writer.lua
-- Tests for sequencer/song_writer.lua — the in-place loop-boundary rewriter.
-- Run with: lua tests/song_writer.lua

local SongWriter = require("sequencer/song_writer")
local Player     = require("player/player")

-- Builds a song with two NOTE_ONs (and paired NOTE_OFFs) where each NOTE_ON
-- carries a configurable probability. pairOff/srcStepProb/srcVelocity arrays
-- are populated as the compiler would.
local function makeProbSong(prob1, prob2)
    return {
        bpm            = 120,
        pulsesPerBeat  = 4,
        durationPulses = 8,
        loop           = true,
        eventCount     = 4,
        --       i=1 ON@0  i=2 OFF@2  i=3 ON@4  i=4 OFF@6
        atPulse        = { 0, 2, 4, 6 },
        kind           = { 1, 0, 1, 0 },
        pitch          = { 60, 60, 62, 62 },
        velocity       = { 100, 0, 100, 0 },
        channel        = { 1, 1, 1, 1 },
        hasProbability = true,
        pairOff        = { 2, 0, 4, 0 },
        srcStepProb    = { prob1, 0, prob2, 0 },
        srcVelocity    = { 100, 0, 100, 0 },
    }
end

-- ── Static song (hasProbability false) is a no-op ────────────────────────────

do
    local song = {
        kind = { 1, 0 }, eventCount = 2,
        -- intentionally no other fields; rollNextLoop must early-out.
    }
    SongWriter.rollNextLoop(song, 1)
    assert(song.kind[1] == 1 and song.kind[2] == 0, "static song untouched")
end

-- ── prob = 100 always plays, even if previously muted ─────────────────────

do
    local song = makeProbSong(100, 100)
    -- Pre-mute and confirm the next roll restores to play state.
    song.kind[1], song.kind[2] = 2, 3
    song.kind[3], song.kind[4] = 2, 3
    SongWriter.rollNextLoop(song, 1)
    assert(song.kind[1] == 1, "prob=100 unmutes NOTE_ON")
    assert(song.kind[2] == 0, "prob=100 unmutes paired NOTE_OFF")
    assert(song.kind[3] == 1, "prob=100 unmutes second NOTE_ON")
    assert(song.kind[4] == 0, "prob=100 unmutes second paired NOTE_OFF")
end

-- ── prob = 0 always mutes ──────────────────────────────────────────────────

do
    local song = makeProbSong(0, 0)
    SongWriter.rollNextLoop(song, 1)
    assert(song.kind[1] == 2, "prob=0 mutes NOTE_ON (kind=2)")
    assert(song.kind[2] == 3, "prob=0 mutes paired NOTE_OFF (kind=3)")
    assert(song.kind[3] == 2, "prob=0 mutes second NOTE_ON")
    assert(song.kind[4] == 3, "prob=0 mutes second paired NOTE_OFF")
end

-- ── Config flip between loops re-evaluates ─────────────────────────────────

do
    local song = makeProbSong(0, 0)
    SongWriter.rollNextLoop(song, 1)
    assert(song.kind[1] == 2, "first roll: muted")

    -- Sequencer changes config between loops.
    song.srcStepProb[1] = 100
    SongWriter.rollNextLoop(song, 2)
    assert(song.kind[1] == 1, "config change to prob=100 unmutes")
    assert(song.kind[2] == 0, "paired NOTE_OFF follows")
end

-- ── prob in (0,100) is statistical ─────────────────────────────────────────

do
    math.randomseed(42)
    local song = makeProbSong(50, 50)
    local plays1, plays3 = 0, 0
    for _ = 1, 1000 do
        SongWriter.rollNextLoop(song, 1)
        if song.kind[1] == 1 then plays1 = plays1 + 1 end
        if song.kind[3] == 1 then plays3 = plays3 + 1 end
    end
    -- Both should be ~500. Allow ±100 tolerance for randomness.
    assert(plays1 > 380 and plays1 < 620, "prob=50 plays roughly half: " .. plays1)
    assert(plays3 > 380 and plays3 < 620, "prob=50 plays roughly half: " .. plays3)
end

-- ── Paired NOTE_OFF tracks NOTE_ON state ───────────────────────────────────

do
    math.randomseed(7)
    local song = makeProbSong(50, 50)
    for _ = 1, 100 do
        SongWriter.rollNextLoop(song, 1)
        if song.kind[1] == 1 then
            assert(song.kind[2] == 0, "active NOTE_ON paired with active NOTE_OFF")
        else
            assert(song.kind[1] == 2, "muted NOTE_ON has kind=2")
            assert(song.kind[2] == 3, "muted paired NOTE_OFF has kind=3")
        end
    end
end

-- ── Integration: player + writer wired through onLoopBoundary ──────────────

do
    math.randomseed(123)
    local song = makeProbSong(0, 100)   -- step 1 always mutes, step 2 always plays
    -- Pre-roll loop 0 (the writer would normally fire at boundary, but for
    -- the very first loop the compiler's initial kind[] is what plays).
    SongWriter.rollNextLoop(song, 0)
    song.onLoopBoundary = SongWriter.rollNextLoop

    local p = Player.new(song, nil, 120)
    Player.start(p)

    local emitted = {}
    local emit = function(t, pitch, vel, ch)
        emitted[#emitted + 1] = { type = t, pitch = pitch, ch = ch }
    end

    -- Run two full loops.
    for _ = 1, 16 do Player.externalPulse(p, emit) end

    local p60on, p62on = 0, 0
    for _, e in ipairs(emitted) do
        if e.type == "NOTE_ON" and e.pitch == 60 then p60on = p60on + 1 end
        if e.type == "NOTE_ON" and e.pitch == 62 then p62on = p62on + 1 end
    end
    assert(p60on == 0, "pitch 60 (prob=0) never plays, got " .. p60on)
    assert(p62on == 2, "pitch 62 (prob=100) plays each loop, got " .. p62on)
    assert(p.loopIndex == 2, "two loops completed")
end

print("song_writer: all tests passed")
