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
--     formatVersion  = 2,
--     bpm            = <integer>,
--     pulsesPerBeat  = <integer>,
--     durationPulses = <integer>,           -- bars * beatsPerBar * ppb
--     loop           = true,
--     trackCount     = <integer>,
--
--     -- Player-facing arrays (interleaved NOTE_ON + NOTE_OFF, sorted by atPulse).
--     -- kind values:
--     --   1 = NOTE_ON  (active)
--     --   0 = NOTE_OFF (active)
--     --   2 = NOTE_ON  muted by writer this loop  (player skips)
--     --   3 = NOTE_OFF muted by writer this loop  (player skips)
--     eventCount  = <integer>,
--     atPulse     = { ... },                -- pulse offset
--     kind        = { ... },                -- 0/1/2/3 (numeric, cheap)
--     pitch       = { ... },                -- MIDI pitch (already scale-quantized)
--     velocity    = { ... },
--     channel     = { ... },
--
--     -- Writer-only arrays (omitted entirely if song has no probability/jitter).
--     -- pairOff[i] = index of the matching NOTE_OFF (or 0 for NOTE_OFF rows).
--     -- srcStepProb[i] = original step probability 0..100 (NOTE_ON rows only).
--     -- srcVelocity[i] = original (un-jittered) velocity for re-jitter.
--     hasProbability = <bool>,
--     pairOff        = { ... } | nil,
--     srcStepProb    = { ... } | nil,
--     srcVelocity    = { ... } | nil,
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

    -- First pass: collect raw NOTE_ON records as the engine emits them.
    -- We'll then interleave NOTE_OFFs (paired by gate length) and sort.
    local raw = {}   -- list of { atPulse, pitch, vel, ch, gate, prob }
    local hasProbability = false

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
                        local prob       = Step.getProbability(step) or 100

                        if prob < 100 then hasProbability = true end

                        raw[#raw + 1] = {
                            atPulse = pulseCount,
                            pitch   = pitch,
                            vel     = Step.getVelocity(step),
                            channel = channel,
                            gate    = gatePulses,
                            prob    = prob,
                        }
                    end
                end
            end

            Engine.onPulse(engine, pulseCount)
        end
    end

    -- Second pass: build interleaved (NOTE_ON, NOTE_OFF) sorted timeline.
    -- We emit a row per NOTE_ON and a row per NOTE_OFF. Stable sort by
    -- (atPulse asc, kind asc) so kind=0 (NOTE_OFF) fires before kind=1 at
    -- the same pulse, giving correct retrigger semantics.
    local interleaved = {}
    for i, r in ipairs(raw) do
        interleaved[#interleaved + 1] = {
            at = r.atPulse, kind = 1, pitch = r.pitch, vel = r.vel,
            ch = r.channel, srcIdx = i, prob = r.prob,
        }
        local offAt = r.atPulse + r.gate
        -- Clamp NOTE_OFF that would land past loop end onto the last pulse
        -- (matches old player behaviour where loop-wrap dropped the off).
        if offAt > durationPulses then offAt = durationPulses end
        interleaved[#interleaved + 1] = {
            at = offAt, kind = 0, pitch = r.pitch, vel = 0,
            ch = r.channel, srcIdx = i,
        }
    end

    table.sort(interleaved, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        return a.kind < b.kind
    end)

    -- Build a map srcIdx -> off-event index in the sorted timeline so we can
    -- compute pairOff for NOTE_ONs.
    local offIdxBySrc = {}
    for newIdx, e in ipairs(interleaved) do
        if e.kind == 0 then offIdxBySrc[e.srcIdx] = newIdx end
    end

    local events = {
        atPulse     = {},
        kind        = {},
        pitch       = {},
        velocity    = {},
        channel     = {},
        pairOff     = {},
        srcStepProb = {},
        srcVelocity = {},
    }

    for newIdx, e in ipairs(interleaved) do
        events.atPulse[newIdx]  = e.at
        events.kind[newIdx]     = e.kind
        events.pitch[newIdx]    = e.pitch
        events.velocity[newIdx] = e.vel
        events.channel[newIdx]  = e.ch
        if e.kind == 1 then
            events.pairOff[newIdx]     = offIdxBySrc[e.srcIdx] or 0
            events.srcStepProb[newIdx] = e.prob
            events.srcVelocity[newIdx] = e.vel
        else
            events.pairOff[newIdx]     = 0
            events.srcStepProb[newIdx] = 0
            events.srcVelocity[newIdx] = 0
        end
    end

    events.count          = #interleaved
    events.durationPulses = durationPulses
    events.hasProbability = hasProbability
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

