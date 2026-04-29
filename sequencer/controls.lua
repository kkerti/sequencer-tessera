-- sequencer/controls.lua
-- VSN1 on-device control surface: editing model + screen renderer for the
-- sequencer UI. Owns the parameter-selection state, applies edits from the
-- endless knob, and draws the 4x2 cell grid on the 320x240 LCD.
--
-- Bundled separately into grid/controls.lua for the device — see
-- tools/build_grid.lua. Lazy-loaded by the device on first BUTTON event.
--
-- Design:
--   * Single global state table M.S (one allocation, shared across events).
--   * Parameter codes are single chars: see PARAM CODES below.
--   * Dirty flags drive surgical screen updates (no full-screen redraw).
--   * Functions take no implicit `self` other than the screen-element `scr`
--     passed to draw(); the rest of the API is procedural.
--
-- PARAM CODES (used everywhere — keep short for paste budget on host side):
--   "s" = step       "t" = track     "p" = pattern     "n" = sNapshot
--   "b" = cvB (note) "a" = cvA (vel) "d" = duration    "g" = gate
--
-- Wired against the LITE engine via the build_grid.lua aliases:
--   sequencer/step    → Step (lite)
--   sequencer/track   → Track (lite)
--   sequencer/pattern → Pattern (lite)
--   sequencer/engine  → Engine (lite)

local Step  = require("sequencer/step")
local Track = require("sequencer/track")

local M = {}

-- Shared state (populated by init).
local S

-- Display labels shown above each cell value.
local LB = { s="STEP", t="TRK",  p="PAT", m="DIR",
             b="NOTE", a="VEL",  d="DUR", g="GATE",
             l="LSTRT", e="LEND" }

-- Screen layout: parameter order, top-left to bottom-right, row-major.
-- Index in this list ALSO doubles as button-0..7 → param-code mapping.
-- `l` and `e` are reached via the 4 small under-LCD buttons (selectAux),
-- so they are NOT in PO and have no top-grid cell.
local PO = { "s","t","p","m",  "b","a","d","g" }

-- Direction modes in cycle order (matches Track.setDirection valid set).
local DIR_CYCLE = { "forward", "reverse", "pingpong", "random", "brownian" }
local DIR_INDEX = {}
for i, d in ipairs(DIR_CYCLE) do DIR_INDEX[d] = i end

-- Public so the host can iterate (BLOCK button events use indices to wire
-- buttons to selectors via M.PO[i] if desired; current controls.lua hardcodes
-- the codes directly to keep button-event blocks at one line each).
M.PO = PO
M.LB = LB

-- ---------------------------------------------------------------------------
-- Layout constants (320x240 LCD)
-- ---------------------------------------------------------------------------
-- Top half  y=0..120  : 4x2 editable cells (8 cells, 80x60 each)
-- Divider   y=120     : 1px line separating cells from timeline
-- Bottom    y=121..240: timeline strip (status row + step boxes)
-- ---------------------------------------------------------------------------
local CELL_W, CELL_H = 80, 60
local TL_Y     = 121               -- timeline top
local TL_H     = 240 - TL_Y        -- 119px
local TL_STAT_Y = TL_Y + 4         -- status text row
local TL_BOX_Y  = TL_Y + 28        -- step-box top
local TL_BOX_H  = 40               -- step-box height
local TL_PAD    = 8                -- horizontal margin around step boxes

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

