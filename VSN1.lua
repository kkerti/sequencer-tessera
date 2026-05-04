-- VSN1.lua
-- =============================================================================
-- ON-DEVICE ENTRY POINT for the VSN1 module of the sequencer.
-- =============================================================================
--
-- Two-bundle layout (memory-conscious):
--   dist/sequencer.lua     -- Core only. Loaded at module init. ~8 KB.
--   dist/sequencer_ui.lua  -- Controls layer. Lazy-loaded on first input
--                             event or first screen draw. ~8 KB.
--
-- Hardware mapping:
--   Screen        : 320 x 240 EDIT view + LASTSTEP takeover screen.
--   8 keyswitches : 1=NOTE 2=VEL 3=GATE 4=MUTE 5=DUR 6=RATCH 7=LASTSTEP
--                   8=SHIFT (momentary hold).
--   4 small btns  : (no shift) viewport region 1..4  (which 16-step window)
--                   (+ shift)  select track 1..4
--   Endless       : turn  = edit selected step's current-mode param
--                   click = toggle selected step's mute
--                   In LASTSTEP mode, turn edits track lastStep (1..64).
--
-- EN16 module talks via immediate_send. SHIFT+EN16 press = select step
-- (no mute toggle); plain press = toggle mute (or set lastStep in LASTSTEP).
-- =============================================================================


-- =============================================================================
-- [1] MODULE INIT EVENT
-- =============================================================================

SEQ     = require("sequencer")     -- Core bundle (dist/sequencer.lua)
ENGINE  = SEQ.Core.engine
TRACK   = SEQ.Core.track
STEP    = SEQ.Core.step
CTL     = nil                      -- lazy: SEQ.Controls.screen after loadUI()
EN16    = nil                      -- lazy: SEQ.Controls.en16   after loadUI()

ENGINE.init({
    trackCount    = 4,
    stepsPerTrack = 64,
})

-- Default seed: a short C minor riff in track 1, steps 1..8.
local notes = { 60, 63, 67, 70, 72, 67, 63, 60 }
for i, p in ipairs(notes) do
    ENGINE.tracks[1].steps[i] = STEP.pack({
        pitch = p, vel = 100, dur = 6, gate = 3,
    })
end
ENGINE.tracks[1].chan = 1

function loadUI()
    if CTL then return end
    local UI = require("sequencer_ui")
    SEQ.Controls = UI
    CTL  = UI.screen
    EN16 = UI.en16
    CTL.dirtyAll()
end


-- =============================================================================
-- [2] MIDI RX  (clock + transport from master)
-- =============================================================================

self.rtmrx_cb = function(self, t)
    if t == 0xF8 then
        local events = ENGINE.onPulse()
        if events then
            for i = 1, #events do
                local e = events[i]
                if e.type == 1 then
                    midi_send(e.ch, 0x90, e.pitch, e.vel)
                else
                    midi_send(e.ch, 0x80, e.pitch, 0)
                end
            end
        end
    elseif t == 0xFA then
        ENGINE.onStart()
    elseif t == 0xFB then
        if not ENGINE.running then ENGINE.onStart() end
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
-- First draw triggers UI lazy-load. EN16 LED refresh piggybacks here,
-- cache-gated per (encoder, layer) so idle frames send no immediate_send.
-- =============================================================================

if not CTL then loadUI() end
CTL.draw(self)

if not EN16_LED_CACHE then
    -- 16 encoders × 2 layers; pack r,g,b into one int 0xRRGGBB.
    EN16_LED_CACHE = {}
    for i = 1, 32 do EN16_LED_CACHE[i] = -1 end
end
local _BEAUTIFY = EN16.LED.beautify
EN16.refreshLeds(function(idx, layer, r, g, b)
    local k = (idx - 1) * 2 + layer
    local packed = (r << 16) | (g << 8) | b
    if EN16_LED_CACHE[k] == packed then return end
    EN16_LED_CACHE[k] = packed
    immediate_send(0, 1,
        "led_color(" .. (idx - 1) .. "," .. layer
        .. "," .. r .. "," .. g .. "," .. b
        .. "," .. _BEAUTIFY .. ")")
end)


-- =============================================================================
-- [4] KEYSWITCH BUTTON EVENTS  (8 buttons)
-- -----------------------------------------------------------------------------
-- 1=NOTE 2=VEL 3=GATE 4=MUTE 5=DUR 6=RATCH 7=LASTSTEP 8=SHIFT (momentary).
-- Slot 8 must fire on BOTH press and release for SHIFT to release.
-- =============================================================================

if not CTL then loadUI() end
local idx = self:element_index() + 1
local pressed = (self:button_state() == 127)
if idx == 8 then
    CTL.setShift(pressed)
elseif pressed and idx >= 1 and idx <= 7 then
    CTL.onKey(idx)
end


-- =============================================================================
-- [5] ENDLESS ENCODER EVENT  (relative: 65=up, 63=down)
-- =============================================================================

if not CTL then loadUI() end
local v = self:encoder_value()
if v == 65 then
    CTL.onEndless(1)
elseif v == 63 then
    CTL.onEndless(-1)
end


-- =============================================================================
-- [6] ENDLESS CLICK EVENT  -> toggle selected step's mute
-- =============================================================================

if self:button_state() == 127 then
    if not CTL then loadUI() end
    CTL.onEndlessClick()
end


-- =============================================================================
-- [7] SMALL BUTTONS UNDER SCREEN  (4 buttons)
-- -----------------------------------------------------------------------------
-- No SHIFT -> change viewport region 1..4 (which 16-step window).
-- + SHIFT  -> select track 1..4.
-- =============================================================================

if self:button_state() == 127 then
    if not CTL then loadUI() end
    local sidx = self:element_index() + 1
    if sidx >= 1 and sidx <= 4 then CTL.onSmallBtn(sidx) end
end


-- =============================================================================
-- [8] CROSS-MODULE COMMUNICATION  (VSN1 [0,0]  <->  EN16 [0,1])
-- -----------------------------------------------------------------------------
-- Outbound (VSN1 -> EN16): in [3], `led_color(idx, layer, r, g, b, beautify)`
-- per CHANGED LED-layer. Cache-gated.
--
-- Inbound (EN16 -> VSN1):
--   immediate_send(0, -1, 'vsn1_en16_turn(idx, delta)')
--   immediate_send(0, -1, 'vsn1_en16_press(idx)')
--
-- Press routing: if SHIFT is held when EN16 press arrives, we move the
-- selected step instead of toggling mute. EN16 module itself is
-- shift-unaware; VSN1 is the brain.
-- =============================================================================

function vsn1_en16_turn(idx, delta)
    if not EN16 then loadUI() end
    if EN16 then EN16.onEncoder(idx, delta) end
end

function vsn1_en16_press(idx)
    if not EN16 then loadUI() end
    if not EN16 then return end
    if CTL.shift then
        local s = CTL.viewportLo(CTL.viewport) + (idx - 1)
        CTL.setSelectedStep(s)
    else
        EN16.onEncoderPress(idx)
    end
end


-- =============================================================================
-- NOTES
-- -----------------------------------------------------------------------------
-- * Two-bundle split keeps boot heap small.
-- * No internal clock. No regions in the engine. Polyrhythm = per-track
--   lastStep + per-step dur.
-- * One voice per track. Track-N notes default to MIDI channel N.
-- * Zero allocations per pulse - locked by tests/test_no_alloc.lua.
-- * Rebuild after src/ changes:  lua tools/build_dist.lua
-- =============================================================================
