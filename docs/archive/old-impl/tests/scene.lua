-- tests/scene.lua
-- Behavioural tests for sequencer/scene.lua.
-- Run with: lua tests/scene.lua

require("authoring")
local Scene   = require("sequencer").Scene
local Track   = require("sequencer").Track
local Step    = require("sequencer").Step

-- ---------------------------------------------------------------------------
-- Scene construction
-- ---------------------------------------------------------------------------

do
    local s = Scene.new()
    assert(s.repeats == 1, "default repeats should be 1")
    assert(s.lengthBeats == 4, "default lengthBeats should be 4")
    assert(s.name == "", "default name should be empty")
    assert(type(s.trackLoops) == "table", "trackLoops should be a table")
end

do
    local s = Scene.new(4, 8, "intro")
    assert(s.repeats == 4, "repeats should be 4")
    assert(s.lengthBeats == 8, "lengthBeats should be 8")
    assert(s.name == "intro", "name should be 'intro'")
end

-- ---------------------------------------------------------------------------
-- Scene track loop overrides
-- ---------------------------------------------------------------------------

do
    local s = Scene.new()
    Scene.setTrackLoop(s, 1, 5, 8)
    local loop = Scene.getTrackLoop(s, 1)
    assert(loop ~= nil, "track 1 loop should be set")
    assert(loop.loopStart == 5, "loopStart should be 5")
    assert(loop.loopEnd == 8, "loopEnd should be 8")

    -- Track 2 has no override.
    assert(Scene.getTrackLoop(s, 2) == nil, "track 2 loop should be nil")

    -- Clear override.
    Scene.setTrackLoop(s, 1, nil, nil)
    assert(Scene.getTrackLoop(s, 1) == nil, "track 1 loop should be cleared")
end

-- Validation: loopStart > loopEnd should fail.
do
    local s = Scene.new()
    local ok, _ = pcall(Scene.setTrackLoop, s, 1, 8, 5)
    assert(not ok, "loopStart > loopEnd should error")
end

-- ---------------------------------------------------------------------------
-- Scene setters/getters
-- ---------------------------------------------------------------------------

do
    local s = Scene.new()
    Scene.setRepeats(s, 3)
    assert(Scene.getRepeats(s) == 3, "repeats should be 3")

    Scene.setLengthBeats(s, 16)
    assert(Scene.getLengthBeats(s) == 16, "lengthBeats should be 16")

    Scene.setName(s, "chorus")
    assert(Scene.getName(s) == "chorus", "name should be 'chorus'")
end

-- Invalid repeats.
do
    local s = Scene.new()
    local ok, _ = pcall(Scene.setRepeats, s, 0)
    assert(not ok, "repeats 0 should error")
    ok, _ = pcall(Scene.setRepeats, s, 1.5)
    assert(not ok, "non-integer repeats should error")
end

-- Invalid lengthBeats.
do
    local s = Scene.new()
    local ok, _ = pcall(Scene.setLengthBeats, s, 0)
    assert(not ok, "lengthBeats 0 should error")
    ok, _ = pcall(Scene.setLengthBeats, s, 2.5)
    assert(not ok, "non-integer lengthBeats should error")
end

-- ---------------------------------------------------------------------------
-- SceneChain construction
-- ---------------------------------------------------------------------------

do
    local chain = Scene.newChain()
    assert(chain.sceneCount == 0, "new chain should have 0 scenes")
    assert(chain.cursor == 1, "cursor should start at 1")
    assert(chain.repeatCount == 0, "repeatCount should start at 0")
    assert(chain.beatCount == 0, "beatCount should start at 0")
    assert(chain.active == false, "chain should not be active by default")
end

-- ---------------------------------------------------------------------------
-- chainAppend / chainGetScene / chainGetCount
-- ---------------------------------------------------------------------------

do
    local chain = Scene.newChain()
    local s1 = Scene.new(2, 4, "A")
    local s2 = Scene.new(1, 4, "B")
    Scene.chainAppend(chain, s1)
    Scene.chainAppend(chain, s2)

    assert(Scene.chainGetCount(chain) == 2, "count should be 2")
    assert(Scene.chainGetScene(chain, 1) == s1, "scene 1 should be s1")
    assert(Scene.chainGetScene(chain, 2) == s2, "scene 2 should be s2")
end

-- ---------------------------------------------------------------------------
-- chainInsert
-- ---------------------------------------------------------------------------

do
    local chain = Scene.newChain()
    Scene.chainAppend(chain, Scene.new(1, 4, "A"))
    Scene.chainAppend(chain, Scene.new(1, 4, "C"))
    Scene.chainInsert(chain, 2, Scene.new(1, 4, "B"))

    assert(Scene.chainGetCount(chain) == 3, "count should be 3 after insert")
    assert(Scene.getName(Scene.chainGetScene(chain, 1)) == "A", "scene 1 should be A")
    assert(Scene.getName(Scene.chainGetScene(chain, 2)) == "B", "scene 2 should be B (inserted)")
    assert(Scene.getName(Scene.chainGetScene(chain, 3)) == "C", "scene 3 should be C (shifted)")
