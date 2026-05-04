-- VSN1.lua
-- =============================================================================
-- ON-DEVICE ENTRY POINT for the VSN1 module of the sequencer.
-- =============================================================================
--
-- Three-bundle layout:
--   dist/sequencer.lua      Core only. Loaded at module init.
--   dist/sequencer_ui.lua   Screen UI. Lazy-loaded on first input/draw.
--   (EN16 module loads its own dist/sequencer_en16.lua independently.)
--
-- VSN1 owns the engine; EN16 holds a SHADOW of the visible 16 steps + meta.
-- VSN1 pushes deltas to EN16 only when something changes (push-on-change).
-- EN16 runs its own timer, computes LED colors locally, and sends them to
-- its own LED hardware. This keeps LED math off VSN1 and shrinks the UI
-- bundle that has to fit on VSN1's tighter heap.
--
-- Hardware mapping:
--   Screen     : 320x240 EDIT view.
--   Keyswitch  : 1=NOTE 2=VEL 3=GATE 4=MUTE 5=STEP 6=- 7=LASTSTEP 8=SHIFT.
--   4 small btns: viewport (no shift) / track select (+ shift).
--   Endless    : turn = act-per-mode; click = mute toggle (or RATCH w/SHIFT).
-- =============================================================================


-- =============================================================================
-- [1] MODULE INIT
-- =============================================================================

SEQ    = require("sequencer")
ENGINE = SEQ.Core.engine
STEP   = SEQ.Core.step
CTL    = nil      -- lazy: SEQ.Controls.screen after loadUI()

ENGINE.init({ trackCount = 4, stepsPerTrack = 64 })

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
    CTL = UI.screen
    CTL.dirtyAll()
end

-- ---- Push helpers (VSN1 -> EN16 shadow) -------------------------------------
-- Sent over immediate_send(0, 1, "...") to the EN16 module which has the
-- functions en16_shadow / en16_meta defined in its own init chunk.

EN16_LAST_PH = -1   -- last playhead value pushed (gate setMeta on tick)

function en16_push_full()
    if not CTL then return end
    local lo = CTL.viewportLo(CTL.viewport)
    local tr = ENGINE.tracks[CTL.selT]
    for i = 1, 16 do
        local s = lo + i - 1
        immediate_send(nil, nil,
            "EN16.setShadow(" .. i .. "," .. tr.steps[s] .. ")")
    end
    immediate_send(nil, nil, string.format(
        "EN16.setMeta(%d,%d,%d,%d,%d,%d)",
        CTL.focus, tr.lastStep, tr.pos, CTL.selS, lo,
        CTL.shift and 1 or 0))
    EN16_LAST_PH = tr.pos
end

function en16_push_meta_only()
    if not CTL then return end
    local lo = CTL.viewportLo(CTL.viewport)
    local tr = ENGINE.tracks[CTL.selT]
    immediate_send(nil, nil, string.format(
        "EN16.setMeta(%d,%d,%d,%d,%d,%d)",
        CTL.focus, tr.lastStep, tr.pos, CTL.selS, lo,
        CTL.shift and 1 or 0))
    EN16_LAST_PH = tr.pos
end


-- =============================================================================
-- [2] MIDI RX
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
-- -----------------------------------------------------------------------------
-- Pure render. First draw lazy-loads UI and arms the EN16-sync timer.
-- =============================================================================

if not CTL then loadUI() end
CTL.draw(self)
if not LED_TIMER_ARMED then
    LED_TIMER_ARMED = true
    timer_start(0, 33)
    en16_push_full()    -- seed EN16 with initial shadow + meta
end


-- =============================================================================
-- [4] KEYSWITCHES
-- =============================================================================

if not CTL then loadUI() end
local idx = self:element_index() + 1
local pressed = (self:button_state() == 127)
if idx == 8 then
    CTL.setShift(pressed)
    en16_push_full()
elseif pressed and idx >= 1 and idx <= 7 then
    CTL.onKey(idx)
    en16_push_full()
end


-- =============================================================================
-- [5] ENDLESS TURN
-- =============================================================================

if not CTL then loadUI() end
local v = self:encoder_value()
if v == 65 then
    CTL.onEndless(1); en16_push_full()
elseif v == 63 then
    CTL.onEndless(-1); en16_push_full()
end


-- =============================================================================
-- [6] ENDLESS CLICK
-- =============================================================================

if self:button_state() == 127 then
    if not CTL then loadUI() end
    CTL.onEndlessClick()
    en16_push_full()
end


-- =============================================================================
-- [7] SMALL BUTTONS  (element_index 9..12)
-- =============================================================================

if self:button_state() == 127 then
    if not CTL then loadUI() end
    local sidx = self:element_index() - 8
    if sidx >= 1 and sidx <= 4 then
        CTL.onSmallBtn(sidx)
        en16_push_full()
    end
end


-- =============================================================================
-- [8] CROSS-MODULE CALLBACKS  (EN16 -> VSN1)
-- -----------------------------------------------------------------------------
-- EN16 sends:
--   immediate_send(0, -1, 'vsn1_en16_turn(idx, delta)')
--   immediate_send(0, -1, 'vsn1_en16_press(idx)')
-- =============================================================================

function vsn1_en16_turn(idx, delta)
    if not CTL then loadUI() end
    if idx < 1 or idx > 16 then return end
    local f = CTL.focus
    if f == 7 or f == 5 then return end
    local s = CTL.viewportLo(CTL.viewport) + (idx - 1)
    if s > ENGINE.tracks[CTL.selT].lastStep then return end
    CTL.setSelectedStep(s)
    CTL.setParam(f, CTL.selT, s, delta > 0 and 1 or -1)
    CTL.dirtyValueCells()
    en16_push_full()
end

function vsn1_en16_press(idx)
    if not CTL then loadUI() end
    if idx < 1 or idx > 16 then return end
    local s = CTL.viewportLo(CTL.viewport) + (idx - 1)
    if CTL.shift then
        CTL.setSelectedStep(s)
    elseif CTL.focus == 7 then
        ENGINE.setLastStep(CTL.selT, s)
    else
        local stp = ENGINE.tracks[CTL.selT].steps[s]
        ENGINE.setStepParam(CTL.selT, s, "mute",
            STEP.muted(stp) and 0 or 1)
    end
    CTL.dirtyValueCells()
    en16_push_full()
end


-- =============================================================================
-- [9] TIMER  (slot 0, ~30 Hz)
-- -----------------------------------------------------------------------------
-- Push playhead-only updates so EN16 LEDs follow the music. Single int
-- per push, gated by EN16_LAST_PH so idle = zero broadcasts.
-- =============================================================================

if CTL then
    local ph = ENGINE.tracks[CTL.selT].pos
    if ph ~= EN16_LAST_PH then
        EN16_LAST_PH = ph
        immediate_send(nil, nil, "EN16.setPlayhead(" .. ph .. ")")
    end
end
timer_start(0, 33)


-- =============================================================================
-- NOTES
-- -----------------------------------------------------------------------------
-- * Three-bundle split keeps boot heap small. EN16 owns its own LED math.
-- * No internal clock. Polyrhythm = per-track lastStep + per-step dur.
-- * Zero allocations per pulse - locked by tests/test_no_alloc.lua.
-- * Rebuild after src/ changes:  lua tools/build_dist.lua
-- =============================================================================
