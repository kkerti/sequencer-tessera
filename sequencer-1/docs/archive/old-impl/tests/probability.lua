-- tests/probability.lua
-- Behavioural tests for sequencer/probability.lua and Step probability API.
-- Player-side probability evaluation has moved to sequencer/song_writer.lua;
-- see tests/song_writer.lua for that integration.
-- Run with: lua tests/probability.lua

require("authoring")
local Step        = require("sequencer").Step
local Probability = require("probability")

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

-- nil probability case is no longer reachable: Step is now a packed integer
-- and Step.new always sets probability (default 100). Test removed.

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
    s = Step.setProbability(s, 50)
    assert(Step.getProbability(s) == 50)
    s = Step.setProbability(s, 0)
    assert(Step.getProbability(s) == 0)
    s = Step.setProbability(s, 100)
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

-- ── Probability is non-destructive: step value unchanged ───────────────────

do
    local s = Step.new(60, 100, 4, 2, false, 50)
    local origPitch = Step.getPitch(s)
    local origProb  = Step.getProbability(s)
    local origStep  = s
    for _ = 1, 100 do
        Probability.shouldPlay(s)
    end
    -- Step is an immutable integer; identity check is sufficient.
    assert(s == origStep, "probability evaluation should not modify step value")
    assert(Step.getPitch(s) == origPitch, "pitch unchanged")
    assert(Step.getProbability(s) == origProb, "probability unchanged")
end

print("probability: all tests passed")
