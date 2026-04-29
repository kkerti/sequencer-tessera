-- tests/controls.lua
-- Tests for sequencer/controls.lua: the VSN1 control-surface helper.
-- Verifies the editing / selection / dirty-flag model without involving
-- the actual screen API.

package.path = package.path .. ";./?.lua"

local Controls    = require("sequencer/controls")
local PatchLoader = require("sequencer/patch_loader")

-- Build a small engine to drive the controls against.
local descriptor = {
    bpm = 120,
    ppb = 4,
    tracks = {
        {
            midiChannel = 1,
            patterns = {
                { name = "P1", steps = {
                    { pitch = 60, velocity = 100, duration = 4, gate = 2 },
                    { pitch = 62, velocity = 100, duration = 4, gate = 2 },
                    { pitch = 64, velocity = 100, duration = 4, gate = 2 },
                } },
                { name = "P2", steps = {
                    { pitch = 67, velocity = 110, duration = 4, gate = 2 },
                } },
            },
        },
        {
            midiChannel = 2,
            patterns = {
                { name = "T2P1", steps = {
                    { pitch = 36, velocity = 100, duration = 4, gate = 2 },
                    { pitch = 38, velocity = 100, duration = 4, gate = 2 },
                } },
            },
        },
    },
}

local engine = PatchLoader.build(descriptor)
Controls.init(engine)

-- ---- INITIAL STATE -------------------------------------------------------
assert(Controls.S.sel == "s",   "init selects step")
assert(Controls.S.tr  == 1,     "init track = 1")
assert(Controls.S.pa  == 1,     "init pattern = 1")
assert(Controls.S.st  == 1,     "init step = 1")
assert(Controls.S.focusDirty,   "init focusDirty true")
for _, c in ipairs({"s","t","p","m","b","a","d","g"}) do
    assert(Controls.S.dirty[c], "init " .. c .. " dirty")
end

-- ---- VALUE READS ---------------------------------------------------------
assert(Controls.value("s") == 1)
assert(Controls.value("t") == 1)
assert(Controls.value("p") == 1)
assert(Controls.value("m") == "forward", "init direction defaults to forward")
assert(Controls.value("l") == nil,       "init loopStart is nil (off)")
assert(Controls.value("e") == nil,       "init loopEnd is nil (off)")
assert(Controls.value("b") == 60,  "step 1 pitch = 60")
assert(Controls.value("a") == 100, "step 1 velocity = 100")
assert(Controls.value("d") == 4,   "step 1 duration = 4")
assert(Controls.value("g") == 2,   "step 1 gate = 2")

-- ---- SELECT --------------------------------------------------------------
Controls.S.dirty.s = false
Controls.S.focusDirty = false
Controls.select("b")
assert(Controls.S.sel  == "b", "select switches sel")
assert(Controls.S.prev == "s", "select records prev")
assert(Controls.S.focusDirty,  "select sets focusDirty")

-- Same-selection no-op
Controls.S.focusDirty = false
Controls.select("b")
assert(not Controls.S.focusDirty, "same-select is a no-op")

-- ---- EDIT cvB (pitch) ----------------------------------------------------
Controls.edit(1)
assert(Controls.value("b") == 61, "cvB +1")
assert(Controls.S.dirty.b,        "cvB edit flags b dirty")

Controls.edit(-5)
assert(Controls.value("b") == 56)

-- Clamp
Controls.edit(-1000)
assert(Controls.value("b") == 0,  "cvB clamps low to 0")
Controls.edit(99999)
assert(Controls.value("b") == 127, "cvB clamps high to 127")

-- ---- EDIT duration (clamped 0..99) ---------------------------------------
Controls.select("d")
Controls.edit(200)
assert(Controls.value("d") == 99, "duration clamps to 99")
Controls.edit(-200)
assert(Controls.value("d") == 0,  "duration clamps to 0")

-- ---- EDIT step (clamped 1..stepCount) ------------------------------------
-- Track 1 has patterns of 3 + 1 = 4 flat steps total.
Controls.select("s")
Controls.edit(1)
assert(Controls.value("s") == 2, "step +1")
Controls.edit(99)
assert(Controls.value("s") == 4, "step clamps to step count (4)")
Controls.edit(-99)
assert(Controls.value("s") == 1, "step clamps low to 1")

-- ---- EDIT track resets pattern + step + flags step cells -----------------
-- Move to a non-default state first.
Controls.select("s"); Controls.edit(2)        -- step = 3
Controls.select("p"); Controls.edit(1)        -- pattern = 2
assert(Controls.value("s") == 3)
assert(Controls.value("p") == 2)

