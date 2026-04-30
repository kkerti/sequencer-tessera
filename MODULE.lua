-- MODULE.lua
-- =============================================================================
-- ON-DEVICE ENTRY POINT for the sequencer running on Intech Studio Grid VSN1.
-- =============================================================================
--
-- This file is NOT a runnable Lua script. It is a reference manual that shows
-- which sequencer code goes into which Grid event slot. Copy each labeled
-- section into the matching event in the Grid Editor.
--
-- Build first:
--     lua tools/build_dist.lua          -> dist/sequencer.lua  (~12 KB)
--
-- Upload `dist/sequencer.lua` to the module's filesystem so `require("sequencer")`
-- can find it. (Grid Editor's "page module" upload covers this; the exact
-- mechanism depends on how you packaged the module.)
--
-- Hardware mapping for VSN1 (per docs/archive/LIB-2-HW-MAP.md):
--   Screen        : 320 x 240, 4x2 cell layout
--   4 small btns  : optional shortcuts (RESET, PANIC, etc.)  -- NOT used in v1
--   8 keyswitches : select which parameter the endless controls (cells 1..8)
--   Endless       : relative encoder; emits 65 (up) / 63 (down). Edits the
--                   currently selected parameter.
--
-- Contracts (all "self:" calls are required by the Grid runtime; see
-- docs/archive/GRID_HARDWARE_API.md).
-- =============================================================================


-- =============================================================================
-- [1] MODULE INIT EVENT
-- -----------------------------------------------------------------------------
-- Place this in the module-level Init event. Runs once on power-on / page load.
-- Loads the bundled sequencer, configures default tracks, and stores the
-- modules in globals so other events can reach them.
-- =============================================================================

-- The bundled file returns a table of submodules: step / track / engine /
-- driver_grid / controls. We expose them via globals because Grid events run
-- in separate Lua chunks.
SEQ    = require("sequencer")     -- requires dist/sequencer.lua present
ENGINE = SEQ.engine
TRACK  = SEQ.track
STEP   = SEQ.step
CTL    = SEQ.controls

ENGINE.init({
    trackCount    = 4,
    stepsPerTrack = 64,
    -- log = nil  -- no logging on device; saves a function call per pulse
})

-- Optional: seed first track with something audible so we can verify on boot.
-- Comment out for production once you're authoring sequences via the UI.
local notes = { 60, 63, 67, 70, 72, 67, 63, 60 }
for i, p in ipairs(notes) do
    ENGINE.tracks[1].steps[i] = STEP.pack({
        pitch = p, vel = 100, dur = 6, gate = 3,
    })
end
ENGINE.tracks[1].len  = #notes
ENGINE.tracks[1].chan = 1

CTL.dirtyAll() -- mark all 8 screen cells for first-frame redraw


