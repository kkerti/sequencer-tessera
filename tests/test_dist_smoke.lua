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
    -- EN16 bundle is standalone (no Core dependency). The UI shim's
    -- fall-through path is unused. Wiring through it anyway proves harmless.
    local core = dofile("dist/sequencer.lua")
    package.loaded["sequencer"] = core
    local en16 = dofile("dist/sequencer_en16.lua")
    package.loaded["sequencer"] = nil

    if type(en16.U)        ~= "function" then error("EN16 missing U()") end
    if type(en16.H)        ~= "function" then error("EN16 missing H()") end
    if type(en16.refresh)  ~= "function" then error("EN16 missing refresh()") end

    -- mu=0 (none muted), focus=1 (NOTE), sel=1, cap=16
    en16.U(0, 1, 1, 16)

    local emits = 0
    en16.refresh(function(_, _, _, _) emits = emits + 1 end)
    if emits ~= 16 then error("expected 16 color emits on first refresh, got " .. emits) end

    -- second refresh same state -> 0 emits (cache hit)
    en16.refresh(function(_, _, _, _) emits = emits + 1 end)
    if emits ~= 16 then error("color cache failed: re-emitted on idle refresh") end

    -- focus change -> dirties; cells re-emit (at minimum the selection cell)
    en16.U(0, 2, 1, 16)
    local before = emits
    en16.refresh(function(_, _, _, _) emits = emits + 1 end)
    if emits == before then error("focus change should re-emit colors") end

    -- mute mask: bit 2 set (slot 3 muted) -> slot 3 must repaint
    before = emits
    en16.U(1 << 2, 2, 1, 16)
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
