-- VSN1.lua
-- =============================================================================
-- ON-DEVICE ENTRY POINT for the VSN1 module of the sequencer.
-- =============================================================================
--
-- Two-bundle layout:
--   dist/sequencer.lua      Core only. Loaded at module init.
--   dist/sequencer_ui.lua   Screen UI. Lazy-loaded by loadUI() on first
--                           input event or first screen draw. Eager load
--                           at init was too heavy and hung module boot.
--
-- Hardware mapping:
--   Screen     : 320x240 EDIT view.
--   Keyswitch  : 1=NOTE 2=VEL 3=GATE 4=MUTE 5=STEP 6=- 7=LASTSTEP 8=SHIFT.
--   4 small btns: viewport (no shift) / track select (+ shift).
--   Endless    : turn = act-per-mode; click = mute toggle (RATCH w/SHIFT in MUTE).
--                In GATE focus, SHIFT + turn edits dur instead of gate.
--
-- EN16 satellite (optional, at relative position dx=+1, dy=0):
--   VSN1 -> EN16   immediate_send( 1, 0, "EN16.U(mu,f,sel,cap);paint()")
--                  immediate_send( 1, 0, "EN16.H(slot);paint()")
--   EN16 -> VSN1   immediate_send(-1, 0, "vsn1_t(i,d)")
--                  immediate_send(-1, 0, "vsn1_p(i)")
-- VSN1 owns the engine. EN16 holds 5 numbers + a 16-bit mute mask.
-- Every input handler ends with EU() to push fresh state. No drain queue,
-- no dirty flags, no per-step shadow. If no EN16 is wired the message
-- goes nowhere harmlessly.
-- =============================================================================


-- =============================================================================
-- [1] MODULE INIT
-- =============================================================================

SEQ    = require("sequencer")
ENGINE = SEQ.Core.engine
STEP   = SEQ.Core.step

ENGINE.init({ trackCount = 4, stepsPerTrack = 64 })

-- Seed track 1 with a small motif so the screen has something to show.
local notes = { 60, 63, 67, 70, 72, 67, 63, 60 }
for i, p in ipairs(notes) do
    ENGINE.tracks[1].steps[i] = STEP.pack({
        pitch = p, vel = 100, dur = 6, gate = 3,
    })
end

-- UI is lazy-loaded. Eager require("sequencer_ui") at init was heavy
-- enough to hang module boot. loadUI() is idempotent: first input event
-- or first screen draw pays the cost; pure-playback paths never do.
CTL = nil
function loadUI()
    if CTL then return end
    local UI = require("sequencer_ui")
    SEQ.Controls = UI
    CTL = UI.screen
    CTL.dirtyAll()
end

-- ---- EN16 push (single function, called at end of any input handler) ------
-- Computes mute mask (16 bits over visible viewport), focus, sel-relative,
-- visible cap. One immediate_send per call. Cheap: ~25 byte payload.
-- Caller MUST have loaded UI (every input handler does).
local function vplo() return (CTL.viewport - 1) * 16 + 1 end

function EU()
    if not CTL then return end
    local lo  = vplo()
    local tr  = ENGINE.tracks[CTL.selT]
    local s   = tr.steps
    local mu  = 0
    for i = 1, 16 do
        if STEP.muted(s[lo + i - 1]) then mu = mu | (1 << (i - 1)) end
    end
    local sel = CTL.selS - lo + 1
    if sel < 1 or sel > 16 then sel = 0 end
    -- visible cap: how many of the 16 slots are <= lastStep
    local cap = tr.lastStep - lo + 1
    if cap > 16 then cap = 16 elseif cap < 0 then cap = 0 end
    immediate_send(1, 0, "EN16.U(" ..
        mu .. "," .. CTL.focus .. "," .. sel .. "," .. cap .. ");paint()")
end

