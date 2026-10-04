-- engine.lua — the Core: lanes + transport + sources -> a preallocated event
-- buffer. Pure Lua: no IO, no drawing, no device knowledge. Zero allocation on
-- the pulse path.
--
-- Event buffer: out.n entries; out.typ 1=note on, 0=note off, 2=control;
-- out.pitch/velocity/channel carry the payload. The host adapter renders it.
--
-- Public action API matches docs/ACTION_API.md. In a shell:
--   local seq3 = require("engine"); seq3.init{lanes=4}; seq3.onStart()

local Sources   = require("sources")
local Scales    = require("scales")
local Lane      = require("lane")
local Transport = require("transport")

-- ops.lua and preset.lua load LAZILY (see loadOps/loadPresetMod below): the
-- pulse path needs neither, so they compile on first use — each resident
-- module costs device RAM (see dist/README.md measurements).

local M = {}

local OUT_CAP = 64

M.lanes = {}
M.out = { n = 0, typ = {}, pitch = {}, velocity = {}, channel = {} }
M.transport = Transport.new()
M.running = false
M.fired = {}               -- per lane: emitted a note this pulse (a trigger)
M.suppressFire = false

-- ---------------------------------------------------------------- init ---

function M.init(opts)
    opts = opts or {}
    local count = opts.lanes or 4
    local baseChannel = opts.channel or 1
    for i = 1, count do
        local kind = (opts.types and opts.types[i]) or "note"
        local l = Lane.new(kind)
        l.channel = baseChannel + i - 1
        M.lanes[i] = l
        M.fired[i] = false
    end
    for i = count + 1, #M.fired do M.fired[i] = false end
    M.out.n = 0
    for i = 1, OUT_CAP do
        M.out.typ[i] = 0
        M.out.pitch[i] = 0
        M.out.velocity[i] = 0
        M.out.channel[i] = 0
    end
    M.transport = Transport.new()
    M.running = false
    return M
end

-- -------------------------------------------------------------- events ---

local function addEvent(kind, pitch, velocity, channel)
    local n = M.out.n + 1
    if n > OUT_CAP then return end
    M.out.n = n
    M.out.typ[n] = kind
    M.out.pitch[n] = pitch
    M.out.velocity[n] = velocity
    M.out.channel[n] = channel
end

-- ------------------------------------------------------------- sources ---

-- A source is a transport tap, another lane firing (LANE_FIRST + n - 1), or
-- OFF. External MIDI sources were cut for device RAM.
local LANE_FIRST = Sources.LANE_FIRST
local function sourceFired(src)
    if src >= LANE_FIRST then return M.fired[src - LANE_FIRST + 1] == true end
    return src ~= Sources.OFF and Transport.tapFired(M.transport, src)
end

-- ------------------------------------------------------------ setpulse ---

local function applyAdvance(lane, kind)
    if lane.pendingReset then
        lane.position = 1
        lane.divCount, lane.yDivCount = 0, 0
        lane.pendingReset = false
        lane.emit = true
        return
    end
    -- Y divides on its own counter, so X and Y never eat each other's counts.
    if kind == "y" then
        lane.yDivCount = lane.yDivCount + 1
        if lane.yDivCount < lane.division then return end
        lane.yDivCount = 0
        return Lane.advanceY(lane)
    end
    lane.divCount = lane.divCount + 1
    if lane.divCount < lane.division then return end
    lane.divCount = 0
    if kind == "x" then Lane.advanceX(lane)
    elseif kind == "back" then Lane.advanceBackward(lane)
    else Lane.advanceForward(lane) end
end

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi else return v end
end

-- Lazy module loads: first call requires the module and re-points the stub,
-- so every later call is a plain table field (no __index on the pulse path).
-- ops = shred/randomize/zero/rotate; preset = copy + loadPreset.
local Ops, Preset, Edit
local lanep                              -- forward decl (defined below)
local function loadOps()
    if not Ops then
        Ops = require("ops")(M, { lanep = lanep, clamp = clamp })
    end
    return Ops
end
local function loadEdit()
    if not Edit then
        Edit = require("edit")(M, { lanep = lanep, clamp = clamp })
    end
    return Edit
end
local function loadPresetMod()
    if not Preset then
        Preset = require("preset")(M, { lanep = lanep, clamp = clamp })
    end
    return Preset
