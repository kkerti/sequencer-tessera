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

function M.test_en16_bundle_loads_standalone()
    -- EN16 bundle is fully standalone. No Core, no Step.
    local en16 = dofile("dist/sequencer_en16.lua")
    if type(en16.refreshColors) ~= "function" then
        error("EN16 bundle missing refreshColors()")
    end
    if type(en16.setShadow) ~= "function" then
        error("EN16 bundle missing setShadow()")
    end
    if type(en16.setMeta) ~= "function" then
        error("EN16 bundle missing setMeta()")
    end
    en16.setShadow(1, 60 | (100 << 7) | (4 << 14) | (2 << 21))
    en16.setMeta(1, 16, 1, 1, 1, 0)
    local emits = 0
    en16.refreshColors(function(_, _, _, _) emits = emits + 1 end)
    if emits ~= 16 then error("expected 16 color emits on first call, got " .. emits) end
    -- second call same state -> 0 emits (cache hit)
    en16.refreshColors(function(_, _, _, _) emits = emits + 1 end)
    if emits ~= 16 then error("color cache failed: re-emitted on identical state") end
    -- focus change -> non-playhead encoders re-emit (15 of 16; playhead stays white)
    en16.setMeta(2, 16, 1, 1, 1, 0)
    en16.refreshColors(function(_, _, _, _) emits = emits + 1 end)
    if emits ~= 31 then error("focus change should emit 15 colors (playhead unchanged), got " .. (emits - 16)) end
end

return M
