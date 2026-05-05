-- controls_en16.lua  (EN16-side logic; standalone bundle target)
-- =============================================================================
-- EN16 holds its own tiny shadow:
--   mu     16-bit mute mask
--   focus  current edit mode (1..6)
--   sel    selected slot (1..16, 0 = outside this window)
--   cap    visible in-range cap (slots > cap render off)
--   tr     selected track (1..4) — drives per-track LED hue
--   ph     playhead slot (1..16, 0 = not in this window)
--   vals   16 values (0..127), interpreted per focus
--
-- Protocol from VSN1:
--   M.U(mu, f, sel, cap, tr, v1..v16)  full state + value snapshot
--   M.H(slot)                          playhead at slot 1..16, or 0
--
-- Color model:
--   * Track palette: T1=blue, T2=orange, T3=green, T4=purple
--   * NOTE/VEL/GATE focus: brightness ramps from dim track-hue to full
--     track-hue (instead of grey).
--   * STEP / LASTSTEP / MUTE focus: dim track-hue floor on in-range slots.
--   * Muted slot           = red (overrides hue, except playhead/sel)
--   * Out-of-range slot    = off
--   * Playhead slot        = white (max contrast)
--   * Selected slot        = white (max contrast — current edit cursor)
--
-- It does NOT own the engine. Local turns/presses are forwarded to VSN1
-- only; VSN1 echoes back via U().
-- =============================================================================

local M = {}
M.NUM_ENC = 16

-- mode constants (kept in sync with controls.lua)
M.MODE_STEP     = 1
M.MODE_NOTE     = 2
M.MODE_VEL      = 3
M.MODE_GATE     = 4
M.MODE_MUTE     = 5
M.MODE_LASTSTEP = 6

-- Track palette as RGB triples.
-- 1=blue, 2=orange, 3=green, 4=purple
M.PAL = {
    {  60, 130, 255 },  -- T1 blue
    { 255, 140,  20 },  -- T2 orange
    {  60, 200,  90 },  -- T3 green
    { 180,  80, 220 },  -- T4 purple
}

-- ---- state ----------------------------------------------------------------

M.mu    = 0
M.focus = 2    -- default NOTE
M.sel   = 1
M.cap   = 16
M.tr    = 1
M.ph    = 0

M.vals = {}
for i = 1, 16 do M.vals[i] = 0 end

-- ---- per-LED last-emitted packed RGB (cheap diff) -------------------------

M.LAST = {}
for i = 1, 16 do M.LAST[i] = -1 end

M.dirty = true

-- ---- VSN1 -> EN16 receivers ----------------------------------------------

function M.U(mu, f, sel, cap, tr, v1,v2,v3,v4,v5,v6,v7,v8,v9,v10,v11,v12,v13,v14,v15,v16)
    M.mu, M.focus, M.sel, M.cap, M.tr = mu, f, sel, cap, tr
    local V = M.vals
    V[1]=v1 or 0;   V[2]=v2 or 0;   V[3]=v3 or 0;   V[4]=v4 or 0
    V[5]=v5 or 0;   V[6]=v6 or 0;   V[7]=v7 or 0;   V[8]=v8 or 0
    V[9]=v9 or 0;   V[10]=v10 or 0; V[11]=v11 or 0; V[12]=v12 or 0
    V[13]=v13 or 0; V[14]=v14 or 0; V[15]=v15 or 0; V[16]=v16 or 0
    M.dirty = true
end

function M.H(slot)
    if slot ~= M.ph then
        M.ph = slot
        M.dirty = true
    end
end

-- ---- LED redraw -----------------------------------------------------------

function M.invalidateAll()
    for i = 1, 16 do M.LAST[i] = -1 end
    M.dirty = true
end

-- emit(idx0, r, g, b) where idx0 is 0..15 (hardware-native).
function M.refresh(emit)
    if not M.dirty then return end
    M.dirty = false

    local f, cap, sel, ph, mu = M.focus, M.cap, M.sel, M.ph, M.mu
    local LAST, V = M.LAST, M.vals
    local heat = (f == M.MODE_NOTE or f == M.MODE_VEL or f == M.MODE_GATE)
    local pal  = M.PAL[M.tr] or M.PAL[1]
    local pr, pg, pb = pal[1], pal[2], pal[3]
    -- floor brightness (0..255 multiplier domain). Idle in-range slots
    -- glow at this fraction of the track hue. Lower = more dynamic range
    -- between silent and loud steps.
    local FLOOR = 14
    -- Perceptual lift table: maps value 0..127 -> brightness 0..255 with a
    -- sqrt-ish curve so mid-range values look noticeably bright instead of
    -- crawling linearly. Pre-baked to avoid sqrt() in the hot path.
    --   index = v + 1 (Lua 1-based); built once at module load.
    local LIFT = M._LIFT

    for i = 1, 16 do
        local r, g, b
        if i > cap then
            r, g, b = 0, 0, 0
        elseif (mu >> (i - 1)) & 1 == 1 then
            -- muted: red, except playhead/selection still win
            if i == ph then
                r, g, b = 255, 255, 255
            elseif i == sel then
                r, g, b = 255, 80, 80    -- bright red (max for mute)
            else
                r, g, b = 120, 0, 0
            end
        elseif i == ph then
            r, g, b = 255, 255, 255
        elseif i == sel then
            r, g, b = 255, 255, 255
        elseif heat then
            -- perceptual lift: small values still register, mids pop
            local v = V[i] or 0
            if v < 0 then v = 0 elseif v > 127 then v = 127 end
            local lifted = LIFT[v + 1]                       -- 0..255
            local k = FLOOR + ((255 - FLOOR) * lifted) // 255
            r = (pr * k) // 255
            g = (pg * k) // 255
            b = (pb * k) // 255
        else
            -- STEP / LASTSTEP / MUTE focus: dim track-hue floor
            r = (pr * FLOOR) // 255
            g = (pg * FLOOR) // 255
            b = (pb * FLOOR) // 255
        end

        local packed = (r << 16) | (g << 8) | b
        if LAST[i] ~= packed then
            LAST[i] = packed
            emit(i - 1, r, g, b)
        end
    end
end

-- Pre-baked perceptual lift table (sqrt curve). v=0..127 -> 0..255.
-- Built once at module load to keep refresh() allocation-free.
M._LIFT = {}
do
    local L = M._LIFT
    for v = 0, 127 do
        -- normalized 0..1, sqrt for perceptual lift, scale to 0..255
        local t = v / 127
        local lifted = t ^ 0.5
        L[v + 1] = (lifted * 255) // 1
    end
end

return M
