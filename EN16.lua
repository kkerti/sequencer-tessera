-- EN16.lua
-- =============================================================================
-- ON-DEVICE ENTRY POINT for the EN16 module of the sequencer.
-- =============================================================================
--
-- This file is NOT a runnable Lua script. It is a reference manual that shows
-- which sequencer code goes into which Grid event slot on the EN16 module.
-- Copy each labeled section into the matching event in the Grid Editor.
--
-- The EN16 hosts NO sequencer engine. The engine + state lives on VSN1.
-- This module is a thin client: 16 push-encoders + 16 LEDs that act on the
-- SELECTED track's CURRENT region of the engine running on VSN1.
--
-- Cross-module addressing (per docs/INTER_GRID.md, immediate_send):
--   VSN1 is at relative [0, -1] from the EN16's perspective.
--   So all EN16 -> VSN1 messages are immediate_send(0, -1, '...').
--   VSN1 reciprocates with immediate_send(0, 1, 'led_value(...)') back here.
--
-- Per-encoder behaviour:
--   turn  -> immediate_send to VSN1 -> EN16.onEncoder(idx, delta)
--            adjusts the parameter currently focused on VSN1
--   click -> immediate_send to VSN1 -> EN16.onEncoderPress(idx)
--            toggles that step's `active` bit
--   LED   -> VSN1 pushes led_value(idx, 2, brightness) here per UI tick,
--            only for encoders whose brightness changed.
-- =============================================================================


-- =============================================================================
-- [1] MODULE INIT EVENT
-- -----------------------------------------------------------------------------
-- Nothing to do on EN16 init. No sequencer require, no global state.
-- VSN1's init seeds EN16_LED_CACHE on its side and forces a full LED push
-- on the first draw tick, so all 16 LEDs reach a known state shortly after
-- both modules are up.
-- =============================================================================


-- =============================================================================
-- [2] ENCODER TURN EVENT  (per encoder, 16x)
-- -----------------------------------------------------------------------------
-- Place this in EACH EN16 encoder's Endless event. Relative encoder:
-- 65 = clockwise/up, 63 = counter-clockwise/down.
--
-- We compute the delta locally and ship a single immediate_send to VSN1.
-- The string executes `vsn1_en16_turn(idx, delta)` on VSN1, defined in
-- VSN1.lua [1].
-- =============================================================================

local v = self:encoder_value()
local delta = (v == 65) and 1 or (v == 63 and -1 or 0)
if delta ~= 0 then
    local idx = self:element_index() + 1   -- 0-based -> 1-based
    immediate_send(0, -1,
        "vsn1_en16_turn(" .. idx .. "," .. delta .. ")")
end


-- =============================================================================
-- [3] ENCODER PRESS EVENT  (per encoder, 16x)
-- -----------------------------------------------------------------------------
-- Place this in EACH EN16 encoder's Button event. Press-edge only.
-- The string executes `vsn1_en16_press(idx)` on VSN1, defined in VSN1.lua [1].
-- =============================================================================

if self:button_state() == 127 then
    local idx = self:element_index() + 1
    immediate_send(0, -1, "vsn1_en16_press(" .. idx .. ")")
end


-- =============================================================================
-- [4] INBOUND LED UPDATES  (from VSN1)
-- -----------------------------------------------------------------------------
-- VSN1 sends `led_value(idx, 2, brightness)` strings via immediate_send
-- once per UI tick, cache-gated so only changed encoders are pushed. The
-- string is executed directly here in EN16's global scope; no event-side
-- code needed for LED reception. led_value is the module-level builtin.
--
-- Brightness scale: 0 = inactive, 80 = active, 255 = playhead.
-- Layer 2 = encoder rotation feedback.
-- =============================================================================


-- =============================================================================
-- NOTES
-- -----------------------------------------------------------------------------
-- * EN16 carries no sequencer state. Reboot order doesn't matter; once
--   VSN1's first draw tick fires, EN16 gets a full LED refresh.
-- * If you add more encoder behaviours (long-press, double-click, etc.),
--   define a matching `vsn1_en16_*` global on VSN1 and call it via
--   immediate_send(0, -1, ...). Keep payloads small — they're parsed as
--   Lua source on every event.
-- =============================================================================
