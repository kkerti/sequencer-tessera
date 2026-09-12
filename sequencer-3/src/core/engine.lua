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

local M = {}

local OUT_CAP = 64

-- A Mod lane counts as "firing" at or above this value, so it can drive
-- another lane's trigger source (MD2's Out-threshold behaviour).
local MOD_FIRE_THRESHOLD = 64

M.lanes = {}
M.out = { n = 0, typ = {}, pitch = {}, velocity = {}, channel = {} }
M.transport = Transport.new()
M.externalTrigger = {}
M.externalValue = {}
M.laneFired = {}
M.running = false
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
    end
    M.out.n = 0
    for i = 1, OUT_CAP do
        M.out.typ[i] = 0
        M.out.pitch[i] = 0
        M.out.velocity[i] = 0
        M.out.channel[i] = 0
    end
    for i = 1, Sources.EXTERNAL_COUNT do
        M.externalTrigger[i] = false
        M.externalValue[i] = nil   -- unset until a CC arrives, so it never pins
    end
    for i = 1, Sources.LANE_COUNT do M.laneFired[i] = false end
    M.transport = Transport.new()
    M.running = false
    M.suppressFire = false
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

local function sourceFired(src)
    if src == Sources.OFF then return false end
    if Sources.isTransport(src) then
        return Transport.tapFired(M.transport, src)
    elseif Sources.isExternal(src) then
        return M.externalTrigger[src - Sources.EXTERNAL_FIRST + 1] == true
    elseif Sources.isLane(src) then
        return M.laneFired[src - Sources.LANE_FIRST + 1] == true
    end
    return false
end

local function sourceValue(src)
    if Sources.isExternal(src) then
        return M.externalValue[src - Sources.EXTERNAL_FIRST + 1]
    elseif Sources.isLane(src) then
        local l = M.lanes[src - Sources.LANE_FIRST + 1]
        if not l then return nil end
        if l.type == "note" then return l.pitch[l.position]
        elseif l.type == "mod" then return l.value[l.position]
        else return l.gate[l.position] * 127 end
    end
    return nil
end

-- ------------------------------------------------------------ setpulse ---

local function applyAdvance(lane, kind)
    if lane.pendingReset then
        lane.position = 1
        lane.divCount = 0
        lane.pendingReset = false
        lane.emit = true
        return
    end
    lane.divCount = lane.divCount + 1
    if lane.divCount < lane.division then return end
    lane.divCount = 0
    if kind == "x" then Lane.advanceX(lane)
    elseif kind == "y" then Lane.advanceY(lane)
    elseif kind == "back" then Lane.advanceBackward(lane)
    else Lane.advanceForward(lane) end
end

local function applyAddress(lane, src)
    local v = sourceValue(src)
    if not v then return end
    local used = Lane.usedSteps(lane)
    local pos = (v * used) // 127 + 1
    if pos > used then pos = used end
    if pos < 1 then pos = 1 end
    if pos ~= lane.position then
        lane.position = pos
        lane.emit = true
    end
end

local function applyXAddress(lane, src)
    local v = sourceValue(src)
    if not v then return end
    local x = (v * lane.width) // 127
    if x >= lane.width then x = lane.width - 1 end
    if x < 0 then x = 0 end
    local y = (lane.position - 1) // lane.width
    local pos = y * lane.width + x + 1
    if pos ~= lane.position then
        lane.position = pos
        lane.emit = true
    end
end

local function applyYAddress(lane, src)
    local v = sourceValue(src)
    if not v then return end
    local y = (v * lane.height) // 127
    if y >= lane.height then y = lane.height - 1 end
    if y < 0 then y = 0 end
    local x = (lane.position - 1) % lane.width
    local pos = y * lane.width + x + 1
    if pos ~= lane.position then
        lane.position = pos
        lane.emit = true
    end
end

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi else return v end
end

