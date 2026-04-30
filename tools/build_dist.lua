-- tools/build_dist.lua
-- Build dist/sequencer.lua from src/.
--
-- Pipeline (safe, deterministic):
--   1. Concatenate src files via a tiny require-shim.
--   2. Strip comments (line + block).
--   3. Strip top-level assert(...) calls.
--   4. Collapse whitespace.
--
-- Verifies the bundle parses on macOS Lua 5.4 before exiting.

local SRC = "src"
local OUT = "dist/sequencer.lua"

-- order matters: leaves first
local FILES = {
    "step",
    "track",
    "engine",
    "controls",
}

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

-- ---------- comment stripping ----------

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
    -- whole-line assert statement
    src = src:gsub("\n[ \t]*assert%b()[ \t]*\n", "\n")
    -- expression-position assert(x) -> x  (a few passes for nesting)
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

-- ---------- bundle ----------

local function bundle()
    local parts = {
        "-- dist/sequencer.lua (auto-generated; do not edit)\n",
        "local R={}\n",
        "local function require(n) return R[n] end\n",
    }
    for _, name in ipairs(FILES) do
        local body = read(SRC .. "/" .. name .. ".lua")
        body = stripComments(body)
        body = stripAsserts(body)
        body = collapseWs(body)
        parts[#parts+1] = string.format("R[%q]=(function()\n%s\nend)()\n", name, body)
    end
    parts[#parts+1] = "return R\n"
    return table.concat(parts)
end

-- ---------- main ----------

local out = bundle()
local rawTotal = 0
for _, name in ipairs(FILES) do
    rawTotal = rawTotal + #read(SRC .. "/" .. name .. ".lua")
end

io.write(string.format("source: %d bytes\n", rawTotal))
io.write(string.format("dist:   %d bytes (%.1f%%)\n", #out, 100 * #out / rawTotal))

write(OUT, out)
io.write("wrote " .. OUT .. "\n")

-- verify
local ok, err = loadfile(OUT)
if not ok then
    io.stderr:write("VERIFY FAIL: " .. tostring(err) .. "\n")
    os.exit(1)
end
io.write("verify: bundle parses OK\n")
