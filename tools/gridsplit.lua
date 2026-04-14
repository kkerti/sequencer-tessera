-- tools/gridsplit.lua
-- Splits Lua module files into <=880 character (minified) chunks for Grid.
--
-- Pipeline per source file:
--   1. Read source
--   2. Strip assert() calls (dev-only guards, not needed on device)
--   3. Parse into blocks: preamble, local functions, public functions, return
--   4. Minify each block
--   5. Group blocks into chunks that fit the character limit
--   6. Emit:  root file  -> creates module table, requires all chunks, returns it
--            chunk files -> require root, attach functions to the module table
--
-- Naming scheme:
--   sequencer/step.lua  ->  grid/seq_step.lua, grid/seq_step_1.lua, ...
--   utils.lua           ->  grid/seq_utils.lua, grid/seq_utils_1.lua, ...
--
-- Usage:
--   lua tools/gridsplit.lua                         -- split all engine files
--   lua tools/gridsplit.lua sequencer/step.lua      -- split one file
--   lua tools/gridsplit.lua --outdir build          -- custom output dir
--   lua tools/gridsplit.lua --limit 800             -- custom char limit
--   lua tools/gridsplit.lua --dry                   -- dry run, report only
--   lua tools/gridsplit.lua --keep-asserts          -- don't strip asserts

local GRID_CHAR_LIMIT = 880
local DEFAULT_OUTDIR = "grid"

-- -----------------------------------------------------------------------
-- Minifier
-- -----------------------------------------------------------------------

