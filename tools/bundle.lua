-- tools/bundle.lua
-- Splice multiple Lua modules into one self-contained file.
--
-- Each input is wrapped in a `do ... end` block so its locals stay private.
-- The block's final `return <Module>` is captured into a top-level local
-- named after the module. Cross-module `require("...")` calls are rewritten
-- to read those locals directly. The bundled file ends with a `return` of
-- the last module's local (the "main" export).
--
-- Usage:
--   lua tools/bundle.lua --out <path> --as A=mod_a.lua [--as B=mod_b.lua ...] \
--       [--main MAIN]
--
-- Where:
--   --as NAME=PATH   declare module NAME sourced from PATH (repeatable)
--                    NAME is the local name it gets in the bundle; PATH
--                    is also the string that require("PATH-without-.lua")
--                    will be rewritten away from. NAME also matches the
--                    require-string with extension stripped.
--   --main NAME      the module whose local value is the bundle's return.
--                    Defaults to the last --as.
--
-- Example:
--   lua tools/bundle.lua --out grid/sequencer.lua \
--       --as Step=sequencer/step.lua \
--       --as Pattern=sequencer/pattern.lua \
--       --as Scene=sequencer/scene.lua \
--       --as Track=sequencer/track.lua \
--       --as Engine=sequencer/engine.lua \
--       --main Engine
--
-- The bundle's final return value is the Engine module table. Other locals
-- (Step, Pattern, Track, Utils) are accessible by accessing fields of
-- Engine if exposed, or by adding them to the engine's return table.
-- For now consumers must `require` the bundle to get Engine, then call
-- Engine functions; if they need Step/Pattern/Track directly, the bundle
-- exposes them as fields on the returned table (see --expose).
--
--   --expose NAME    also expose this module as a field on the returned table
--                    (repeatable; --main is always exposed implicitly)

local function readFile(path)
    local f, err = io.open(path, "rb")
    if not f then error("cannot read " .. path .. ": " .. tostring(err)) end
    local s = f:read("*a")
    f:close()
    return s
end

local function writeFile(path, content)
    local f, err = io.open(path, "wb")
    if not f then error("cannot write " .. path .. ": " .. tostring(err)) end
    f:write(content)
    f:close()
end

-- Parse CLI
local args = arg or {}
local outPath
local mainName
local modules = {}    -- ordered list of {name, path, requireKey}
local aliases = {}    -- list of {key, name} for extra require-key mappings
local exposeSet = {}
local i = 1
while i <= #args do
    local a = args[i]
    if a == "--out" then
        outPath = args[i + 1]; i = i + 2
    elseif a == "--main" then
        mainName = args[i + 1]; i = i + 2
    elseif a == "--as" then
        local spec = args[i + 1]
        local name, path = spec:match("^([%w_]+)=(.+)$")
        if not name then error("--as expects NAME=PATH, got: " .. tostring(spec)) end
        -- requireKey is the path without trailing .lua, used to match require("...") strings
        local key = path:gsub("%.lua$", "")
        modules[#modules + 1] = { name = name, path = path, requireKey = key }
        i = i + 2
    elseif a == "--expose" then
        exposeSet[args[i + 1]] = true; i = i + 2
    elseif a == "--alias" then
        -- Extra require-key -> local-name mapping (no source file).
        -- Use when a module is required under multiple paths (e.g. the lite
        -- engine is bundled as Engine but PatchLoader requires it under
        -- "sequencer/engine"): --alias sequencer/engine=Engine
        local spec = args[i + 1]
        local key, name = spec:match("^(.+)=([%w_]+)$")
        if not key then error("--alias expects KEY=NAME, got: " .. tostring(spec)) end
        aliases[#aliases + 1] = { key = key, name = name }
        i = i + 2
    else
        error("unknown arg: " .. a)
    end
end

if not outPath then error("--out required") end
if #modules == 0 then error("at least one --as required") end
if not mainName then mainName = modules[#modules].name end
exposeSet[mainName] = true

-- Build a require-key -> local-name map for rewriting.
local keyToLocal = {}
for _, m in ipairs(modules) do
    keyToLocal[m.requireKey] = m.name
end
for _, a in ipairs(aliases) do
    keyToLocal[a.key] = a.name
end

-- Rewrite any `require("KEY")` call in the source to reference the local.
-- Replacement is a parenthesised expression so it remains a value usable
-- in `local X = require(...)` contexts.
local function rewriteRequires(src)
    return (src:gsub('require%s*%(%s*(["\'])(.-)%1%s*%)', function(q, key)
        local name = keyToLocal[key]
        if name then return '(' .. name .. ')' end
        return 'require(' .. q .. key .. q .. ')'
    end))
end

-- Strip a trailing `return <ident>` (with optional whitespace and one
-- semicolon) from a module so we can capture it ourselves. Returns the
-- stripped body and the captured name.
local function extractReturn(body)
    local stripped, returned = body:gsub(
        "(\n)%s*return%s+([%w_%.]+)%s*;?%s*$", "%1")
    if returned > 0 then
        local name = body:match("\nreturn%s+([%w_%.]+)%s*;?%s*$")
        return stripped, name
    end
    -- Try the very-end form without leading newline (defensive)
    stripped = body:gsub("^return%s+([%w_%.]+)%s*;?%s*$", "")
    if stripped ~= body then
        local name = body:match("^return%s+([%w_%.]+)%s*;?%s*$")
        return stripped, name
    end
    error("module body must end with `return <ident>`")
end

-- Build the bundle.
local out = {
    "-- Bundled by tools/bundle.lua. Do not edit.",
    "-- Modules: " .. (function()
        local names = {}
        for _, m in ipairs(modules) do names[#names + 1] = m.name end
        return table.concat(names, ", ")
    end)(),
    "",
}

-- Forward-declare all module locals so cross-module requires resolve
-- regardless of declaration order in the bundle.
do
    local names = {}
    for _, m in ipairs(modules) do names[#names + 1] = m.name end
    out[#out + 1] = "local " .. table.concat(names, ", ")
end
out[#out + 1] = ""

for _, m in ipairs(modules) do
    local src = readFile(m.path)
    local rewritten = rewriteRequires(src)
    local body, returned = extractReturn(rewritten)
    out[#out + 1] = "-- ========== " .. m.name .. " (from " .. m.path .. ")"
    out[#out + 1] = m.name .. " = (function()"
    out[#out + 1] = body
    out[#out + 1] = "    return " .. returned
    out[#out + 1] = "end)()"
    out[#out + 1] = ""
end

-- Build the main export. If anything else is in exposeSet, attach it
-- as a field on the main table (non-destructive: only if not present).
local exposed = {}
for name in pairs(exposeSet) do
    if name ~= mainName then exposed[#exposed + 1] = name end
end
table.sort(exposed)

if #exposed > 0 then
    out[#out + 1] = "-- Expose secondary modules as fields on the main export."
    for _, name in ipairs(exposed) do
        out[#out + 1] = "if " .. mainName .. "." .. name ..
            " == nil then " .. mainName .. "." .. name .. " = " .. name .. " end"
    end
    out[#out + 1] = ""
end

out[#out + 1] = "return " .. mainName
out[#out + 1] = ""

writeFile(outPath, table.concat(out, "\n"))
local f = io.open(outPath, "rb"); local sz = f:seek("end"); f:close()
io.stderr:write(string.format(
    "Bundled %d modules -> %s (%d bytes, main=%s)\n",
    #modules, outPath, sz, mainName))