end

-- ---------------------------------------------------------------------------
-- chainRemove
-- ---------------------------------------------------------------------------

do
    local chain = Scene.newChain()
    Scene.chainAppend(chain, Scene.new(1, 4, "A"))
    Scene.chainAppend(chain, Scene.new(1, 4, "B"))
    Scene.chainAppend(chain, Scene.new(1, 4, "C"))

    Scene.chainRemove(chain, 2)
    assert(Scene.chainGetCount(chain) == 2, "count should be 2 after remove")
    assert(Scene.getName(Scene.chainGetScene(chain, 1)) == "A", "scene 1 should be A")
    assert(Scene.getName(Scene.chainGetScene(chain, 2)) == "C", "scene 2 should be C (shifted)")
end

-- chainRemove adjusts cursor if it goes out of range.
do
    local chain = Scene.newChain()
    Scene.chainAppend(chain, Scene.new(1, 4, "A"))
    Scene.chainAppend(chain, Scene.new(1, 4, "B"))
    chain.cursor = 2

    Scene.chainRemove(chain, 2)
    assert(chain.cursor == 1, "cursor should be adjusted to 1 after removing last scene")
end

-- ---------------------------------------------------------------------------
-- chainGetCurrent / chainReset
-- ---------------------------------------------------------------------------

do
    local chain = Scene.newChain()
    assert(Scene.chainGetCurrent(chain) == nil, "current should be nil on empty chain")

    local s1 = Scene.new(2, 4, "intro")
    Scene.chainAppend(chain, s1)
    assert(Scene.chainGetCurrent(chain) == s1, "current should be s1")
end

do
    local chain = Scene.newChain()
    Scene.chainAppend(chain, Scene.new(1, 4, "A"))
    Scene.chainAppend(chain, Scene.new(1, 4, "B"))
    chain.cursor = 2
    chain.repeatCount = 1
    chain.beatCount = 3

    Scene.chainReset(chain)
    assert(chain.cursor == 1, "reset should set cursor to 1")
    assert(chain.repeatCount == 0, "reset should clear repeatCount")
    assert(chain.beatCount == 0, "reset should clear beatCount")
end

-- ---------------------------------------------------------------------------
-- chainSetActive / chainIsActive
-- ---------------------------------------------------------------------------

do
    local chain = Scene.newChain()
    assert(Scene.chainIsActive(chain) == false, "chain should not be active initially")
    Scene.chainSetActive(chain, true)
    assert(Scene.chainIsActive(chain) == true, "chain should be active after setActive(true)")
    Scene.chainSetActive(chain, false)
    assert(Scene.chainIsActive(chain) == false, "chain should be inactive after setActive(false)")
end

-- ---------------------------------------------------------------------------
-- chainCompletePass — advance logic
-- ---------------------------------------------------------------------------

-- Single scene with repeat=2: first pass does not advance, second does (wraps).
do
    local chain = Scene.newChain()
    Scene.chainAppend(chain, Scene.new(2, 4, "only"))

    local advanced = Scene.chainCompletePass(chain)
    assert(not advanced, "first pass should not advance (repeat 1 of 2)")
    assert(chain.cursor == 1, "cursor should still be 1")
    assert(chain.repeatCount == 1, "repeatCount should be 1")

    advanced = Scene.chainCompletePass(chain)
    assert(advanced, "second pass should advance")
    assert(chain.cursor == 1, "cursor should wrap to 1 (only scene)")
    assert(chain.repeatCount == 0, "repeatCount should reset")
end

-- Two scenes: advance from scene 1 (repeat=1) to scene 2 (repeat=1) to wrap.
do
    local chain = Scene.newChain()
    Scene.chainAppend(chain, Scene.new(1, 4, "A"))
    Scene.chainAppend(chain, Scene.new(1, 4, "B"))

    local advanced = Scene.chainCompletePass(chain)
    assert(advanced, "scene A (repeat=1) should advance immediately")
    assert(chain.cursor == 2, "cursor should be at scene 2")

    advanced = Scene.chainCompletePass(chain)
    assert(advanced, "scene B (repeat=1) should advance")
    assert(chain.cursor == 1, "cursor should wrap to scene 1")
end

-- Three scenes with varying repeat counts.
do
    local chain = Scene.newChain()
    Scene.chainAppend(chain, Scene.new(1, 4, "A"))
    Scene.chainAppend(chain, Scene.new(3, 4, "B"))
    Scene.chainAppend(chain, Scene.new(2, 4, "C"))

    -- Scene A: 1 pass
    Scene.chainCompletePass(chain)
    assert(chain.cursor == 2, "should be at scene B after A")

    -- Scene B: 3 passes
    Scene.chainCompletePass(chain) -- 1 of 3
    assert(chain.cursor == 2, "still scene B after pass 1")
    Scene.chainCompletePass(chain) -- 2 of 3
    assert(chain.cursor == 2, "still scene B after pass 2")
    Scene.chainCompletePass(chain) -- 3 of 3
    assert(chain.cursor == 3, "should be at scene C after B")

    -- Scene C: 2 passes
    Scene.chainCompletePass(chain) -- 1 of 2
    assert(chain.cursor == 3, "still scene C after pass 1")
    Scene.chainCompletePass(chain) -- 2 of 2
    assert(chain.cursor == 1, "should wrap to scene A after C")
