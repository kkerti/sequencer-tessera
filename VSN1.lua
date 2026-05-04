-- VSN1.lua
-- =============================================================================
-- ON-DEVICE ENTRY POINT for the VSN1 module of the sequencer.
-- =============================================================================
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
--
-- EN16 satellite (optional, at relative position dx=+1, dy=0):
--   VSN1 -> EN16   immediate_send( 1, 0, "EN16.S(...)" / "EN16.M(...)" / "EN16.V(...)")
--   EN16 -> VSN1   immediate_send(-1, 0, "vsn1_t(i,d)" / "vsn1_p(i)")
-- VSN1 owns the engine; EN16 holds a shadow of the visible 16 steps.
-- Sends are coalesced and drained at end of each input handler block.
-- VSN1 broadcasts seed (V+M) on boot — if no EN16 is wired, the message
-- goes nowhere harmlessly.
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

-- ---- EN16 push state -------------------------------------------------------
-- Dirty flags set by input handlers; drained at end of each handler block.
-- View flag dominates step flags (full window resync supersedes per-step).
EN16_DIRTY_META  = false
EN16_DIRTY_VIEW  = false
EN16_DIRTY_STEPS = {}

function en16_mark_meta()  EN16_DIRTY_META = true end
function en16_mark_view()  EN16_DIRTY_VIEW = true end

function en16_mark_step(absStep)
    if not CTL then return end
    local i = absStep - ((CTL.viewport - 1) * 16 + 1) + 1
    if i >= 1 and i <= 16 then EN16_DIRTY_STEPS[i] = true end
end

-- selS expressed relative to current viewport (1..16, or 0 if outside).
local function selR()
    local lo = (CTL.viewport - 1) * 16 + 1
    local r  = CTL.selS - lo + 1
    if r < 1 or r > 16 then return 0 end
    return r
end

function en16_send_M()
    local tr = ENGINE.tracks[CTL.selT]
    immediate_send(1, 0, string.format(
        "EN16.M(%d,%d,%d,%d);paint()",
        CTL.focus, tr.lastStep, selR(), CTL.shift and 1 or 0))
end

function en16_send_V()
    local lo = (CTL.viewport - 1) * 16 + 1
    local s  = ENGINE.tracks[CTL.selT].steps
    immediate_send(1, 0, string.format(
        "EN16.V(%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d);paint()",
        s[lo],   s[lo+1], s[lo+2], s[lo+3],
        s[lo+4], s[lo+5], s[lo+6], s[lo+7],
        s[lo+8], s[lo+9], s[lo+10],s[lo+11],
        s[lo+12],s[lo+13],s[lo+14],s[lo+15]))
end

function en16_drain()
    if EN16_DIRTY_VIEW then
        en16_send_V()
        EN16_DIRTY_VIEW  = false
        EN16_DIRTY_STEPS = {}                 -- subsumed by V
    else
        local lo = (CTL.viewport - 1) * 16 + 1
        local s  = ENGINE.tracks[CTL.selT].steps
        for i, _ in pairs(EN16_DIRTY_STEPS) do
            immediate_send(1, 0,
                "EN16.S(" .. i .. "," .. s[lo + i - 1] .. ");paint()")
            EN16_DIRTY_STEPS[i] = nil
        end
    end
    if EN16_DIRTY_META then
        en16_send_M()
        EN16_DIRTY_META = false
    end
end

-- ---- EN16 playhead push ----------------------------------------------------
-- Invariant: EN16_LAST_PH = the playhead slot (0 or 1..16) we last sent to
-- EN16 for the current (selT, viewport) tuple. -1 = invalidated; force a
-- send on next pulse regardless of pos. Set to -1 on transport stop, on
-- viewport switch, and on track switch.
EN16_LAST_PH = -1

function en16_invalidate_playhead() EN16_LAST_PH = -1 end

