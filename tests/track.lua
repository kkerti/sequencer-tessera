-- tests/track.lua
-- Behavioural tests for sequencer/track.lua.
-- Run with: lua tests/track.lua

local Track   = require("sequencer/track")
local Pattern = require("sequencer/pattern")
local Step    = require("sequencer/step")

-- ---------------------------------------------------------------------------
-- Construction (zero patterns)
-- ---------------------------------------------------------------------------

do
    local t = Track.new()
    assert(t.cursor           == 1,  "cursor should start at 1")
    assert(t.pulseCounter     == 0,  "pulseCounter should start at 0")
    assert(t.patternCount     == 0,  "patternCount should start at 0")
    assert(Track.getStepCount(t) == 0, "stepCount should be 0 on empty track")
end

-- advance on empty track returns nil
do
    local t  = Track.new()
    local ev = Track.advance(t)
    assert(ev == nil, "advance on empty track should return nil")
end

-- ---------------------------------------------------------------------------
-- addPattern / getPattern / getPatternCount
-- ---------------------------------------------------------------------------

do
    local t   = Track.new()
    local pat = Track.addPattern(t, 4)
    assert(Track.getPatternCount(t) == 1, "patternCount should be 1 after addPattern")
    assert(Track.getPattern(t, 1) == pat, "getPattern(1) should return the added pattern")
    assert(Track.getStepCount(t) == 4, "stepCount should be 4 after adding 4-step pattern")
end

do
    local t = Track.new()
    Track.addPattern(t, 4)
    Track.addPattern(t, 8)
    assert(Track.getPatternCount(t) == 2, "patternCount should be 2")
    assert(Track.getStepCount(t) == 12, "stepCount should be 12 (4+8)")
end

-- addPattern with zero steps is allowed.
do
    local t   = Track.new()
    local pat = Track.addPattern(t, 0)
    assert(Track.getPatternCount(t) == 1, "patternCount should be 1")
    assert(Track.getStepCount(t) == 0, "stepCount should remain 0")
end

-- ---------------------------------------------------------------------------
-- patternStartIndex / patternEndIndex
-- ---------------------------------------------------------------------------

do
    local t = Track.new()
    Track.addPattern(t, 4)  -- pattern 1: steps 1-4
    Track.addPattern(t, 3)  -- pattern 2: steps 5-7

    assert(Track.patternStartIndex(t, 1) == 1, "pattern 1 should start at flat index 1")
    assert(Track.patternEndIndex(t, 1)   == 4, "pattern 1 should end at flat index 4")
    assert(Track.patternStartIndex(t, 2) == 5, "pattern 2 should start at flat index 5")
    assert(Track.patternEndIndex(t, 2)   == 7, "pattern 2 should end at flat index 7")
end

-- ---------------------------------------------------------------------------
-- Step access via flat index
-- ---------------------------------------------------------------------------

do
    local t   = Track.new()
    local pat = Track.addPattern(t, 3)

    -- setStep / getStep round-trip
    local newStep = Step.new(72, 80, 6, 3)
    Track.setStep(t, 2, newStep)
    local got = Track.getStep(t, 2)
    assert(Step.getPitch(got) == 72, "getStep should return the updated step")
end

-- getStep out of range
do
    local t   = Track.new()
    Track.addPattern(t, 2)
    local ok, _ = pcall(Track.getStep, t, 3)
    assert(not ok, "getStep beyond stepCount should error")
end

-- ---------------------------------------------------------------------------
-- NOTE_ON / NOTE_OFF sequence — single pattern
-- ---------------------------------------------------------------------------

