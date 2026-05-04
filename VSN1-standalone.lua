-- VSN1.lua
-- =============================================================================
-- ON-DEVICE ENTRY POINT for the VSN1 module of the sequencer.
-- =============================================================================
--
-- Solo VSN1 build. No EN16 bus traffic, no shadow state, no LED timer.
--
-- Two-bundle layout:
--   dist/sequencer.lua      Core only. Loaded at module init.
--   dist/sequencer_ui.lua   Screen UI. Lazy-loaded on first input/draw.
--
-- Hardware mapping:
--   Screen     : 320x240 EDIT view.
--   Keyswitch  : 1=NOTE 2=VEL 3=GATE 4=MUTE 5=STEP 6=- 7=LASTSTEP 8=SHIFT.
--   4 small btns: viewport (no shift) / track select (+ shift).
--   Endless    : turn = act-per-mode; click = mute toggle (RATCH w/SHIFT in MUTE).
--                In GATE focus, SHIFT + turn edits dur instead of gate.
-- =============================================================================


-- =============================================================================
-- [1] MODULE INIT
-- =============================================================================

SEQ    = require("sequencer")
ENGINE = SEQ.Core.engine
STEP   = SEQ.Core.step
CTL    = nil      -- lazy: SEQ.Controls.screen after loadUI()

ENGINE.init({ trackCount = 4, stepsPerTrack = 64 })

-- Seed track 1 with a small motif so the screen has something to show.
local notes = { 60, 63, 67, 70, 72, 67, 63, 60 }
for i, p in ipairs(notes) do
    ENGINE.tracks[1].steps[i] = STEP.pack({
        pitch = p, vel = 100, dur = 6, gate = 3,
    })
end

function loadUI()
    if CTL then return end
    local UI = require("sequencer_ui")
    SEQ.Controls = UI
    CTL = UI.screen
    CTL.dirtyAll()
end


-- =============================================================================
-- [2] MIDI RX  (external clock + transport)
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
-- [3] SCREEN DRAW
-- =============================================================================

if not CTL then loadUI() end
CTL.draw(self)


-- =============================================================================
-- [4] KEYSWITCHES  (element_index 0..7  ->  idx 1..8)
-- -----------------------------------------------------------------------------
-- 1=NOTE 2=VEL 3=GATE 4=MUTE 5=STEP 6=- 7=LASTSTEP 8=SHIFT
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
-- [5] ENDLESS TURN
-- =============================================================================

if not CTL then loadUI() end
local v = self:endless_value()
if v == 65 or v == 63 then
    CTL.onEndless((v == 65) and 1 or -1)
end


-- =============================================================================
-- [6] ENDLESS CLICK
-- =============================================================================

if self:button_state() == 127 then
    if not CTL then loadUI() end
    CTL.onEndlessClick()
end


-- =============================================================================
-- [7] SMALL BUTTONS  (element_index 9..12  ->  sidx 1..4)
-- -----------------------------------------------------------------------------
-- No shift = viewport 1..4.   Shift held = select track 1..4.
-- =============================================================================

if self:button_state() == 127 then
    if not CTL then loadUI() end
    local sidx = self:element_index() - 8
    if sidx >= 1 and sidx <= 4 then
        CTL.onSmallBtn(sidx)
    end
end


-- =============================================================================
-- NOTES
-- -----------------------------------------------------------------------------
-- * No internal clock. Polyrhythm = per-track lastStep + per-step dur.
-- * Zero allocations per pulse - locked by tests/test_no_alloc.lua.
-- * Rebuild after src/ changes:  lua tools/build_dist.lua
-- =============================================================================
