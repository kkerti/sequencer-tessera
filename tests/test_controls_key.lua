-- tests/test_controls_key.lua
-- Slot 6 (KEY focus): root pitch + major/minor selector. Display-only.

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
    Engine.rootPitch = 0
    Engine.scaleMode = 0
    Controls.selT, Controls.selS = 1, 1
    Controls.viewport = 1
    Controls.focus = Controls.MODE_NOTE
    Controls.shift = false
end

function M.test_engine_defaults_root_C_major()
    Engine.init({})
    eq(Engine.rootPitch, 0, "default root")
    eq(Engine.scaleMode, 0, "default mode")
end

function M.test_setRootPitch_wraps_modulo_12()
    setup()
    Engine.setRootPitch(13); eq(Engine.rootPitch, 1, "wrap up")
    Engine.setRootPitch(-1); eq(Engine.rootPitch, 11, "wrap down")
    Engine.setRootPitch(24); eq(Engine.rootPitch, 0, "wrap multiple")
end

function M.test_setScaleMode_normalises_to_0_or_1()
    setup()
    Engine.setScaleMode(1); eq(Engine.scaleMode, 1)
    Engine.setScaleMode(0); eq(Engine.scaleMode, 0)
    Engine.setScaleMode(7); eq(Engine.scaleMode, 1, "any nonzero -> 1")
end

function M.test_onKey_now_accepts_slot_6()
    setup()
    Controls.onKey(6)
    eq(Controls.focus, Controls.MODE_KEY, "focus moved to KEY")
end

function M.test_endless_turn_in_KEY_focus_cycles_root()
    setup()
    Controls.onKey(6)
    Controls.onEndless(1)
    eq(Engine.rootPitch, 1, "+1 -> C# (1)")
    Controls.onEndless(-2)
    eq(Engine.rootPitch, 11, "-2 from 1 wraps to 11 (B)")
end

function M.test_shift_endless_in_KEY_focus_toggles_mode()
    setup()
    Controls.onKey(6)
    Controls.setShift(true)
    Controls.onEndless(1)
    eq(Engine.scaleMode, 1, "first shift+turn flips to minor")
    Controls.onEndless(1)
    eq(Engine.scaleMode, 0, "second shift+turn flips back to major")
end

function M.test_endless_click_in_KEY_focus_toggles_mode()
    setup()
    Controls.onKey(6)
    Controls.onEndlessClick()
    eq(Engine.scaleMode, 1, "click flips to minor")
    Controls.onEndlessClick()
    eq(Engine.scaleMode, 0, "click flips back to major")
end

function M.test_KEY_focus_does_not_modify_step_data()
    setup()
    local before = Engine.tracks[1].steps[1]
    Controls.onKey(6)
    Controls.onEndless(5)
    Controls.setShift(true)
    Controls.onEndless(1)
    Controls.setShift(false)
    Controls.onEndlessClick()
    eq(Engine.tracks[1].steps[1], before, "step pack unchanged by KEY edits")
end

function M.test_header_shows_key_when_focus_is_KEY()
    setup()
    Engine.setRootPitch(2)   -- D
    Engine.setScaleMode(1)   -- minor
    Controls.onKey(6)

    local seen = nil
    local scr = {
        draw_rectangle_filled = function() end,
        draw_rectangle = function() end,
        draw_text_fast = function(self, s) if not seen then seen = s end end,
        draw_swap = function() end,
    }
    Controls.dirtyAll()
    Controls.draw(scr)
    if not (seen and seen:find("KEY") and seen:find("D") and seen:find("min")) then
        error("expected header to mention KEY, D and min; got: " .. tostring(seen))
    end
end

return M