do
    local t = Track.new()
    Track.addPattern(t, 4)

    Track.setStep(t, 1, Step.new(60, 100, 4, 2))
    Track.setStep(t, 2, Step.new(64, 100, 4, 2))
    Track.setStep(t, 3, Step.new(67, 100, 4, 2))
    Track.setStep(t, 4, Step.new(60, 100, 4, 0)) -- rest

    -- Pulse 0 of step 1 → NOTE_ON
    local ev = Track.advance(t)
    assert(ev == "NOTE_ON",  "expected NOTE_ON at pulse 0")
    assert(t.cursor == 1,    "cursor should still be on step 1")

    -- Pulse 1 → no event
    ev = Track.advance(t)
    assert(ev == nil, "expected no event on pulse 1")

    -- Pulse 2 → NOTE_OFF (gate == 2)
    ev = Track.advance(t)
    assert(ev == "NOTE_OFF", "expected NOTE_OFF at gate boundary")

    -- Pulse 3 → no event; cursor advances to step 2
    ev = Track.advance(t)
    assert(ev == nil)
    assert(t.cursor == 2, "expected cursor to advance to step 2")

    -- Pulse 0 of step 2 → NOTE_ON E4
    ev = Track.advance(t)
    assert(ev == "NOTE_ON", "expected NOTE_ON for step 2")
    assert(Step.getPitch(Track.getCurrentStep(t)) == 64, "expected pitch 64 on step 2")
end

-- ---------------------------------------------------------------------------
-- Rest step fires no events
-- ---------------------------------------------------------------------------

do
    local t = Track.new()
    Track.addPattern(t, 1)
    Track.setStep(t, 1, Step.new(60, 100, 4, 0)) -- gate=0 = rest

    local ev = Track.advance(t)
    assert(ev == nil, "rest step should fire no NOTE_ON")
end

-- ---------------------------------------------------------------------------
-- Reset
-- ---------------------------------------------------------------------------

do
    local t = Track.new()
    Track.addPattern(t, 4)
    -- advance several pulses
    Track.advance(t)
    Track.advance(t)
    Track.reset(t)
    assert(t.cursor == 1 and t.pulseCounter == 0, "reset should return to step 1 pulse 0")
end

-- ---------------------------------------------------------------------------
-- Zero-duration step is skipped
-- ---------------------------------------------------------------------------

do
    local t = Track.new()
    Track.addPattern(t, 2)
    Track.setStep(t, 1, Step.new(60, 100, 0, 0)) -- skip
    Track.setStep(t, 2, Step.new(64, 100, 4, 2))

    local ev = Track.advance(t)
    assert(ev == "NOTE_ON" and t.cursor == 2,
        "zero-duration step should be skipped; cursor should be on step 2")
end

-- ---------------------------------------------------------------------------
-- Ratchet in playback
-- ---------------------------------------------------------------------------

do
    local t = Track.new()
    Track.addPattern(t, 1)
    local st = Step.new(60, 100, 4, 1, 2)
    Track.setStep(t, 1, st)

    local ev
    ev = Track.advance(t)
    assert(ev == "NOTE_ON", "ratchet step should NOTE_ON on pulse 0")
    ev = Track.advance(t)
    assert(ev == "NOTE_OFF", "ratchet step should NOTE_OFF on pulse 1")
    ev = Track.advance(t)
    assert(ev == "NOTE_ON", "ratchet step should NOTE_ON on pulse 2")
    ev = Track.advance(t)
    assert(ev == "NOTE_OFF", "ratchet step should NOTE_OFF on pulse 3")
end

-- ---------------------------------------------------------------------------
-- Loop points — single pattern
-- ---------------------------------------------------------------------------

do
    local t = Track.new()
    Track.addPattern(t, 4)
    Track.setStep(t, 1, Step.new(60, 100, 1, 1))
    Track.setStep(t, 2, Step.new(61, 100, 1, 1))
    Track.setStep(t, 3, Step.new(62, 100, 1, 1))
    Track.setStep(t, 4, Step.new(63, 100, 1, 1))
    Track.setLoopStart(t, 2)
    Track.setLoopEnd(t, 3)

    -- step 1 → cursor moves to step 2 (loopStart)
    Track.advance(t)
    assert(t.cursor == 2, "cursor should be at loopStart (2)")
    -- step 2 → cursor moves to step 3
    Track.advance(t)
    assert(t.cursor == 3, "cursor should be at step 3")
    -- step 3 (loopEnd) → cursor wraps back to loopStart
    Track.advance(t)
    assert(t.cursor == 2, "cursor should wrap back to loopStart (2)")
end

