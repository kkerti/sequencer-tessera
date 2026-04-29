-- tools/memprofile.lua
-- Estimate runtime memory cost of loading the grid bundle and instantiating
-- a patch. Uses collectgarbage("count") which returns Lua-VM-managed memory
-- in KB (does not include the Lua VM overhead itself, only allocations).
--
-- Usage: lua tools/memprofile.lua [patch_name ...]

local function gc()
    collectgarbage("collect"); collectgarbage("collect")
    return collectgarbage("count")
end

local function delta(label, before, after)
    print(string.format("  %-40s %+8.2f KB  (%.2f -> %.2f)",
        label, after - before, before, after))
end

local function profilePatch(patchName)
    print("\n=== " .. patchName .. " ===")

    -- Reset module cache for repeatable measurement.
    for k in pairs(package.loaded) do
        if k:sub(1, 8) == "/" .. "" or k == "sequencer" or k == patchName
            or k:match("^/") then
            package.loaded[k] = nil
        end
    end
    collectgarbage("collect"); collectgarbage("collect")

    local base = gc()

    -- 1. Load bundled engine.
    local Driver = require("sequencer")
    local afterEngine = gc()
    delta("require('/sequencer')", base, afterEngine)

    -- 2. Load patch descriptor.
    local descriptor = require(patchName)
    local afterPatch = gc()
    delta("require('/" .. patchName .. "')", afterEngine, afterPatch)

    -- 3. Build engine instance from descriptor.
    local engine = Driver.PatchLoader.build(descriptor)
    local afterBuild = gc()
    delta("PatchLoader.build (engine)", afterPatch, afterBuild)

    -- 4. Construct driver.
    local driver = Driver.new(engine, function() return 0 end, descriptor.bpm)
    local afterDriver = gc()
    delta("Driver.new", afterBuild, afterDriver)

    -- 5. Start driver (runs panic, resets tracks).
    Driver.start(driver)
    local afterStart = gc()
    delta("Driver.start", afterDriver, afterStart)

    -- 6. Run 100 external pulses to populate any lazy state.
    local function emit() end
    for _ = 1, 100 do Driver.externalPulse(driver, emit) end
    local afterPulses = gc()
    delta("100 x Driver.externalPulse", afterStart, afterPulses)

    print(string.format("  %-40s = %.2f KB", "PLAYBACK TOTAL (no UI)", afterPulses - base))

    -- 7. Lazy-load the controls UI module (simulates first BUTTON press).
    local Controls = require("/controls")
    Controls.init(engine)
    collectgarbage("collect"); collectgarbage("collect")
    local afterControls = gc()
    delta("require('/controls') + init", afterPulses, afterControls)

    print(string.format("  %-40s = %.2f KB", "TOTAL (with UI)", afterControls - base))

    -- Stats per descriptor scale.
    local trackCount = #descriptor.tracks
    local stepCount, patternCount = 0, 0
    for _, t in ipairs(descriptor.tracks) do
        for _, p in ipairs(t.patterns) do
            patternCount = patternCount + 1
            stepCount = stepCount + #p.steps
        end
    end
    print(string.format("  scale: %d tracks, %d patterns, %d steps",
        trackCount, patternCount, stepCount))
    print(string.format("  per step: %.2f KB",
        (afterPulses - base) / math.max(1, stepCount)))
end

-- Wire up package.path so require("/sequencer") and require("/<patch>") work
-- the same way as on device (literal paths, leading slash). On macOS we just
-- map the leading slash to the grid/ directory.
package.path = "grid/?.lua;./grid/?.lua;" .. package.path

-- Also support require("name") forms (no leading slash) by making them resolve
-- to grid/name.lua too.
local origLoader = package.searchers[2] or package.loaders[2]
package.searchers[2] = function(modname)
    -- Strip leading slash if present (device-style paths).
    local clean = modname:gsub("^/", "")
    local path = "grid/" .. clean .. ".lua"
    local f = io.open(path, "r")
    if f then
        f:close()
        local chunk, err = loadfile(path)
        if chunk then return chunk end
        return err
    end
    return origLoader(modname)
end

local patches = arg
if #patches == 0 then patches = { "four_on_floor", "dark_groove", "empty" } end

print(string.format("Lua VM baseline: %.2f KB", gc()))
for _, p in ipairs(patches) do profilePatch(p) end
