-- tests/euclidean/test_dist_smoke.lua
-- Loads the three Euclidean dist bundles and proves the same lazy-load
-- wiring used by the step sequencer works for euclid: Core required at
-- boot, UI + VSN1 lazy-loaded on first input.

local M = {}

function M.test_euclid_core_loads_and_runs()
    local mods = dofile("dist/euclid.lua")
    local Engine = mods.Core.engine
    local Track  = mods.Core.track
    if not Engine or not Track then error("missing Core modules in euclid bundle") end
    Engine.init({ trackCount = 4 })
    Engine.setSteps(1, 4); Engine.setEvents(1, 4); Engine.setPpstep(1, 1); Engine.setGate(1, 1); Engine.setKey(1, 60)
    Engine.onStart()
    local ev = Engine.onPulse()
    if not ev or ev[1].pitch ~= 60 then error("euclid runtime: expected pitch 60") end
end

function M.test_euclid_namespace_shape()
    local mods = dofile("dist/euclid.lua")
    if not mods.Core then error("missing Core layer") end
    if mods.Controls ~= nil then error("Controls must be nil in Core bundle") end
    if not mods.Core.track or not mods.Core.engine then error("Core layer incomplete") end
    -- dotted aliases for the UI shim's fall-through path
    if mods["euclidean.engine"] ~= mods.Core.engine then
        error("dotted alias drifted from Core.engine")
    end
end

function M.test_euclid_ui_loads_via_core()
    local core = dofile("dist/euclid.lua")
    package.loaded["euclid"] = core
    local ui = dofile("dist/euclid_ui.lua")
    package.loaded["euclid"] = nil
    if not ui.screen then error("UI bundle missing screen module") end
    if type(ui.screen.draw) ~= "function" then error("UI.screen.draw missing") end
    if type(ui.screen.onEndless) ~= "function" then error("UI.screen.onEndless missing") end
end

function M.test_euclid_vsn1_loads_via_core()
    local core = dofile("dist/euclid.lua")
    package.loaded["euclid"] = core
    local ui   = dofile("dist/euclid_ui.lua")
    local app  = dofile("dist/euclid_vsn1.lua")
    package.loaded["euclid"] = nil

    if type(app.init)        ~= "function" then error("vsn1 missing init()") end
    if type(app.onKey)       ~= "function" then error("vsn1 missing onKey()") end
    if type(app.onTurn)      ~= "function" then error("vsn1 missing onTurn()") end
    if type(app.onSmallBtn)  ~= "function" then error("vsn1 missing onSmallBtn()") end
    if type(app.draw)        ~= "function" then error("vsn1 missing draw()") end

    core.Core.engine.init({ trackCount = 4 })
    local ret = app.init(ui.screen)
    if ret ~= app then error("init() must return the app module") end
    if app.CTL ~= ui.screen then error("init() must store controls in CTL") end

    -- end-to-end: focus to STEPS (mode 1 in current spec: 1=STEPS 2=PULSES
    -- 3=ROTATE 4=RATE 5=PITCH), encoder turn changes selected track's steps.
    local before = core.Core.engine.tracks[1].steps
    app.onKey(1, true)             -- MODE_STEPS
    app.onTurn(1)                  -- +1 step
    if core.Core.engine.tracks[1].steps ~= before + 1 then
        error("end-to-end: encoder turn did not bump steps")
    end

    -- Screen-draw forward: app.draw(stub) must call CTL.draw, which
    -- must call draw_swap when dirty (init marks dirty).
    local swaps = 0
    local stub = {
        draw_rectangle_filled = function() end,
        draw_rectangle        = function() end,
        draw_text_fast        = function() end,
        draw_pixel            = function() end,
        draw_line             = function() end,
        draw_polygon_filled   = function() end,
        draw_swap             = function() swaps = swaps + 1 end,
    }
    app.draw(stub)
    if swaps ~= 1 then
        error("app.draw(self) must trigger one screen swap when dirty, got " .. swaps)
    end
    -- second draw with no state change: dirty flag cleared -> no swap
    app.draw(stub)
    if swaps ~= 1 then
        error("idempotent draw must not re-swap, got " .. swaps)
    end
end

return M