-- clearLoopStart / clearLoopEnd
do
    local t = Track.new()
    Track.addPattern(t, 4)
    Track.setLoopStart(t, 2)
    Track.setLoopEnd(t, 3)
    Track.clearLoopStart(t)
    Track.clearLoopEnd(t)
    assert(Track.getLoopStart(t) == nil, "loopStart should be nil after clear")
    assert(Track.getLoopEnd(t)   == nil, "loopEnd should be nil after clear")
end

-- ---------------------------------------------------------------------------
-- Loop points spanning two patterns
-- ---------------------------------------------------------------------------

do
    local t = Track.new()
    Track.addPattern(t, 3)  -- steps 1-3
    Track.addPattern(t, 3)  -- steps 4-6

    -- Set every step to duration=1 gate=1 with distinct pitches.
    for i = 1, 6 do
        Track.setStep(t, i, Step.new(60 + i - 1, 100, 1, 1))
    end

    -- Loop from step 3 (last of pattern 1) to step 4 (first of pattern 2).
    Track.setLoopStart(t, 3)
    Track.setLoopEnd(t, 4)

    -- With loop points active, out-of-range cursor is snapped into the loop range.
    Track.advance(t) -- cursor 1 -> 3 (loopStart)
    assert(t.cursor == 3, "cursor should snap to step 3 (loopStart)")

    Track.advance(t) -- cursor → 4 (cross-pattern boundary)
    assert(t.cursor == 4, "cursor should cross pattern boundary to step 4")

    Track.advance(t) -- loopEnd reached → wrap to loopStart (3)
    assert(t.cursor == 3, "cursor should wrap from loopEnd (4) to loopStart (3)")
end

-- ---------------------------------------------------------------------------
-- patternStartIndex used as loop point anchor
-- ---------------------------------------------------------------------------

do
    local t = Track.new()
    Track.addPattern(t, 4)  -- steps 1-4
    Track.addPattern(t, 4)  -- steps 5-8

    for i = 1, 8 do
        Track.setStep(t, i, Step.new(60, 100, 1, 1))
    end

    -- Loop the whole second pattern using boundary helpers.
    local loopS = Track.patternStartIndex(t, 2)
    local loopE = Track.patternEndIndex(t, 2)
    Track.setLoopStart(t, loopS)
    Track.setLoopEnd(t, loopE)
    assert(loopS == 5, "second pattern should start at flat index 5")
    assert(loopE == 8, "second pattern should end at flat index 8")

    -- With loop points active, out-of-range cursor snaps into loop on first advance.
    Track.advance(t)
    assert(t.cursor == 5, "cursor should snap to pattern 2 start (5)")

    -- Walk through pattern 2 and verify wrap.
    Track.advance(t) -- cursor → 6
    Track.advance(t) -- cursor → 7
    Track.advance(t) -- cursor → 8 (loopEnd)
    Track.advance(t) -- should wrap to loopStart (5)
    assert(t.cursor == 5, "cursor should wrap from loopEnd (8) to loopStart (5)")
end

-- ---------------------------------------------------------------------------
-- Reset ignores loop points (ER-101 behaviour)
-- ---------------------------------------------------------------------------

do
    local t = Track.new()
    Track.addPattern(t, 4)
    for i = 1, 4 do
        Track.setStep(t, i, Step.new(60, 100, 1, 1))
    end
    Track.setLoopStart(t, 2)
    Track.setLoopEnd(t, 3)

    -- Run into the loop, then reset.
    Track.advance(t)  -- step 1 done, cursor → 2
    Track.advance(t)  -- step 2 done, cursor → 3
    assert(t.cursor == 3, "cursor should be inside the loop range")
    Track.reset(t)
    assert(t.cursor == 1, "reset should go to step 1 regardless of loop points")
    assert(t.pulseCounter == 0, "pulseCounter should be 0 after reset")
end

-- ---------------------------------------------------------------------------
-- Clock div/mult setters
-- ---------------------------------------------------------------------------

do
    local t = Track.new()
    Track.setClockDiv(t, 2)
    Track.setClockMult(t, 3)
    assert(Track.getClockDiv(t)  == 2, "clockDiv should be 2")
    assert(Track.getClockMult(t) == 3, "clockMult should be 3")
end

