-- tests/live_edit.lua
-- Behavioural tests for live/edit.lua, the in-place compiled-song editor.

local Edit = require("live/edit")
local Player = require("player/player")

-- Build a tiny synthetic song with two notes (C3 then E3, gate=2 each, on
-- a 4-pulse grid). Includes the writer sidecars so we can exercise pairOff.
local function makeSong()
    return {
        bpm = 120, pulsesPerBeat = 4, durationPulses = 16, loop = true,
        eventCount = 4,
        atPulse  = { 1, 3, 5, 7 },
        kind     = { 1, 0, 1, 0 },        -- ON, OFF, ON, OFF
        pitch    = { 60, 60, 64, 64 },
        velocity = { 100, 0, 110, 0 },
        channel  = { 1, 1, 1, 1 },
        hasProbability = true,
        pairOff     = { 2, 0, 4, 0 },
        srcStepProb = { 100, 0, 100, 0 },
        srcVelocity = { 100, 0, 110, 0 },
    }
end

-- ---------------------------------------------------------------------------
-- O(1) edits
-- ---------------------------------------------------------------------------

local s = makeSong()
Edit.setPitch(s, 1, 67)
assert(s.pitch[1] == 67, "setPitch: NOTE_ON pitch updated")
assert(s.pitch[2] == 67, "setPitch: paired NOTE_OFF pitch updated")
assert(s.pitch[3] == 64, "setPitch: other event untouched")
print("OK  setPitch updates ON and paired OFF")

-- Regression: setPitch on a STATIC song (no pairOff sidecar) must still
-- update the matching NOTE_OFF, otherwise the player emits NOTE_ON on the
-- new pitch but NOTE_OFF on the old pitch and the new note hangs forever.
-- This caught a bug where setPitch mutated song.pitch[on] BEFORE calling
-- findMate, which then scanned for a NOTE_OFF on the new pitch and missed.
local function makeStaticSong()
    return {
        bpm = 120, pulsesPerBeat = 4, durationPulses = 16, loop = true,
        eventCount = 4,
        atPulse  = { 1, 3, 5, 7 },
        kind     = { 1, 0, 1, 0 },
        pitch    = { 36, 36, 36, 36 },   -- two kicks, identical pitch+channel
        velocity = { 100, 0, 100, 0 },
        channel  = { 10, 10, 10, 10 },
    }
end
s = makeStaticSong()
Edit.setPitch(s, 1, 38)
assert(s.pitch[1] == 38, "setPitch (static): NOTE_ON pitch updated")
assert(s.pitch[2] == 38, "setPitch (static): paired NOTE_OFF pitch updated (would hang otherwise)")
assert(s.pitch[3] == 36, "setPitch (static): later identical-pitch ON untouched")
assert(s.pitch[4] == 36, "setPitch (static): later identical-pitch OFF untouched")
print("OK  setPitch updates paired OFF on static song (no pairOff sidecar)")

s = makeSong()
Edit.setVelocity(s, 3, 80)
assert(s.velocity[3] == 80, "setVelocity: NOTE_ON updated")
assert(s.srcVelocity[3] == 80, "setVelocity: srcVelocity baseline updated")
assert(s.velocity[4] == 0, "setVelocity: NOTE_OFF velocity stays 0")
print("OK  setVelocity updates velocity and srcVelocity baseline")

s = makeSong()
Edit.mutePair(s, 1)
assert(s.kind[1] == 2, "mutePair: NOTE_ON -> 2")
assert(s.kind[2] == 3, "mutePair: NOTE_OFF -> 3")
assert(s.kind[3] == 1, "mutePair: untouched event still active")
Edit.unmutePair(s, 1)
assert(s.kind[1] == 1 and s.kind[2] == 0, "unmutePair restores both halves")
print("OK  mutePair/unmutePair flip kind on both halves")

-- mute() alone only flips the addressed half
s = makeSong()
Edit.mute(s, 1)
assert(s.kind[1] == 2 and s.kind[2] == 0, "mute: only addressed event muted")
print("OK  mute() addresses single half")