end
-- Two lane types. A Note lane plays its quantized pitch; a Trig lane plays
-- midiNote on active steps. Both use the step's velocity and hold for its
-- stepLength (a long Trig step is a gate). Mod and Gate lanes were folded in
-- for device RAM: CV/CC conversion is the FH-2's job downstream.
local function emitStep(lane, i)
    local pos = lane.position
    local p = lane.midiNote
    if lane.type == "note" then
        p = clamp(Scales.quantize(lane.pitch[pos], lane.scaleMask), lane.minNote, lane.maxNote)
    elseif lane.gate[pos] ~= 1 then
        p = nil
    end
    if p then
        if lane.activeNote then addEvent(0, lane.activeNote, 0, lane.channel) end
        addEvent(1, p, lane.velocity[pos], lane.channel)
        lane.activeNote = p
        lane.noteOffIn = lane.stepLength[pos]
        -- a sounding step is a trigger for lanes routed from this one; not
        -- on the first pulse after start (every lane emits step 1 there)
        M.fired[i] = not M.suppressFire
    end
    lane.emit = false
end

-- ---------------------------------------------------------------- pulse ---

function M.onPulse()
    M.out.n = 0
    local lanes = M.lanes
    local n = #lanes

    -- release expired note-offs first, so step lengths are honoured
    for i = 1, n do
        local l = lanes[i]
        if l.activeNote then
            l.noteOffIn = l.noteOffIn - 1
            if l.noteOffIn <= 0 then
                addEvent(0, l.activeNote, 0, l.channel)
                l.activeNote = false
            end
        end
    end

    if not M.running then return M.out end

    Transport.tick(M.transport)

    -- Lanes are processed in order. A lane's fire flag is cleared at the start
    -- of its own turn, so lane.k drives lane.j (j>k) on the SAME pulse; a
    -- higher-index -> lower-index route lands one pulse later. Deterministic
    -- either way.
    for i = 1, n do
        local l = lanes[i]
        M.fired[i] = false
        if sourceFired(l.resetSource) then l.pendingReset = true end
        if sourceFired(l.randomSource) then Lane.randomizePosition(l) end
        if sourceFired(l.shiftSource) then Lane.rotate(l, l.shiftAmount) end
        if sourceFired(l.previousSource) then applyAdvance(l, "back") end
        if sourceFired(l.advanceSource) then applyAdvance(l, "linear") end
        if sourceFired(l.xAdvanceSource) then applyAdvance(l, "x") end
        if sourceFired(l.yAdvanceSource) then applyAdvance(l, "y") end
        if l.emit then emitStep(l, i) end
    end
    M.suppressFire = false

    return M.out
end

local function rewind()
    M.out.n = 0
    for i = 1, #M.lanes do
        local l = M.lanes[i]
        l.position = 1
        l.divCount, l.yDivCount = 0, 0
        l.pendingReset = false
        l.emit = true
        M.fired[i] = false
    end
    M.suppressFire = true
    return M.out
end

function M.onStart()
    rewind()
    M.running = true
    Transport.start(M.transport)
    return M.out
end

function M.onStop()
    M.out.n = 0
    M.running = false
    Transport.stop(M.transport)
    for i = 1, #M.lanes do
        local l = M.lanes[i]
        if l.activeNote then
            addEvent(0, l.activeNote, 0, l.channel)
            l.activeNote = false
        end
        l.emit = false
    end
    return M.out
end

-- --------------------------------------------------------- aliases/API ---

-- Action-API names (docs/ACTION_API.md): plain aliases, no extra functions.
M.start, M.stop, M.tick, M.reset = M.onStart, M.onStop, M.onPulse, rewind

-- ------------------------------------------------------------ lane cfg ---

lanep = function(index) return M.lanes[index] end

-- The setters (setType, setPitch, set*Source, ...) live in edit.lua, LAZY in
-- the editing bundle: app start never calls one (the device demo writes lane
-- fields directly), so it never compiles them. Any missing `set*` key
-- resolves through __index below and is cached as a plain field.

-- --------------------------------------------------- sequence operations ---
-- LAZY: the ops live in ops.lua / preset.lua and load on first use (via
-- __index). After first resolution they are plain fields, so the hot path
-- never sees the metamethod.

setmetatable(M, {
    __index = function(t, k)
        -- one round-trip: resolve through the lazy module, then cache as a
        -- real field (later calls never touch the metamethod)
        local fn
        if k == "shred" or k == "randomize" or k == "zero" or k == "rotate" then
            fn = loadOps()[k]
        elseif k == "copy" or k == "loadPreset" then
            fn = loadPresetMod()[k]
        elseif type(k) == "string" and k:sub(1, 3) == "set" then
            fn = loadEdit()[k]
        end
        if fn then t[k] = fn end
        return fn
    end,
})

-- ------------------------------------------------------- introspection ---

function M.get(lane, field)
    local l = lanep(lane); if not l then return nil end
    return l[field]
end

function M.set(lane, field, value)
    local l = lanep(lane); if not l then return false end
    l[field] = value
    return true
end

function M.state(lane) return lanep(lane) end

return M