-- Out-of-range clock guards
do
    local t      = Track.new()
    local ok, _  = pcall(Track.setClockDiv, t, 0)
    assert(not ok, "clockDiv 0 should error")
    ok, _ = pcall(Track.setClockDiv, t, 100)
    assert(not ok, "clockDiv 100 should error")
end

-- ---------------------------------------------------------------------------
-- Direction modes
-- ---------------------------------------------------------------------------

do
    local t = Track.new()
    Track.addPattern(t, 4)
    for i = 1, 4 do
        Track.setStep(t, i, Step.new(60 + i - 1, 100, 1, 1))
    end

    -- reverse: 1 -> 4 -> 3 -> 2 -> 1
    Track.setDirection(t, "reverse")
    Track.advance(t)
    assert(t.cursor == 4, "reverse should wrap from 1 to 4")
    Track.advance(t)
    assert(t.cursor == 3, "reverse should move 4 -> 3")
    Track.advance(t)
    assert(t.cursor == 2, "reverse should move 3 -> 2")

    Track.reset(t)
    assert(t.cursor == 1, "reset should still go to step 1 in reverse mode")
end

do
    local t = Track.new()
    Track.addPattern(t, 4)
    for i = 1, 4 do
        Track.setStep(t, i, Step.new(60 + i - 1, 100, 1, 1))
    end

    -- pingpong: 1 -> 2 -> 3 -> 4 -> 3 -> 2 -> 1 -> 2
    Track.setDirection(t, "pingpong")
    local expected = { 2, 3, 4, 3, 2, 1, 2 }
    for i = 1, #expected do
        Track.advance(t)
        assert(t.cursor == expected[i], "pingpong cursor mismatch at step " .. i)
    end
end

do
    local t = Track.new()
    Track.addPattern(t, 5)
    for i = 1, 5 do
        Track.setStep(t, i, Step.new(60 + i - 1, 100, 1, 1))
    end

    Track.setLoopStart(t, 2)
    Track.setLoopEnd(t, 4)

    Track.setDirection(t, "random")
    math.randomseed(1234)
    for _ = 1, 40 do
        Track.advance(t)
        assert(t.cursor >= 2 and t.cursor <= 4, "random direction should stay inside loop range")
    end

    Track.setDirection(t, "brownian")
    math.randomseed(4321)
    for _ = 1, 40 do
        Track.advance(t)
        assert(t.cursor >= 2 and t.cursor <= 4, "brownian direction should stay inside loop range")
    end
end

-- Direction input guard
do
    local t = Track.new()
    local ok, _ = pcall(Track.setDirection, t, "diagonal")
    assert(not ok, "invalid direction should error")
end

-- MIDI channel override
do
    local t = Track.new()
    Track.setMidiChannel(t, 10)
    assert(Track.getMidiChannel(t) == 10, "midi channel should be set")
    Track.clearMidiChannel(t)
    assert(Track.getMidiChannel(t) == nil, "midi channel should clear to nil")
end

-- ---------------------------------------------------------------------------
-- copyPattern — appends a deep copy
-- ---------------------------------------------------------------------------

do
    local t = Track.new()
    Track.addPattern(t, 3)
    Track.setStep(t, 1, Step.new(72, 110, 3, 2))
    Track.setStep(t, 2, Step.new(74,  90, 2, 1))
    Track.setStep(t, 3, Step.new(76, 100, 4, 3))

    local copied = Track.copyPattern(t, 1)
    assert(Track.getPatternCount(t) == 2, "copyPattern should append a new pattern")
    assert(Track.getStepCount(t) == 6, "stepCount should be 6 after copying 3-step pattern")

    -- Verify data is correct.
    assert(Step.getPitch(Track.getStep(t, 4)) == 72, "copied step 1 pitch should be 72")
    assert(Step.getPitch(Track.getStep(t, 5)) == 74, "copied step 2 pitch should be 74")
    assert(Step.getPitch(Track.getStep(t, 6)) == 76, "copied step 3 pitch should be 76")

    -- Verify deep copy — mutating the copy should not affect the original.
    Step.setPitch(Track.getStep(t, 4), 48)
    assert(Step.getPitch(Track.getStep(t, 1)) == 72, "original should be unaffected by copy mutation")
