-- src/euclidean/controls.lua
-- VSN1 screen UI for the Euclidean engine.
--
-- Draw model: concentric overlay. T1 outermost ring, T4 innermost. Each
-- track's hits are dots in the track palette colour; rests are dim outline
-- pips. A polygon (closed) connects each track's hits in its colour. A
-- per-track playhead marker travels its own ring.
--
-- Focus modes (selected with VSN1 keyswitches 1..5):
--   1 ROTATE    encoder edits rot      (0..steps-1, wraps)
--   2 EVENTS    encoder edits k        (0..steps)
--   3 STEPS     encoder edits n        (1..32; clamps k, rot)
--   4 KEY       encoder edits MIDI key (0..127; SHIFT = +/-12)
--   5 RATE      encoder edits ppstep   (1..127 pulses per step; polyrhythm)
-- MODE_MUTE (6) is not bound to a keyswitch; mute is toggled via encoder
-- click instead (mirrors the step sequencer convention).
--
-- Track selection: small buttons 1..4 (no shift). With SHIFT held, small
-- buttons 1..4 still select track (we have no viewport concept). SHIFT+key 1..4
-- is reserved for future per-track preset slots.
--
-- Brightness-only highlight on the active param row, mirroring controls.lua.
-- Mute is the only colored signal.

local Engine = require("euclidean.engine")

local M = {}

local MN = { "ROTATE", "EVENTS", "STEPS", "KEY", "RATE", "MUTE" }
M.MODES = MN
M.MODE_ROTATE = 1
M.MODE_EVENTS = 2
M.MODE_STEPS  = 3
M.MODE_KEY    = 4
M.MODE_RATE   = 5
M.MODE_MUTE   = 6

-- Musical RATE ladder (pulses per pattern step, assumes 24 PPQN clock).
-- Mirrors the step sequencer's `dur` ladder for cross-module consistency.
--   3  = 32nd            6  = 16th             12 = 8th
--   18 = dotted-8th      24 = quarter          30 = dotted-quarter
-- Encoder snaps to the next entry in turn direction. Off-ladder values
-- (e.g. ppstep=4 from a hand-edited boot patch) jump to the nearest
-- on-ladder neighbour in the requested direction on first turn.
local RATE_LADDER = { 3, 6, 12, 18, 24, 30 }
local RATE_NAMES  = { "1/32", "1/16", "1/8", "1/8.", "1/4", "1/4." }

-- Step `cur` along RATE_LADDER by `dir` (+1 / -1). Off-ladder values are
-- snapped to the closest neighbour on the requested side, then nudged.
local function rateStep(cur, dir)
    local L = RATE_LADDER
    if dir > 0 then
        for i = 1, #L do
            if L[i] > cur then return L[i] end
        end
        return L[#L]    -- already at top: clamp
    else
        for i = #L, 1, -1 do
            if L[i] < cur then return L[i] end
        end
        return L[1]     -- already at bottom: clamp
    end
end
M._rateStep = rateStep   -- exposed for tests

-- Pretty-print ppstep for the PARAMS row. Off-ladder values shown as raw
-- pulse count so the field stays diagnosable.
local function rateLabel(p)
    for i = 1, #RATE_LADDER do
        if RATE_LADDER[i] == p then return RATE_NAMES[i] end
    end
    return tostring(p) .. "p"
end

-- selection state
M.selT  = 1
M.focus = 1
M.shift = false

local dirty = true

local function dAll() dirty = true end
M.dirtyAll = dAll

-- ---------- input ----------

function M.setShift(b)
    b = b and true or false
    if b == M.shift then return end
    M.shift = b; dirty = true
end

function M.setSelectedTrack(t)
    if t < 1 or t > #Engine.tracks or t == M.selT then return end
    M.selT = t; dirty = true
end

function M.onKey(idx)
    if idx < 1 or idx > #MN or idx == M.focus then return end
    M.focus = idx; dirty = true
end

function M.onSmallBtn(idx)
    if idx < 1 or idx > 4 then return end
    M.setSelectedTrack(idx)
end

local function applyDelta(t, f, d)
    local tr = Engine.tracks[t]
    if f == M.MODE_EVENTS then
        Engine.setEvents(t, tr.events + d)
    elseif f == M.MODE_STEPS then
        Engine.setSteps(t, tr.steps + d)
    elseif f == M.MODE_ROTATE then
        Engine.setRot(t, tr.rot + d)
    elseif f == M.MODE_KEY then
        local big = M.shift and 12 or 1
        Engine.setKey(t, tr.key + d * big)
    elseif f == M.MODE_RATE then
        Engine.setPpstep(t, rateStep(tr.ppstep, d))
    elseif f == M.MODE_MUTE then
        -- nothing on turn; click toggles
    end
end
M.applyDelta = applyDelta

function M.onEndless(dir)
    applyDelta(M.selT, M.focus, dir)
    dirty = true
end

function M.onEndlessClick()
    if M.focus == M.MODE_MUTE then
        local tr = Engine.tracks[M.selT]
        Engine.setMuted(M.selT, tr.muted == 1 and 0 or 1)
        dirty = true
        return
    end
    -- Outside MUTE focus, click toggles mute too (mirrors step sequencer)
    local tr = Engine.tracks[M.selT]
    Engine.setMuted(M.selT, tr.muted == 1 and 0 or 1)
    dirty = true
end

-- ---------- draw ----------

local C_BG    = {  14,  14,  18 }
local C_HD    = {  30,  30,  42 }
local C_FG    = { 235, 235, 240 }
local C_DIM   = { 120, 120, 140 }
local C_RING  = {  70,  70,  84 }
local C_HI    = {  60,  60,  65 }
local C_HIFG  = { 255, 255, 255 }
local C_PLY   = { 250,  90,  90 }
local C_MUTE  = { 160,  30,  30 }
local C_SHIFT = { 210, 140,  80 }

-- Track palette: T1 cyan, T2 green, T3 amber, T4 magenta. Mirrors the
-- screens/euclid_*.lua mocks so the visual identity carries through.
local PAL = {
    {  80, 180, 255 },
    { 120, 220, 140 },
    { 250, 200,  80 },
    { 240, 110, 160 },
}
M.PAL = PAL

-- Geometry mirrors screens/euclid_circle.lua: a single big ring on the
-- left, params + pattern column on the right. With one configured track
-- we get the full mock look; additional tracks layer as concentric inner
-- rings (R - 18 each).
local W, H   = 320, 240
local CX, CY = 130, 128
local R0     = 88                       -- outer (selected) track radius
local R_DELTA = 18
local TAU    = 6.2831853

local function ringPoint(R, i, n)
    local a = -1.5707963 + TAU * i / n
    return CX + math.floor(R * math.cos(a) + 0.5),
           CY + math.floor(R * math.sin(a) + 0.5),
           a
end

-- Scratch arrays for polygon vertices and diamond. Reused per draw to
-- avoid per-track table churn. Max hits per track == MAX_STEPS == 32, +1 close.
local PX, PY = {}, {}
local DX, DY = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }

