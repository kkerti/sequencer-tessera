-- tools/strip.lua
-- Strips comments and statement-form `assert(...)` calls from Lua source,
-- preserving formatting otherwise. Intended for shipping authoring-engine
-- modules to the Grid module, where input-validation asserts are dead weight
-- (the engine already passed those checks during dev/testing on macOS).
--
-- What is removed:
--   * Single-line comments  (-- ... \n)
--   * Long comments          (--[[ ... ]], --[=[ ... ]=], etc.)
--   * Statement-form asserts: a line whose first non-whitespace token is
--     `assert(`. The whole call is removed, parenthesis-balanced across
--     multiple lines, respecting strings and comments inside the call.
--
-- What is preserved:
--   * All code structure, indentation, blank lines.
--   * `assert(...)` used as a value, e.g. `local f = assert(io.open(p))`.
--     Only leading-position asserts (statements) are stripped.
--   * String literals (single, double, long-bracket).
--
-- Usage:
--   lua tools/strip.lua <file.lua>                       -- write to stdout
--   lua tools/strip.lua <file.lua> --outdir <dir>        -- write to <dir>/<basename>
--   lua tools/strip.lua <file.lua> --out <path>          -- write to exact path
--   lua tools/strip.lua <file1> <file2> --outdir <dir>   -- batch
--   lua tools/strip.lua <file> --keep-blanks             -- preserve blank lines
--
-- Reports raw vs stripped byte counts on stderr.

-- ---------------------------------------------------------------------------
-- Lexical helpers — operate on the raw source string with a cursor `i`.
-- Each helper returns the cursor positioned just past the consumed span.
-- ---------------------------------------------------------------------------

local function skipLongBracket(src, i, openSeq)
    -- Caller has already consumed `[<eq>[`. Find the matching `]<eq>]`.
    local closePat = "%]" .. openSeq .. "%]"
    local _, e = src:find(closePat, i)
    if e then return e + 1 end
    return #src + 1
end

local function skipShortString(src, i)
    -- Caller positioned at opening quote.
    local quote = src:sub(i, i)
    local j = i + 1
    local len = #src
    while j <= len do
        local c = src:sub(j, j)
        if c == "\\" then
            j = j + 2
        elseif c == quote then
            return j + 1
        elseif c == "\n" then
            -- Lua strings do not span raw newlines — bail.
            return j + 1
        else
            j = j + 1
        end
    end
    return len + 1
end

