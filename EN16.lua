-- EN16.lua
-- =============================================================================
-- ON-DEVICE ENTRY POINT for the EN16 module of the sequencer.
-- =============================================================================
--
-- LED MODEL: color-only. One led_color call per encoder when state changes.
-- No led_value (brightness) traffic at all.
--
-- Cross-module: VSN1 broadcasts EN16.setShadow / EN16.setMeta via
-- immediate_send(nil, nil, ...). EN16 broadcasts vsn1_en16_turn / press
-- back the same way.
--
-- Bundle: dist/sequencer_en16.lua (standalone).
-- =============================================================================


-- =============================================================================
-- [1] MODULE INIT EVENT
-- -----------------------------------------------------------------------------
-- Load the EN16 bundle, expose as global, seed every LED so hardware
-- accepts updates, arm the timer.
-- =============================================================================

EN16 = require("sequencer_en16")

-- Hardware bootstrap. led_value sets overall LED brightness ceiling;
-- 120/255 keeps the EN16 visibly dimmer than VSN1's screen.
do
    local r, g, b = EN16.MR[1], EN16.MG[1], EN16.MB[1]
    for i = 0, 15 do
        led_color(i, 2, r, g, b, 0)
        led_value(i, 2, 120)
    end
end

timer_start(0, 33)


-- =============================================================================
-- [2] ENCODER TURN EVENT  (per encoder, 16x)
-- =============================================================================

local v = self:encoder_value()
local delta = (v == 65) and 1 or (v == 63 and -1 or 0)
if delta ~= 0 then
    immediate_send(nil, nil,
        "vsn1_en16_turn(" .. (self:element_index() + 1) .. "," .. delta .. ")")
end


-- =============================================================================
-- [3] ENCODER PRESS EVENT  (per encoder, 16x)
-- =============================================================================

if self:button_state() == 127 then
    immediate_send(nil, nil,
        "vsn1_en16_press(" .. (self:element_index() + 1) .. ")")
end


-- =============================================================================
-- [4] TIMER EVENT  (slot 0)
-- -----------------------------------------------------------------------------
-- Cache lives inside EN16.LAST inside the bundle so the timer chunk is
-- as small as possible. Only changed encoders are written to hardware.
-- IMPORTANT: timer must self-restart, otherwise it fires once and stops.
-- =============================================================================

EN16.refreshColors(function(idx, r, g, b)
    led_color(idx - 1, 2, r, g, b, 0)
end)
timer_start(0, 33)
