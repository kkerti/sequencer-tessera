-- tools/song_compile.lua
-- Compiles a song source (the rich, sequencer-driven format consumed by
-- song_loader.lua) into a flat compiled-song schema that a tiny on-device
-- player can walk without any sequencer engine code.
--
-- Usage:
--   lua tools/song_compile.lua patches/dark_groove.lua
--   lua tools/song_compile.lua patches/dark_groove.lua --outdir compiled
--
-- The source song must declare `bars` (length in bars). `beatsPerBar` is
-- optional and defaults to 4.
--
-- Output: a single self-contained Lua file with all event arrays inline.
-- Schema (compiled/<name>.lua):
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
--     pitch       = { ... },                -- MIDI pitch
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

    while pulseCount < durationPulses do
        pulseCount = pulseCount + 1

        for trackIndex = 1, engine.trackCount do
            local track = engine.tracks[trackIndex]

            track.clockAccum = track.clockAccum + track.clockMult
            local advanceCount = math.floor(track.clockAccum / track.clockDiv)
            track.clockAccum   = track.clockAccum % track.clockDiv

            for _ = 1, advanceCount do
                local step, event = Engine.advanceTrack(engine, trackIndex)
                if event == "NOTE_ON" then
                    local channel    = track.midiChannel or trackIndex
                    local pitch      = Step.getPitch(step)
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
-- Code generator — emits a single self-contained Lua file with the compiled
-- schema. All arrays inlined; no sidecars, no chunking. Grid's filesystem
-- accepts arbitrarily large files now.
-- ---------------------------------------------------------------------------

-- Joins integers into a comma list, no spaces (compact for ESP32 RAM).
local function intList(arr, count)
    local parts = {}
    for i = 1, count do
        parts[i] = tostring(arr[i])
    end
    return table.concat(parts, ",")
end

-- Player-facing arrays (always emitted).
local PLAYER_FIELDS = { "atPulse", "kind", "pitch", "velocity", "channel" }
-- Writer-only arrays (emitted only when song has probability/jitter).
local WRITER_FIELDS = { "pairOff", "srcStepProb", "srcVelocity" }

local function emitCompiledSource(song, ppb, durationPulses, events)
    local fields = {}
    for _, f in ipairs(PLAYER_FIELDS) do fields[#fields + 1] = f end
    if events.hasProbability then
        for _, f in ipairs(WRITER_FIELDS) do fields[#fields + 1] = f end
    end

    local lines = {}
    local function w(s) lines[#lines + 1] = s end

    w("local s={}")
    w(string.format("s.bpm=%d", song.bpm))
    w(string.format("s.pulsesPerBeat=%d", ppb))
    w(string.format("s.durationPulses=%d", durationPulses))
    if song.loop == false then
        w("s.loop=false")
    else
        w("s.loop=true")
    end
    if events.hasProbability then w("s.hasProbability=true") end
    w(string.format("s.eventCount=%d", events.count))
    for _, field in ipairs(fields) do
        w(string.format("s.%s={%s}", field, intList(events[field], events.count)))
    end
    w("return s")
    return table.concat(lines, "\n") .. "\n"
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
        loop           = song.loop ~= false,
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

-- Compiles a song file and writes the result to outdir/<name>.lua.
function SongCompile.compileFile(sourcePath, outdir)
    outdir = outdir or "compiled"
    local song = dofile(sourcePath)

    local name = sourcePath:match("([^/]+)%.lua$") or "song"
    local compiled = SongCompile.compile(song)
    local source = emitCompiledSource(song, compiled.pulsesPerBeat,
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
        })

    os.execute("mkdir -p " .. outdir)
    local outPath = outdir .. "/" .. name .. ".lua"
    local f = assert(io.open(outPath, "w"), "songCompile: cannot write " .. outPath)
    f:write(source)
    f:close()

    return outPath, compiled, #source
end

-- ---------------------------------------------------------------------------
-- CLI entry
-- ---------------------------------------------------------------------------

if arg and arg[0] and arg[0]:match("song_compile%.lua$") then
    local sourcePath = nil
    local outdir     = "compiled"
    local i = 1
    while i <= #arg do
        if arg[i] == "--outdir" then
            i = i + 1; outdir = arg[i]
        else
            sourcePath = arg[i]
        end
        i = i + 1
    end

    if not sourcePath then
        print("Usage: lua tools/song_compile.lua <song.lua> [--outdir DIR]")
        os.exit(1)
    end

    local outPath, compiled, byteSize = SongCompile.compileFile(sourcePath, outdir)
    print(string.format("Compiled %s -> %s", sourcePath, outPath))
    print(string.format("  events:    %d", compiled.eventCount))
    print(string.format("  duration:  %d pulses (%d bars at %d BPM)",
        compiled.durationPulses,
        compiled.durationPulses / (compiled.pulsesPerBeat * 4),
        compiled.bpm))
    print(string.format("  file size: %d bytes", byteSize))
end

return SongCompile
