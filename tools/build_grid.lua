-- tools/build_grid.lua
-- Build the device-side bundle: grid/sequencer.lua containing
--   sequencer (Step, Pattern, Scene, Track, Engine)
--   + MidiTranslate
--   + PatchLoader
--   + Driver
-- and copies patch files into grid/ at the root.
--
-- Usage: lua tools/build_grid.lua

local function sh(cmd)
    io.stderr:write("$ " .. cmd .. "\n")
    local ok = os.execute(cmd)
    if not (ok == true or ok == 0) then error("command failed: " .. cmd) end
end

local function readFile(p)
    local f = assert(io.open(p, "rb")); local s = f:read("*a"); f:close(); return s
end
local function writeFile(p, s)
    local f = assert(io.open(p, "wb")); f:write(s); f:close()
end

-- 1. Wipe stale grid contents (keep bridge.py + grid_module.lua if present).
local stale = {
    "grid/player.lua", "grid/edit.lua", "grid/sequencer_lite.lua",
    "grid/dark_groove.lua", "grid/four_on_floor.lua", "grid/empty.lua",
    "grid/utils.lua", "grid/sequencer.lua", "grid/controls.lua",
}
for _, p in ipairs(stale) do os.remove(p) end

-- ---------------------------------------------------------------------------
-- 2. Bundle sequencer.lua  (engine + driver only — NO controls/UI)
-- ---------------------------------------------------------------------------
-- Controls is shipped separately as grid/controls.lua and lazy-loaded on
-- the device by the first BUTTON event. Pure-playback patches never pay
-- the controls heap cost. See docs/2026-04-29-memory-overflow-plan.md.
sh(table.concat({
    "lua tools/bundle.lua",
    "--out grid/sequencer.lua",
    "--as Step=sequencer/step.lua",
    "--as Pattern=sequencer/pattern.lua",
    "--as Scene=sequencer/scene.lua",
    "--as Track=sequencer/track.lua",
    "--as Engine=sequencer/engine.lua",
    "--as MidiTranslate=sequencer/midi_translate.lua",
    "--as PatchLoader=sequencer/patch_loader.lua",
    "--as Driver=driver/driver.lua",
    "--main Driver",
    "--expose Engine --expose PatchLoader --expose MidiTranslate",
    "--expose Track --expose Pattern --expose Step --expose Scene",
}, " "))

-- 3. Strip the bundle (comments + asserts).
sh("lua tools/strip.lua grid/sequencer.lua --out grid/sequencer.lua")

-- ---------------------------------------------------------------------------
-- 4. Bundle controls.lua  (loaded lazily on first BUTTON event)
-- ---------------------------------------------------------------------------
-- The controls module needs Step + Track; both are exposed on the
-- /sequencer.lua bundle as Driver.Step / Driver.Track. We prepend a shim
-- that grabs them from there and rewrite the require() calls inside
-- controls.lua to read those locals via --alias.
sh(table.concat({
    "lua tools/bundle.lua",
    "--out grid/controls.lua",
    "--as Controls=sequencer/controls.lua",
    "--alias sequencer/step=Step",
    "--alias sequencer/track=Track",
    "--main Controls",
}, " "))
-- Prepend the shim that resolves Step + Track from the already-loaded bundle.
do
    local body = readFile("grid/controls.lua")
    local shim = table.concat({
        "-- grid/controls.lua  (lazy-loaded UI module)",
        "-- Resolves Step + Track from the already-loaded /sequencer bundle so",
        "-- this file does not re-bundle them.",
        "local _D = require(\"/sequencer\")",
        "local Step  = _D.Step",
        "local Track = _D.Track",
        "",
    }, "\n")
    writeFile("grid/controls.lua", shim .. body)
end
sh("lua tools/strip.lua grid/controls.lua --out grid/controls.lua")

-- 5. Run LuaSrcDiet --maximum on both stripped bundles. This shortens local
-- identifiers, drops empty lines/whitespace, and rewrites numeric literals.
-- We disable the binary-equivalence check (--noopt-binequiv) because diet
-- was authored for Lua 5.1 and its check fails on Lua 5.4+ bytecode; the
-- source-equivalence check (--opt-srcequiv, default ON) still guards us.
local hasDiet = os.execute("command -v LuaSrcDiet >/dev/null 2>&1")
if hasDiet == true or hasDiet == 0 then
    for _, f in ipairs({ "grid/sequencer.lua", "grid/controls.lua" }) do
        sh("LuaSrcDiet --maximum --noopt-binequiv --quiet -o " .. f .. ".diet " .. f)
        os.remove(f)
        assert(os.rename(f .. ".diet", f))
    end
else
    io.stderr:write("WARN: LuaSrcDiet not found on PATH; skipping diet pass.\n")
    io.stderr:write("      Install: luarocks --lua-version=5.5 install luasrcdiet\n")
end

-- 4. Copy patch files into grid/ as plain Lua data tables.
for _, name in ipairs({ "dark_groove", "four_on_floor", "empty" }) do
    local src = readFile("patches/" .. name .. ".lua")
    writeFile("grid/" .. name .. ".lua", src)
end

-- 5. Report sizes.
io.stderr:write("\n--- grid/ contents ---\n")
sh("ls -la grid/")
