-- controls_en16.lua  (EN16-side logic; standalone bundle target)
-- =============================================================================
-- EN16 holds FIVE numbers and a 16-bit mute mask. That's its entire state.
--
-- Protocol from VSN1:
--   M.U(mu, f, sel, cap)    full state update (mute mask, focus, sel slot,
--                           visible cap = min(lastStep within window, 16))
--   M.H(slot)               playhead at slot 1..16, or 0 = not in this window
--
-- It does NOT own the engine, does NOT listen to MIDI clock, does NOT keep
-- a per-step shadow. Local turns/presses are forwarded to VSN1 only.
-- =============================================================================

local M = {}
M.NUM_ENC = 16

-- ---- state (5 numbers) -----------------------------------------------------

M.mu    = 0    -- 16-bit mask: bit (i-1) set = slot i is muted
M.focus = 1    -- 1..7 (NOTE/VEL/GATE/MUTE/STEP/-/LASTSTEP)
M.sel   = 1    -- selected slot 1..16, or 0 = selection outside window
M.cap   = 16   -- visible in-range cap; slots > cap render off
M.ph    = 0    -- playhead slot 1..16, or 0 = not in this window

-- ---- mode color table (matches controls.lua) -------------------------------

local MR = {  30, 255, 240, 220,  60,  70, 230 }
local MG = { 200, 140, 210,  50, 120,  70, 230 }
local MB = { 220,  30,  40,  50, 255,  75, 230 }
M.MR, M.MG, M.MB = MR, MG, MB

-- ---- per-LED last-emitted packed RGB (cheap diff) --------------------------

M.LAST = {}
for i = 1, 16 do M.LAST[i] = -1 end

M.dirty = true

-- ---- VSN1 -> EN16 receivers ------------------------------------------------

function M.U(mu, f, sel, cap)
    M.mu, M.focus, M.sel, M.cap = mu, f, sel, cap
    M.dirty = true
end

-- Playhead push from VSN1. slot=1..16 lights that slot; slot=0 clears.
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

    local f, cap, sel, ph, mu = M.focus, M.cap, M.sel, M.ph, M.mu
    local mr, mg, mb = MR[f], MG[f], MB[f]
    local LAST = M.LAST

    -- precompute dim mode color (~30%)
    local dr = (mr * 80) >> 8
    local dg = (mg * 80) >> 8
    local db = (mb * 80) >> 8

    for i = 1, 16 do
        local r, g, b
        if i > cap then
            r, g, b = 0, 0, 0
        elseif i == ph then
            r, g, b = 255, 255, 255
        elseif i == sel then
            r, g, b = mr, mg, mb
        elseif (mu >> (i - 1)) & 1 == 1 then
            r, g, b = 60, 0, 0
        else
            r, g, b = dr, dg, db
        end

        local packed = (r << 16) | (g << 8) | b
        if LAST[i] ~= packed then
            LAST[i] = packed
            emit(i - 1, r, g, b)
        end
    end
end

return M