-- Called from rtmrx_cb after engine.onPulse(). Cheap path: if the engine
-- pos hasn't changed AND last_ph was already pushed, do nothing.
function en16_push_playhead()
    if not CTL then return end
    local pos = ENGINE.tracks[CTL.selT].pos    -- 1..lastStep, or 0 before first fire
    local lo  = (CTL.viewport - 1) * 16 + 1
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
        en16_invalidate_playhead()
    elseif t == 0xFB then
        if not ENGINE.running then ENGINE.onStart() end
        en16_invalidate_playhead()
    elseif t == 0xFC then
        local off = ENGINE.onStop()
        if off then
            for i = 1, #off do
                local e = off[i]
                midi_send(e.ch, 0x80, e.pitch, 0)
            end
        end
        -- Clear EN16's playhead LED.
        EN16_LAST_PH = 0
        immediate_send(1, 0, "EN16.H(0);paint()")
    end
end


-- =============================================================================
-- [3] SCREEN DRAW
-- -----------------------------------------------------------------------------
-- First draw lazy-loads UI and seeds EN16 unconditionally (V + M) so the
-- satellite gets a populated shadow even without prior interaction.
-- =============================================================================

if not CTL then loadUI() end
CTL.draw(self)
if not EN16_SEEDED then
    EN16_SEEDED = true
    en16_send_V()
    en16_send_M()
end


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
    en16_mark_meta()
elseif pressed and idx >= 1 and idx <= 7 then
    CTL.onKey(idx)
    en16_mark_meta()
end
en16_drain()


-- =============================================================================
-- [5] ENDLESS TURN
-- =============================================================================

if not CTL then loadUI() end
local v = self:endless_value()
if v == 65 or v == 63 then
    CTL.onEndless((v == 65) and 1 or -1)
    local f = CTL.focus
    if f == 7 then
        en16_mark_meta()                       -- lastStep
    elseif f == 5 then
        en16_mark_meta()                       -- selS moved
    elseif f >= 1 and f <= 4 then
        en16_mark_step(CTL.selS)               -- single-step value edit
    end
    en16_drain()
end


-- =============================================================================
-- [6] ENDLESS CLICK
-- =============================================================================

if self:button_state() == 127 then
    if not CTL then loadUI() end
    CTL.onEndlessClick()
    if CTL.focus ~= 7 and CTL.focus ~= 5 then
        en16_mark_step(CTL.selS)               -- mute/ratch toggle
    end
    en16_drain()
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
        en16_mark_view()                       -- whole window changes
        en16_mark_meta()                       -- focus stays, but selR may shift
        en16_invalidate_playhead()             -- viewport/track may have changed
    end
    en16_drain()
end


-- =============================================================================
-- [8] CROSS-MODULE RECEIVERS  (EN16 -> VSN1)
-- -----------------------------------------------------------------------------
-- vsn1_t(i, d) = encoder i (1..16) turned by delta d (-1/+1)
-- vsn1_p(i)    = encoder i (1..16) pressed
-- After mutating engine state, mark dirty + drain so the change echoes
-- back to EN16 (single S(i,p) message). No oscillation: EN16 only updates
-- its shadow on receiving S, not on its own input.
-- =============================================================================

function vsn1_t(i, d)
    if not CTL then loadUI() end
    if i < 1 or i > 16 then return end
    local f = CTL.focus
    if f == 5 or f == 7 then return end        -- STEP/LASTSTEP: ignore turns
    local s = (CTL.viewport - 1) * 16 + i
    if s > ENGINE.tracks[CTL.selT].lastStep then return end
    CTL.setSelectedStep(s)
    CTL.setParam(f, CTL.selT, s, d)
    en16_mark_step(s)
    en16_mark_meta()                            -- selS moved
    en16_drain()
end

function vsn1_p(i)
    if not CTL then loadUI() end
    if i < 1 or i > 16 then return end
    local s = (CTL.viewport - 1) * 16 + i
    if CTL.shift then
        CTL.setSelectedStep(s)
        en16_mark_meta()
    elseif CTL.focus == 7 then
        ENGINE.setLastStep(CTL.selT, s)
        en16_mark_meta()
    else
        local stp = ENGINE.tracks[CTL.selT].steps[s]
        ENGINE.setStepParam(CTL.selT, s, "mute",
            STEP.muted(stp) and 0 or 1)
        en16_mark_step(s)
    end
    en16_drain()
end


-- =============================================================================
-- NOTES
-- -----------------------------------------------------------------------------
-- * No internal clock. Polyrhythm = per-track lastStep + per-step dur.
-- * Zero allocations per pulse - locked by tests/test_no_alloc.lua.
-- * Rebuild after src/ changes:  lua tools/build_dist.lua
-- =============================================================================
