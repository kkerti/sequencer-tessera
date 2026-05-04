-- controls_en16.lua  (EN16-side logic; standalone bundle target)
-- =============================================================================
-- EN16 holds:
--   * a 16-step shadow of the visible viewport of the selected track
--   * meta (focus, lastStep, selS-relative, shift)
--   * the current playhead slot (1..16, or 0 = playhead not in this window)
--
-- It does NOT own the engine. VSN1 is the source of truth.
-- It does NOT listen to MIDI clock. VSN1 pushes playhead changes via H().
-- It does NOT compute LED colors per pulse — only when something changed.
--
-- Anti-feedback: local turns/presses are forwarded to VSN1 only. Shadow is
-- only mutated by S/V/M/H calls received FROM VSN1.
--
-- Public API (called from EN16.lua entry):
--   M.S(i, p)              one shadow step changed (slot 1..16, packed int)
--   M.V(p1,...,p16)        full window snapshot (16 packed ints)
--   M.M(f, L, sR, sh)      meta: focus, lastStep (real), selS-rel, shift
--   M.H(slot)              playhead at slot 1..16, or 0 = not in window
--   M.refresh(emit)        emit(idx0, r, g, b) for each changed LED, then clear dirty
--   M.dirty                read-only flag; true = redraw needed
-- =============================================================================

local M = {}
M.NUM_ENC = 16

-- ---- shadow + meta ---------------------------------------------------------

M.SH       = {}
for i = 1, 16 do M.SH[i] = 0 end
M.focus    = 1     -- 1..7  (NOTE/VEL/GATE/MUTE/STEP/-/LASTSTEP)
M.lastStep = 16    -- real lastStep on selected track (1..64)
M.selR     = 1     -- selS relative to viewport (1..16); 0 = not in window
M.shift    = 0
M.ph       = 0     -- playhead slot 1..16, or 0 = not in this viewport

-- ---- mode color table (matches controls.lua) -------------------------------

local MR = {  30, 255, 240, 220,  60,  70, 230 }
local MG = { 200, 140, 210,  50, 120,  70, 230 }
local MB = { 220,  30,  40,  50, 255,  75, 230 }
M.MR, M.MG, M.MB = MR, MG, MB

-- ---- per-LED last-emitted packed RGB (cheap diff) --------------------------

M.LAST = {}
for i = 1, 16 do M.LAST[i] = -1 end

M.dirty = true

-- step pack layout: bit 29 = mute (see src/step.lua)
local function muted(p) return ((p >> 29) & 1) == 1 end

-- ---- VSN1 -> EN16 receivers ------------------------------------------------

function M.S(i, p)
    if i >= 1 and i <= 16 then
        M.SH[i] = p
        M.dirty = true
    end
end

function M.V(p1,p2,p3,p4,p5,p6,p7,p8,p9,p10,p11,p12,p13,p14,p15,p16)
    M.SH[1]=p1   M.SH[2]=p2   M.SH[3]=p3   M.SH[4]=p4
    M.SH[5]=p5   M.SH[6]=p6   M.SH[7]=p7   M.SH[8]=p8
    M.SH[9]=p9   M.SH[10]=p10 M.SH[11]=p11 M.SH[12]=p12
    M.SH[13]=p13 M.SH[14]=p14 M.SH[15]=p15 M.SH[16]=p16
    M.dirty = true
end

function M.M(f, L, sR, sh)
    M.focus    = f
    M.lastStep = L
    M.selR     = sR
    M.shift    = sh
    M.dirty = true
end

-- Playhead push from VSN1. slot=1..16 lights that slot; slot=0 clears.
-- Cheap: integer compare; only dirties when slot actually changed.
function M.H(slot)
    if slot ~= M.ph then
        M.ph = slot
        M.dirty = true
    end
end

-- ---- LED redraw ------------------------------------------------------------

function M.invalidateAll()
    for i = 1, 16 do M.LAST[i] = -1 end
    M.dirty = true
end

-- emit(idx0, r, g, b) where idx0 is 0..15 (hardware-native).
function M.refresh(emit)
    if not M.dirty then return end
    M.dirty = false

    local f, ls = M.focus, M.lastStep
    local mr, mg, mb = MR[f], MG[f], MB[f]
    local SH, LAST = M.SH, M.LAST
    local ph  = M.ph                    -- 1..16 or 0
    local sel = M.selR

    -- Window slot i is in-range iff its absolute step <= lastStep.
    -- We don't track viewport here; rely on VSN1 sending S(i, 0) for OOR
    -- slots when the viewport is the LAST one. Conservative cap: clamp
    -- i > min(16, lastStep) when lastStep < 16 (only viewport 1 case).
    -- Otherwise all 16 slots are valid candidates.
    local cap = (ls < 16) and ls or 16

    for i = 1, 16 do
        local r, g, b
        if i > cap then
            r, g, b = 0, 0, 0
        elseif i == ph then
            r, g, b = 255, 255, 255
        elseif i == sel then
            r, g, b = mr, mg, mb
        elseif muted(SH[i]) then
            r, g, b = 60, 0, 0
        else
            -- normal step: dim mode color (~30%)
            r = (mr * 80) >> 8
            g = (mg * 80) >> 8
            b = (mb * 80) >> 8
        end

        local packed = (r << 16) | (g << 8) | b
        if LAST[i] ~= packed then
            LAST[i] = packed
            emit(i - 1, r, g, b)
        end
    end
end

return M
