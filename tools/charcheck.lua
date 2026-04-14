-- tools/charcheck.lua
-- Validates that a Lua file fits within the Grid controller's 880-character
-- limit (minified). Reports raw size, minified size, and pass/fail status.
--
-- Usage:
--   lua tools/charcheck.lua <file.lua>                  -- check one file
--   lua tools/charcheck.lua <file1.lua> <file2.lua> ... -- check multiple
--   lua tools/charcheck.lua sequencer/*.lua              -- glob works too
--   lua tools/charcheck.lua --limit 500 <file.lua>      -- custom limit

local GRID_CHAR_LIMIT = 880

-- -----------------------------------------------------------------------
-- Minimal Lua minifier (comment + whitespace removal, no AST rewriting)
-- -----------------------------------------------------------------------

local function minifyLua(source)
    local out = {}
    local i = 1
    local len = #source

    while i <= len do
        local c = source:sub(i, i)

        -- Long string / long comment detection
        if c == "-" and source:sub(i, i + 1) == "--" then
            -- Check for long comment  --[=*[
            local eqStart = source:match("^%[(=*)%[", i + 2)
            if eqStart then
                local closePattern = "%]" .. eqStart .. "%]"
                local _, closeEnd = source:find(closePattern, i + 4 + #eqStart)
                if closeEnd then
                    i = closeEnd + 1
                else
                    -- unterminated long comment, skip to end
                    i = len + 1
                end
            else
                -- Single-line comment: skip to end of line
                local eol = source:find("\n", i + 2)
                if eol then
                    i = eol + 1
                else
                    i = len + 1
                end
            end
        elseif c == "[" then
            -- Long string literal [=*[
            local eqStart = source:match("^%[(=*)%[", i)
            if eqStart then
                local closePattern = "%]" .. eqStart .. "%]"
                local _, closeEnd = source:find(closePattern, i + 2 + #eqStart)
                if closeEnd then
                    out[#out + 1] = source:sub(i, closeEnd)
                    i = closeEnd + 1
                else
                    out[#out + 1] = source:sub(i)
                    i = len + 1
                end
            else
                out[#out + 1] = c
                i = i + 1
            end
        elseif c == '"' or c == "'" then
            -- String literal: copy verbatim, respecting escapes
            local quote = c
            local j = i + 1
            while j <= len do
                local sc = source:sub(j, j)
                if sc == "\\" then
                    j = j + 2 -- skip escaped character
                elseif sc == quote then
                    j = j + 1
                    break
                else
                    j = j + 1
                end
            end
            out[#out + 1] = source:sub(i, j - 1)
            i = j
        elseif c == "\n" or c == "\r" then
            -- Replace newline with single space (to avoid merging tokens)
            out[#out + 1] = " "
            i = i + 1
            -- Skip \r\n pairs
            if c == "\r" and i <= len and source:sub(i, i) == "\n" then
                i = i + 1
            end
        elseif c == " " or c == "\t" then
            -- Collapse runs of whitespace to a single space
            while i <= len and (source:sub(i, i) == " " or source:sub(i, i) == "\t") do
                i = i + 1
            end
            out[#out + 1] = " "
        else
            out[#out + 1] = c
            i = i + 1
        end
    end

    local result = table.concat(out)

    -- Trim leading/trailing whitespace
    result = result:match("^%s*(.-)%s*$")

    -- Collapse multiple spaces into one
    result = result:gsub("  +", " ")

    -- Remove spaces around operators and punctuation where safe
    -- (conservative — only removes spaces adjacent to non-alphanumeric chars)
    result = result:gsub(" *([%(%)%{%}%[%]%;%,%.%=%(%)%+%-%*%/%^%%#<>~]) *", "%1")

    -- Restore space where needed: after keywords followed by ( or identifier
    -- e.g. "function(" needs to stay, but "return x" needs the space
    for _, kw in ipairs({
        "and", "break", "do", "else", "elseif", "end", "false", "for",
        "function", "if", "in", "local", "nil", "not", "or", "repeat",
        "return", "then", "true", "until", "while"
    }) do
        -- Ensure space after keyword when followed by an alphanumeric/underscore
        result = result:gsub("(" .. kw .. ")([%w_])", "%1 %2")
    end

    return result
end

-- -----------------------------------------------------------------------
-- CLI
-- -----------------------------------------------------------------------

local args = { ... }
if #args == 0 then
    args = arg
end

local limit = GRID_CHAR_LIMIT
local files = {}

local i = 1
while i <= #args do
    if args[i] == "--limit" then
        i = i + 1
        limit = tonumber(args[i])
        assert(limit and limit > 0, "charcheck: --limit must be a positive number")
    elseif args[i]:sub(1, 1) ~= "-" then
        files[#files + 1] = args[i]
    end
    i = i + 1
end

if #files == 0 then
    print("Usage: lua tools/charcheck.lua [--limit N] <file.lua> [file2.lua ...]")
    print("Default limit: " .. GRID_CHAR_LIMIT .. " characters (Grid controller)")
    os.exit(1)
end

local allPass = true
local totalRaw = 0
local totalMinified = 0

print(string.format("%-40s %8s %8s %8s  %s", "FILE", "RAW", "MINIFIED", "LIMIT", "STATUS"))
print(string.rep("-", 80))

for _, filePath in ipairs(files) do
    local file = io.open(filePath, "r")
    if not file then
        print(string.format("%-40s  -- FILE NOT FOUND --", filePath))
        allPass = false
    else
        local source = file:read("*a")
        file:close()

        local rawLen = #source
        local minified = minifyLua(source)
        local minLen = #minified

        totalRaw = totalRaw + rawLen
        totalMinified = totalMinified + minLen

        local status = "PASS"
        if minLen > limit then
            status = "FAIL (+" .. (minLen - limit) .. ")"
            allPass = false
        end

        -- Shorten long paths for display
        local displayPath = filePath
        if #displayPath > 40 then
            displayPath = "..." .. displayPath:sub(-37)
        end

        print(string.format("%-40s %8d %8d %8d  %s", displayPath, rawLen, minLen, limit, status))
    end
end

print(string.rep("-", 80))
print(string.format("%-40s %8d %8d", "TOTAL", totalRaw, totalMinified))

if allPass then
    print("\nAll files PASS the " .. limit .. "-character limit.")
else
    local chunks = math.ceil(totalMinified / limit)
    print("\nSome files FAIL. Total minified would need at least " .. chunks .. " chunks of " .. limit .. " chars.")
end

os.exit(allPass and 0 or 1)