Controls.select("t")
Controls.edit(1)                              -- track 1 -> 2
assert(Controls.value("t") == 2, "track +1")
assert(Controls.value("p") == 1, "track change resets pattern to 1")
assert(Controls.value("s") == 1, "track change resets step to 1")
assert(Controls.S.dirty.b and Controls.S.dirty.a
   and Controls.S.dirty.d and Controls.S.dirty.g,
   "track change flags step-scoped cells dirty")

-- Clamp
Controls.edit(99)
assert(Controls.value("t") == 2, "track clamps high to trackCount (2)")
Controls.edit(-99)
assert(Controls.value("t") == 1, "track clamps low to 1")

-- ---- EDIT pattern (clamped 1..patternCount on current track) -------------
Controls.select("p")
Controls.edit(99)
assert(Controls.value("p") == 2, "pattern clamps to patternCount (2)")
Controls.edit(-99)
assert(Controls.value("p") == 1)

-- Switch back to track 2 (only 1 pattern there) and verify clamp.
Controls.select("t"); Controls.edit(1)        -- track 2
Controls.select("p")
Controls.edit(5)
assert(Controls.value("p") == 1, "pattern on track 2 clamps to 1")

-- ---- EDIT direction (cycles through 5 modes) ----------------------------
Controls.select("m")
assert(Controls.value("m") == "forward")
Controls.edit(1)
assert(Controls.value("m") == "reverse",  "m +1 -> reverse")
Controls.edit(1)
assert(Controls.value("m") == "pingpong", "m +1 -> pingpong")
Controls.edit(1)
assert(Controls.value("m") == "random",   "m +1 -> random")
Controls.edit(1)
assert(Controls.value("m") == "brownian", "m +1 -> brownian")
Controls.edit(1)
assert(Controls.value("m") == "forward",  "m wraps brownian -> forward")
Controls.edit(-1)
assert(Controls.value("m") == "brownian", "m -1 wraps forward -> brownian")
-- Toggle is a no-op for `m`.
local mBefore = Controls.value("m")
Controls.toggle()
assert(Controls.value("m") == mBefore, "toggle is no-op when m selected")
-- Reset back to forward for downstream tests.
Controls.edit(1)
assert(Controls.value("m") == "forward")

-- ---- EDIT loopStart / loopEnd (clamped + nil semantics) ------------------
-- Switch back to track 1 (4 flat steps). Move edit cursor to step 3 so we
-- can verify "rotation initialises nil to current cursor".
Controls.select("t"); Controls.edit(-1)        -- track 2 -> 1
assert(Controls.value("t") == 1)
Controls.select("s"); Controls.edit(2)         -- step = 3
assert(Controls.value("s") == 3)

Controls.select("l")
assert(Controls.value("l") == nil)
Controls.edit(1)                               -- nil -> initialise to cursor = 3 (delta ignored)
assert(Controls.value("l") == 3, "loopStart initialises to current step on first rotation")
Controls.edit(-1)
assert(Controls.value("l") == 2, "loopStart -1")
Controls.edit(-99)
assert(Controls.value("l") == 1, "loopStart clamps low to 1")
-- loopEnd still nil; loopStart bound by stepCount when loopEnd nil.
Controls.edit(99)
assert(Controls.value("l") == 4, "loopStart clamps high to stepCount when loopEnd nil")

-- Clear loopStart and test loopEnd init independently.
Controls.toggle()
assert(Controls.value("l") == nil, "click clears loopStart back to nil")

-- loopEnd initialises to the current edit cursor.
Controls.select("e")
Controls.edit(-1)                              -- nil -> initialise to cursor = 3 (delta ignored)
assert(Controls.value("e") == 3, "loopEnd initialises to current step on first rotation")
Controls.edit(-1)
assert(Controls.value("e") == 2, "loopEnd -1")

-- Now bring loopStart back and verify it clamps to loopEnd.
Controls.select("l")
Controls.edit(1)                               -- init -> cursor = 3, but clamped by loopEnd = 2
assert(Controls.value("l") == 2, "loopStart init clamps to loopEnd")
Controls.edit(99)
assert(Controls.value("l") == 2, "loopStart cannot exceed loopEnd")

-- Click clears the boundary back to nil.
Controls.toggle()
assert(Controls.value("l") == nil, "toggle on l clears loopStart to nil")
Controls.select("e")
Controls.toggle()
assert(Controls.value("e") == nil, "toggle on e clears loopEnd to nil")

