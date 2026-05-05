-- tests/test_controls_swing.lua
-- LASTSTEP focus + shift: encoder edits global swing with 4-detent
-- decimation; click resets swing to 0; row + header swap to show swing.

local Engine   = require("engine")
local Controls = require("controls")
local M = {}

local function eq(a, b, msg)
    if a ~= b then
        error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2)
    end
end

local function setup()
    Engine.init({ trackCount = 4, stepsPerTrack = 64 })
    Engine.swing = 0
    Controls.selT, Controls.selS = 1, 1
    Controls.viewport = 1
    Controls.focus = Controls.MODE_LASTSTEP
    -- Force shift toggle so the module-local swing accumulator is cleared
    -- between tests (pairs() ordering means a prior test may have left it
    -- non-zero; setup() must put us in a known state).
    Controls.shift = false
    Controls.setShift(true)
end

local function makeScr()
    local seen = {}
    return {
        seen = seen,
        draw_rectangle_filled = function() end,
        draw_rectangle = function() end,
        draw_text_fast = function(self, s) seen[#seen + 1] = s end,
        draw_swap = function() end,
    }
end

-- ---- decimation ----

function M.test_three_detents_no_swing_change()
    setup()
    Controls.onEndless(1)
    Controls.onEndless(1)
    Controls.onEndless(1)
    eq(Engine.swing, 0, "3 detents below threshold")
end

function M.test_four_detents_advance_one_step()
    setup()
    for _ = 1, 4 do Controls.onEndless(1) end
    eq(Engine.swing, 1, "4 detents -> +1")
end

function M.test_eight_detents_advance_two_steps()
    setup()
    for _ = 1, 8 do Controls.onEndless(1) end
    eq(Engine.swing, 2, "8 detents -> +2")
end

function M.test_negative_decimation_symmetric()
    setup()
    Engine.setSwing(2)
    for _ = 1, 4 do Controls.onEndless(-1) end
    eq(Engine.swing, 1, "-4 detents -> -1")
    for _ = 1, 3 do Controls.onEndless(-1) end
    eq(Engine.swing, 1, "still -1, only 3 negative below threshold")
    Controls.onEndless(-1)
    eq(Engine.swing, 0, "fourth -1 fires the step")
end

function M.test_remainder_carries_across_calls()
    setup()
    Controls.onEndless(1); Controls.onEndless(1)   -- accum=2, no fire
    Controls.onEndless(1); Controls.onEndless(1)   -- accum=4, fire
    eq(Engine.swing, 1, "split-call accumulation still fires")
end

-- ---- accumulator reset ----

function M.test_focus_change_resets_accumulator()
    setup()
    Controls.onEndless(1); Controls.onEndless(1); Controls.onEndless(1)
    Controls.onKey(Controls.MODE_NOTE)
    Controls.onKey(Controls.MODE_LASTSTEP)
    Controls.shift = true
    Controls.onEndless(1)   -- only 1 detent post-reset
    eq(Engine.swing, 0, "stale accumulator did not leak across focus change")
end

function M.test_shift_release_resets_accumulator()
    setup()
    Controls.onEndless(1); Controls.onEndless(1); Controls.onEndless(1)
    Controls.setShift(false)
    Controls.setShift(true)
    Controls.onEndless(1)
    eq(Engine.swing, 0, "stale accumulator did not leak across shift toggle")
end

-- ---- click resets ----

function M.test_shift_click_in_LASTSTEP_resets_swing()
    setup()
    Engine.setSwing(3)
    Controls.onEndlessClick()
    eq(Engine.swing, 0, "shift+click in LASTSTEP focus zeroes swing")
end

function M.test_unshifted_click_in_LASTSTEP_does_nothing()
    setup()
    Controls.shift = false
    Engine.setSwing(2)
    Controls.onEndlessClick()
    eq(Engine.swing, 2, "click without shift in LASTSTEP focus is inert")
end

-- ---- screen affordance ----

function M.test_lastStep_row_swaps_to_swing_when_shift_held()
    setup()
    Engine.setSwing(2)   -- 67%
    local scr = makeScr()
    Controls.dirtyAll()
    Controls.draw(scr)

    local sawSwingRow = false
    for _, s in ipairs(scr.seen) do
        if s:find("swing") and s:find("67") then sawSwingRow = true end
    end
    if not sawSwingRow then
        error("expected lastStep row to read 'swing  67%' under shift")
    end
end

function M.test_lastStep_row_shows_last_when_shift_released()
    setup()
    Controls.shift = false
    Engine.tracks[1].lastStep = 12
    Engine.setSwing(2)
    local scr = makeScr()
    Controls.dirtyAll()
    Controls.draw(scr)

    local sawLast = false
    for _, s in ipairs(scr.seen) do
        if s:find("last") and s:find("12") then sawLast = true end
    end
    if not sawLast then
        error("expected lastStep row to read 'last  12' without shift")
    end
end

function M.test_header_omits_sw_suffix_when_swing_row_is_visible()
    setup()
    Engine.setSwing(2)
    local scr = makeScr()
    Controls.dirtyAll()
    Controls.draw(scr)

    -- header is split into two draw_text_fast calls (T-chip + rest);
    -- check both seen[1] and seen[2] for the suffix
    local header = (scr.seen[1] or "") .. " " .. (scr.seen[2] or "")
    if header:find("sw ") then
        error("header redundantly showed 'sw' while swing row is on screen: "
            .. header)
    end
end

function M.test_header_shows_sw_suffix_when_in_other_focus()
    setup()
    Engine.setSwing(1)   -- 58%
    Controls.focus = Controls.MODE_NOTE
    Controls.shift = false
    local scr = makeScr()
    Controls.dirtyAll()
    Controls.draw(scr)

    local header = (scr.seen[1] or "") .. " " .. (scr.seen[2] or "")
    if not header:find("sw") then
        error("expected 'sw' in header under non-LASTSTEP focus, got: "
            .. header)
    end
end

return M