local function cl(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function getTrack()   return S.engine.tracks[S.tr] end
local function getStep()    return Track.getStep(getTrack(), S.st) end

-- Mark all four step-scoped cells dirty (b/a/d/g). Used after a track
-- change or active-flag toggle.
local function dirtyStepCells()
    local d = S.dirty
    d.b = true; d.a = true; d.d = true; d.g = true
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- Initialise / reset the controls against an engine. Call ONCE from BLOCK 1.
function M.init(engine)
    S = {
        engine = engine,
        sel    = "s",   -- selected param code
        prev   = "s",   -- previous selected (for focus-swap redraw)
        tr     = 1,     -- track index
        pa     = 1,     -- pattern index
        st     = 1,     -- step index (flat)
        cur    = 0,     -- last cursor seen on the timeline (0 = unknown)
        dirty  = { s=true, t=true, p=true, m=true,
                   b=true, a=true, d=true, g=true },
        focusDirty = true,
        timelineDirty = true,   -- bottom strip needs a full repaint
    }
    M.S = S
end

-- Read the current value of a parameter code. Returns a string for codes
-- whose natural representation isn't an integer (direction, "off"-able loop
-- bounds); integer for everything else. Callers convert to string at the
-- draw site.
function M.value(c)
    if c == "s" then return S.st end
    if c == "t" then return S.tr end
    if c == "p" then return S.pa end
    if c == "m" then return getTrack().direction or "forward" end
    if c == "l" then return getTrack().loopStart end   -- may be nil
    if c == "e" then return getTrack().loopEnd   end   -- may be nil
    local s = getStep()
    if c == "b" then return Step.getPitch(s)    end
    if c == "a" then return Step.getVelocity(s) end
    if c == "d" then return Step.getDuration(s) end
    if c == "g" then return Step.getGate(s)     end
    return 0
end

-- Switch the selected parameter (called from button events).
-- No-op if the selection is unchanged (avoids a needless redraw).
function M.select(c)
    if S.sel == c then return end
    S.prev      = S.sel
    S.sel       = c
    S.focusDirty = true
    -- `l` and `e` have no top-cell; their selection state is shown only on
    -- the timeline status line. Always flag the strip dirty on selection
    -- changes that involve them (in either direction).
    if c == "l" or c == "e" or S.prev == "l" or S.prev == "e" then
        S.timelineDirty = true
    end
end

-- Apply a +1/-1 delta to the currently-selected parameter (endless event).
function M.edit(d)
    local c  = S.sel
    local tk = getTrack()
    if c == "s" then
        S.st = cl(S.st + d, 1, Track.getStepCount(tk))
        dirtyStepCells()      -- the value-cells are bound to the new step
        S.timelineDirty = true
    elseif c == "t" then
        S.tr = cl(S.tr + d, 1, S.engine.trackCount)
        S.pa = 1; S.st = 1
        S.dirty.p = true; S.dirty.s = true
        S.dirty.m = true
        dirtyStepCells()
        S.timelineDirty = true
    elseif c == "p" then
        S.pa = cl(S.pa + d, 1, Track.getPatternCount(tk))
        S.timelineDirty = true
    elseif c == "m" then
        local i = (DIR_INDEX[tk.direction] or 1) - 1
        i = (i + d) % #DIR_CYCLE
        if i < 0 then i = i + #DIR_CYCLE end
        Track.setDirection(tk, DIR_CYCLE[i + 1])
        S.timelineDirty = true
    elseif c == "l" then
        local n  = Track.getStepCount(tk)
        local hi = tk.loopEnd or n
        local nv
        if tk.loopStart == nil then
            -- First rotation after "off": initialise to the current edit
            -- cursor (clamped 1..loopEnd). Delta is ignored on the init step.
            nv = cl(S.st, 1, hi)
        else
            nv = cl(tk.loopStart + d, 1, hi)
        end
        Track.setLoopStart(tk, nv)
        S.timelineDirty = true
    elseif c == "e" then
        local n  = Track.getStepCount(tk)
        local lo = tk.loopStart or 1
        local nv
        if tk.loopEnd == nil then
            nv = cl(S.st, lo, n)
        else
            nv = cl(tk.loopEnd + d, lo, n)
        end
        Track.setLoopEnd(tk, nv)
        S.timelineDirty = true
    elseif c == "b" or c == "a" or c == "d" or c == "g" then
        local s  = getStep()
        local hi = (c == "d" or c == "g") and 99 or 127
        local nv = cl(M.value(c) + d, 0, hi)
        if     c == "b" then s = Step.setPitch(s, nv)
        elseif c == "a" then s = Step.setVelocity(s, nv)
        elseif c == "d" then s = Step.setDuration(s, nv)
        else                 s = Step.setGate(s, nv) end
        Track.setStep(tk, S.st, s)
        S.timelineDirty = true
    end
    S.dirty[c] = true
