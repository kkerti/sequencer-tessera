-- ===========================================================================
-- controls.lua — Grid VSN1 control surface for the sequencer
-- ---------------------------------------------------------------------------
-- This file is laid out in BLOCKS. Each block is the Lua you paste into a
-- specific event slot inside the Grid Editor for the VSN1 module. The block
-- header tells you exactly which control element + event to paste it into.
--
-- Hardware layout (VSN1):
--   8 keyswitch buttons    → step-scoped + direction selectors:
--                              0:s  1:t  2:p  3:m   (top row)
--                              4:b  5:a  6:d  7:g   (bottom row)
--   1 endless jog-wheel    → edits the value of the currently-selected param
--   1 endless click        → toggles current step's active flag, OR clears
--                            the loop boundary when `l` / `e` is selected
--   1 320x240 LCD screen   → top half = 4x2 cells of (label, value); bottom
--                            half = timeline strip (status + step boxes)
--   4 small screen buttons → 0:l (loopStart)  1:e (loopEnd)  2,3 reserved
--
-- Transport (start/stop/reset/panic) is driven by EXTERNAL MIDI CLOCK
-- (0xFA / 0xFC) via the rtmidi callback in grid_module.lua. There is no
-- "start" hardware button on this control surface.
--
-- Required uploads:
--   /sequencer.lua      ← grid/sequencer.lua    (engine + driver)
--   /controls.lua       ← grid/controls.lua     (UI; LAZY-LOADED on first
--                                                 button press — see PI())
--   /four_on_floor.lua  ← grid/four_on_floor.lua
--
-- The UI module is intentionally NOT loaded at boot. It costs ~25 KB of
-- heap, and pure-playback patches never touch the controls. The first
-- button press calls PI() which lazy-requires it. See
-- docs/2026-04-29-memory-overflow-plan.md for the rationale.
--
-- PARAM CODES (single chars — see docs/CODEBOOK.md):
--   "s" step       "t" track    "p" pattern    "m" direction
--   "b" cvB        "a" cvA      "d" duration   "g" gate
--   "l" loopStart  "e" loopEnd  (small buttons only)
--
-- Globals exported by BLOCK 1:
--   D  = driver instance      P  = Controls module (nil until PI() runs)
--   E  = engine instance      EM = midi-emit callback
--   DR = Driver module        (referenced by BLOCK 14 rtmidi callback)
--   MC = midi-clock counter   MP = midi-clocks per engine pulse
--   PI = function() lazy-loads /controls.lua and inits it
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- BLOCK 1 — UTILITY EVENT (system event → setup)
-- ---------------------------------------------------------------------------
-- Runs ONCE on module boot / page load, AFTER all per-element init events.
-- Loads the bundle, builds the engine + driver, and defines PI() — the
-- on-demand loader for the UI module. The UI itself is NOT loaded here:
-- it loads only when the user presses a control button (or initialises the
-- screen — see BLOCK 12).
-- ---------------------------------------------------------------------------

local Driver = require("/sequencer")
local desc   = require("/four_on_floor")
DR = Driver       -- global so the rtmidi callback (BLOCK 14) can reach it
E  = Driver.PatchLoader.build(desc)
D  = Driver.new(E, nil, desc.bpm)
MC = 0
MP = 24 / E.pulsesPerBeat
package.loaded["/four_on_floor"] = nil
desc = nil
collectgarbage("collect")
EM = function(ev, pi, ve, ch)
    if ev == "NOTE_ON" then midi_send(ch, 0x90, pi, ve)
    else                    midi_send(ch, 0x80, pi, 0) end
end
-- Lazy loader for the UI. Idempotent. SCREEN INIT (BLOCK 12) may have
-- already required the module before this block ran (event-order is not
-- guaranteed); in that case `P` is already a table and we just need to
-- call P.init(E) once `E` exists.
function PI()
    if not P then P = require("/controls") end
    if not P.S then P.init(E) end
end


-- ---------------------------------------------------------------------------
-- BLOCK 2 — BUTTON 0  (top-left keyswitch) → BUTTON EVENT
-- ---------------------------------------------------------------------------
-- One line per button. The argument is the param code from BLOCK 1's table.
-- The `button_state() == 127` guard fires only on the press edge.
-- PI() lazy-loads the UI module on first use.
-- ---------------------------------------------------------------------------

if self:button_state() == 127 then PI() P.select("s") end

-- ---------------------------------------------------------------------------
-- BLOCK 3 — BUTTON 1 → BUTTON EVENT
-- ---------------------------------------------------------------------------
if self:button_state() == 127 then PI() P.select("t") end

-- ---------------------------------------------------------------------------
-- BLOCK 4 — BUTTON 2 → BUTTON EVENT
-- ---------------------------------------------------------------------------
if self:button_state() == 127 then PI() P.select("p") end

-- ---------------------------------------------------------------------------
-- BLOCK 5 — BUTTON 3 → BUTTON EVENT  (direction-mode selector)
-- ---------------------------------------------------------------------------
-- Selects `m`. Rotation on the endless cycles forward → reverse → pingpong
-- → random → brownian (and wraps). The endless click is a no-op when `m`
-- is selected (cycling is already covered by rotation).
-- ---------------------------------------------------------------------------
if self:button_state() == 127 then PI() P.select("m") end

-- ---------------------------------------------------------------------------
-- BLOCK 6 — BUTTON 4 → BUTTON EVENT
-- ---------------------------------------------------------------------------
if self:button_state() == 127 then PI() P.select("b") end

-- ---------------------------------------------------------------------------
-- BLOCK 7 — BUTTON 5 → BUTTON EVENT
-- ---------------------------------------------------------------------------
if self:button_state() == 127 then PI() P.select("a") end