-- Returning to step selector resets edit cursor to 1 for downstream tests.
Controls.select("s"); Controls.edit(-99)

-- ---- TOGGLE active -------------------------------------------------------
-- Reset to track 1, step 1.
Controls.select("t"); Controls.edit(-1)
Controls.select("s")
local Step  = require("sequencer/step")
local Track = require("sequencer/track")
local function curStepActive()
    return Step.getActive(Track.getStep(engine.tracks[Controls.S.tr], Controls.S.st))
end
assert(curStepActive(), "step starts active")
Controls.toggle()
assert(not curStepActive(), "toggle deactivates")
assert(Controls.S.dirty.b and Controls.S.dirty.a
   and Controls.S.dirty.d and Controls.S.dirty.g,
   "toggle flags step-scoped cells")
Controls.toggle()
assert(curStepActive(), "toggle reactivates")

-- ---- SELECTING `l`/`e` MARKS TIMELINE DIRTY ------------------------------
-- The aux selectors have no top cell, so their selection state is shown only
-- on the timeline status line. Confirm select() flags the strip dirty.
Controls.S.timelineDirty = false
Controls.select("l")
assert(Controls.S.timelineDirty, "selecting l marks timelineDirty")
Controls.S.timelineDirty = false
Controls.select("e")
assert(Controls.S.timelineDirty, "selecting e marks timelineDirty")
Controls.S.timelineDirty = false
Controls.select("s")
assert(Controls.S.timelineDirty, "leaving an aux selector also marks timelineDirty")

-- ---- DRAW dispatch (no-op screen) ----------------------------------------
-- Verify draw clears all dirty flags + calls draw_swap when dirty cells exist.
-- The timeline (bottom strip) also paints when its dirty flag is set or when
-- the engine cursor advances; tests below take that into account.
local calls = { swap = 0, rect = 0, text = 0, line = 0 }
local fakeScr = {}
function fakeScr:draw_rectangle_filled() calls.rect = calls.rect + 1 end
function fakeScr:draw_text_fast()        calls.text = calls.text + 1 end
function fakeScr:draw_swap()             calls.swap = calls.swap + 1 end
function fakeScr:draw_line()             calls.line = calls.line + 1 end

-- Mark every cell dirty + force timeline clean so we count cells precisely.
for _, c in ipairs({"s","t","p","m","b","a","d","g"}) do
    Controls.S.dirty[c] = true
end
Controls.S.focusDirty    = false  -- isolate dirty-cell path
Controls.S.timelineDirty = false
Controls.S.cur           = engine.tracks[Controls.S.tr].cursor   -- suppress auto-redraw

Controls.draw(fakeScr)
assert(calls.swap == 1, "draw issues exactly one swap when dirty")
assert(calls.rect == 8, "draw paints 8 cell backgrounds (timeline suppressed)")
assert(calls.text == 16, "draw paints 8 labels + 8 values")
for _, c in ipairs({"s","t","p","m","b","a","d","g"}) do
    assert(not Controls.S.dirty[c], "draw clears " .. c .. " dirty flag")
end

-- Second draw with no dirty + cursor stable: no swap.
calls.swap = 0; calls.rect = 0; calls.text = 0; calls.line = 0
Controls.draw(fakeScr)
assert(calls.swap == 0, "draw with nothing dirty issues no swap")

-- Timeline auto-redraw: bump cursor and verify the strip repaints.
engine.tracks[Controls.S.tr].cursor = 2
calls.swap = 0; calls.rect = 0; calls.text = 0; calls.line = 0
Controls.draw(fakeScr)
assert(calls.swap == 1, "cursor advance triggers a swap (timeline redraw)")
assert(calls.rect >= 2, "timeline redraw paints wipe + step boxes")
assert(calls.text >= 1, "timeline redraw paints status line")
assert(Controls.S.cur == 2, "S.cur tracks engine cursor after redraw")

-- focusDirty path: redraws old + new cells only (timeline already up to date).
Controls.S.sel  = "s"
Controls.S.prev = "g"
Controls.S.focusDirty = true
Controls.S.timelineDirty = false
calls.swap = 0; calls.rect = 0; calls.text = 0; calls.line = 0
Controls.draw(fakeScr)
assert(calls.swap == 1, "focus-only draw issues one swap")
assert(calls.rect == 2, "focus-only draw repaints 2 cells")

print("controls: all tests passed")