local function skipComment(src, i)
    -- Caller has matched `--` at positions [i, i+1].
    local eqOpen = src:match("^%[(=*)%[", i + 2)
    if eqOpen then
        return skipLongBracket(src, i + 4 + #eqOpen, eqOpen)
    end
    local eol = src:find("\n", i + 2, true)
    if eol then return eol end
    return #src + 1
end

-- ---------------------------------------------------------------------------
-- Find the matching `)` for an `assert(` call, accounting for nested parens,
-- strings, and comments inside the argument list.
-- ---------------------------------------------------------------------------

local function findCallEnd(src, openParenPos)
    local len = #src
    local depth = 1
    local i = openParenPos + 1
    while i <= len do
        local c = src:sub(i, i)
        if c == "(" then
            depth = depth + 1
            i = i + 1
        elseif c == ")" then
            depth = depth - 1
            if depth == 0 then return i end
            i = i + 1
        elseif c == "-" and src:sub(i + 1, i + 1) == "-" then
            i = skipComment(src, i)
        elseif c == "[" then
            local eqOpen = src:match("^%[(=*)%[", i)
            if eqOpen then
                i = skipLongBracket(src, i + 2 + #eqOpen, eqOpen)
            else
                i = i + 1
            end
        elseif c == '"' or c == "'" then
            i = skipShortString(src, i)
        else
            i = i + 1
        end
    end
    return nil   -- unterminated; caller will fall back
end

-- ---------------------------------------------------------------------------
-- Main strip pass.
-- Walks the source as a token stream, copying everything to `out` except:
--   * comments (always removed)
--   * statement-form `assert(...)` calls (removed including the call's span)
-- A statement-form assert is recognised by its position: only when it
-- appears at the start of a line (preceded only by spaces/tabs since the
-- last newline). This protects `local f = assert(...)` and similar uses.
-- ---------------------------------------------------------------------------

local function stripSource(src)
    local out = {}
    local len = #src
    local i = 1
    local lineStart = true   -- true when no non-space chars seen since \n

    while i <= len do
        local c = src:sub(i, i)

        if c == "\n" then
            out[#out + 1] = c
            i = i + 1
            lineStart = true

        elseif c == " " or c == "\t" then
            out[#out + 1] = c
            i = i + 1
            -- still at line start

        elseif c == "-" and src:sub(i + 1, i + 1) == "-" then
            -- Comment: drop entirely. If it ends mid-line (long comment that
            -- finishes on the same line), the next char keeps lineStart as-is
            -- — but to be safe we set lineStart = false only if more code
            -- follows on the same line; we treat as unchanged here.
            local nextI = skipComment(src, i)
            -- A trailing newline of a single-line comment is consumed by
            -- skipComment (it returns the index at the \n). Preserve it.
            i = nextI
            -- lineStart unchanged — comment is invisible to the layout

        elseif c == '"' or c == "'" then
            local nextI = skipShortString(src, i)
            out[#out + 1] = src:sub(i, nextI - 1)
            i = nextI
            lineStart = false

        elseif c == "[" then
            local eqOpen = src:match("^%[(=*)%[", i)
            if eqOpen then
                local nextI = skipLongBracket(src, i + 2 + #eqOpen, eqOpen)
                out[#out + 1] = src:sub(i, nextI - 1)
                i = nextI
            else
                out[#out + 1] = c
                i = i + 1
            end
            lineStart = false

        elseif lineStart and c == "a" and src:sub(i, i + 6) == "assert(" then
            -- Statement-form assert. Skip the entire call.
            local closeParen = findCallEnd(src, i + 6)
            if not closeParen then
                -- Malformed; leave the source alone for this region.
                out[#out + 1] = c
                i = i + 1
                lineStart = false
            else
                -- Consume any trailing semicolon and trailing whitespace
                -- through the next newline (so we don't leave a blank
                -- indent residue).
                local j = closeParen + 1
                if src:sub(j, j) == ";" then j = j + 1 end
                while j <= len and (src:sub(j, j) == " " or src:sub(j, j) == "\t") do
                    j = j + 1
                end
                if src:sub(j, j) == "\n" then
                    -- Also drop the leading whitespace we already emitted
                    -- on this line (between lineStart and i).
                    -- Walk back through `out` to remove trailing spaces/tabs
                    -- since the last newline.
                    local k = #out
                    while k > 0 and (out[k] == " " or out[k] == "\t") do
                        out[k] = nil
                        k = k - 1
                    end
                    -- Skip the newline so we collapse the whole line.
                    i = j + 1
                else
                    -- Mid-line follow-on (rare); drop just the call.
                    i = j
                end
                -- lineStart stays true if we collapsed the whole line,
                -- false otherwise.
                lineStart = (i == 1) or src:sub(i - 1, i - 1) == "\n"
            end

        else
            out[#out + 1] = c
            i = i + 1
            lineStart = false
        end
    end

    return table.concat(out)
end

-- ---------------------------------------------------------------------------
-- Blank-line collapse pass.
-- After stripping comments and statement asserts, the source is left with
-- runs of blank/whitespace-only lines where comment blocks used to be. This
-- is dead weight on device. Collapse:
--   * leading blank lines (file head)  -> dropped entirely
--   * runs of 2+ blank lines (mid-file) -> a single blank line
--   * trailing blank lines              -> a single trailing newline
-- A "blank line" is a line whose contents are empty or whitespace only.
-- ---------------------------------------------------------------------------

local function collapseBlankLines(src)
    local lines = {}
    -- Split preserving a trailing empty line if the source ends with \n.
    local pos = 1
    local len = #src
    while pos <= len do
        local nl = src:find("\n", pos, true)
        if nl then
            lines[#lines + 1] = src:sub(pos, nl - 1)
            pos = nl + 1
        else
            lines[#lines + 1] = src:sub(pos)
            pos = len + 1
        end
    end
    -- If source ended with \n, add a trailing empty line so join works out.
    if src:sub(-1) == "\n" then lines[#lines + 1] = "" end

    local function isBlank(s) return s:match("^%s*$") ~= nil end

    -- Drop leading blank lines.
    local first = 1
    while first <= #lines and isBlank(lines[first]) do
        first = first + 1
    end

    local out = {}
    local prevBlank = false
    for k = first, #lines do
        local line = lines[k]
        local blank = isBlank(line)
        if blank then
            if not prevBlank then
                out[#out + 1] = ""
            end
            prevBlank = true
        else
            out[#out + 1] = line
            prevBlank = false
        end
    end

    -- Drop trailing blank lines, then re-add exactly one trailing newline.
    while #out > 0 and isBlank(out[#out]) do
        out[#out] = nil
    end
    return table.concat(out, "\n") .. "\n"
end

-- ---------------------------------------------------------------------------
-- CLI
-- ---------------------------------------------------------------------------

local function basename(path)
    return path:match("([^/\\]+)$") or path
end

local function readFile(path)
    local f, err = io.open(path, "rb")
    if not f then return nil, err end
    local s = f:read("*a")
    f:close()
    return s
end

local function writeFile(path, content)
    local f, err = io.open(path, "wb")
    if not f then return nil, err end
    f:write(content)
    f:close()
    return true
end

local function usage()
    io.stderr:write([[
Usage:
  lua tools/strip.lua <file.lua>                     -- print to stdout
  lua tools/strip.lua <file.lua> --out <path>        -- write to <path>
  lua tools/strip.lua <file.lua> [...] --outdir <d>  -- write each as <d>/<basename>
  lua tools/strip.lua <file> --keep-blanks           -- preserve blank-line layout

Strips Lua comments and statement-form `assert(...)` calls.
Preserves formatting, strings, and value-returning asserts
(e.g. `local f = assert(io.open(p))`).
By default, also collapses runs of blank lines to a single blank.
]])
    os.exit(1)
end

local args = arg or {}
local files = {}
local outDir, outPath
local keepBlanks = false
local i = 1
while i <= #args do
    local a = args[i]
    if a == "--outdir" then
        outDir = args[i + 1]; i = i + 2
    elseif a == "--out" then
        outPath = args[i + 1]; i = i + 2
    elseif a == "--keep-blanks" then
        keepBlanks = true; i = i + 1
    elseif a:sub(1, 1) == "-" then
        io.stderr:write("Unknown flag: " .. a .. "\n")
        usage()
    else
        files[#files + 1] = a
        i = i + 1
    end
end

if #files == 0 then usage() end
if outPath and #files ~= 1 then
    io.stderr:write("--out requires exactly one input file\n")
    usage()
end

io.stderr:write(string.format("%-50s %10s %10s %10s\n",
    "FILE", "RAW", "STRIPPED", "DELTA"))
io.stderr:write(string.rep("-", 84) .. "\n")

local totalRaw, totalOut = 0, 0
for _, path in ipairs(files) do
    local src, err = readFile(path)
    if not src then
        io.stderr:write(("ERROR: cannot read %s (%s)\n"):format(path, err))
        os.exit(2)
    end
    local stripped = stripSource(src)
    if not keepBlanks then
        stripped = collapseBlankLines(stripped)
    end
    local rawLen, outLen = #src, #stripped
    totalRaw = totalRaw + rawLen
    totalOut = totalOut + outLen
    local pct = rawLen > 0 and ((rawLen - outLen) / rawLen * 100) or 0

    local display = #path > 50 and ("..." .. path:sub(-47)) or path
    io.stderr:write(string.format("%-50s %10d %10d  %8.1f%%\n",
        display, rawLen, outLen, pct))

    if outPath then
        local ok, werr = writeFile(outPath, stripped)
        if not ok then
            io.stderr:write(("ERROR: cannot write %s (%s)\n"):format(outPath, werr))
            os.exit(2)
        end
    elseif outDir then
        local target = outDir .. "/" .. basename(path)
        local ok, werr = writeFile(target, stripped)
        if not ok then
            io.stderr:write(("ERROR: cannot write %s (%s)\n"):format(target, werr))
            os.exit(2)
        end
    else
        io.write(stripped)
    end
end

if #files > 1 then
    io.stderr:write(string.rep("-", 84) .. "\n")
    local pct = totalRaw > 0 and ((totalRaw - totalOut) / totalRaw * 100) or 0
    io.stderr:write(string.format("%-50s %10d %10d  %8.1f%%\n",
        "TOTAL", totalRaw, totalOut, pct))
end