-- ---------------------------------------------------------------------------
-- BLOCK 8 — BUTTON 6 → BUTTON EVENT
-- ---------------------------------------------------------------------------
if self:button_state() == 127 then PI() P.select("d") end

-- ---------------------------------------------------------------------------
-- BLOCK 9 — BUTTON 7 → BUTTON EVENT
-- ---------------------------------------------------------------------------
if self:button_state() == 127 then PI() P.select("g") end


-- ---------------------------------------------------------------------------
-- BLOCK 10 — ENDLESS (jog-wheel) → ENDLESS EVENT
-- ---------------------------------------------------------------------------
-- The endless emits 65 (clockwise / "up") or 63 (counter-clockwise / "down")
-- per docs/lib-2-hw-map.md. Per intech docs the canonical relative-mode
-- values differ (mode 1 -> 8146/8247, mode 2 -> 127/1) — 65/63 implies a
-- custom min/max scaling configured in the editor. If on-device testing
-- shows different values, swap the constants below. Anything outside the
-- two expected values is silently ignored.
-- Endless rotation before any button press is ignored (no UI loaded yet).
-- ---------------------------------------------------------------------------

if P then
    local v = self:endless_value()
    if     v == 65 then P.edit( 1)
    elseif v == 63 then P.edit(-1)
    end
end


-- ---------------------------------------------------------------------------
-- BLOCK 11 — ENDLESS (jog-wheel) → BUTTON EVENT
-- ---------------------------------------------------------------------------
-- Pressing the jog wheel toggles the currently-selected step's active flag
-- (mute / unmute). Press edge only.
-- ---------------------------------------------------------------------------

if self:button_state() == 127 then PI() P.toggle() end


-- ---------------------------------------------------------------------------
-- BLOCK 12 — SCREEN → INIT EVENT
-- ---------------------------------------------------------------------------
-- One-time full-screen wipe + static grid dividers. Self-bootstrapping:
-- this event may fire BEFORE the UTILITY event (BLOCK 1) on some firmware
-- revisions, so it does NOT depend on `E`, `D`, or `PI` being defined yet.
-- It only needs the `/controls.lua` module on disk; M.initScreen draws
-- static dividers and does not touch the engine. M.init(E) is deferred
-- to the first DRAW pass (BLOCK 13).
-- ---------------------------------------------------------------------------

P = P or require("/controls")
P.initScreen(self)


-- ---------------------------------------------------------------------------
-- BLOCK 13 — SCREEN → DRAW EVENT
-- ---------------------------------------------------------------------------
-- Surgical redraw of any cells flagged dirty since the last frame. The
-- module issues at most one draw_swap() per call (and only if something
-- actually changed). We lazily call M.init(E) on the first frame where
-- the engine is available, so the engine and screen events can fire in
-- any order at boot.
-- ---------------------------------------------------------------------------

if P and E then
    if not P.S then P.init(E) end
    P.draw(self)
end


-- ---------------------------------------------------------------------------
-- BLOCK 14 — RTMIDI CALLBACK (system event → rtmidi receive)
-- ---------------------------------------------------------------------------
-- External MIDI clock drives playback. We only handle the four transport
-- bytes; everything else (note-on/off from upstream, CCs, etc.) is ignored.
--
--   0xF8 = clock pulse (24 ppq) — divided down by MP to engine pulses
--   0xFA = start  (rewind + run)
--   0xFB = continue (run from current position)
--   0xFC = stop   (halt + flush all-notes-off)
--
-- Identical to the rtmidi block in grid_module.lua; kept here so the control
-- surface is self-contained and ready to drop into a stock VSN1 module
-- without also pasting grid_module.lua. If you have already pasted
-- grid_module.lua's callback, skip this block.
-- ---------------------------------------------------------------------------

self.rtmrx_cb = function(self, t)
    if t == 0xF8 then
        if D.running then
            MC = MC + 1
            if MC >= MP then
                MC = 0
                DR.externalPulse(D, EM)
            end
        end
    elseif t == 0xFA then
        MC = 0
        DR.start(D)
    elseif t == 0xFB then
        MC = 0
        D.running = true
    elseif t == 0xFC then
        DR.stop(D)
        DR.allNotesOff(D, EM)
    end
end


-- ===========================================================================
-- END OF CONTROLS.LUA
--
-- Notes for future expansion:
--   * Small screen buttons 2 + 3 are reserved. Easy candidates: page
--     left/right, parameter sub-mode (e.g. mathops jitter on the focused
--     param), screen mode toggle (grid / step list).
--   * A "step list" view would draw all N steps of the current pattern as
--     a horizontal row with the cursor highlighted. Add it as a second
--     screen mode behind one of the small buttons.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- BLOCK 15 — SMALL BUTTON 0 → BUTTON EVENT  (loopStart selector)
-- ---------------------------------------------------------------------------
-- Selects `l`. Rotation on the endless moves loopStart by ±1 (clamped
-- 1..loopEnd). If loopStart was nil ("off"), rotation initialises it to
-- the current step. The endless click clears loopStart back to nil.
-- ---------------------------------------------------------------------------
if self:button_state() == 127 then PI() P.select("l") end


-- ---------------------------------------------------------------------------
-- BLOCK 16 — SMALL BUTTON 1 → BUTTON EVENT  (loopEnd selector)
-- ---------------------------------------------------------------------------
-- Same as BLOCK 15 but for loopEnd. Clamped loopStart..stepCount.
-- The endless click clears loopEnd back to nil.
-- ---------------------------------------------------------------------------
if self:button_state() == 127 then PI() P.select("e") end