-- =============================================================================
-- [2] MIDI RX  (clock + transport from Ableton)
-- -----------------------------------------------------------------------------
-- Place this in the module's MIDI Rx event. The runtime calls `rtmrx_cb`
-- with the incoming Real-Time status byte:
--     0xF8  CLOCK    -> advance engine one pulse, ship its events out
--     0xFA  START    -> reset transport, start playing
--     0xFB  CONTINUE -> resume without reset
--     0xFC  STOP     -> stop, flush any held notes
--
-- We consume the engine's events here and call `midi_send(channel, command,
-- p1, p2)` directly. No driver layer in between.
--
-- IMPORTANT: each Grid event is its own Lua chunk; globals set in [1] do
-- not necessarily survive into [2]. We therefore compare event types against
-- the literal values defined in src/track.lua: 1 = note-on, 2 = note-off.
-- =============================================================================

self.rtmrx_cb = function(self, t)
    if t == 0xF8 then
        local events = ENGINE.onPulse()
        if events then
            for i = 1, #events do
                local e = events[i]
                if e.type == 1 then              -- EV_ON
                    midi_send(e.ch, 0x90, e.pitch, e.vel)
                else                              -- EV_OFF
                    midi_send(e.ch, 0x80, e.pitch, 0)
                end
            end
        end
    elseif t == 0xFA then
        ENGINE.onStart()
    elseif t == 0xFB then
        if not ENGINE.running then
            ENGINE.onStart()
        end
    elseif t == 0xFC then
        local off = ENGINE.onStop()
        if off then
            for i = 1, #off do
                local e = off[i]
                midi_send(e.ch, 0x80, e.pitch, 0)
            end
        end
    end
end


-- =============================================================================
-- [3] SCREEN DRAW EVENT
-- -----------------------------------------------------------------------------
-- Place this in the Screen control element's Draw event. Runs every render
-- cycle (capped at ~20 fps by the runtime).
--
-- M.draw() does surgical redraws — only cells flagged dirty since last frame
-- are repainted, then ONE draw_swap() commits them. Idle frames are nearly
-- free.
-- =============================================================================

CTL.draw(self)


-- =============================================================================
-- [4] KEYSWITCH BUTTON EVENTS  (8 buttons -> select parameter)
-- -----------------------------------------------------------------------------
-- Place this in the Button event of EACH of the 8 keyswitches. The handler
-- only acts on the press edge. `self:element_index()` returns the element's
-- index (0..15 on a 16-button module); we map keyswitches 0..7 to cells 1..8
-- of the screen grid.
--
-- Cell layout (from src/controls.lua):
--     1 TRACK   2 STEP    3 NOTE   4 VEL
--     5 DUR     6 GATE    7 RATCH  8 PROB
-- =============================================================================

if self:button_state() == 127 then       -- press edge only
    local idx = self:element_index() + 1 -- 0-based -> 1-based
    if idx >= 1 and idx <= 8 then
        CTL.onKey(idx)
    end
end


-- =============================================================================
-- [5] ENDLESS ENCODER EVENT  (relative; edits the focused parameter)
-- -----------------------------------------------------------------------------
-- Place this in the Endless control element's Endless event. The encoder
-- emits 65 for clockwise (up) and 63 for counter-clockwise (down) in
-- relative mode (see docs/archive/LIB-2-HW-MAP.md).
-- =============================================================================

local v = self:enc_value() -- adjust to your runtime's encoder getter
if v == 65 then
    CTL.onEndless(1)
elseif v == 63 then
    CTL.onEndless(-1)
end


-- =============================================================================
-- [6] (OPTIONAL) ENDLESS CLICK EVENT  -> cycle some setting
-- -----------------------------------------------------------------------------
-- The endless wheel is also clickable (button event on the same control
-- element). Wire this only if you want a click action (e.g. toggle the
-- focused step's `active` flag). Skip for v1.
-- =============================================================================

if self:button_state() == 127 then
    -- Example: toggle `active` of the currently selected step
    local cur = STEP.active(ENGINE.tracks[CTL.selT].steps[CTL.selS]) and 1 or 0
    ENGINE.setStepParam(CTL.selT, CTL.selS, "active", 1 - cur)
    CTL.dirtyAll()
end


-- =============================================================================
-- [7] (OPTIONAL) GROUP EDIT TRIGGER  -> 4 small buttons under the screen
-- -----------------------------------------------------------------------------
-- The 4 small buttons under the LCD are unused in v1. Suggested mapping for
-- v2 group-edit experiments (do not include yet):
--     small btn 0 : begin range (anchor at current step)
--     small btn 1 : end range and apply "set" to focused param
--     small btn 2 : end range and apply "add +1" to focused param
--     small btn 3 : end range and apply "rand" min..max (hard-coded for now)
--
-- The Core API is already there:
--     ENGINE.groupEdit(t, from, to, "set"|"add"|"rand", paramName, value)
-- =============================================================================


-- =============================================================================
-- [8] DEBUG / SANITY CHECK  (paste into a temp button to verify install)
-- -----------------------------------------------------------------------------
-- Quick "are the modules really loaded?" check. Returns a string visible in
-- the Grid Editor console.
-- =============================================================================

-- print(string.format("tracks=%d cap=%d step1=%d",
--     #ENGINE.tracks, ENGINE.tracks[1].cap,
--     STEP.pitch(ENGINE.tracks[1].steps[1])))


-- =============================================================================
-- NOTES
-- -----------------------------------------------------------------------------
-- * Ableton: enable "Sync" -> send MIDI clock to the Grid module's input port.
--   The module's MIDI Rx event handler ([2]) does the rest.
-- * No internal clock — if Ableton is stopped, the engine produces no events.
-- * One voice per track. Track-N notes go out on MIDI channel N (1..4) by
--   default; change in [1] via `ENGINE.tracks[i].chan = ch`.
-- * Memory budget: 4 tracks * 64 packed-int steps = 256 ints (~2 KB) plus a
--   few hundred bytes of runtime state. Under 5 KB total in Lua heap terms.
-- * If you change `src/`, rebuild with `lua tools/build_dist.lua` and re-upload
--   `dist/sequencer.lua` before re-loading the page.
-- =============================================================================