-- ---- EN16 playhead push (per pulse, only on slot change) ------------------
-- Runs from MIDI rx; must NOT lazy-load UI. If CTL not yet loaded, skip
-- (no UI means no viewport concept; the user hasn't interacted yet).
EN16_LAST_PH = -1

local function en16_push_playhead()
    if not CTL then return end
    local pos = ENGINE.tracks[CTL.selT].pos
    local lo  = vplo()
    local slot
    if pos == 0 then
        slot = 0
    else
        local r = pos - lo + 1
        slot = (r >= 1 and r <= 16) and r or 0
    end
    if slot ~= EN16_LAST_PH then
        EN16_LAST_PH = slot
        immediate_send(1, 0, "EN16.H(" .. slot .. ");paint()")
    end
end

-- Boot seed for EN16: clear playhead only. Full state push happens on
-- first input event after loadUI(). This keeps boot light.
immediate_send(1, 0, "EN16.H(0);paint()")


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
        en16_push_playhead()
    elseif t == 0xFA then
        ENGINE.onStart()
        EN16_LAST_PH = -1
    elseif t == 0xFB then
        if not ENGINE.running then ENGINE.onStart() end
        EN16_LAST_PH = -1
    elseif t == 0xFC then
        local off = ENGINE.onStop()
        if off then
            for i = 1, #off do
                local e = off[i]
                midi_send(e.ch, 0x80, e.pitch, 0)
            end
        end
        EN16_LAST_PH = 0
        immediate_send(1, 0, "EN16.H(0);paint()")
    end
end


-- =============================================================================
-- [3] SCREEN DRAW
-- =============================================================================

loadUI()
CTL.draw(self)


-- =============================================================================
-- [4] KEYSWITCHES  (element_index 0..7  ->  idx 1..8)
-- =============================================================================

loadUI()
local idx = self:element_index() + 1
local pressed = (self:button_state() == 127)
if idx == 8 then
    CTL.setShift(pressed)
    EU()
elseif pressed and idx >= 1 and idx <= 7 then
    CTL.onKey(idx)
    EU()
end


-- =============================================================================
-- [5] ENDLESS TURN
-- =============================================================================

loadUI()
local v = self:endless_value()
if v == 65 or v == 63 then
    CTL.onEndless((v == 65) and 1 or -1)
    EU()
end


-- =============================================================================
-- [6] ENDLESS CLICK
-- =============================================================================

loadUI()
if self:button_state() == 127 then
    CTL.onEndlessClick()
    EU()
end


-- =============================================================================
-- [7] SMALL BUTTONS  (element_index 9..12  ->  sidx 1..4)
-- =============================================================================

loadUI()
if self:button_state() == 127 then
    local sidx = self:element_index() - 8
    if sidx >= 1 and sidx <= 4 then
        CTL.onSmallBtn(sidx)
        EN16_LAST_PH = -1                       -- viewport/track may have changed
        EU()
    end
end


-- =============================================================================
-- [8] CROSS-MODULE RECEIVERS  (EN16 -> VSN1)
-- -----------------------------------------------------------------------------
-- vsn1_t(i, d) = encoder i (1..16) turned by delta d (-1/+1)
-- vsn1_p(i)    = encoder i (1..16) pressed
--
-- These globals are defined at init. They lazy-load UI on first invocation
-- so EN16 can drive VSN1 even if no local input has happened yet.
-- =============================================================================

function vsn1_t(i, d)
    loadUI()
    if i < 1 or i > 16 then return end
    local f = CTL.focus
    if f == 5 or f == 7 then return end
    local s = (CTL.viewport - 1) * 16 + i
    if s > ENGINE.tracks[CTL.selT].lastStep then return end
    CTL.setSelectedStep(s)
    CTL.setParam(f, CTL.selT, s, d)
    EU()
end

function vsn1_p(i)
    loadUI()
    if i < 1 or i > 16 then return end
    local s = (CTL.viewport - 1) * 16 + i
    if CTL.shift then
        CTL.setSelectedStep(s)
    elseif CTL.focus == 7 then
        ENGINE.setLastStep(CTL.selT, s)
        CTL.dirtyAll()
    else
        local stp = ENGINE.tracks[CTL.selT].steps[s]
        ENGINE.setStepParam(CTL.selT, s, "mute",
            STEP.muted(stp) and 0 or 1)
        CTL.dirtyAll()
    end
    EU()
end


-- =============================================================================
-- NOTES
-- -----------------------------------------------------------------------------
-- * No internal clock. Polyrhythm = per-track lastStep + per-step dur.
-- * Zero allocations per pulse - locked by tests/test_no_alloc.lua.
-- * Rebuild after src/ changes:  lua tools/build_dist.lua
-- =============================================================================
