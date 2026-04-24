-- tools/song_compile.lua
-- Compiles a song source (the rich, sequencer-driven format consumed by
-- song_loader.lua) into a flat compiled-song schema that a tiny on-device
-- player can walk without any sequencer engine code.
--
-- Usage:
--   lua tools/song_compile.lua songs/dark_groove.lua
--   lua tools/song_compile.lua songs/dark_groove.lua --outdir compiled
--
-- The source song must declare `bars` (length in bars). `beatsPerBar` is
-- optional and defaults to 4.
--
-- Output schema (compiled/<name>.lua):
--   {
--     formatVersion  = 1,
--     name           = "<name>",
--     bpm            = <integer>,
--     pulsesPerBeat  = <integer>,
--     durationPulses = <integer>,           -- bars * beatsPerBar * ppb
--     loop           = true,
--     trackCount     = <integer>,
--
--     eventCount  = <integer>,
--     atPulse     = { ... },                -- pulse offset of each NOTE_ON
--     pitch       = { ... },                -- MIDI pitch (already scale-quantized)
--     velocity    = { ... },
--     channel     = { ... },
--     gatePulses  = { ... },                -- length of note in pulses
--     probability = { ... },                -- 0-100, walker rolls per playback
--   }

local SongLoader = require("song_loader")
local Engine     = require("sequencer/engine")
local Track      = require("sequencer/track")
local Step       = require("sequencer/step")
local Performance = require("sequencer/performance")

-- ---------------------------------------------------------------------------
-- Pulse-driven walker — mirrors Player.tick but records pulse positions.
-- ---------------------------------------------------------------------------

local function compileTrackEvents(player, songBars, beatsPerBar)
    local engine         = player.engine
    local pulsesPerBeat  = engine.pulsesPerBeat
    local durationPulses = songBars * beatsPerBar * pulsesPerBeat

    local events = {
        atPulse     = {},
        pitch       = {},
        velocity    = {},
        channel     = {},
        gatePulses  = {},
        probability = {},
    }
    local count = 0

    local pulseCount   = 0
    local swingCarry   = 0

    while pulseCount < durationPulses do
        pulseCount = pulseCount + 1

        local shouldHold
        shouldHold, swingCarry = Performance.nextSwingHold(
            pulseCount,
            pulsesPerBeat,
            player.swingPercent,
            swingCarry
        )

        if not shouldHold then
            for trackIndex = 1, engine.trackCount do
                local track = engine.tracks[trackIndex]

                track.clockAccum = track.clockAccum + track.clockMult
                local advanceCount = math.floor(track.clockAccum / track.clockDiv)
                track.clockAccum   = track.clockAccum % track.clockDiv

                for _ = 1, advanceCount do
                    local step, event = Engine.advanceTrack(engine, trackIndex)
                    if event == "NOTE_ON" then
                        local channel    = track.midiChannel or trackIndex
                        local pitch      = Step.resolvePitch(step, player.scaleTable, player.rootNote)
                        local gatePulses = Step.getGate(step)
                        local prob       = Step.getProbability(step)

                        count = count + 1
                        events.atPulse[count]     = pulseCount
                        events.pitch[count]       = pitch
                        events.velocity[count]    = Step.getVelocity(step)
                        events.channel[count]     = channel
                        events.gatePulses[count]  = gatePulses
                        events.probability[count] = prob
                    end
                    -- NOTE_OFF events from the engine are ignored: the
                    -- compiled walker derives NOTE_OFF time from gatePulses.
                end
            end

            Engine.onPulse(engine, pulseCount)
        end
    end

    events.count          = count
    events.durationPulses = durationPulses
    return events
end

-- ---------------------------------------------------------------------------
-- Code generator — emits a Lua source file with the compiled schema.
-- For Grid-friendly file sizes, large parallel arrays are split into
-- separate sibling files (`<name>_atpulse.lua`, `<name>_pitch.lua`, ...)
-- when the inline literal would exceed `splitThreshold` characters.
-- ---------------------------------------------------------------------------

-- Joins integers into a comma list, no spaces (compact for ESP32).
local function intList(arr, count)
    local parts = {}
    for i = 1, count do
        parts[i] = tostring(arr[i])
    end
    return table.concat(parts, ",")
end