-- Per-track ring painter. NO ring outline: 24 draw_pixel × 4 rings = 96
-- draw_pixel calls per frame was the dominant on-device cost (confirmed
-- via the EXP harness, see commit history). Hit pips alone mark the ring;
-- density and rotation remain readable from pip distribution.
local function drawTrack(scr, ti, tr, R, isSel)
    local col   = PAL[ti] or PAL[1]
    local muted = tr.muted == 1
    local c     = muted and C_MUTE or col
    local rDot, rRest
    if isSel then rDot, rRest = 8, 4 else rDot, rRest = 5, 2 end

    local nh = 0
    for i = 0, tr.steps - 1 do
        local x, y = ringPoint(R, i, tr.steps)
        local hit  = ((tr.hits >> i) & 1) == 1
        if hit then
            nh = nh + 1
            PX[nh] = x; PY[nh] = y
            scr:draw_rectangle_filled(x - rDot, y - rDot, x + rDot, y + rDot, c)
        else
            scr:draw_rectangle(x - rRest, y - rRest, x + rRest, y + rRest, C_RING)
        end
    end

    -- connecting polygon between hits
    if nh >= 2 then
        PX[nh + 1] = PX[1]; PY[nh + 1] = PY[1]
        for i = 1, nh do
            scr:draw_line(PX[i], PY[i], PX[i + 1], PY[i + 1], c)
        end
    end

    -- Sweep-line playhead from center to current step (selected track only).
    -- Mirrors euclid_circle.lua: radial line + diamond at slot. Drawing only
    -- on the selected track keeps the visual uncluttered as we add tracks.
    if isSel and tr.pos >= 0 and tr.steps > 0 then
        local px, py, a = ringPoint(R, tr.pos, tr.steps)
        local x2 = CX + math.floor((R + 12) * math.cos(a) + 0.5)
        local y2 = CY + math.floor((R + 12) * math.sin(a) + 0.5)
        scr:draw_line(CX, CY, x2, y2, C_PLY)
        DX[1] = px;     DY[1] = py - 5
        DX[2] = px + 5; DY[2] = py
        DX[3] = px;     DY[3] = py + 5
        DX[4] = px - 5; DY[4] = py
        scr:draw_polygon_filled(DX, DY, C_PLY)
    end
end