local function minifyLua(source)
    local out = {}
    local i = 1
    local len = #source

    while i <= len do
        local c = source:sub(i, i)

        -- Long comment  --[=*[
        if c == "-" and source:sub(i, i + 1) == "--" then
            local eqStart = source:match("^%[(=*)%[", i + 2)
            if eqStart then
                local closePattern = "%]" .. eqStart .. "%]"
                local _, closeEnd = source:find(closePattern, i + 4 + #eqStart)
                i = closeEnd and (closeEnd + 1) or (len + 1)
            else
                local eol = source:find("\n", i + 2)
                i = eol and (eol + 1) or (len + 1)
            end

        -- Long string [=*[
        elseif c == "[" then
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

        -- Quoted strings
        elseif c == '"' or c == "'" then
            local quote = c
            local j = i + 1
            while j <= len do
                local sc = source:sub(j, j)
                if sc == "\\" then j = j + 2
                elseif sc == quote then j = j + 1; break
                else j = j + 1 end
            end
            out[#out + 1] = source:sub(i, j - 1)
            i = j

        -- Newlines -> space
        elseif c == "\n" or c == "\r" then
            out[#out + 1] = " "
            i = i + 1
            if c == "\r" and i <= len and source:sub(i, i) == "\n" then i = i + 1 end

        -- Whitespace collapse
        elseif c == " " or c == "\t" then
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
    result = result:match("^%s*(.-)%s*$") or ""
    result = result:gsub("  +", " ")
    result = result:gsub(" *([%(%)%{%}%[%]%;%,%.%=%+%-%*%/%^%%#<>~:]) *", "%1")

    -- Restore mandatory spaces after/before Lua keywords
    local keywords = {
        "and","break","do","else","elseif","end","false","for",
        "function","goto","if","in","local","nil","not","or",
        "repeat","return","then","true","until","while"
    }
    for _, kw in ipairs(keywords) do
        result = result:gsub("(" .. kw .. ")([%w_])", "%1 %2")
        result = result:gsub("([%w_])(" .. kw .. "%f[%W])", "%1 %2")
    end

    return result
end

-- -----------------------------------------------------------------------
-- Assert stripper
-- -----------------------------------------------------------------------

-- Removes lines that are standalone `assert(...)` calls.
-- Also handles multi-line asserts (assert that spans continuation lines).
local function stripAsserts(source)
    local lines = {}
    for line in (source .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end

    local out = {}
    local i = 1

    while i <= #lines do
        local trimmed = lines[i]:match("^%s*(.-)%s*$")

        -- Match standalone assert( at start of line
        if trimmed:match("^assert%(") then
            -- Count parens to handle multi-line asserts
            local full = lines[i]
            local depth = 0
            for ch in full:gmatch(".") do
                if ch == "(" then depth = depth + 1 end
                if ch == ")" then depth = depth - 1 end
            end

            while depth > 0 and i < #lines do
                i = i + 1
                full = full .. "\n" .. lines[i]
                for ch in lines[i]:gmatch(".") do
                    if ch == "(" then depth = depth + 1 end
                    if ch == ")" then depth = depth - 1 end
                end
            end

            -- Skip this assert entirely
            i = i + 1
        else
            out[#out + 1] = lines[i]
            i = i + 1
        end
    end

    return table.concat(out, "\n")
end

-- -----------------------------------------------------------------------
-- Block parser — extracts top-level function blocks from Lua source
-- -----------------------------------------------------------------------

local function parseBlocks(source)
    local blocks = {}
    local lines = {}
    for line in (source .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end

    local currentType = "preamble"
    local currentText = {}
    local currentName = nil
    local nestDepth = 0
    local inPreamble = true

    local function flushBlock()
        if #currentText > 0 then
            local text = table.concat(currentText, "\n")
            if text:match("%S") then
                blocks[#blocks + 1] = {
                    type = currentType,
                    text = text,
                    name = currentName,
                }
            end
        end
        currentText = {}
        currentName = nil
    end

    -- Count block-open and block-close keywords on a line.
    -- Strips comments and strings first for accuracy.
    local function countNesting(line)
        -- Strip end-of-line comments
        local s = line:gsub("%-%-.*$", "")
        -- Strip string literals (simple heuristic)
        s = s:gsub('"[^"]*"', '""')
        s = s:gsub("'[^']*'", "''")

        local opens = 0
        local closes = 0

        -- Count block openers. Lua grammar: function, if (but not elseif),
        -- for, while, repeat each open a block. `do` by itself also opens,
        -- but `for ... do` and `while ... do` already count through for/while.
        -- We handle by counting `do` but NOT counting for/while's implicit do.
        -- Actually, both `for` and `while` require a `do` — the do IS the
        -- block opener. So count: function, if, repeat as openers, and `do`
        -- separately (covers for..do, while..do, and bare do..end).

        -- function
        for _ in s:gmatch("%f[%w_]function%f[^%w_]") do opens = opens + 1 end
        -- if (but not elseif)
        for _ in s:gmatch("%f[%w_]if%f[^%w_]") do opens = opens + 1 end
        opens = opens - select(2, s:gsub("%f[%w_]elseif%f[^%w_]", ""))
        -- do (covers for..do, while..do, standalone do)
        for _ in s:gmatch("%f[%w_]do%f[^%w_]") do opens = opens + 1 end
        -- repeat
        for _ in s:gmatch("%f[%w_]repeat%f[^%w_]") do opens = opens + 1 end

        -- Closers
        for _ in s:gmatch("%f[%w_]end%f[^%w_]") do closes = closes + 1 end
        for _ in s:gmatch("%f[%w_]until%f[^%w_]") do closes = closes + 1 end

        return opens, closes
    end

    for _, line in ipairs(lines) do
        local trimmed = line:match("^%s*(.-)%s*$")

        -- Detect top-level function declarations
        local moduleFuncName = trimmed:match("^function%s+(%S+)%s*%(")
        local localFuncName = trimmed:match("^local%s+function%s+(%S+)%s*%(")

        if (moduleFuncName or localFuncName) and nestDepth == 0 then
            flushBlock()
            inPreamble = false

            currentType = moduleFuncName and "function" or "local_function"
            currentName = moduleFuncName or localFuncName
            currentText[#currentText + 1] = line

            local opens, closes = countNesting(trimmed)
            nestDepth = opens - closes
            if nestDepth <= 0 then
                nestDepth = 0
                flushBlock()
                currentType = "other"
            end

        elseif nestDepth > 0 then
            currentText[#currentText + 1] = line
            local opens, closes = countNesting(trimmed)
            nestDepth = nestDepth + opens - closes
            if nestDepth <= 0 then
                nestDepth = 0
                flushBlock()
                currentType = "other"
            end

        elseif trimmed:match("^return%s") or trimmed == "return" then
            flushBlock()
            currentType = "return"
            currentText[#currentText + 1] = line
            flushBlock()
            currentType = "other"

        else
            if inPreamble then currentType = "preamble" end
            currentText[#currentText + 1] = line
        end
    end

    flushBlock()
    return blocks
end

-- -----------------------------------------------------------------------
-- Path helpers
-- -----------------------------------------------------------------------

-- "sequencer/step.lua" -> "seq_step"
-- "utils.lua"          -> "seq_utils"
local function sourceToGridPrefix(sourcePath)
    local base = sourcePath:match("([^/]+)%.lua$") or
                 sourcePath:gsub("%.lua$", ""):gsub("[/\\]", "_")
    return "seq_" .. base
end

-- Remap a require path to grid prefix:
-- "sequencer/step" -> "seq_step"
-- "utils"          -> "seq_utils"
local function requirePathToGridPrefix(reqPath)
    return sourceToGridPrefix(reqPath .. ".lua")
end

-- -----------------------------------------------------------------------
-- Chunk builder
-- -----------------------------------------------------------------------

local function buildGridFiles(sourcePath, source, limit, outdir, stripAssertsFlag)
    local prefix = sourceToGridPrefix(sourcePath)
    local result = { files = {}, warnings = {} }

    -- Phase 1: strip asserts
    if stripAssertsFlag then
        source = stripAsserts(source)
    end

    -- Phase 2: parse into blocks
    local blocks = parseBlocks(source)

    -- Classify blocks
    local preambleBlocks = {}
    local localFuncBlocks = {}
    local publicFuncBlocks = {}
    local moduleName = nil

    for _, block in ipairs(blocks) do
        if block.type == "preamble" then
            preambleBlocks[#preambleBlocks + 1] = block
            if not moduleName then
                for line in block.text:gmatch("[^\n]+") do
                    local name = line:match("^local%s+(%u%w+)%s*=%s*{")
                    if name then moduleName = name; break end
                end
            end
        elseif block.type == "local_function" then
            localFuncBlocks[#localFuncBlocks + 1] = block
        elseif block.type == "function" then
            publicFuncBlocks[#publicFuncBlocks + 1] = block
        end
    end

    moduleName = moduleName or "M"

    -- Extract preamble info
    local preambleText = ""
    for _, b in ipairs(preambleBlocks) do
        preambleText = preambleText .. "\n" .. b.text
    end

    local requires = {}
    local localVars = {}

    for line in preambleText:gmatch("[^\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        local varName, modPath = trimmed:match('^local%s+(%w+)%s*=%s*require%("([^"]+)"%)')
        if not varName then
            varName, modPath = trimmed:match("^local%s+(%w+)%s*=%s*require%('([^']+)'%)")
        end
        if varName then
            requires[#requires + 1] = { var = varName, path = modPath }
        elseif trimmed:match("^local%s+") and
               not trimmed:match("^local%s+%u%w*%s*=%s*{") and
               not trimmed:match("^%-%-") then
            localVars[#localVars + 1] = trimmed
        end
    end

    -- Phase 3: Build the chunk preamble that each chunk file will start with
    local chunkPreambleLines = {}
    chunkPreambleLines[#chunkPreambleLines + 1] = string.format(
        'local %s=require("%s")', moduleName, prefix)
    for _, req in ipairs(requires) do
        chunkPreambleLines[#chunkPreambleLines + 1] = string.format(
            'local %s=require("%s")', req.var, requirePathToGridPrefix(req.path))
    end

    -- Phase 4: Decide how to handle local functions.
    -- Strategy A: include in each chunk (if they're small enough)
    -- Strategy B: promote to module table under _ prefix, put in root or separate chunks

    local localFuncNames = {}
    for _, lfb in ipairs(localFuncBlocks) do
        if lfb.name then localFuncNames[#localFuncNames + 1] = lfb.name end
    end

    -- Calculate size if we include local funcs + local vars in each chunk
    local localFuncText = ""
    for _, lfb in ipairs(localFuncBlocks) do
        localFuncText = localFuncText .. "\n" .. lfb.text
    end
    local localVarsText = ""
    for _, lv in ipairs(localVars) do
        localVarsText = localVarsText .. "\n" .. lv
    end

    local chunkPreambleBase = table.concat(chunkPreambleLines, "\n")
    local chunkPreambleFull = chunkPreambleBase .. localVarsText .. localFuncText
    local chunkPreambleFullMin = #minifyLua(chunkPreambleFull)

    local promoteLocalFuncs = false

    if chunkPreambleFullMin > limit * 0.6 then
        -- Local functions are too expensive to duplicate in every chunk.
        -- Promote them to the module table.
        promoteLocalFuncs = true

        -- Rewrite public function bodies: replace local func calls with module calls
        for _, pfb in ipairs(publicFuncBlocks) do
            for _, fname in ipairs(localFuncNames) do
                -- Replace standalone calls (not already prefixed with a dot)
                pfb.text = pfb.text:gsub(
                    "([^%.%w_])" .. fname .. "(%s*%()",
                    "%1" .. moduleName .. "._" .. fname .. "%2")
                pfb.text = pfb.text:gsub(
                    "^" .. fname .. "(%s*%()",
                    moduleName .. "._" .. fname .. "%1")
            end
        end

        -- Also rewrite local function bodies: they might call each other
        for _, lfb in ipairs(localFuncBlocks) do
            for _, fname in ipairs(localFuncNames) do
                if fname ~= lfb.name then
                    lfb.text = lfb.text:gsub(
                        "([^%.%w_])" .. fname .. "(%s*%()",
                        "%1" .. moduleName .. "._" .. fname .. "%2")
                    lfb.text = lfb.text:gsub(
                        "^" .. fname .. "(%s*%()",
                        moduleName .. "._" .. fname .. "%1")
                end
            end
        end
    end

    -- Phase 5: Build chunk preamble (final version)
    local chunkPreamble
    if promoteLocalFuncs then
        chunkPreamble = chunkPreambleBase .. localVarsText
    else
        chunkPreamble = chunkPreambleFull
    end

    -- Phase 6: Group public functions into chunks
    local allFuncBlocks = {}
    for _, b in ipairs(publicFuncBlocks) do
        allFuncBlocks[#allFuncBlocks + 1] = b
    end

    -- Group by minified size
    local chunks = {}
    local curChunk = {}
    local curSize = #minifyLua(chunkPreamble)

    for _, block in ipairs(allFuncBlocks) do
        local blockMin = #minifyLua(block.text)

        if curSize + blockMin + 1 > limit and #curChunk > 0 then
            chunks[#chunks + 1] = curChunk
            curChunk = {}
            curSize = #minifyLua(chunkPreamble)
        end

        curChunk[#curChunk + 1] = block
        curSize = curSize + blockMin + 1
    end

    if #curChunk > 0 then
        chunks[#chunks + 1] = curChunk
    end

    -- Phase 7: Handle promoted local functions — they become chunks too
    local localFuncChunks = {}
    if promoteLocalFuncs then
        local lfCurChunk = {}
        local lfCurSize = #minifyLua(chunkPreambleBase .. localVarsText)

        for _, lfb in ipairs(localFuncBlocks) do
            -- Convert: local function name(  ->  function Module._name(
            local converted = lfb.text:gsub(
                "^local%s+function%s+(%S+)",
                "function " .. moduleName .. "._" .. "%1")
            local convBlock = { text = converted, name = moduleName .. "._" .. (lfb.name or "?") }
            local blockMin = #minifyLua(converted)

            if lfCurSize + blockMin + 1 > limit and #lfCurChunk > 0 then
                localFuncChunks[#localFuncChunks + 1] = lfCurChunk
                lfCurChunk = {}
                lfCurSize = #minifyLua(chunkPreambleBase .. localVarsText)
            end

            lfCurChunk[#lfCurChunk + 1] = convBlock
            lfCurSize = lfCurSize + blockMin + 1
        end

        if #lfCurChunk > 0 then
            localFuncChunks[#localFuncChunks + 1] = lfCurChunk
        end
    end

    -- Phase 8: Emit files

    -- Total chunk count = local func chunks + public func chunks
    local totalChunks = #localFuncChunks + #chunks

    -- Root file: create module table + local vars (if small) + require chunks
    local rootLines = {}
    rootLines[#rootLines + 1] = string.format("local %s={}", moduleName)

    -- If local vars are small, include in root. Otherwise they go in chunks.
    if not promoteLocalFuncs then
        -- Local funcs are in each chunk already, but vars should be in root
        -- Actually: if not promoting, local vars + funcs are in chunk preamble
        -- Root just creates table + requires chunks
    else
        -- Include local vars in root only if they're small
        for _, lv in ipairs(localVars) do
            rootLines[#rootLines + 1] = lv
        end
    end

    -- Require all chunks (local func chunks first, then public func chunks)
    for i = 1, totalChunks do
        rootLines[#rootLines + 1] = string.format('require("%s_%d")', prefix, i)
    end

    rootLines[#rootLines + 1] = string.format("return %s", moduleName)

    local rootContent = table.concat(rootLines, "\n") .. "\n"
    local rootMinSize = #minifyLua(rootContent)

    result.files[#result.files + 1] = {
        path = outdir .. "/" .. prefix .. ".lua",
        content = rootContent,
        minSize = rootMinSize,
        isRoot = true,
        functions = {},
    }

    if rootMinSize > limit then
        result.warnings[#result.warnings + 1] = string.format(
            "Root file %s/%s.lua is %d chars (limit %d)",
            outdir, prefix, rootMinSize, limit)
    end

    -- Emit local function chunks
    local chunkIndex = 0
    for ci, chunk in ipairs(localFuncChunks) do
        chunkIndex = chunkIndex + 1
        local chunkLines = {}

        -- Preamble: require module + dependencies
        chunkLines[#chunkLines + 1] = chunkPreambleBase
        if #localVars > 0 then
            chunkLines[#chunkLines + 1] = localVarsText
        end

        local funcNames = {}
        for _, block in ipairs(chunk) do
            chunkLines[#chunkLines + 1] = block.text
            funcNames[#funcNames + 1] = block.name or "?"
        end

        local content = table.concat(chunkLines, "\n") .. "\n"
        local minSize = #minifyLua(content)

        result.files[#result.files + 1] = {
            path = string.format("%s/%s_%d.lua", outdir, prefix, chunkIndex),
            content = content,
            minSize = minSize,
            isRoot = false,
            functions = funcNames,
        }

        if minSize > limit then
            for _, fn in ipairs(funcNames) do
                result.warnings[#result.warnings + 1] = string.format(
                    "Chunk %d (%s) is %d chars (limit %d) — function may need manual split",
                    chunkIndex, fn, minSize, limit)
            end
        end
    end

    -- Emit public function chunks
    for ci, chunk in ipairs(chunks) do
        chunkIndex = chunkIndex + 1
        local chunkLines = {}

        chunkLines[#chunkLines + 1] = chunkPreamble

        -- If NOT promoting, include local functions in the chunk
        if not promoteLocalFuncs and localFuncText ~= "" then
            chunkLines[#chunkLines + 1] = localFuncText
        end

        local funcNames = {}
        for _, block in ipairs(chunk) do
            chunkLines[#chunkLines + 1] = block.text
            funcNames[#funcNames + 1] = block.name or "?"
        end

        local content = table.concat(chunkLines, "\n") .. "\n"
        local minSize = #minifyLua(content)

        result.files[#result.files + 1] = {
            path = string.format("%s/%s_%d.lua", outdir, prefix, chunkIndex),
            content = content,
            minSize = minSize,
            isRoot = false,
            functions = funcNames,
        }

        if minSize > limit then
            for _, fn in ipairs(funcNames) do
                result.warnings[#result.warnings + 1] = string.format(
                    "Chunk %d (%s) is %d chars (limit %d) — function may need manual split",
                    chunkIndex, fn, minSize, limit)
            end
        end
    end

    -- Stats
    result.publicFuncCount = #publicFuncBlocks
    result.localFuncCount = #localFuncBlocks
    result.promoteLocalFuncs = promoteLocalFuncs

    return result
end

-- -----------------------------------------------------------------------
-- CLI
-- -----------------------------------------------------------------------

local args = arg or { ... }
local limit = GRID_CHAR_LIMIT
local outdir = DEFAULT_OUTDIR
local dryRun = false
local keepAsserts = false
local sourceFiles = {}

local DEFAULT_SOURCES = {
    "utils.lua",
    "sequencer/step.lua",
    "sequencer/pattern.lua",
    "sequencer/performance.lua",
    "sequencer/mathops.lua",
    "sequencer/track.lua",
    "sequencer/engine.lua",
    "sequencer/snapshot.lua",
    "sequencer/scene.lua",
}

local i = 1
while i <= #args do
    if args[i] == "--limit" then
        i = i + 1; limit = tonumber(args[i])
    elseif args[i] == "--outdir" then
        i = i + 1; outdir = args[i]
    elseif args[i] == "--dry" then
        dryRun = true
    elseif args[i] == "--keep-asserts" then
        keepAsserts = true
    elseif args[i]:sub(1, 1) ~= "-" then
        sourceFiles[#sourceFiles + 1] = args[i]
    end
    i = i + 1
end

if #sourceFiles == 0 then sourceFiles = DEFAULT_SOURCES end

if not dryRun then os.execute("mkdir -p " .. outdir) end

print(string.format("Grid Split — limit: %d chars, output: %s/, asserts: %s",
    limit, outdir, keepAsserts and "keep" or "strip"))
print(string.rep("=", 80))

local totalFiles = 0
local totalMinified = 0
local allWarnings = {}

for _, sourcePath in ipairs(sourceFiles) do
    local file = io.open(sourcePath, "r")
    if not file then
        print("  SKIP: " .. sourcePath .. " (not found)"); goto continue
    end

    local source = file:read("*a")
    file:close()

    print(string.format("\n--- %s (%d bytes raw) ---", sourcePath, #source))

    local result = buildGridFiles(sourcePath, source, limit, outdir, not keepAsserts)

    print(string.format("  Parsed: %d public + %d local functions, local funcs %s",
        result.publicFuncCount, result.localFuncCount,
        result.promoteLocalFuncs and "PROMOTED to module table" or "inlined in chunks"))

    for _, w in ipairs(result.warnings) do
        print("  WARNING: " .. w)
        allWarnings[#allWarnings + 1] = sourcePath .. ": " .. w
    end

    for _, f in ipairs(result.files) do
        local label = f.isRoot and "ROOT " or "CHUNK"
        local status = f.minSize <= limit and "  OK" or "OVER"
        local funcList = #f.functions > 0
            and (" [" .. table.concat(f.functions, ", ") .. "]") or ""
        print(string.format("  %s %-35s %4d chars  %s%s",
            label, f.path, f.minSize, status, funcList))

        totalFiles = totalFiles + 1
        totalMinified = totalMinified + f.minSize

        if not dryRun then
            local out = io.open(f.path, "w")
            if out then out:write(f.content); out:close()
            else print("  ERROR: could not write " .. f.path) end
        end
    end

    ::continue::
end

print(string.rep("=", 80))
print(string.format("Total: %d files, %d chars minified", totalFiles, totalMinified))

if #allWarnings > 0 then
    print(string.format("\n%d warnings:", #allWarnings))
    for _, w in ipairs(allWarnings) do print("  - " .. w) end
end

if dryRun then print("\n(Dry run — no files written)") end
