-- tests/test_dist_smoke.lua
-- Loads both built bundles and runs basic sanity checks.
-- Locks the IoT-style separation: Core bundle is engine-only; UI bundle
-- (lazy-loaded on device) carries the Controls layer.
local M = {}

function M.test_dist_loads_and_runs()
    local ok, mods = pcall(dofile, "dist/sequencer.lua")
    if not ok then error("dist load failed: " .. tostring(mods)) end
    local Engine = mods.Core.engine
    local Step   = mods.Core.step
    if not Engine or not Step then error("missing Core modules in bundle") end
    Engine.init({ trackCount = 1 })
    Engine.tracks[1].steps[1] = Step.pack({ pitch=60, vel=100, dur=4, gate=2 })
    Engine.onStart()
    local ev = Engine.onPulse()
    if not ev or ev[1].pitch ~= 60 then error("dist runtime: bad event") end
end

function M.test_dist_scale_settable_through_bundle()
    -- Regression: the Core bundle once built track before scale, so
    -- require("scale") resolved nil inside the bundle and setTrackScale
    -- crashed on device. Lock the dependency ordering.
    local mods = dofile("dist/sequencer.lua")
    local Engine = mods.Core.engine
    Engine.init({ trackCount = 1 })
    Engine.setTrackScale(1, 3)
    if Engine.tracks[1].scale ~= 3 then
        error("dist: setTrackScale did not take effect")
    end
    if not Engine.scales or not mods.Core.scale then
        error("dist: scale module not present in Core bundle")
    end
end

function M.test_dist_namespace_shape()
    local mods = dofile("dist/sequencer.lua")
    if not mods.Core     then error("missing Core layer")     end
    if not mods.HAL      then error("missing HAL layer")      end
    if mods.Controls ~= nil then
        error("Controls must be nil in Core bundle (lazy-loaded)")
    end
    if not mods.Core.step or not mods.Core.track or not mods.Core.engine then
        error("Core layer missing step/track/engine")
    end
    if not mods.Core.scale then error("Core layer missing scale") end
    if not mods.Core.persist then error("Core layer missing persist") end
    -- flat aliases for UI bundle's require-shim fallback
    if mods.engine ~= mods.Core.engine then
        error("flat alias mods.engine drifted from Core.engine")
    end
end

function M.test_ui_bundle_loads_via_core()
    -- Simulate the VSN1 wiring: Core loaded, then UI required.
    local core = dofile("dist/sequencer.lua")
    package.loaded["sequencer"] = core
    local ui = dofile("dist/sequencer_ui.lua")
    package.loaded["sequencer"] = nil
    if not ui.screen then error("UI bundle missing screen module") end
    if type(ui.screen.draw) ~= "function" then
        error("UI screen module missing draw()")
    end
end

function M.test_vsn1_bundle_loads_via_core()
    -- VSN1 handler bundle: lazy-loaded after the screen UI bundle.
    local core = dofile("dist/sequencer.lua")
    package.loaded["sequencer"] = core
    local ui   = dofile("dist/sequencer_ui.lua")
    local app  = dofile("dist/sequencer_vsn1.lua")
    package.loaded["sequencer"] = nil

    if type(app.init)     ~= "function" then error("vsn1 missing init()") end
    if type(app.onKey)    ~= "function" then error("vsn1 missing onKey()") end
    if type(app.pushEN16) ~= "function" then error("vsn1 missing pushEN16()") end

    -- init wires the screen controls module
    core.Core.engine.init({ trackCount = 4, stepsPerTrack = 64 })
    local ret = app.init(ui.screen)
    if ret ~= app then error("init() must return the app module") end
    if app.CTL ~= ui.screen then error("init() must store controls in CTL") end
end

function M.test_en16_bundle_loads_via_core()
    -- EN16 bundle is standalone (no Core dependency). The UI shim's
    -- fall-through path is unused. Wiring through it anyway proves harmless.
    local core = dofile("dist/sequencer.lua")
    package.loaded["sequencer"] = core
    local en16 = dofile("dist/sequencer_en16.lua")
    package.loaded["sequencer"] = nil

    if type(en16.U)        ~= "function" then error("EN16 missing U()") end
    if type(en16.H)        ~= "function" then error("EN16 missing H()") end
    if type(en16.refresh)  ~= "function" then error("EN16 missing refresh()") end

    -- mu=0 (none muted), focus=2 (NOTE), sel=1, cap=16, tr=1, all values 0
    en16.U(0, 2, 1, 16, 1, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0)

    local emits = 0
    en16.refresh(function(_, _, _, _) emits = emits + 1 end)
    if emits ~= 16 then error("expected 16 color emits on first refresh, got " .. emits) end

    -- second refresh same state -> 0 emits (cache hit)
    en16.refresh(function(_, _, _, _) emits = emits + 1 end)
    if emits ~= 16 then error("color cache failed: re-emitted on idle refresh") end

    -- value change on slot 5 -> brightness changes -> re-emit
    en16.U(0, 2, 1, 16, 1, 0,0,0,0, 127,0,0,0, 0,0,0,0, 0,0,0,0)
    local before = emits
    en16.refresh(function(_, _, _, _) emits = emits + 1 end)
    if emits == before then error("value change should re-emit affected slot") end

    -- mute mask: bit 2 set (slot 3 muted) -> slot 3 must repaint
    before = emits
    en16.U(1 << 2, 2, 1, 16, 1, 0,0,0,0, 127,0,0,0, 0,0,0,0, 0,0,0,0)
    en16.refresh(function(_, _, _, _) emits = emits + 1 end)
    if emits == before then error("mute mask change should re-emit slot 3") end

    -- playhead push: H(7) lights slot 7 white
    before = emits
    en16.H(7)
    en16.refresh(function(_, _, _, _) emits = emits + 1 end)
    if emits == before then error("H(7) should cause a re-emit") end

    -- H(7) again -> idempotent
    before = emits
    en16.H(7)
    en16.refresh(function(_, _, _, _) emits = emits + 1 end)
    if emits ~= before then error("H(slot) idempotent for same slot") end

    -- H(0) clears playhead
    before = emits
    en16.H(0)
    en16.refresh(function(_, _, _, _) emits = emits + 1 end)
    if emits == before then error("H(0) should clear playhead and re-emit") end
end

return M