end

-- ---------------------------------------------------------------------------
-- duplicatePattern — inserts right after the source
-- ---------------------------------------------------------------------------

do
    local t = Track.new()
    Track.addPattern(t, 2)  -- pattern 1: steps 1-2
    Track.addPattern(t, 2)  -- pattern 2: steps 3-4
    Track.setStep(t, 1, Step.new(60, 100, 1, 1))
    Track.setStep(t, 2, Step.new(62, 100, 1, 1))
    Track.setStep(t, 3, Step.new(64, 100, 1, 1))
    Track.setStep(t, 4, Step.new(66, 100, 1, 1))

    Track.duplicatePattern(t, 1)
    assert(Track.getPatternCount(t) == 3, "duplicatePattern should insert a new pattern")
    assert(Track.getStepCount(t) == 6, "stepCount should be 6 after duplicating 2-step pattern")

    -- Pattern order should be: original(1), copy(2), old-pattern-2(3)
    assert(Step.getPitch(Track.getStep(t, 1)) == 60, "pattern 1 step 1 unchanged")
    assert(Step.getPitch(Track.getStep(t, 2)) == 62, "pattern 1 step 2 unchanged")
    assert(Step.getPitch(Track.getStep(t, 3)) == 60, "duplicated pattern step 1 should match source")
    assert(Step.getPitch(Track.getStep(t, 4)) == 62, "duplicated pattern step 2 should match source")
    assert(Step.getPitch(Track.getStep(t, 5)) == 64, "old pattern 2 step 1 shifted")
    assert(Step.getPitch(Track.getStep(t, 6)) == 66, "old pattern 2 step 2 shifted")

    -- Deep copy verification.
    Step.setPitch(Track.getStep(t, 3), 48)
    assert(Step.getPitch(Track.getStep(t, 1)) == 60, "original unaffected by duplicated step mutation")
end

-- ---------------------------------------------------------------------------
-- deletePattern — removes pattern and adjusts loop points
-- ---------------------------------------------------------------------------

do
    local t = Track.new()
    Track.addPattern(t, 4)  -- pattern 1: steps 1-4
    Track.addPattern(t, 4)  -- pattern 2: steps 5-8
    Track.addPattern(t, 4)  -- pattern 3: steps 9-12

    -- Set loop to pattern 3.
    Track.setLoopStart(t, 9)
    Track.setLoopEnd(t, 12)

    -- Delete pattern 1 — loop points should shift down by 4.
    Track.deletePattern(t, 1)
    assert(Track.getPatternCount(t) == 2, "patternCount should be 2 after delete")
    assert(Track.getStepCount(t) == 8, "stepCount should be 8 after deleting 4-step pattern")
    assert(Track.getLoopStart(t) == 5, "loopStart should shift from 9 to 5")
    assert(Track.getLoopEnd(t) == 8, "loopEnd should shift from 12 to 8")
end

-- deletePattern clears loop points that fall inside the deleted range
do
    local t = Track.new()
    Track.addPattern(t, 4)  -- pattern 1: steps 1-4
    Track.addPattern(t, 4)  -- pattern 2: steps 5-8

    Track.setLoopStart(t, 5)
    Track.setLoopEnd(t, 8)

    Track.deletePattern(t, 2)
    assert(Track.getLoopStart(t) == nil, "loopStart inside deleted range should be cleared")
    assert(Track.getLoopEnd(t) == nil, "loopEnd inside deleted range should be cleared")
end

-- deletePattern cannot remove the last pattern
do
    local t = Track.new()
    Track.addPattern(t, 4)
    local ok, _ = pcall(Track.deletePattern, t, 1)
    assert(not ok, "deleting the last pattern should error")
end

-- ---------------------------------------------------------------------------
-- insertPattern — inserts at a specific position
-- ---------------------------------------------------------------------------

