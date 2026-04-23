-- tests/probability.lua
-- Behavioural tests for sequencer/probability.lua and player integration.
-- Run with: lua tests/probability.lua

local Step        = require("sequencer/step")
local Engine      = require("sequencer/engine")
local Player      = require("player/player")
local Track       = require("sequencer/track")
local Probability = require("sequencer/probability")

-- ── Probability.shouldPlay unit tests ───────────────────────────────────────

-- probability = 100 always plays
do
    local s = Step.new(60, 100, 4, 2, 1, 100)
    for _ = 1, 100 do
        assert(Probability.shouldPlay(s) == true,
            "probability 100 should always play")
    end
end

-- probability = 0 never plays
do
    local s = Step.new(60, 100, 4, 2, 1, 0)
    for _ = 1, 100 do
        assert(Probability.shouldPlay(s) == false,
            "probability 0 should never play")
    end
end

-- nil probability (legacy steps) always plays
do
    local s = { pitch = 60, velocity = 100, duration = 4, gate = 2, ratchet = 1, active = true }
    for _ = 1, 100 do
        assert(Probability.shouldPlay(s) == true,
            "nil probability should default to always play")
    end
end

-- probability = 50 should produce a mix over many trials
do
    math.randomseed(12345)
    local s = Step.new(60, 100, 4, 2, 1, 50)
    local played = 0
    local trials = 1000
    for _ = 1, trials do
        if Probability.shouldPlay(s) then
            played = played + 1
        end
    end
    -- With 1000 trials at 50%, expect roughly 500 ± reasonable margin.
    assert(played > 300 and played < 700,
        "probability 50 should produce a mix: got " .. played .. "/1000")
end

-- ── Step.new default probability ────────────────────────────────────────────

do
    local s = Step.new()
    assert(Step.getProbability(s) == 100,
        "default probability should be 100")
end

-- ── Step.setProbability / getProbability ─────────────────────────────────────

do
    local s = Step.new()
    Step.setProbability(s, 50)
    assert(Step.getProbability(s) == 50)
    Step.setProbability(s, 0)
    assert(Step.getProbability(s) == 0)
    Step.setProbability(s, 100)
    assert(Step.getProbability(s) == 100)
end

-- Out-of-range probability rejected
do
    local ok = pcall(Step.new, 60, 100, 4, 2, 1, 101)
    assert(not ok, "expected error for probability > 100")
    ok = pcall(Step.new, 60, 100, 4, 2, 1, -1)
    assert(not ok, "expected error for probability < 0")
    local s = Step.new()
    ok = pcall(Step.setProbability, s, 200)
    assert(not ok, "expected error for setProbability > 100")
end

-- ── Player integration: probability 0 suppresses NOTE_ON and NOTE_OFF ───────

do
    math.randomseed(99999)
    local e = Engine.new(120, 4, 1, 2)
    local t = Engine.getTrack(e, 1)
    -- Step 1: probability 0 (never plays), Step 2: probability 100 (always plays)
    Track.setStep(t, 1, Step.new(60, 100, 2, 1, 1, 0))
    Track.setStep(t, 2, Step.new(64, 100, 2, 1, 1, 100))

    local player = Player.new(e, 120, function() return 0 end)
    Player.start(player)

    local function tickEvents()
        local evs = {}
        Player.tick(player, function(ev) evs[#evs + 1] = ev end)
        return evs
    end

    -- Pulse 1: step 1 NOTE_ON suppressed by probability 0.
    local evs = tickEvents()
    local noteOns = {}
    for _, ev in ipairs(evs) do if ev.type == "NOTE_ON" then noteOns[#noteOns+1] = ev end end
    assert(#noteOns == 0, "probability 0 should suppress NOTE_ON, got " .. #noteOns)

    -- Pulse 2: step 1 NOTE_OFF also suppressed (probSuppressed flag).
    evs = tickEvents()
    assert(#evs == 0, "probability 0 should suppress NOTE_OFF, got " .. #evs)

    -- Pulse 3: step 2 fires NOTE_ON normally (probability 100).
    evs = tickEvents()
    noteOns = {}
    for _, ev in ipairs(evs) do if ev.type == "NOTE_ON" then noteOns[#noteOns+1] = ev end end
    assert(#noteOns == 1 and noteOns[1].pitch == 64,
        "probability 100 step should fire NOTE_ON normally")
end

-- ── Player: suppressed NOTE_ON does not register an active note ──────────────

do
    local e = Engine.new(120, 4, 1, 1)
    local t = Engine.getTrack(e, 1)
    Track.setStep(t, 1, Step.new(60, 100, 2, 1, 1, 0))

    local player = Player.new(e, 120, function() return 0 end)
    Player.start(player)

    Player.tick(player, function() end)  -- suppressed NOTE_ON
    assert(player.activeNoteCount == 0,
        "activeNoteCount should be 0 after suppressed NOTE_ON")

    Player.tick(player, function() end)  -- suppressed NOTE_OFF
    assert(player.activeNoteCount == 0,
        "activeNoteCount should remain 0 after suppressed NOTE_OFF")
end

-- ── Player.allNotesOff after suppressed note returns empty list ──────────────

do
    local e = Engine.new(120, 4, 1, 2)
    local t = Engine.getTrack(e, 1)
    Track.setStep(t, 1, Step.new(60, 100, 4, 2, 1, 0))
    Track.setStep(t, 2, Step.new(64, 100, 4, 2, 1, 100))

    local player = Player.new(e, 120, function() return 0 end)
    Player.start(player)
    Player.tick(player, function() end)  -- suppressed NOTE_ON for step 1

    -- probSuppressed[1] should be true after suppressed NOTE_ON
    assert(player.probSuppressed[1] == true,
        "probSuppressed should be true after suppressed NOTE_ON")
end

-- ── Probability is non-destructive: step data unchanged ─────────────────────

do
    local s = Step.new(60, 100, 4, 2, 1, 50)
    local origPitch = s.pitch
    local origProb = s.probability
    for _ = 1, 100 do
        Probability.shouldPlay(s)
    end
    assert(s.pitch == origPitch, "probability evaluation should not modify step pitch")
    assert(s.probability == origProb, "probability evaluation should not modify step probability")
end

print("probability: all tests passed")
