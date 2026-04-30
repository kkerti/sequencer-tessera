-- tests/test_dist_smoke.lua
-- Loads the built dist bundle (if present) and runs a basic sanity check.
local M = {}

function M.test_dist_loads_and_runs()
    local ok, mods = pcall(dofile, "dist/sequencer.lua")
    if not ok then error("dist load failed: " .. tostring(mods)) end
    local Engine = mods.engine
    local Step   = mods.step
    if not Engine or not Step then error("missing modules in bundle") end
    Engine.init({ trackCount = 1 })
    Engine.tracks[1].steps[1] = Step.pack({ pitch=60, vel=100, dur=4, gate=2 })
    Engine.tracks[1].len = 1
    Engine.onStart()
    local ev = Engine.onPulse()
    if not ev or ev[1].pitch ~= 60 then error("dist runtime: bad event") end
end

return M