local function emitStep(lane)
    local pos = lane.position
    lane.fired = false
    if lane.type == "note" then
        if lane.activeNote then
            addEvent(0, lane.activeNote, 0, lane.channel)
            lane.activeNote = nil
        end
        local p = Scales.quantize(lane.pitch[pos], lane.scaleMask)
        p = clamp(p, lane.minNote, lane.maxNote)
        addEvent(1, p, lane.velocity[pos], lane.channel)
        lane.activeNote = p
        lane.noteOffIn = lane.stepLength[pos]
        lane.sustain = false
        lane.fired = true
    elseif lane.type == "mod" then
        local v = clamp(lane.value[pos], lane.minValue, lane.maxValue)
        addEvent(2, lane.controller or 0, v, lane.channel)
        lane.fired = v >= MOD_FIRE_THRESHOLD
    elseif lane.type == "trig" then
        if lane.gate[pos] == 1 then
            addEvent(1, lane.midiNote, 100, lane.channel)
            lane.activeNote = lane.midiNote
            lane.noteOffIn = 1
            lane.sustain = false
            lane.fired = true
        end
    elseif lane.type == "gate" then
        if lane.gate[pos] == 1 then
            if not lane.activeNote then
                addEvent(1, lane.midiNote, 100, lane.channel)
                lane.activeNote = lane.midiNote
                lane.sustain = true
                lane.fired = true
            end
        elseif lane.activeNote then
            addEvent(0, lane.activeNote, 0, lane.channel)
            lane.activeNote = nil
            lane.sustain = false
        end
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
        if l.activeNote and not l.sustain then
            l.noteOffIn = l.noteOffIn - 1
            if l.noteOffIn <= 0 then
                addEvent(0, l.activeNote, 0, l.channel)
                l.activeNote = nil
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
        if sourceFired(l.resetSource) then l.pendingReset = true end
        if sourceFired(l.randomSource) then Lane.randomizePosition(l) end
        if sourceFired(l.shiftSource) then Lane.rotate(l, l.shiftAmount) end
        if sourceFired(l.previousSource) then applyAdvance(l, "back") end
        if sourceFired(l.advanceSource) then applyAdvance(l, "linear") end
        if sourceFired(l.xAdvanceSource) then applyAdvance(l, "x") end
        if sourceFired(l.yAdvanceSource) then applyAdvance(l, "y") end
        if l.addressSource ~= Sources.OFF then applyAddress(l, l.addressSource) end
        if l.xAddressSource ~= Sources.OFF then applyXAddress(l, l.xAddressSource) end
        if l.yAddressSource ~= Sources.OFF then applyYAddress(l, l.yAddressSource) end
        if l.emit then emitStep(l) end
        if i <= Sources.LANE_COUNT then
            M.laneFired[i] = (not M.suppressFire) and l.fired or false
        end
    end
    M.suppressFire = false

    for i = 1, Sources.EXTERNAL_COUNT do M.externalTrigger[i] = false end

    return M.out
end

function M.onStart()
    M.out.n = 0
    M.running = true
    Transport.start(M.transport)
    for i = 1, #M.lanes do
        local l = M.lanes[i]
        l.position = 1
        l.divCount = 0
        l.pendingReset = false
        l.emit = true
    end
    for i = 1, Sources.LANE_COUNT do M.laneFired[i] = false end
    M.suppressFire = true
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
            l.activeNote = nil
        end
        l.emit = false
    end
    return M.out
end

-- --------------------------------------------------------- aliases/API ---

-- Action-API names (docs/ACTION_API.md).
function M.start() return M.onStart() end
function M.stop()  return M.onStop() end
function M.tick()  return M.onPulse() end

function M.reset()
    M.out.n = 0
    for i = 1, #M.lanes do
        local l = M.lanes[i]
        l.position = 1
        l.divCount = 0
        l.pendingReset = false
        l.emit = true
    end
    return M.out
end

-- --------------------------------------------------------- external in ---

function M.triggerExternal(index)   -- 1-based
    if index >= 1 and index <= Sources.EXTERNAL_COUNT then
        M.externalTrigger[index] = true
    end
end

function M.setExternalValue(index, value)
    if index >= 1 and index <= Sources.EXTERNAL_COUNT then
        M.externalValue[index] = clamp(value, 0, 127)
    end
end

-- ------------------------------------------------------------ lane cfg ---

local function lanep(index) return M.lanes[index] end

function M.setType(lane, kind)
    local l = lanep(lane); if not l then return false end
    l.type = kind or "note"
    return true
end

function M.setDimensions(lane, name)
    local l = lanep(lane); if not l then return false end
    return Lane.setDims(l, name)
end

function M.setLength(lane, n)
    local l = lanep(lane); if not l then return false end
    if l.height ~= 1 then return false end
    l.length = clamp(n, 1, Lane.CAP)
    if l.position > l.length then l.position = 1 end
    return true
end

function M.setDivision(lane, n)
    local l = lanep(lane); if not l then return false end
    l.division = clamp(n, 1, 16)
    return true
end

function M.setChannel(lane, channel)
    local l = lanep(lane); if not l then return false end
    l.channel = clamp(channel, 1, 16)
    return true
end

function M.setController(lane, cc)
    local l = lanep(lane); if not l then return false end
    l.controller = clamp(cc, 0, 127)
    return true
end

function M.setMidiNote(lane, note)
    local l = lanep(lane); if not l then return false end
    l.midiNote = clamp(note, 0, 127)
    return true
end

function M.setScale(lane, mask, root)
    local l = lanep(lane); if not l then return false end
    l.rawScaleMask = mask or 0
    l.root = (root or 0) % 12
    l.scaleMask = Scales.rotate(l.rawScaleMask, l.root)
    return true
end

