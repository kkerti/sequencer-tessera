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

print("\nALL OK — live/edit.lua tests passed")
