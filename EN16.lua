-- EN16.lua
-- =============================================================================
-- ON-DEVICE ENTRY POINT for the EN16 satellite module.
-- =============================================================================
--
-- Topology:  [ ... ][ VSN1 ][ EN16 ]   (EN16 is one column right of VSN1)
--   VSN1 -> EN16   immediate_send( 1, 0, "EN16.S(...)") etc.   (VSN1's right neighbour)
--   EN16 -> VSN1   immediate_send(-1, 0, "vsn1_t(...)") etc.   (EN16's left neighbour)
--
-- EN16 is a pure reactive shadow. It does NOT own the engine, does NOT
-- listen to MIDI clock, and does NOT keep time. VSN1 pushes everything
-- it needs to know:
--   S/V/M : shadow + meta updates on edits or viewport/track switches
--   H     : playhead slot (1..16, or 0 = playhead not in this window)
--
-- Bundle: dist/sequencer_en16.lua  (standalone — no Core dependency)
--
-- Anti-feedback: EN16 only mutates its shadow when VSN1 pushes. Local
-- turns/presses are forwarded as intent only (vsn1_t/vsn1_p).
-- =============================================================================


-- =============================================================================
-- [1] MODULE INIT EVENT
-- -----------------------------------------------------------------------------
-- Load the EN16 bundle. It has no `require()` calls of its own; the
-- bundler's UI-shim is harmless here (no fall-through is ever taken).
-- Expose under a short global so VSN1's S/M/V/H calls fit in tiny strings
-- (e.g. "EN16.H(7);paint()"). Seed LED brightness once.
-- =============================================================================

EN16 = require("sequencer_en16")

-- Set every LED's brightness ceiling once. Color comes later from refresh().
for i = 0, 15 do led_value(i, 2, 120) end

-- Global emit helper. Called at the END of each VSN1->EN16 message string
-- (e.g. "EN16.H(7);paint()") so LED writes happen the moment the shadow
-- updates. With the playhead push model, paint() is called ~32 times/sec
-- at 96 ppqn / dur=6 / 120 BPM — only when a step actually moves.
function paint()
    EN16.refresh(function(idx0, r, g, b)
        led_color(idx0, 2, r, g, b, 0)
    end)
end


-- =============================================================================
-- [2] ENCODER TURN EVENT  (per encoder, 16x)
-- -----------------------------------------------------------------------------
-- Forward intent to VSN1. EN16 does NOT mutate its own shadow. VSN1 will
-- echo back the new packed-int via S(i,p) which updates shadow + dirties.
-- =============================================================================

local v = self:endless_value()
local d = (v == 65) and 1 or (v == 63 and -1 or 0)
if d ~= 0 then
    immediate_send(-1, 0,
        "vsn1_t(" .. (self:element_index() + 1) .. "," .. d .. ")")
end


-- =============================================================================
-- [3] ENCODER PRESS EVENT  (per encoder, 16x)
-- =============================================================================

if self:button_state() == 127 then
    immediate_send(-1, 0,
        "vsn1_p(" .. (self:element_index() + 1) .. ")")
end


-- =============================================================================
-- NOTES
-- -----------------------------------------------------------------------------
-- * No MIDI rx callback. VSN1 listens for clock and pushes playhead via H().
-- * No timer slot.
-- * No broadcasts. All sends target dx=-1 (the VSN1 to our left).
-- * If VSN1 has not pushed any S/V/M yet, all LEDs stay dim/off.
-- * Rebuild after src/ changes:  lua tools/build_dist.lua
-- =============================================================================