function M.setRange(lane, min, max)
    local l = lanep(lane); if not l then return false end
    if l.type == "mod" then
        l.minValue = clamp(min, 0, 127); l.maxValue = clamp(max, 0, 127)
    else
        l.minNote = clamp(min, 0, 127); l.maxNote = clamp(max, 0, 127)
    end
    return true
end

local function setSource(lane, field, value)
    local l = lanep(lane); if not l then return false end
    l[field] = Sources.parse(value)
    return true
end

function M.setAdvanceSource(lane, src) return setSource(lane, "advanceSource", src) end
function M.setXAdvanceSource(lane, src) return setSource(lane, "xAdvanceSource", src) end
function M.setYAdvanceSource(lane, src) return setSource(lane, "yAdvanceSource", src) end
function M.setResetSource(lane, src) return setSource(lane, "resetSource", src) end
function M.setRandomSource(lane, src) return setSource(lane, "randomSource", src) end
function M.setPreviousSource(lane, src) return setSource(lane, "previousSource", src) end
function M.setShiftSource(lane, src) return setSource(lane, "shiftSource", src) end
function M.setAddressSource(lane, src) return setSource(lane, "addressSource", src) end
function M.setXAddressSource(lane, src) return setSource(lane, "xAddressSource", src) end
function M.setYAddressSource(lane, src) return setSource(lane, "yAddressSource", src) end

function M.setShiftAmount(lane, steps)
    local l = lanep(lane); if not l then return false end
    l.shiftAmount = steps | 0
    return true
end

function M.setPosition(lane, step)
    local l = lanep(lane); if not l then return false end
    Lane.setPosition(l, step)
    return true
end

-- --------------------------------------------------------- step edits ---

function M.setPitch(lane, step, note)
    local l = lanep(lane); if not l or step < 1 or step > Lane.CAP then return false end
    l.pitch[step] = clamp(note, 0, 127)
    return true
end

function M.setVelocity(lane, step, v)
    local l = lanep(lane); if not l or step < 1 or step > Lane.CAP then return false end
    l.velocity[step] = clamp(v, 1, 127)
    return true
end

function M.setStepLength(lane, step, ticks)
    local l = lanep(lane); if not l or step < 1 or step > Lane.CAP then return false end
    l.stepLength[step] = math.max(1, ticks | 0)
    return true
end

function M.setValue(lane, step, v)
    local l = lanep(lane); if not l or step < 1 or step > Lane.CAP then return false end
    l.value[step] = clamp(v, 0, 127)
    return true
end

function M.setGate(lane, step, on)
    local l = lanep(lane); if not l or step < 1 or step > Lane.CAP then return false end
    l.gate[step] = (on == false or on == 0 or on == nil) and 0 or 1
    return true
end

-- --------------------------------------------------- sequence operations ---

local function forUsedSteps(lane, fn)
    local used = Lane.limit(lane)
    for i = 1, used do fn(i) end
end

function M.shred(lane)
    local l = lanep(lane); if not l then return false end
    local pos = l.position
    if l.type == "note" then
        l.pitch[pos] = Scales.quantize(math.random(l.minNote, l.maxNote), l.scaleMask)
        l.velocity[pos] = math.random(1, 127)
    elseif l.type == "mod" then
        l.value[pos] = math.random(l.minValue, l.maxValue)
    else
        l.gate[pos] = math.random(0, 1)
    end
    return true
end

function M.shredAll(lane)
    local l = lanep(lane); if not l then return false end
    local saved = l.position
    forUsedSteps(l, function(i)
        l.position = i
        M.shred(lane)
    end)
    l.position = saved
    return true
end

function M.zero(lane)
    local l = lanep(lane); if not l then return false end
    local pos = l.position
    if l.type == "note" then l.pitch[pos] = l.minNote
    elseif l.type == "mod" then l.value[pos] = l.minValue
    else l.gate[pos] = 0 end
    return true
end

function M.nudge(lane)
    local l = lanep(lane); if not l then return false end
    local pos = l.position
    local d = math.random(-2, 2)
    if l.type == "note" then l.pitch[pos] = clamp(l.pitch[pos] + d, 0, 127)
    elseif l.type == "mod" then l.value[pos] = clamp(l.value[pos] + d, 0, 127)
    else if math.random() < 0.5 then l.gate[pos] = 0 else l.gate[pos] = 1 end end
    return true
end

function M.rotate(lane, steps)
    local l = lanep(lane); if not l then return false end
    Lane.rotate(l, steps | 0)
    return true
end

function M.offset(lane, delta)
    local l = lanep(lane); if not l then return false end
    forUsedSteps(l, function(i)
        if l.type == "note" then l.pitch[i] = clamp(l.pitch[i] + delta, 0, 127)
        elseif l.type == "mod" then l.value[i] = clamp(l.value[i] + delta, 0, 127) end
    end)
    return true
end

