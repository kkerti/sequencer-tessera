-- vsn1_app.lua
-- =============================================================================
-- VSN1-side handler logic. Lives in its OWN bundle (dist/sequencer_vsn1.lua)
-- so the screen-UI bundle stays small and loads fast.
--
-- On device:
--   APP = require("sequencer_vsn1").init(SEQ.Controls.screen)
-- and each VSN1.lua per-event scriptlet collapses to one or two calls.
--
-- Hardware globals expected at call time (provided by the Grid runtime):
--   immediate_send(dx, dy, str)    -- bus message to neighbour module
--   midi_send(ch, status, p1, p2)  -- MIDI out
--
-- This module never touches the engine through Core.midi_rx; transport is
-- handled in VSN1.lua's MIDI rx scriptlet so the pure-playback path
-- never requires this bundle.
-- =============================================================================

local Engine  = require("engine")
local Step    = require("step")
local Persist = require("persist")

local M = {}

-- On-device path for the saved sequence file. Single source of truth so
-- VSN1.lua's boot autoload and the SHIFT+key 7 save call agree.
M.SAVE_PATH = "sequencer_data.lua"

M.CTL    = nil       -- screen controls module (controls.lua exports)
M.lastPh = -1        -- last playhead slot pushed to EN16

-- Reused scratch buffer for EN16.U(...) string assembly. One table; we
-- overwrite indices each call and table.concat for the wire payload.
local SBUF = {}

-- -----------------------------------------------------------------------------
-- init
-- -----------------------------------------------------------------------------

function M.init(controls)
    M.CTL = controls
    controls.dirtyAll()
    return M
end

-- -----------------------------------------------------------------------------
-- Per-focus value extractor for EN16 LED brightness.
-- f: 1=NOTE 2=VEL 3=GATE(+shift -> dur) 4=MUTE 5=LASTSTEP
-- -----------------------------------------------------------------------------

local function valueFor(stp, f, shift)
    if f == 1 then return Step.pitch(stp) end
    if f == 2 then return Step.vel(stp) end
    if f == 3 then
        if shift then return Step.dur(stp) end
        return Step.gate(stp)
    end
    return 0
end

-- -----------------------------------------------------------------------------
-- EN16.U(...) push: full state snapshot + 16 values for the visible viewport.
-- Loop-based to keep code small. One immediate_send per call.
-- -----------------------------------------------------------------------------

function M.pushEN16()
    local CTL = M.CTL; if not CTL then return end
    local lo  = (CTL.viewport - 1) * 16 + 1
    local tr  = Engine.tracks[CTL.selT]
    local s   = tr.steps
    local f   = CTL.focus
    local sh  = CTL.shift

    local mu = 0
    for i = 1, 16 do
        if Step.muted(s[lo + i - 1]) then mu = mu | (1 << (i - 1)) end
    end

    local sel = CTL.selS - lo + 1
    if sel < 1 or sel > 16 then sel = 0 end
    local cap = tr.lastStep - lo + 1
    if cap > 16 then cap = 16 elseif cap < 0 then cap = 0 end

    SBUF[1] = "EN16.U("
    SBUF[2] = mu
    SBUF[3] = ","
    SBUF[4] = f
    SBUF[5] = ","
    SBUF[6] = sel
    SBUF[7] = ","
    SBUF[8] = cap
    SBUF[9] = ","
    SBUF[10] = CTL.selT
    local n = 10
    for i = 0, 15 do
        n = n + 1; SBUF[n] = ","
        n = n + 1; SBUF[n] = valueFor(s[lo + i], f, sh)
    end
    n = n + 1; SBUF[n] = ");paint()"
    immediate_send(1, 0, table.concat(SBUF, "", 1, n))
end

-- -----------------------------------------------------------------------------
-- EN16 playhead push. Cheap: only emits when slot changes.
-- -----------------------------------------------------------------------------

function M.pushPlayhead()
    local CTL = M.CTL; if not CTL then return end
    local pos = Engine.tracks[CTL.selT].pos
    local lo  = (CTL.viewport - 1) * 16 + 1
    local slot
    if pos == 0 then
        slot = 0
    else
        local r = pos - lo + 1
        slot = (r >= 1 and r <= 16) and r or 0
    end
    if slot ~= M.lastPh then
        M.lastPh = slot
        immediate_send(1, 0, "EN16.H(" .. slot .. ");paint()")
    end
end

-- -----------------------------------------------------------------------------
-- Input handlers (each ends with pushEN16 to keep the satellite in sync)
-- -----------------------------------------------------------------------------

