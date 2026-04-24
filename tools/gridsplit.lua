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

local GRID_CHAR_LIMIT = 800
local DEFAULT_OUTDIR = "grid"

-- -----------------------------------------------------------------------
-- Minifier
-- -----------------------------------------------------------------------

-- Grid counts non-whitespace characters only — newlines, spaces, and tabs
-- on the device-stored script do not consume the per-file budget.
local function gridCharCount(source)
    return (#(source:gsub("[ \t\n\r]", "")))
end

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

        -- Count block openers that each require exactly one matching closer.
        -- Rules:
        --   function  -> closed by end
        --   if        -> closed by end  (elseif/else do NOT open new blocks)
        --   do        -> closed by end  (this covers for..do, while..do, bare do)
        --   repeat    -> closed by until
        -- NOTE: `for` and `while` themselves are NOT counted — their `do` is
        -- the actual block opener and is already counted above.

        -- function
        for _ in s:gmatch("%f[%w_]function%f[^%w_]") do opens = opens + 1 end
        -- if (but not elseif — match `if` only when preceded by a non-word char
        -- or start of string, and NOT part of `elseif`)
        -- Strategy: temporarily blank out `elseif` tokens, then count `if`.
        local sNoElseif = s:gsub("%f[%w_]elseif%f[^%w_]", "      ")
        for _ in sNoElseif:gmatch("%f[%w_]if%f[^%w_]") do opens = opens + 1 end
        -- do (covers for..do, while..do, standalone do — NOT for/while alone)
        for _ in s:gmatch("%f[%w_]do%f[^%w_]") do opens = opens + 1 end
        -- repeat (closed by until, not end)
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
    local moduleDataLines = {}     -- preamble lines that aren't handled elsewhere
                                   -- (e.g. `Utils.SCALES = {...}`, multi-line tables)
    local promotedLocalNames = {}  -- multi-line `local NAME = {...}` we promote to Module._NAME

    -- Group preamble into logical statements.  Statements that open `{` and
    -- don't close it on the same line continue across lines until braces match.
    local stmtBuf = {}
    local stmtDepth = 0
    local statements = {}
    local function flushStmt()
        if #stmtBuf > 0 then
            statements[#statements + 1] = table.concat(stmtBuf, "\n")
            stmtBuf = {}
        end
    end
    for line in preambleText:gmatch("[^\n]+") do
        stmtBuf[#stmtBuf + 1] = line
        for ch in line:gmatch(".") do
            if ch == "{" then stmtDepth = stmtDepth + 1 end
            if ch == "}" then stmtDepth = stmtDepth - 1 end
        end
        if stmtDepth <= 0 then
            stmtDepth = 0
            flushStmt()
        end
    end
    flushStmt()

    for _, stmt in ipairs(statements) do
        local firstLine = stmt:match("^[^\n]*") or stmt
        local trimmed = firstLine:match("^%s*(.-)%s*$")

        local varName, modPath = trimmed:match('^local%s+(%w+)%s*=%s*require%("([^"]+)"%)')
        if not varName then
            varName, modPath = trimmed:match("^local%s+(%w+)%s*=%s*require%('([^']+)'%)")
        end

        local isModuleDecl = trimmed:match("^local%s+" .. (moduleName or "X") .. "%s*=%s*{%s*}%s*$")
        local isComment    = trimmed:match("^%-%-") or trimmed == ""
        local isLocalReq   = varName ~= nil
        -- Any `local NAME = ...` (single-line OR multi-line) that isn't a require
        -- gets promoted to `Module._NAME = ...` so it survives chunk boundaries
        -- and is visible everywhere with no per-chunk duplication.
        local promoteName = stmt:match("^%s*local%s+([%w_]+)%s*=")

        if isLocalReq then
            requires[#requires + 1] = { var = varName, path = modPath }
        elseif isModuleDecl or isComment then
            -- skip — handled by root or irrelevant
        elseif promoteName then
            local promoted = stmt:gsub(
                "^(%s*)local%s+" .. promoteName,
                "%1" .. moduleName .. "._" .. promoteName, 1)
            moduleDataLines[#moduleDataLines + 1] = promoted
            promotedLocalNames[#promotedLocalNames + 1] = promoteName
        else
            -- Module-table data or arbitrary preamble code.
            moduleDataLines[#moduleDataLines + 1] = stmt
        end
    end

    local moduleDataText = table.concat(moduleDataLines, "\n")

    -- Rewrite references to promoted locals in all function bodies.
    local function rewritePromotedRefs(blocks)
        for _, b in ipairs(blocks) do
            for _, name in ipairs(promotedLocalNames) do
                b.text = b.text:gsub(
                    "([^%.%w_])" .. name .. "([^%w_])",
                    "%1" .. moduleName .. "._" .. name .. "%2")
            end
        end
    end
    rewritePromotedRefs(publicFuncBlocks)
    rewritePromotedRefs(localFuncBlocks)

    -- Phase 3: Build per-chunk preamble helpers.
    -- Only emit require lines for variables actually referenced in a chunk's code.

    -- Returns the require line for the module itself (always needed).
    local moduleRequireLine = string.format('local %s=require("%s")', moduleName, prefix)

    -- Map: varName -> require line string, for each preamble dependency.
    local requireLineFor = {}
    for _, req in ipairs(requires) do
        requireLineFor[req.var] = string.format(
            'local %s=require("%s")', req.var, requirePathToGridPrefix(req.path))
    end

    -- Build a preamble string for a list of function-body texts.
    -- Includes the module self-require, then only deps referenced in those texts.
    local function buildChunkPreamble(funcTexts, extraText)
        local combined = table.concat(funcTexts, "\n") .. (extraText or "")
        local lines = { moduleRequireLine }
        for _, req in ipairs(requires) do
            -- Check if the variable name appears as a word in the combined text
            if combined:find("%f[%w_]" .. req.var .. "%f[^%w_]") then
                lines[#lines + 1] = requireLineFor[req.var]
            end
        end
        return table.concat(lines, "\n")
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

    -- For the promote-local-funcs threshold check, use all requires (worst case).
    local allRequiresLine = moduleRequireLine
    for _, req in ipairs(requires) do
        allRequiresLine = allRequiresLine .. "\n" .. requireLineFor[req.var]
    end
    local chunkPreambleFull = allRequiresLine .. localVarsText .. localFuncText
    local chunkPreambleFullMin = gridCharCount(chunkPreambleFull)

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

    -- Phase 6: Group public functions into chunks.
    -- Use worst-case preamble size (all requires) for the bin-packing estimate;
    -- actual per-chunk preambles are built later with only used deps.
    local allFuncBlocks = {}
    for _, b in ipairs(publicFuncBlocks) do
        allFuncBlocks[#allFuncBlocks + 1] = b
    end

    local worstCasePreambleSize = gridCharCount(allRequiresLine .. localVarsText
        .. (promoteLocalFuncs and "" or localFuncText))

    local chunks = {}
    local curChunk = {}
    local curSize = worstCasePreambleSize

    for _, block in ipairs(allFuncBlocks) do
        local blockMin = gridCharCount(block.text)

        if curSize + blockMin + 1 > limit and #curChunk > 0 then
            chunks[#chunks + 1] = curChunk
            curChunk = {}
            curSize = worstCasePreambleSize
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
        local lfCurSize = gridCharCount(allRequiresLine .. localVarsText)

        for _, lfb in ipairs(localFuncBlocks) do
            -- Convert: local function name(  ->  function Module._name(
            local converted = lfb.text:gsub(
                "^local%s+function%s+(%S+)",
                "function " .. moduleName .. "._" .. "%1")
            local convBlock = { text = converted, name = moduleName .. "._" .. (lfb.name or "?") }
            local blockMin = gridCharCount(converted)

            if lfCurSize + blockMin + 1 > limit and #lfCurChunk > 0 then
                localFuncChunks[#localFuncChunks + 1] = lfCurChunk
                lfCurChunk = {}
                lfCurSize = gridCharCount(allRequiresLine .. localVarsText)
            end

            lfCurChunk[#lfCurChunk + 1] = convBlock
            lfCurSize = lfCurSize + blockMin + 1
        end

        if #lfCurChunk > 0 then
            localFuncChunks[#localFuncChunks + 1] = lfCurChunk
        end
    end

    -- Phase 8: Emit files

    -- Module data chunks (preamble assignments like `Utils.SCALES = {...}`).
    -- Multi-line table values may exceed the limit on their own; for those we
    -- fall back to writing one big chunk and warn — splitting an inner table
    -- literal across files would require re-parsing the table body.
    local hasDataChunk = moduleDataText:match("%S") ~= nil
    local dataChunks = {}   -- list of strings, each a complete chunk content
    if hasDataChunk then
        local dataPreamble = string.format('local %s=require("%s")', moduleName, prefix)
        local preambleSize = gridCharCount(dataPreamble .. "\n")
        local cur = { dataPreamble }
        local curSize = preambleSize
        for _, stmt in ipairs(moduleDataLines) do
            local stmtSize = gridCharCount(stmt)
            if curSize + stmtSize > limit and #cur > 1 then
                dataChunks[#dataChunks + 1] = table.concat(cur, "\n") .. "\n"
                cur = { dataPreamble }
                curSize = preambleSize
            end
            cur[#cur + 1] = stmt
            curSize = curSize + stmtSize
        end
        if #cur > 1 then
            dataChunks[#dataChunks + 1] = table.concat(cur, "\n") .. "\n"
        end
    end

    -- Total chunk count = data chunks + local func chunks + public func chunks
    local totalChunks = #dataChunks + #localFuncChunks + #chunks

    -- Root file: create module table + local vars (if small) + require chunks.
    -- IMPORTANT: register the module in package.loaded BEFORE requiring chunks.
    -- Chunks call require("seq_xxx") to get this same table; without the early
    -- registration, that re-entry hits Lua's "loading sentinel" and the chunk
    -- receives `true` instead of the table → infinite recursion / load failure.
    local rootLines = {}
    rootLines[#rootLines + 1] = string.format("local %s={}", moduleName)
    rootLines[#rootLines + 1] = string.format(
        'package.loaded["%s"]=%s', prefix, moduleName)

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

    -- Require all chunks (data chunk first, then local-func chunks, then public).
    -- A single trailing GC pass after all requires keeps the root small enough
    -- to fit the char limit even with many chunks (per-require GC was costing
    -- ~38 non-whitespace chars per chunk).
    for i = 1, totalChunks do
        rootLines[#rootLines + 1] = string.format('require("%s_%d")', prefix, i)
    end
    rootLines[#rootLines + 1] = 'collectgarbage("collect")'

    rootLines[#rootLines + 1] = string.format("return %s", moduleName)

    local rootContent = table.concat(rootLines, "\n") .. "\n"
    local rootMinSize = gridCharCount(rootContent)

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

    -- Emit data chunks (preamble assignments) FIRST so module data is in place
    -- before functions are attached.
    local chunkIndex = 0
    for _, content in ipairs(dataChunks) do
        chunkIndex = chunkIndex + 1
        local minSize = gridCharCount(content)
        result.files[#result.files + 1] = {
            path = string.format("%s/%s_%d.lua", outdir, prefix, chunkIndex),
            content = content,
            minSize = minSize,
            isRoot = false,
            functions = { "<module data>" },
        }
        if minSize > limit then
            result.warnings[#result.warnings + 1] = string.format(
                "Data chunk %d for %s is %d chars (limit %d) — single statement too large",
                chunkIndex, prefix, minSize, limit)
        end
    end

    -- Emit local function chunks
    for ci, chunk in ipairs(localFuncChunks) do
        chunkIndex = chunkIndex + 1
        local funcTexts = {}
        local funcNames = {}
        for _, block in ipairs(chunk) do
            funcTexts[#funcTexts + 1] = block.text
            funcNames[#funcNames + 1] = block.name or "?"
        end

        local preamble = buildChunkPreamble(funcTexts, localVarsText)
        local chunkLines = { preamble }
        if #localVars > 0 then
            chunkLines[#chunkLines + 1] = localVarsText
        end
        for _, block in ipairs(chunk) do
            chunkLines[#chunkLines + 1] = block.text
        end

        local content = table.concat(chunkLines, "\n") .. "\n"
        local minSize = gridCharCount(content)

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
        local funcTexts = {}
        local funcNames = {}
        for _, block in ipairs(chunk) do
            funcTexts[#funcTexts + 1] = block.text
            funcNames[#funcNames + 1] = block.name or "?"
        end

        -- Extra text for dep-detection: local vars + local funcs (if inlined)
        local extraForDeps = localVarsText
        if not promoteLocalFuncs then extraForDeps = extraForDeps .. localFuncText end

        local preamble = buildChunkPreamble(funcTexts, extraForDeps)
        local chunkLines = { preamble }

        -- If NOT promoting, include local functions in the chunk
        if not promoteLocalFuncs and localFuncText ~= "" then
            chunkLines[#chunkLines + 1] = localFuncText
        end

        for _, block in ipairs(chunk) do
            chunkLines[#chunkLines + 1] = block.text
        end

        local content = table.concat(chunkLines, "\n") .. "\n"
        local minSize = gridCharCount(content)

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
    "sequencer/probability.lua",
    "player/player.lua",
    "song_loader.lua",
}

local i = 1
local includeSongs = false
while i <= #args do
    if args[i] == "--limit" then
        i = i + 1; limit = tonumber(args[i])
    elseif args[i] == "--outdir" then
        i = i + 1; outdir = args[i]
    elseif args[i] == "--dry" then
        dryRun = true
    elseif args[i] == "--keep-asserts" then
        keepAsserts = true
    elseif args[i] == "--include-songs" then
        includeSongs = true
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

-- Optionally copy songs/ files into outdir as flat names (Grid uses a flat
-- require namespace, so songs/dark_groove.lua becomes outdir/dark_groove.lua).
if includeSongs and not dryRun then
    print("")
    local handle = io.popen("ls songs/*.lua 2>/dev/null")
    local copied = 0
    if handle then
        for path in handle:lines() do
            local base = path:match("([^/]+)%.lua$")
            if base then
                local src = io.open(path, "r")
                local dst = io.open(outdir .. "/" .. base .. ".lua", "w")
                if src and dst then
                    dst:write(src:read("*a"))
                    src:close(); dst:close()
                    copied = copied + 1
                    print(string.format("  COPY  %-35s -> %s/%s.lua",
                        path, outdir, base))
                end
            end
        end
        handle:close()
    end
    print(string.format("Copied %d song file(s) into %s/", copied, outdir))
end

if #allWarnings > 0 then
    print(string.format("\n%d warnings:", #allWarnings))
    for _, w in ipairs(allWarnings) do print("  - " .. w) end
end

if dryRun then print("\n(Dry run — no files written)") end