-- Splits an integer array into N chunks of at most `maxItems` items each.
-- Returns a list of joined comma-strings.
local function chunkList(arr, count, maxItems)
    local chunks = {}
    local i = 1
    while i <= count do
        local last = math.min(i + maxItems - 1, count)
        local parts = {}
        for j = i, last do parts[#parts + 1] = tostring(arr[j]) end
        chunks[#chunks + 1] = table.concat(parts, ",")
        i = last + 1
    end
    return chunks
end

local ARRAY_FIELDS = { "atPulse", "pitch", "velocity", "channel", "gatePulses", "probability" }

-- Grid per-file char limit (non-whitespace). Main song file must fit in this.
local GRID_CHAR_LIMIT = 800

-- Counts non-whitespace chars (Grid's actual budget).
local function gridCharCount(s)
    return (#(s:gsub("[ \t\n\r]", "")))
end

-- Builds the require-string a compiled song uses to load a sidecar.
-- With prefix "/dark_groove" and name "dark_groove_atpulse_1"
--   -> "/dark_groove/dark_groove_atpulse_1".
local function gridRequireName(prefix, name)
    if prefix and prefix ~= "" then
        return prefix .. "/" .. name
    end
    return name
end

-- Splits an integer array into N chunks of at most `maxItems` items each.
-- Returns a list of joined comma-strings.
local function chunkPieces(arr, count, maxItems)
    local pieces = {}
    local i = 1
    while i <= count do
        local last = math.min(i + maxItems - 1, count)
        local parts = {}
        for j = i, last do parts[#parts + 1] = tostring(arr[j]) end
        pieces[#pieces + 1] = table.concat(parts, ",")
        i = last + 1
    end
    return pieces
end

-- Returns: mainSource, sidecarFiles (map of name → source).
-- Strategy: emit a tight preamble + all arrays inline, then if the file
-- exceeds the Grid char limit, externalise arrays to sidecars in descending
-- size order until it fits.
-- If `noSplit` is true, all arrays stay inline regardless of file size
-- (use this when the device tolerates a single large file).
local function emitCompiledSources(name, song, ppb, durationPulses, events, requirePrefix, noSplit)
    -- Materialise each array as its inline literal text once.
    local literals = {}
    local sizes    = {}
    for _, field in ipairs(ARRAY_FIELDS) do
        literals[field] = intList(events[field], events.count)
        sizes[field]    = #literals[field]
    end

    -- Decide which arrays go to sidecars.
    -- Start with all inline; if too big, externalise the largest first.
    local externalised = {}   -- field -> true
    local function buildMain()
        local lines = {}
        local function w(s) lines[#lines + 1] = s end
        w("local s={}")
        w(string.format("s.bpm=%d", song.bpm))
        w(string.format("s.pulsesPerBeat=%d", ppb))
        w(string.format("s.durationPulses=%d", durationPulses))
        w("s.loop=true")
        w(string.format("s.eventCount=%d", events.count))
        for _, field in ipairs(ARRAY_FIELDS) do
            if externalised[field] then
                -- Sidecar: split into <=150-item pieces.
                local pieces = chunkPieces(events[field], events.count, 150)
                for pi, _ in ipairs(pieces) do
                    local sidecarName = string.format("%s_%s_%d", name, field:lower(), pi)
                    local req = gridRequireName(requirePrefix, sidecarName)
                    if pi == 1 then
                        w(string.format('s.%s=require("%s")', field, req))
                    else
                        w(string.format('do local x=require("%s")for i=1,#x do s.%s[#s.%s+1]=x[i] end end',
                            req, field, field))
                    end
                end
            else
                w(string.format("s.%s={%s}", field, literals[field]))
            end
        end
        w("return s")
        return table.concat(lines, "\n") .. "\n"
    end

    local mainSource = buildMain()
    if not noSplit then
        while gridCharCount(mainSource) > GRID_CHAR_LIMIT do
            -- Pick largest still-inline field to externalise.
            local pickField, pickSize = nil, -1
            for _, field in ipairs(ARRAY_FIELDS) do
                if not externalised[field] and sizes[field] > pickSize then
                    pickField, pickSize = field, sizes[field]
                end
            end
            if not pickField then break end   -- nothing left to externalise
            externalised[pickField] = true
            mainSource = buildMain()
        end
    end

    -- Build sidecars only for fields actually externalised.
    local sidecars = {}
    for _, field in ipairs(ARRAY_FIELDS) do
        if externalised[field] then
            local pieces = chunkPieces(events[field], events.count, 150)
            for pi, piece in ipairs(pieces) do
                local sidecarName = string.format("%s_%s_%d", name, field:lower(), pi)
                sidecars[sidecarName .. ".lua"] = string.format("return{%s}\n", piece)
            end
        end
    end

    return mainSource, sidecars
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

local SongCompile = {}

-- Compiles a loaded song table to the flat schema. Returns the compiled
-- table (not Lua source). Pure function — no file I/O.
function SongCompile.compile(song)
    assert(type(song) == "table", "songCompile: song must be a table")
    assert(type(song.bars) == "number" and song.bars >= 1,
        "songCompile: song must declare bars >= 1")

    local beatsPerBar = song.beatsPerBar or 4
    local ppb         = song.ppb or 4

    -- A clockFn is required by SongLoader/Player even though we drive pulses
    -- ourselves; use a stub that returns 0 — the compiler doesn't consult
    -- wall-clock at all.
    local stubClock = function() return 0 end
    local result    = SongLoader.load(song, stubClock)
    local player    = result.player

    local events = compileTrackEvents(player, song.bars, beatsPerBar)

    return {
        formatVersion  = 1,
        bpm            = song.bpm,
        pulsesPerBeat  = ppb,
        durationPulses = events.durationPulses,
        loop           = true,
        trackCount     = #song.tracks,
        eventCount     = events.count,
        atPulse        = events.atPulse,
        pitch          = events.pitch,
        velocity       = events.velocity,
        channel        = events.channel,
        gatePulses     = events.gatePulses,
        probability    = events.probability,
    }
end

-- Compiles a song file and writes the result (and any sidecar array files)
-- to outdir/<name>.lua and outdir/<name>_<field>_N.lua.
function SongCompile.compileFile(sourcePath, outdir, requirePrefix, noSplit)
    outdir = outdir or "compiled"
    if requirePrefix then
        requirePrefix = requirePrefix:gsub("/+$", "")
        if requirePrefix == "" then requirePrefix = nil end
    end
    local song = dofile(sourcePath)

    local name = sourcePath:match("([^/]+)%.lua$") or "song"
    local compiled = SongCompile.compile(song)
    local source, sidecars = emitCompiledSources(name, song, compiled.pulsesPerBeat,
        compiled.durationPulses, {
            count       = compiled.eventCount,
            atPulse     = compiled.atPulse,
            pitch       = compiled.pitch,
            velocity    = compiled.velocity,
            channel     = compiled.channel,
            gatePulses  = compiled.gatePulses,
            probability = compiled.probability,
        }, requirePrefix, noSplit)

    os.execute("mkdir -p " .. outdir)
    local outPath = outdir .. "/" .. name .. ".lua"
    local f = assert(io.open(outPath, "w"), "songCompile: cannot write " .. outPath)
    f:write(source)
    f:close()

    local sidecarCount = 0
    for fname, content in pairs(sidecars) do
        local p = outdir .. "/" .. fname
        local sf = assert(io.open(p, "w"), "songCompile: cannot write " .. p)
        sf:write(content)
        sf:close()
        sidecarCount = sidecarCount + 1
    end

    return outPath, compiled, sidecarCount
end

-- ---------------------------------------------------------------------------
-- CLI entry
-- ---------------------------------------------------------------------------

if arg and arg[0] and arg[0]:match("song_compile%.lua$") then
    local sourcePath = nil
    local outdir     = "compiled"
    local requirePrefix = nil
    local noSplit = false
    local i = 1
    while i <= #arg do
        if arg[i] == "--outdir" then
            i = i + 1; outdir = arg[i]
        elseif arg[i] == "--require-prefix" then
            i = i + 1; requirePrefix = arg[i]
        elseif arg[i] == "--no-split" then
            noSplit = true
        else
            sourcePath = arg[i]
        end
        i = i + 1
    end

    if not sourcePath then
        print("Usage: lua tools/song_compile.lua <song.lua> [--outdir DIR] [--require-prefix /tt] [--no-split]")
        os.exit(1)
    end

    local outPath, compiled, sidecars = SongCompile.compileFile(sourcePath, outdir, requirePrefix, noSplit)
    print(string.format("Compiled %s → %s", sourcePath, outPath))
    print(string.format("  events:    %d", compiled.eventCount))
    print(string.format("  duration:  %d pulses (%d bars at %d BPM)",
        compiled.durationPulses,
        compiled.durationPulses / (compiled.pulsesPerBeat * 4),
        compiled.bpm))
    print(string.format("  sidecars:  %d", sidecars))

    -- Verify all written files fit Grid's 800-char (non-whitespace) budget,
    -- but only when splitting is enabled — --no-split is an explicit opt-out.
    if not noSplit then
        local handle = io.popen("ls " .. outdir .. "/*.lua 2>/dev/null")
        if handle then
            local maxSize, overCount = 0, 0
            for path in handle:lines() do
                local f = io.open(path, "r")
                if f then
                    local content = f:read("*a"); f:close()
                    local nws = (#(content:gsub("[ \t\n\r]", "")))
                    if nws > maxSize then maxSize = nws end
                    if nws > 800 then
                        overCount = overCount + 1
                        print(string.format("  WARNING: %s is %d non-ws chars (>800)", path, nws))
                    end
                end
            end
            handle:close()
            print(string.format("  largest file: %d non-ws chars  (limit 800)", maxSize))
            if overCount > 0 then os.exit(1) end
        end
    else
        -- Still report the main file size for visibility.
        local f = io.open(outPath, "r")
        if f then
            local content = f:read("*a"); f:close()
            local nws = (#(content:gsub("[ \t\n\r]", "")))
            print(string.format("  main file:    %d non-ws chars  (--no-split, limit not enforced)", nws))
        end
    end
end

return SongCompile