function M.ramp(lane)
    local l = lanep(lane); if not l then return false end
    local used = Lane.limit(l)
    for i = 1, used do
        local t = (i - 1) / (used - 1)
        if l.type == "note" then
            l.pitch[i] = clamp(math.floor(l.minNote + t * (l.maxNote - l.minNote)), 0, 127)
        elseif l.type == "mod" then
            l.value[i] = clamp(math.floor(l.minValue + t * (l.maxValue - l.minValue)), 0, 127)
        end
    end
    return true
end

function M.hill(lane)
    local l = lanep(lane); if not l then return false end
    local used = Lane.limit(l)
    for i = 1, used do
        local t = (i - 1) / (used - 1)
        t = 1 - math.abs(2 * t - 1)
        if l.type == "note" then
            l.pitch[i] = clamp(math.floor(l.minNote + t * (l.maxNote - l.minNote)), 0, 127)
        elseif l.type == "mod" then
            l.value[i] = clamp(math.floor(l.minValue + t * (l.maxValue - l.minValue)), 0, 127)
        end
    end
    return true
end

function M.boost(lane, factor)
    local l = lanep(lane); if not l then return false end
    forUsedSteps(l, function(i)
        if l.type == "note" then l.pitch[i] = clamp(math.floor(l.pitch[i] * factor), 0, 127)
        elseif l.type == "mod" then l.value[i] = clamp(math.floor(l.value[i] * factor), 0, 127) end
    end)
    return true
end

function M.copy(from, to)
    local src, dst = lanep(from), lanep(to)
    if not src or not dst then return false end
    local used = Lane.limit(dst)
    for i = 1, Lane.CAP do
        dst.pitch[i] = src.pitch[i]
        dst.velocity[i] = src.velocity[i]
        dst.stepLength[i] = src.stepLength[i]
        dst.value[i] = src.value[i]
        dst.gate[i] = src.gate[i]
    end
    dst.type = src.type
    dst.scaleMask, dst.rawScaleMask, dst.root = src.scaleMask, src.rawScaleMask, src.root
    dst.minNote, dst.maxNote = src.minNote, src.maxNote
    dst.minValue, dst.maxValue = src.minValue, src.maxValue
    dst.controller = src.controller
    dst.length = src.length
    dst.division = src.division
    if (dst.width * dst.height) < used then dst.length = dst.width * dst.height end
    return true
end

function M.generate(lane, opts)
    return false   -- Euclidean/Gamut generators land in M4
end

-- ------------------------------------------------------------ presets ---

function M.loadPreset(data)
    if type(data) ~= "table" or type(data.lanes) ~= "table" then return false end
    for i = 1, #M.lanes do
        local p = data.lanes[i]
        if type(p) == "table" then
            local l = M.lanes[i]
            if p.type then M.setType(i, p.type) end
            if p.dims then M.setDimensions(i, p.dims) end
            if p.length then M.setLength(i, p.length) end
            if p.division then M.setDivision(i, p.division) end
            if p.channel then M.setChannel(i, p.channel) end
            if p.controller then M.setController(i, p.controller) end
            if p.midiNote then M.setMidiNote(i, p.midiNote) end
            if p.scaleMask then M.setScale(i, p.scaleMask, p.root or 0) end
            if p.advanceSource then M.setAdvanceSource(i, p.advanceSource) end
            if p.xAdvanceSource then M.setXAdvanceSource(i, p.xAdvanceSource) end
            if p.yAdvanceSource then M.setYAdvanceSource(i, p.yAdvanceSource) end
            if p.resetSource then M.setResetSource(i, p.resetSource) end
            if p.randomSource then M.setRandomSource(i, p.randomSource) end
            if p.previousSource then M.setPreviousSource(i, p.previousSource) end
            if p.shiftSource then M.setShiftSource(i, p.shiftSource) end
            if p.shiftAmount then M.setShiftAmount(i, p.shiftAmount) end
            if p.addressSource then M.setAddressSource(i, p.addressSource) end
            if p.xAddressSource then M.setXAddressSource(i, p.xAddressSource) end
            if p.yAddressSource then M.setYAddressSource(i, p.yAddressSource) end
            if p.minNote or p.maxNote then M.setRange(i, p.minNote or 0, p.maxNote or 127) end
            if p.pitch then for k = 1, #p.pitch do l.pitch[k] = p.pitch[k] end end
            if p.velocity then for k = 1, #p.velocity do l.velocity[k] = p.velocity[k] end end
            if p.stepLength then for k = 1, #p.stepLength do l.stepLength[k] = p.stepLength[k] end end
            if p.value then for k = 1, #p.value do l.value[k] = p.value[k] end end
            if p.gate then for k = 1, #p.gate do l.gate[k] = p.gate[k] end end
        end
    end
    return true
end

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
function M.dump() return M.lanes, M.out end

return M