end

-- Endless-click action.
--   * On a step-scoped selector (b/a/d/g) or step/track/pattern: toggle the
--     current step's active flag (legacy behaviour, mute / unmute).
--   * On `l` or `e`: clear that loop boundary back to nil ("off").
--   * On `m`: no-op (cycling is already covered by rotation).
function M.toggle()
    local c  = S.sel
    local tk = getTrack()
    if c == "l" then
        Track.clearLoopStart(tk)
        S.dirty.l = true
        S.timelineDirty = true
    elseif c == "e" then
        Track.clearLoopEnd(tk)
        S.dirty.e = true
        S.timelineDirty = true
    elseif c == "m" then
        -- nothing
    else
        local s = getStep()
        s = Step.setActive(s, not Step.getActive(s))
        Track.setStep(tk, S.st, s)
        dirtyStepCells()
        S.timelineDirty = true
    end
end

-- ---------------------------------------------------------------------------
-- Screen rendering
-- ---------------------------------------------------------------------------
-- Top half (y 0..120): 4x2 cells, 80x60 each. Label at +4,+4 (size 12); value
-- at +4,+22 (size 32). Selected cell has red bg, white fg. Muted step-scoped
-- params (b/a/d/g when step.active=false) drawn dim.
--
-- Bottom half (y 121..240): timeline strip for the current track.
--   y 125 .. 137  status line: TRK, dir, loop range, cursor pos / step count.
--   y 149 .. 189  step boxes: one box per step; cursor highlighted; loop
--                 range tinted; inactive steps drawn dim.
-- ---------------------------------------------------------------------------

-- Direction-mode short labels for the timeline status line.
local DIR_LB = { forward="FWD", reverse="REV", pingpong="P-P",
                 random="RND", brownian="BRN" }

-- One-time screen layout: full wipe + static dividers.
function M.initScreen(scr)
    scr:draw_rectangle_filled(0, 0, 320, 240, {0, 0, 0})
    -- vertical dividers between cells (top half only)
    for c = 1, 3 do
        scr:draw_line(c * CELL_W, 0, c * CELL_W, CELL_H * 2, {40, 40, 40})
    end
    -- horizontal divider: between cell rows + between top half and timeline
    scr:draw_line(0, CELL_H,    320, CELL_H,    {40, 40, 40})
    scr:draw_line(0, CELL_H * 2,320, CELL_H * 2,{60, 60, 60})
    scr:draw_swap()
end

-- Draw one cell. Index 1..8, code is one of the param codes.
local function drawCell(scr, idx, c)
    local col = (idx - 1) % 4
    local row = (idx > 4) and 1 or 0
    local x   = col * CELL_W
    local y   = row * CELL_H
    local fc  = (c == S.sel)
    local bg  = fc and {200, 30, 30} or {0, 0, 0}
    -- step-scoped params dim when the step is muted
    local mu  = (c == "b" or c == "a" or c == "d" or c == "g")
                and (not Step.getActive(getStep()))
    local fg
    if fc then           fg = {255, 255, 255}
    elseif mu then       fg = {90, 90, 90}
    else                 fg = {200, 200, 200} end
    scr:draw_rectangle_filled(x, y, x + CELL_W, y + CELL_H, bg)
    scr:draw_text_fast(LB[c], x + 4, y + 4, 12, fg)
    scr:draw_text_fast(tostring(M.value(c)), x + 4, y + 22, 32, fg)
