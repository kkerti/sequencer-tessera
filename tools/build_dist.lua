-- tools/build_dist.lua
-- Build TWO bundles from src/:
--   dist/sequencer.lua     -- Core only (step + track + engine). ~10 KB.
--                             Required at module init. Engine + MIDI alone.
--   dist/sequencer_ui.lua  -- Controls layer (controls + controls_en16). ~8 KB.
--                             Lazy-loaded by VSN1.lua on first input event so
--                             pure-playback or boot-failure paths never pay
--                             the screen-UI heap cost.
--
-- The UI bundle's internal require-shim falls back to the host's `require`
-- so `require("engine")` / `require("track")` / `require("step")` inside
-- the UI modules resolves through the already-loaded Core bundle. This
-- works because Core is a regular `require("sequencer")` whose three-layer
-- table makes step/track/engine available as flat aliases.
--
-- Pipeline (per file, both bundles):
--   1. Strip comments (line + block).
--   2. Strip top-level assert(...) calls.
--   3. Collapse whitespace.
--
-- Verifies both bundles parse on macOS Lua 5.4 before exiting.

local SRC = "src"

-- ---------- bundle definitions ----------

-- Core bundle: pure logic, no IO, no UI.
local CORE = {
    out   = "dist/sequencer.lua",
    files = { "step", "track", "engine" },
    namespaces = [[
return {
    Core     = { step = R.step, track = R.track, engine = R.engine },
    Controls = nil,   -- lazy-loaded; require("sequencer_ui") to populate
    HAL      = {},
    -- flat aliases (same table refs); UI bundle resolves through these
    step   = R.step,
    track  = R.track,
    engine = R.engine,
}
]],
}

-- UI bundle: Controls layer. Depends on Core being already loaded.
-- Its internal require-shim falls back to the host `require` for missing
-- modules so `require("engine")` etc. resolves through Core's flat aliases
-- (see SHIM_UI below).
local UI = {
    out   = "dist/sequencer_ui.lua",
    files = { "controls", "controls_en16" },
    namespaces = [[
return {
    screen = R.controls,
    en16   = R.controls_en16,
}
]],
}

-- Require-shim variants ------------------------------------------------------

local SHIM_CORE = [[
local R={}
local function require(n) return R[n] end
]]

-- UI shim: prefer locally-bundled module, else delegate to host require
-- (which on device returns the Core bundle and exposes step/track/engine
-- as flat fields). This keeps the inner module sources unmodified.
local SHIM_UI = [[
local R={}
local _hostReq = require
local _seq
local function require(n)
    local r = R[n]
    if r ~= nil then return r end
    if not _seq then _seq = _hostReq("sequencer") end
    return _seq[n]
end
]]

-- ---------- io ----------

local function read(path)
    local f = assert(io.open(path, "r"))
    local s = f:read("*a")
    f:close()
    return s
end

local function write(path, content)
    os.execute("mkdir -p dist")
    local f = assert(io.open(path, "w"))
    f:write(content)
    f:close()
end

-- ---------- comment stripping (string-aware, long-bracket-aware) ----------

local function stripComments(src)
    local out = {}
    local i, n = 1, #src
    while i <= n do
        local c = src:sub(i, i)
        if c == '"' or c == "'" then
            local q = c
            out[#out+1] = c; i = i + 1
            while i <= n do
                local d = src:sub(i, i)
                out[#out+1] = d; i = i + 1
                if d == "\\" and i <= n then
                    out[#out+1] = src:sub(i, i); i = i + 1
                elseif d == q then
                    break
                end
            end
        elseif c == "[" then
            local eqs = src:match("^=*", i + 1)
            local startIdx = i + 1 + #eqs
            if src:sub(startIdx, startIdx) == "[" then
                local closing = "]" .. eqs .. "]"
                local endIdx = src:find(closing, startIdx + 1, true)
                if endIdx then
                    out[#out+1] = src:sub(i, endIdx + #closing - 1)
                    i = endIdx + #closing
                else
                    out[#out+1] = c; i = i + 1
                end
            else
                out[#out+1] = c; i = i + 1
            end
        elseif c == "-" and src:sub(i + 1, i + 1) == "-" then
            local after = i + 2
            if src:sub(after, after) == "[" then
                local eqs = src:match("^=*", after + 1)
                local startIdx = after + 1 + #eqs
                if src:sub(startIdx, startIdx) == "[" then
                    local closing = "]" .. eqs .. "]"
                    local endIdx = src:find(closing, startIdx + 1, true)
                    if endIdx then
                        i = endIdx + #closing
                    else
                        i = n + 1
                    end
                else
                    local nl = src:find("\n", i, true)
                    i = nl and nl or (n + 1)
                end
            else
                local nl = src:find("\n", i, true)
                i = nl and nl or (n + 1)
            end
        else
            out[#out+1] = c
            i = i + 1
        end
    end
    return table.concat(out)
end

-- ---------- assert stripping ----------

local function stripAsserts(src)
    src = src:gsub("\n[ \t]*assert%b()[ \t]*\n", "\n")
    for _ = 1, 3 do
        src = src:gsub("assert(%b())", "%1")
    end
    return src
end

-- ---------- whitespace collapse (conservative) ----------

local function collapseWs(src)
    src = src:gsub("\r\n", "\n"):gsub("\r", "\n")
    src = src:gsub("[ \t]+\n", "\n")
    src = src:gsub("\n\n+", "\n")
    src = src:gsub("[ \t]+", " ")
    return src
end

-- ---------- bundle one set of files ----------

local function buildBundle(spec, shim, header)
    local parts = { header, shim }
    local rawTotal = 0
    for _, name in ipairs(spec.files) do
        local raw = read(SRC .. "/" .. name .. ".lua")
        rawTotal = rawTotal + #raw
        local body = collapseWs(stripAsserts(stripComments(raw)))
        parts[#parts+1] = string.format("R[%q]=(function()\n%s\nend)()\n", name, body)
    end
    parts[#parts+1] = spec.namespaces
    local out = table.concat(parts)
    write(spec.out, out)

    io.write(string.format("%-26s source: %5d  dist: %5d  (%.1f%%)\n",
        spec.out, rawTotal, #out, 100 * #out / rawTotal))

    local ok, err = loadfile(spec.out)
    if not ok then
        io.stderr:write("VERIFY FAIL " .. spec.out .. ": " .. tostring(err) .. "\n")
        os.exit(1)
    end
end

-- ---------- main ----------

buildBundle(CORE, SHIM_CORE, "-- dist/sequencer.lua (auto-generated; Core only)\n")
buildBundle(UI,   SHIM_UI,   "-- dist/sequencer_ui.lua (auto-generated; Controls layer)\n")

io.write("verify: both bundles parse OK\n")