-- ---------------------------------------------------------------------------
-- findMate
-- ---------------------------------------------------------------------------

s = makeSong()
assert(Edit.findMate(s, 1) == 2, "findMate: ON->OFF forward scan")
assert(Edit.findMate(s, 4) == 3, "findMate: OFF->ON backward scan")
print("OK  findMate scans forward and backward correctly")

-- ---------------------------------------------------------------------------
-- Player picks up edits at runtime
-- ---------------------------------------------------------------------------

s = makeSong()
Edit.mutePair(s, 1)
local emitted = {}
local function emit(evt, p, v, c)
    emitted[#emitted + 1] = { evt = evt, p = p }
end
local p = Player.new(s)
Player.start(p)
for _ = 1, 8 do Player.externalPulse(p, emit) end
-- Only the second note should have fired (ON+OFF for pitch 64).
assert(#emitted == 2, "player skipped muted pair")
assert(emitted[1].p == 64 and emitted[1].evt == "NOTE_ON",
    "player emitted only the unmuted note's ON")
assert(emitted[2].evt == "NOTE_OFF" and emitted[2].p == 64,
    "player emitted only the unmuted note's OFF")
print("OK  player skips muted pair at runtime")

-- ---------------------------------------------------------------------------
-- setRatchet — splice
-- ---------------------------------------------------------------------------

-- Start from a single-step (currentCount=1) and ratchet it to 4.
-- subPulses=1, gatePulses=1 => 4 ratchets at pulses 1,2,3,4 with OFFs at 2,3,4,5.
s = {
    bpm = 120, pulsesPerBeat = 4, durationPulses = 16, loop = true,
    eventCount = 2,
    atPulse  = { 1, 2 },
    kind     = { 1, 0 },
    pitch    = { 60, 60 },
    velocity = { 100, 0 },
    channel  = { 1, 1 },
    hasProbability = true,
    pairOff     = { 2, 0 },
    srcStepProb = { 100, 0 },
    srcVelocity = { 100, 0 },
}

Edit.setRatchet(s, {
    firstOnIdx = 1, currentCount = 1, currentSubPulses = 1, currentGate = 1,
    newCount = 4, newSubPulses = 1, newGate = 1,
})
assert(s.eventCount == 8, "setRatchet 1->4: eventCount = 8 (got " .. s.eventCount .. ")")
-- Expected sorted timeline: at=1 ON, at=2 OFF, at=2 ON, at=3 OFF, at=3 ON,
-- at=4 OFF, at=4 ON, at=5 OFF.
local expectedAt   = { 1, 2, 2, 3, 3, 4, 4, 5 }
local expectedKind = { 1, 0, 1, 0, 1, 0, 1, 0 }
for i = 1, 8 do
    assert(s.atPulse[i] == expectedAt[i],
        ("setRatchet 1->4: atPulse[%d]=%d expected %d"):format(i, s.atPulse[i], expectedAt[i]))
    assert(s.kind[i] == expectedKind[i],
        ("setRatchet 1->4: kind[%d]=%d expected %d"):format(i, s.kind[i], expectedKind[i]))
    assert(s.pitch[i] == 60, "setRatchet: pitch carried")
    assert(s.channel[i] == 1, "setRatchet: channel carried")
end
print("OK  setRatchet 1->4 produces 4 ON/OFF pairs in correct order")

-- Verify pairOff is consistent: every ON points to an OFF on same (pitch, ch).
for i = 1, s.eventCount do
    if s.kind[i] == 1 then
        local off = s.pairOff[i]
        assert(off > i, "pairOff: ON points forward")
        assert(s.kind[off] == 0, "pairOff: target is a NOTE_OFF")
        assert(s.pitch[off] == s.pitch[i], "pairOff: same pitch")
    end
end
print("OK  setRatchet rebuilt pairOff consistently")

-- Ratchet down: 4 -> 1
Edit.setRatchet(s, {
    firstOnIdx = 1, currentCount = 4, currentSubPulses = 1, currentGate = 1,
    newCount = 1, newSubPulses = 1, newGate = 1,
})
assert(s.eventCount == 2, "setRatchet 4->1: eventCount = 2 (got " .. s.eventCount .. ")")
assert(s.atPulse[1] == 1 and s.kind[1] == 1, "setRatchet 4->1: ON at pulse 1")
assert(s.atPulse[2] == 2 and s.kind[2] == 0, "setRatchet 4->1: OFF at pulse 2")
print("OK  setRatchet 4->1 collapses back to one pair")

-- ---------------------------------------------------------------------------
-- Edit queue
-- ---------------------------------------------------------------------------

s = {
    bpm = 120, pulsesPerBeat = 4, durationPulses = 16, loop = true,
    eventCount = 2,
    atPulse  = { 1, 2 },
    kind     = { 1, 0 },
    pitch    = { 60, 60 },
    velocity = { 100, 0 },
    channel  = { 1, 1 },
}
local q = Edit.newQueue()
Edit.queueRatchetEdit(q, {
    firstOnIdx = 1, currentCount = 1, currentSubPulses = 1, currentGate = 1,
    newCount = 3, newSubPulses = 1, newGate = 1,
})
assert(#q == 1, "queue holds the edit")
assert(s.eventCount == 2, "song untouched until applyQueue")
local applied = Edit.applyQueue(s, q)
assert(applied == 1, "applyQueue returns count")
assert(#q == 0, "queue cleared after apply")
assert(s.eventCount == 6, "song mutated to 3 ratchets (got " .. s.eventCount .. ")")
print("OK  queueRatchetEdit / applyQueue defers and applies correctly")

-- ---------------------------------------------------------------------------
-- Multi-event song with non-group neighbours: ratchet edit on a middle step
-- must not disturb surrounding notes.
-- ---------------------------------------------------------------------------

s = {
    bpm = 120, pulsesPerBeat = 4, durationPulses = 32, loop = true,
    eventCount = 6,
    atPulse  = { 1, 3, 9, 11, 17, 19 },
    kind     = { 1, 0, 1, 0, 1, 0 },
    pitch    = { 60, 60, 64, 64, 67, 67 },
    velocity = { 100, 0, 100, 0, 100, 0 },
    channel  = { 1, 1, 1, 1, 1, 1 },
    hasProbability = true,
    pairOff     = { 2, 0, 4, 0, 6, 0 },
    srcStepProb = { 100, 0, 100, 0, 100, 0 },
    srcVelocity = { 100, 0, 100, 0, 100, 0 },
}
-- Ratchet the middle step (pitch 64 ON at index 3, OFF at index 4 with
-- gate=2) from 1 to 2 ratchets.
Edit.setRatchet(s, {
    firstOnIdx = 3, currentCount = 1, currentSubPulses = 1, currentGate = 2,
    newCount = 2, newSubPulses = 1, newGate = 1,
})
-- Expected: surrounding events untouched in identity, middle expanded.
-- After splice: pitch 60 group at start, pitch 64 ratchets x2, pitch 67 at end.
assert(s.eventCount == 8, "middle ratchet: eventCount = 8 (got " .. s.eventCount .. ")")
-- Find the pitch-67 ON; its pairOff should still point to a NOTE_OFF on pitch 67.
local found67On = nil
for i = 1, s.eventCount do
    if s.kind[i] == 1 and s.pitch[i] == 67 then found67On = i; break end
end
assert(found67On, "pitch 67 still present after middle ratchet edit")
local mate = s.pairOff[found67On]
assert(s.kind[mate] == 0 and s.pitch[mate] == 67,
    "pitch 67 NOTE_ON still paired with its NOTE_OFF")
print("OK  middle-step ratchet edit preserves neighbouring events")

print("\nALL OK — live/edit.lua tests passed")
