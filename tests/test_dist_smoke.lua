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
    -- flat aliases for UI bundle's require-shim fallback
    if mods.engine ~= mods.Core.engine then
        error("flat alias mods.engine drifted from Core.engine")
    end
end

function M.test_ui_bundle_loads_via_core()
    -- Simulate the device wiring: Core is loaded, then UI is required and
    -- its inner `require("engine")` etc. resolve through Core's flat aliases.
    local core = dofile("dist/sequencer.lua")
    package.loaded["sequencer"] = core    -- mimic on-device require() result
    local ui = dofile("dist/sequencer_ui.lua")
    package.loaded["sequencer"] = nil     -- clean up
    if not ui.screen then error("UI bundle missing screen module") end
    if not ui.en16   then error("UI bundle missing en16 module")   end
    if type(ui.screen.draw) ~= "function" then
        error("UI screen module missing draw()")
    end
    if type(ui.en16.refreshLeds) ~= "function" then
        error("UI en16 module missing refreshLeds()")
    end
end

return M