end

-- Empty chain: completePass returns false.
do
    local chain = Scene.newChain()
    assert(Scene.chainCompletePass(chain) == false, "empty chain should return false")
end

-- ---------------------------------------------------------------------------
-- chainBeat — beat-driven scene progression
-- ---------------------------------------------------------------------------

-- Scene with lengthBeats=4, repeats=1: advances after 4 beats.
do
    local chain = Scene.newChain()
    Scene.chainAppend(chain, Scene.new(1, 4, "A"))
    Scene.chainAppend(chain, Scene.new(1, 4, "B"))

    -- Beats 1-3: no advance.
    for i = 1, 3 do
        local adv = Scene.chainBeat(chain)
        assert(not adv, "beat " .. i .. " should not advance")
    end
    assert(chain.cursor == 1, "should still be on scene A")

    -- Beat 4: completes one pass → advances (repeat=1).
    local adv = Scene.chainBeat(chain)
    assert(adv, "beat 4 should trigger advance")
    assert(chain.cursor == 2, "should be on scene B")
end

-- Scene with lengthBeats=2, repeats=3: takes 6 beats total.
do
    local chain = Scene.newChain()
    Scene.chainAppend(chain, Scene.new(3, 2, "A"))
    Scene.chainAppend(chain, Scene.new(1, 2, "B"))

    -- 6 beats = 3 passes of 2 beats each
    for i = 1, 5 do
        local adv = Scene.chainBeat(chain)
        assert(not adv, "beat " .. i .. " should not advance to next scene")
    end
    -- Beat 6: third pass completes → advance
    local adv = Scene.chainBeat(chain)
    assert(adv, "beat 6 should advance")
    assert(chain.cursor == 2, "should be on scene B")
end

-- Empty chain: chainBeat returns false.
do
    local chain = Scene.newChain()
    assert(Scene.chainBeat(chain) == false, "empty chain beat should return false")
end

-- ---------------------------------------------------------------------------
-- chainJumpTo
-- ---------------------------------------------------------------------------

do
    local chain = Scene.newChain()
    Scene.chainAppend(chain, Scene.new(1, 4, "A"))
    Scene.chainAppend(chain, Scene.new(1, 4, "B"))
    Scene.chainAppend(chain, Scene.new(1, 4, "C"))

    Scene.chainJumpTo(chain, 3)
    assert(chain.cursor == 3, "cursor should jump to 3")
    assert(chain.repeatCount == 0, "repeatCount should reset on jump")
    assert(chain.beatCount == 0, "beatCount should reset on jump")
end

-- jumpTo out of range.
do
    local chain = Scene.newChain()
    Scene.chainAppend(chain, Scene.new(1, 4, "A"))
    local ok, _ = pcall(Scene.chainJumpTo, chain, 2)
    assert(not ok, "jumpTo out of range should error")
end

-- ---------------------------------------------------------------------------
-- applyToTracks — applies scene loop points to tracks
-- ---------------------------------------------------------------------------

do
    local t1 = Track.new()
    Track.addPattern(t1, 8) -- steps 1-8
    local t2 = Track.new()
    Track.addPattern(t2, 4) -- steps 1-4
    local tracks = { t1, t2 }

    local s = Scene.new(1, 4, "test")
    Scene.setTrackLoop(s, 1, 3, 6)
    Scene.setTrackLoop(s, 2, 2, 4)

    Scene.applyToTracks(s, tracks, 2)

    assert(Track.getLoopStart(t1) == 3, "track 1 loopStart should be 3")
    assert(Track.getLoopEnd(t1) == 6, "track 1 loopEnd should be 6")
    assert(Track.getLoopStart(t2) == 2, "track 2 loopStart should be 2")
    assert(Track.getLoopEnd(t2) == 4, "track 2 loopEnd should be 4")
end

-- applyToTracks skips tracks without overrides.
do
    local t1 = Track.new()
    Track.addPattern(t1, 8)
    Track.setLoopStart(t1, 1)
    Track.setLoopEnd(t1, 4)
    local tracks = { t1 }

    local s = Scene.new(1, 4, "empty")
    -- No track loop overrides set.
    Scene.applyToTracks(s, tracks, 1)

    -- Loop points should remain unchanged.
    assert(Track.getLoopStart(t1) == 1, "track 1 loopStart should remain 1")
    assert(Track.getLoopEnd(t1) == 4, "track 1 loopEnd should remain 4")
end

print("tests/scene.lua OK")