-- Player-facing arrays (always emitted).
local PLAYER_FIELDS = { "atPulse", "kind", "pitch", "velocity", "channel" }
-- Writer-only arrays (emitted only when song has probability/jitter).
local WRITER_FIELDS = { "pairOff", "srcStepProb", "srcVelocity" }

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

-- Returns: mainSource, sidecarFiles (map of name → source).
-- Strategy: emit a tight preamble + all arrays inline, then if the file
-- exceeds the Grid char limit, externalise arrays to sidecars in descending
-- size order until it fits.
-- If `noSplit` is true, all arrays stay inline regardless of file size
-- (use this when the device tolerates a single large file).
local function emitCompiledSources(name, song, ppb, durationPulses, events, requirePrefix, noSplit)
    -- Decide which array fields to actually emit.
    local fields = {}
    for _, f in ipairs(PLAYER_FIELDS) do fields[#fields + 1] = f end
    if events.hasProbability then
        for _, f in ipairs(WRITER_FIELDS) do fields[#fields + 1] = f end
    end

    -- Materialise each array as its inline literal text once.
    local literals = {}
    local sizes    = {}
    for _, field in ipairs(fields) do
        literals[field] = intList(events[field], events.count)
        sizes[field]    = #literals[field]
    end

    -- Decide which arrays go to sidecars.
    -- Start with all inline; if too big, externalise the largest first.
    local externalised = {}   -- field -> true
    local function buildMain()
        local lines = {}
        local function w(s) lines[#lines + 1] = s end
        local needR = false
        for _, field in ipairs(fields) do
            if externalised[field] then needR = true; break end
        end
        w("local s={}")
        if needR then w("local R=require") end
        w(string.format("s.bpm=%d", song.bpm))
        w(string.format("s.pulsesPerBeat=%d", ppb))
        w(string.format("s.durationPulses=%d", durationPulses))
        w("s.loop=true")
        if events.hasProbability then w("s.hasProbability=true") end
        w(string.format("s.eventCount=%d", events.count))
        for _, field in ipairs(fields) do
            if externalised[field] then
                -- Sidecar: split into <=150-item pieces.
                local pieces = chunkPieces(events[field], events.count, 150)
                for pi, _ in ipairs(pieces) do
                    local sidecarName = string.format("%s_%s_%d", name, field:lower(), pi)
                    local req = gridRequireName(requirePrefix, sidecarName)
                    if pi == 1 then
                        w(string.format('s.%s=R("%s")', field, req))
                    else
                        w(string.format('do local x=R("%s")table.move(x,1,#x,#s.%s+1,s.%s)end',
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
            for _, field in ipairs(fields) do
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
    for _, field in ipairs(fields) do
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
        formatVersion  = 2,
        bpm            = song.bpm,
        pulsesPerBeat  = ppb,
        durationPulses = events.durationPulses,
        loop           = true,
        trackCount     = #song.tracks,
        eventCount     = events.count,
        atPulse        = events.atPulse,
        kind           = events.kind,
        pitch          = events.pitch,
        velocity       = events.velocity,
        channel        = events.channel,
        hasProbability = events.hasProbability,
        pairOff        = events.hasProbability and events.pairOff or nil,
        srcStepProb    = events.hasProbability and events.srcStepProb or nil,
        srcVelocity    = events.hasProbability and events.srcVelocity or nil,
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
            count          = compiled.eventCount,
            atPulse        = compiled.atPulse,
            kind           = compiled.kind,
            pitch          = compiled.pitch,
            velocity       = compiled.velocity,
            channel        = compiled.channel,
            pairOff        = compiled.pairOff,
            srcStepProb    = compiled.srcStepProb,
            srcVelocity    = compiled.srcVelocity,
            hasProbability = compiled.hasProbability,
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