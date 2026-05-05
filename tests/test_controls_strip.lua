-- tests/test_controls_strip.lua
-- Verifies the bottom 16-cell strip:
--   * always draws a "well" (full-cell-height background) per cell
--   * draws a value-height "bar" anchored to the cell bottom for NOTE/VEL/GATE
--   * SHIFT in GATE focus switches the bar source from gate to dur
--   * MUTE / OOR cells render a coloured well and no bar
--
-- The stub screen records every draw_rectangle_filled call. Strip cells are
-- the ones whose geometry sits inside the strip band. Bars share the cell's
-- x-range but have a smaller (y1 - y0); wells span the full strip height.

local Engine   = require("engine")
local Step     = require("step")
local Controls = require("controls")
local M = {}

local function eq(a, b, msg)
    if a ~= b then
        error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2)
    end
end

local function newScr()
    local fills = {}
    return {
        fills = fills,
        draw_rectangle_filled = function(self, x0, y0, x1, y1, c)
            fills[#fills+1] = { x0=x0, y0=y0, x1=x1, y1=y1,
                                r=c[1], g=c[2], b=c[3] }
        end,
        draw_rectangle = function() end,
        draw_text_fast = function() end,
        draw_swap      = function() end,
    }
end

-- Layout constants mirrored from controls.lua. If they drift, update here.
local COL_W = 20
local STR_Y = 22 * (1 + 5) + 2 + 22 + 4   -- ROW_H*(1+PARAMS) + 2 + LS_H + 4 = 160
local STR_H = 240 - STR_Y - 1              -- 79
local STR_BOT = STR_Y + STR_H - 1          -- 238

-- Returns the well rect for cell c (1..16): the rect spanning the full
-- strip height in the cell's column.
local function cellWell(scr, c)
    local cellX = (c - 1) * COL_W + 1
    for _, r in ipairs(scr.fills) do
        if r.x0 == cellX and r.y0 == STR_Y and r.y1 == STR_BOT then
            return r
        end
    end
    error("no well for cell " .. c)
end

-- Returns the bar rect for cell c, or nil if no bar drawn.
local function cellBar(scr, c)
    local cellX = (c - 1) * COL_W + 1
    for _, r in ipairs(scr.fills) do
        if r.x0 == cellX and r.y1 == STR_BOT and r.y0 > STR_Y then
            return r
        end
    end
    return nil
end

local function setup()
    Engine.init({ trackCount = 4, stepsPerTrack = 64 })
    Controls.selT, Controls.selS = 1, 1
    Controls.viewport = 1
    Controls.focus = Controls.MODE_NOTE
    Controls.shift = false
    Controls.dirtyAll()
end

function M.test_well_drawn_for_every_cell()
    setup()
    local scr = newScr()
    Controls.draw(scr)
    for c = 1, 16 do cellWell(scr, c) end   -- raises if any missing
end

function M.test_vel_focus_bar_height_tracks_value()
    setup()
    local tr = Engine.tracks[1]
    tr.steps[3] = Step.pack({ pitch=60, vel=120, dur=4, gate=2 })
    tr.steps[4] = Step.pack({ pitch=60, vel=10,  dur=4, gate=2 })
    Controls.focus = Controls.MODE_VEL
    Controls.dirtyAll()

    local scr = newScr()
    Controls.draw(scr)

    local b3 = cellBar(scr, 3)
    local b4 = cellBar(scr, 4)
    if not b3 or not b4 then error("expected bars for both cells") end
    local h3 = b3.y1 - b3.y0
    local h4 = b4.y1 - b4.y0
    if h3 <= h4 then
        error("loud bar h(" .. h3 .. ") should exceed quiet bar h(" .. h4 .. ")")
    end
end

function M.test_gate_focus_shift_switches_bar_source_to_dur()
    setup()
    local tr = Engine.tracks[1]
    tr.steps[1] = Step.pack({ pitch=60, vel=100, dur=2,   gate=120 })
    tr.steps[2] = Step.pack({ pitch=60, vel=100, dur=120, gate=2   })
    Controls.focus = Controls.MODE_GATE
    Controls.shift = false
    Controls.dirtyAll()

    local s1 = newScr(); Controls.draw(s1)
    local b1_a = cellBar(s1, 1); local b2_a = cellBar(s1, 2)
    if not (b1_a and b2_a) then error("expected bars in gate focus") end
    if (b1_a.y1 - b1_a.y0) <= (b2_a.y1 - b2_a.y0) then
        error("gate-focus: high-gate bar should be taller than low-gate bar")
    end

    Controls.setShift(true)
    local s2 = newScr(); Controls.draw(s2)
    local b1_b = cellBar(s2, 1); local b2_b = cellBar(s2, 2)
    if not (b1_b and b2_b) then error("expected bars in gate+shift focus") end
    if (b1_b.y1 - b1_b.y0) >= (b2_b.y1 - b2_b.y0) then
        error("gate+shift: high-dur bar should be taller than low-dur bar")
    end
end

function M.test_muted_cell_has_no_bar_and_uses_mute_well_colour()
    setup()
    local tr = Engine.tracks[1]
    tr.steps[5] = Step.pack({ pitch=60, vel=127, dur=4, gate=2, mute=1 })
    Controls.focus = Controls.MODE_VEL
    Controls.dirtyAll()

    local scr = newScr()
    Controls.draw(scr)
    if cellBar(scr, 5) then error("muted cell must not draw a bar") end
    local w = cellWell(scr, 5)
    eq(w.r, 70, "muted well R")
    eq(w.g, 18, "muted well G")
    eq(w.b, 22, "muted well B")
end

function M.test_oor_cell_has_no_bar_and_uses_oor_well_colour()
    setup()
    Engine.setLastStep(1, 8)
    Controls.focus = Controls.MODE_VEL
    Controls.dirtyAll()

    local scr = newScr()
    Controls.draw(scr)
    if cellBar(scr, 10) then error("OOR cell must not draw a bar") end
    local w = cellWell(scr, 10)
    eq(w.r, 35, "oor well R"); eq(w.g, 35, "oor well G"); eq(w.b, 40, "oor well B")
end

function M.test_step_focus_draws_no_bar()
    setup()
    local tr = Engine.tracks[1]
    tr.steps[1] = Step.pack({ pitch=127, vel=127, dur=127, gate=127 })
    Controls.focus = Controls.MODE_STEP
    Controls.dirtyAll()

    local scr = newScr()
    Controls.draw(scr)
    -- STEP focus: wells but no bars on any in-range cell
    for c = 1, 16 do
        if cellBar(scr, c) then
            error("STEP focus must not draw a bar (cell " .. c .. ")")
        end
    end
end

return M