end

-- Compute step-box geometry. Returns (boxWidth, paddedAreaStartX).
-- Steps are laid out across (320 - 2*TL_PAD) px. Boxes have 1px gap if
-- there's room, otherwise butt up against each other.
local function tlBoxGeom(n)
    local avail = 320 - TL_PAD * 2
    local w     = math.floor(avail / n)
    if w < 1 then w = 1 end
    return w, TL_PAD
end

-- Draw the bottom timeline strip for the current track.
local function drawTimeline(scr)
    local tk     = getTrack()
    local nSteps = Track.getStepCount(tk)
    local cur    = tk.cursor or 0
    local lo     = tk.loopStart
    local hi     = tk.loopEnd
    local dir    = DIR_LB[tk.direction] or "?"

    -- Wipe the strip.
    scr:draw_rectangle_filled(0, TL_Y, 320, 240, {0, 0, 0})

    -- Status line. Prefix with `>L` / `>E` when an aux selector is active so
    -- the user has visual confirmation (those codes have no top-cell).
    local prefix = ""
    if     S.sel == "l" then prefix = ">L "
    elseif S.sel == "e" then prefix = ">E "
    end
    local loStr = lo and tostring(lo) or "--"
    local hiStr = hi and tostring(hi) or "--"
    local status = prefix .. "TRK " .. S.tr .. "  " .. dir
                .. "  LOOP " .. loStr .. ".." .. hiStr
                .. "  " .. S.st .. "/" .. nSteps
    scr:draw_text_fast(status, TL_PAD, TL_STAT_Y, 12, {180, 180, 180})

    -- Step boxes.
    local w, x0 = tlBoxGeom(nSteps)
    for i = 1, nSteps do
        local x  = x0 + (i - 1) * w
        local s  = Track.getStep(tk, i)
        local active = Step.getActive(s)
        local inLoop = lo and hi and i >= lo and i <= hi

        local bg
        if i == cur then
            bg = {220, 220, 60}        -- bright cursor (engine playhead)
        elseif i == S.st then
            bg = {200, 30, 30}         -- red edit cursor
        elseif inLoop then
            bg = {30, 60, 30}          -- loop-range tint
        else
            bg = {25, 25, 25}
        end
        scr:draw_rectangle_filled(x, TL_BOX_Y, x + w - 1, TL_BOX_Y + TL_BOX_H, bg)

        -- Inactive steps: small grey overlay so they read as muted.
        if not active then
            scr:draw_line(x, TL_BOX_Y, x + w - 1, TL_BOX_Y + TL_BOX_H, {80, 80, 80})
        end
    end

    S.cur = cur
end

-- Render dirty cells + timeline. Call from BLOCK 13 (screen draw event).
-- Issues at most ONE draw_swap per call, only if something was redrawn.
function M.draw(scr)
    local sw = false

    -- If focus changed this frame, redraw both old and new cell.
    if S.focusDirty then
        for i, c in ipairs(PO) do
            if c == S.sel or c == S.prev then
                drawCell(scr, i, c)
                S.dirty[c] = false
                sw = true
            end
        end
        S.focusDirty = false
        S.prev       = S.sel
    end

    -- Repaint other cells flagged dirty by edits / toggles.
    for i, c in ipairs(PO) do
        if S.dirty[c] then
            drawCell(scr, i, c)
            S.dirty[c] = false
            sw = true
        end
    end

    -- Auto-detect engine cursor advance: if it moved since last draw, redraw
    -- the timeline. This keeps the playhead visible without the host having
    -- to call any "tick" hook.
    local tk  = getTrack()
    local cur = tk.cursor or 0
    if cur ~= S.cur then S.timelineDirty = true end

    if S.timelineDirty then
        drawTimeline(scr)
        S.timelineDirty = false
        sw = true
    end

    if sw then scr:draw_swap() end
end

return M