function M.draw(scr)
    -- Self-marking: if any track's playhead has advanced since the last
    -- draw, set dirty. This decouples the screen from `rtmrx_cb` (which
    -- can't safely draw, and whose dirty mark may race the next frame).
    -- The screen scriptlet runs periodically (≤20fps per Grid docs); we
    -- detect motion here rather than firing a redraw per pulse.
    local LP = M.lastPos
    if not LP then LP = {}; M.lastPos = LP end
    for ti = 1, #Engine.tracks do
        local p = Engine.tracks[ti].pos
        if LP[ti] ~= p then dirty = true; LP[ti] = p end
    end

    if not dirty then return end
    dirty = false

    scr:draw_rectangle_filled(0, 0, W - 1, H - 1, C_BG)

    local tr   = Engine.tracks[M.selT]
    local tcol = PAL[M.selT] or PAL[1]
    local fname = MN[M.focus]

    -- header (mirror euclid_circle.lua layout)
    scr:draw_rectangle_filled(0, 0, W - 1, 18, C_HD)
    scr:draw_text_fast("EUCLIDEAN  E(" .. tr.events .. "," .. tr.steps .. ")",
                       6, 5, 8, C_FG)
    scr:draw_text_fast("TRK " .. M.selT, 150, 5, 8, tcol)
    scr:draw_text_fast("rot " .. tr.rot, 200, 5, 8, C_DIM)
    if M.shift then
        scr:draw_text_fast("SHIFT", 250, 5, 8, C_SHIFT)
    end
    scr:draw_text_fast(fname, 285, 5, 8, C_HIFG)

    -- Rings: selected track outermost (R0), others stacked inward.
    -- Draw non-selected first so the selected ring's polygon sits on top.
    local nT = #Engine.tracks
    if nT > 1 then
        local inner = 1
        for ti = 1, nT do
            if ti ~= M.selT then
                drawTrack(scr, ti, Engine.tracks[ti], R0 - inner * R_DELTA, false)
                inner = inner + 1
            end
        end
    end
    drawTrack(scr, M.selT, tr, R0, true)

    -- center: big k, small /n
    scr:draw_text_fast(tostring(tr.events), CX - 6, CY - 12, 16, C_FG)
    scr:draw_text_fast("/" .. tr.steps, CX - 10, CY + 6, 8, C_DIM)

    -- right column: PARAMS + PATTERN, with brightness-only highlight on
    -- the focused row so the encoder's effect is unambiguous.
    local px, py = 234, 28
    scr:draw_text_fast("PARAMS", px, py, 8, C_DIM)

    local ROWS = {
        { lbl = "rotate ",  val = tr.rot,    mode = M.MODE_ROTATE },
        { lbl = "pulses ",  val = tr.events, mode = M.MODE_EVENTS },
        { lbl = "steps  ",  val = tr.steps,  mode = M.MODE_STEPS  },
        { lbl = "key    ",  val = tr.key,    mode = M.MODE_KEY    },
        { lbl = "rate   ",  val = rateLabel(tr.ppstep), mode = M.MODE_RATE   },
    }
    for i = 1, #ROWS do
        local y = py + 14 + (i - 1) * 12
        local active = (ROWS[i].mode == M.focus)
        if active then
            scr:draw_rectangle_filled(px - 2, y - 1, W - 2, y + 9, C_HI)
        end
        local fg = active and C_HIFG or C_FG
        scr:draw_text_fast(ROWS[i].lbl .. tostring(ROWS[i].val), px, y, 8, fg)
    end
    -- density (read-only derived value)
    local dens = (tr.steps > 0) and ((tr.events * 100) // tr.steps) or 0
    scr:draw_text_fast("density " .. dens .. "%", px, py + 14 + 5 * 12, 8, C_DIM)

    -- PATTERN: ASCII X/. row in track colour (or red if muted).
    local pcol = (tr.muted == 1) and C_MUTE or tcol
    scr:draw_text_fast("PATTERN", px, py + 92, 8, C_DIM)
    local row1_chars, row2_chars = {}, {}
    local n1, n2 = 0, 0
    for i = 0, tr.steps - 1 do
        local ch = (((tr.hits >> i) & 1) == 1) and "X" or "."
        if i < 16 then n1 = n1 + 1; row1_chars[n1] = ch
        else            n2 = n2 + 1; row2_chars[n2] = ch end
    end
    scr:draw_text_fast(table.concat(row1_chars), px, py + 104, 8, pcol)
    if n2 > 0 then
        scr:draw_text_fast(table.concat(row2_chars), px, py + 116, 8, pcol)
    end

    -- now-step + mute indicator
    local nowStr = (tr.pos >= 0) and ("now " .. (tr.pos + 1)) or "now -"
    scr:draw_text_fast(nowStr, px, py + 132, 8, C_PLY)
    if tr.muted == 1 then
        scr:draw_text_fast("MUTE", px + 60, py + 132, 8, C_MUTE)
    end

    -- footer hint strip
    scr:draw_rectangle_filled(0, H - 16, W - 1, H - 1, C_HD)
    scr:draw_text_fast("K1=rot K2=ev K3=st K4=key  small=trk  enc=edit (SHIFT x12)",
                       4, H - 12, 8, C_DIM)

    scr:draw_swap()
end

return M
