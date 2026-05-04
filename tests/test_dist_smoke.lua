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

function M.test_en16_bundle_loads_via_core()
    -- EN16 bundle is standalone; no Core dependency. We still go through
    -- the same wiring path to prove the UI-shim's fall-through is harmless
    -- when the bundle has zero require() calls of its own.
    local core = dofile("dist/sequencer.lua")
    package.loaded["sequencer"] = core
    local en16 = dofile("dist/sequencer_en16.lua")
    package.loaded["sequencer"] = nil

    if type(en16.S)        ~= "function" then error("EN16 missing S()") end
    if type(en16.V)        ~= "function" then error("EN16 missing V()") end
    if type(en16.M)        ~= "function" then error("EN16 missing M()") end
    if type(en16.H)        ~= "function" then error("EN16 missing H()") end
    if type(en16.refresh)  ~= "function" then error("EN16 missing refresh()") end

    -- seed: shadow slot 1 = pitch60/vel100/dur4/gate2; meta = focus1, lastStep16
    en16.S(1, 60 | (100 << 7) | (4 << 14) | (2 << 21))
    en16.M(1, 16, 1, 0)

    local emits = 0
    en16.refresh(function(_, _, _, _) emits = emits + 1 end)
    if emits ~= 16 then error("expected 16 color emits on first refresh, got " .. emits) end

    -- second refresh same state -> 0 emits (cache hit; not dirty)
    en16.refresh(function(_, _, _, _) emits = emits + 1 end)
    if emits ~= 16 then error("color cache failed: re-emitted on idle refresh") end

    -- focus change -> dirties; all 16 may re-emit (selection slot is one of them)
    en16.M(2, 16, 1, 0)
    local before = emits
    en16.refresh(function(_, _, _, _) emits = emits + 1 end)
    if emits == before then error("focus change should re-emit colors") end

    -- playhead push: H(7) lights slot 7 white. At least one new emit.
    before = emits
    en16.H(7)
    en16.refresh(function(_, _, _, _) emits = emits + 1 end)
    if emits == before then error("H(7) should cause a re-emit on slot 7") end

    -- H(7) again -> no dirty, no emits
    before = emits
    en16.H(7)
    en16.refresh(function(_, _, _, _) emits = emits + 1 end)
    if emits ~= before then error("H(slot) idempotent for same slot") end

    -- H(0) clears playhead -> slot 7 must repaint to its non-playhead color
    before = emits
    en16.H(0)
    en16.refresh(function(_, _, _, _) emits = emits + 1 end)
    if emits == before then error("H(0) should clear playhead and re-emit slot 7") end
end

return M