do
    local t = Track.new()
    Track.addPattern(t, 4)  -- pattern 1: steps 1-4
    Track.addPattern(t, 4)  -- pattern 2: steps 5-8
    Track.setStep(t, 1, Step.new(60, 100, 1, 1))
    Track.setStep(t, 5, Step.new(72, 100, 1, 1))

    -- Insert a 2-step pattern at position 2 (between existing patterns).
    Track.insertPattern(t, 2, 2)
    assert(Track.getPatternCount(t) == 3, "patternCount should be 3 after insert")
    assert(Track.getStepCount(t) == 10, "stepCount should be 10 (4+2+4)")

    -- Original pattern 1 still at position 1.
    assert(Step.getPitch(Track.getStep(t, 1)) == 60, "pattern 1 step 1 should be unchanged")
    -- New pattern at position 2 with default steps (pitch 60).
    assert(Step.getPitch(Track.getStep(t, 5)) == 60, "new pattern step 1 should be default")
    -- Original pattern 2 shifted to position 3.
    assert(Step.getPitch(Track.getStep(t, 7)) == 72, "old pattern 2 step 1 should now be at flat index 7")
end

-- insertPattern adjusts loop points
do
    local t = Track.new()
    Track.addPattern(t, 4)  -- pattern 1: steps 1-4
    Track.addPattern(t, 4)  -- pattern 2: steps 5-8
    Track.setLoopStart(t, 5)
    Track.setLoopEnd(t, 8)

    -- Insert 3-step pattern at position 1 (before everything).
    Track.insertPattern(t, 1, 3)
    assert(Track.getLoopStart(t) == 8, "loopStart should shift from 5 to 8")
    assert(Track.getLoopEnd(t) == 11, "loopEnd should shift from 8 to 11")
end

-- ---------------------------------------------------------------------------
-- swapPatterns
-- ---------------------------------------------------------------------------

do
    local t = Track.new()
    Track.addPattern(t, 2)
    Track.addPattern(t, 3)
    Track.setStep(t, 1, Step.new(60, 100, 1, 1))
    Track.setStep(t, 2, Step.new(62, 100, 1, 1))
    Track.setStep(t, 3, Step.new(72, 100, 1, 1))
    Track.setStep(t, 4, Step.new(74, 100, 1, 1))
    Track.setStep(t, 5, Step.new(76, 100, 1, 1))

    Track.setLoopStart(t, 1)
    Track.setLoopEnd(t, 2)

    Track.swapPatterns(t, 1, 2)
    assert(Track.getPatternCount(t) == 2, "swapPatterns should not change patternCount")
    -- After swap: pattern 1 is old pattern 2 (3 steps), pattern 2 is old pattern 1 (2 steps)
    assert(Track.getStepCount(t) == 5, "stepCount should still be 5")
    assert(Step.getPitch(Track.getStep(t, 1)) == 72, "swapped pattern 1 step 1 should be 72")
    assert(Step.getPitch(Track.getStep(t, 4)) == 60, "swapped pattern 2 step 1 should be 60")
    -- Loop points should be cleared after swap.
    assert(Track.getLoopStart(t) == nil, "loopStart should be cleared after swap")
    assert(Track.getLoopEnd(t) == nil, "loopEnd should be cleared after swap")
end

-- ---------------------------------------------------------------------------
-- pastePattern — overwrites destination with source data
-- ---------------------------------------------------------------------------

do
    local t = Track.new()
    Track.addPattern(t, 2)
    Track.addPattern(t, 2)
    Track.setStep(t, 1, Step.new(60, 100, 1, 1))
    Track.setStep(t, 2, Step.new(62, 100, 1, 1))
    Track.setStep(t, 3, Step.new(72, 100, 1, 1))
    Track.setStep(t, 4, Step.new(74, 100, 1, 1))

    -- Paste pattern 1 over pattern 2.
    local src = Track.getPattern(t, 1)
    Track.pastePattern(t, 2, src)

    assert(Step.getPitch(Track.getStep(t, 3)) == 60, "pasted step 1 should match source")
    assert(Step.getPitch(Track.getStep(t, 4)) == 62, "pasted step 2 should match source")

    -- Deep copy — mutating paste target should not affect source.
    Step.setPitch(Track.getStep(t, 3), 48)
    assert(Step.getPitch(Track.getStep(t, 1)) == 60, "source unaffected after pasting and mutating")
end

print("tests/track.lua OK")
