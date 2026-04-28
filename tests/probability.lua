-- tests/probability.lua
-- Behavioural tests for sequencer/probability.lua and Step probability API.
-- Player-side probability evaluation has moved to sequencer/song_writer.lua;
-- see tests/song_writer.lua for that integration.
-- Run with: lua tests/probability.lua

local Step        = require("sequencer/step")
local Probability = require("sequencer/probability")

-- ── Probability.shouldPlay unit tests ───────────────────────────────────────

-- probability = 100 always plays
do
    local s = Step.new(60, 100, 4, 2, false, 100)
    for _ = 1, 100 do
        assert(Probability.shouldPlay(s) == true,
            "probability 100 should always play")
    end
end

-- probability = 0 never plays
do
    local s = Step.new(60, 100, 4, 2, false, 0)
    for _ = 1, 100 do
        assert(Probability.shouldPlay(s) == false,
            "probability 0 should never play")
    end
end

-- nil probability (legacy steps) always plays
do
    local s = { pitch = 60, velocity = 100, duration = 4, gate = 2, ratch = false, active = true }
    for _ = 1, 100 do
        assert(Probability.shouldPlay(s) == true,
            "nil probability should default to always play")
    end
end

-- probability = 50 should produce a mix over many trials
do
    math.randomseed(12345)
    local s = Step.new(60, 100, 4, 2, false, 50)
    local played = 0
    local trials = 1000
    for _ = 1, trials do
        if Probability.shouldPlay(s) then
            played = played + 1
        end
    end
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

-- ── Probability is non-destructive: step data unchanged ─────────────────────

do
    local s = Step.new(60, 100, 4, 2, false, 50)
    local origPitch = s.pitch
    local origProb = s.probability
    for _ = 1, 100 do
        Probability.shouldPlay(s)
    end
    assert(s.pitch == origPitch, "probability evaluation should not modify step pitch")
    assert(s.probability == origProb, "probability evaluation should not modify step probability")
end

print("probability: all tests passed")