-- Keyswitches 1..8. 1..6 = focus modes (NOTE VEL GATE MUTE LASTSTEP SCALE);
-- 7 = RANDOM hold (momentary; while held param-mode presses randomize);
-- 8 = SHIFT (toggle). Persist (LOAD/SAVE) lives on the small-button arm chords.
function M.onKey(idx, pressed)
    local CTL = M.CTL
    -- Armed slot chord (hold small button 11/12, tap keyswitch 0..6 = slot).
    -- Intercepts keyswitches idx 1..7 while armed; slot = idx-1. SHIFT (8) is
    -- excluded. Clearing M.arm on 11/12 release means the load/save only fires
    -- while the button is genuinely held — a stray later keyswitch can't trigger it.
    if pressed and CTL.arm and idx >= 1 and idx <= 7 then
        local p = "d" .. (idx - 1) .. ".lua"
        if CTL.arm == "save" then
            Persist.save(p)
        else
            if Persist.load(p) then CTL.dirtyAll() end
        end
        CTL.setArm(nil)
        CTL.dirtyAll()
        M.pushEN16()
        return
    end
    if idx == 8 then
        -- SHIFT keyswitch is configured as a hardware toggle: each physical
        -- press flips the keyswitch latch, and the scriptlet reports the
        -- latched state here (127 = engaged, 0 = released) on each change.
        -- Adopt it verbatim — a local flip here would double-toggle because
        -- the scriptlet also fires on the release transition.
        CTL.setShift(pressed)
        M.pushEN16()
    elseif idx == 7 then
        -- RANDOM hold (keyswitch 7). Momentary: we act on both the press
        -- (engage) and release (disengage) edges. While held, param-mode
        -- presses randomize instead of switching focus. Persist (LOAD/SAVE)
        -- has moved off this key onto the small-button arm chords.
        CTL.setRandom(pressed)
        M.pushEN16()
    elseif pressed and idx >= 1 and idx <= #CTL.MODES then
        if CTL.random then
            CTL.randomizeParam(idx)
        else
            CTL.onKey(idx)
        end
        M.pushEN16()
    end
end

function M.onTurn(dir)
    M.CTL.onEndless(dir)
    M.pushEN16()
end

function M.onClick()
    M.CTL.onEndlessClick()
    M.pushEN16()
end

-- Small buttons 1..4. With SHIFT active they are track selectors (1..4).
-- Without SHIFT: 1,2 = viewport (first/second 16) as-is; 3,4 = LOAD/SAVE arm
-- chords. Arm sets on press, clears on release. Returns a bool so the caller
-- can skip the EN16 repush when nothing changed (e.g. arm-only edges).
function M.onSmallBtn(sidx, pressed)
    local CTL = M.CTL
    if CTL.shift then
        CTL.onSmallBtn(sidx)      -- track select (1..4)
        M.lastPh = -1
        M.pushEN16()
    elseif sidx == 1 or sidx == 2 then
        if pressed then CTL.onSmallBtn(sidx) end   -- viewport 1/2 on press edge
        M.lastPh = -1
        M.pushEN16()
    elseif sidx == 3 then
        CTL.setArm(pressed and "load" or nil)      -- button 11 = LOAD chord
    elseif sidx == 4 then
        CTL.setArm(pressed and "save" or nil)      -- button 12 = SAVE chord
    end
end

-- -----------------------------------------------------------------------------
-- Cross-module receivers (EN16 -> VSN1)
-- -----------------------------------------------------------------------------

function M.fromEN16Turn(i, d)
    local CTL = M.CTL
    if i < 1 or i > 16 then return end
    local f = CTL.focus
    if f == CTL.MODE_LASTSTEP or f == CTL.MODE_SCALE then return end
    local s = (CTL.viewport - 1) * 16 + i
    if s > Engine.tracks[CTL.selT].lastStep then return end
    CTL.setSelectedStep(s)
    CTL.setParam(f, CTL.selT, s, d)
    M.pushEN16()
end

function M.fromEN16Press(i)
    local CTL = M.CTL
    if i < 1 or i > 16 then return end
    local s = (CTL.viewport - 1) * 16 + i
    if CTL.shift then
        CTL.setSelectedStep(s)
    elseif CTL.focus == CTL.MODE_LASTSTEP then
        Engine.setLastStep(CTL.selT, s)
        CTL.dirtyAll()
    else
        local stp = Engine.tracks[CTL.selT].steps[s]
        Engine.setStepParam(CTL.selT, s, "mute",
            Step.muted(stp) and 0 or 1)
        CTL.dirtyAll()
    end
    M.pushEN16()
end

return M
