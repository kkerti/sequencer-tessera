-- mock_engine.lua — harness-only state provider with the action-API surface.
--
-- Substitutes the real Core in grid-wasm (the VM heap cannot hold the full
-- core's bytecode plus the GUI; see SCREENS.md). Same names, same lane shape
-- as src/core/lane.lua, so the GUI host code is identical on device.
local M = {}
M.lanes = {}
M.running = false

local DIMS = {
    ["16x1"] = { width = 16, height = 1 },
    ["8x2"]  = { width = 8,  height = 2 },
    ["5x3"]  = { width = 5,  height = 3 },
    ["4x3"]  = { width = 4,  height = 3 },
    ["4x4"]  = { width = 4,  height = 4 },
}

local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

function M.init(opts)
    opts = opts or {}
    local count = opts.lanes or 4
    local baseChannel = opts.channel or 1
    for i = 1, count do
        M.lanes[i] = {
            type = "note", dims = "16x1", width = 16, height = 1,
            length = 16, division = 1, divCount = 0,
            position = 1, channel = baseChannel + i - 1,
            controller = 1, midiNote = 60,
            scaleMask = 0xAB5, root = 0,
            minNote = 0, maxNote = 127, minValue = 0, maxValue = 127,
            pitch = {}, velocity = {}, stepLength = {}, value = {}, gate = {},
        }
        for s = 1, 16 do
            local l = M.lanes[i]
            l.pitch[s] = 60; l.velocity[s] = 100; l.stepLength[s] = 6
            l.value[s] = 0; l.gate[s] = 0
        end
    end
    M.running = false
    if not opts.demo then return M end
    -- harness demo pattern (mock-only): 1 note, 2 trig 4x4, 3 mod 8x2, 4 gate 4x3
    local melody = { 60, 62, 64, 67, 69, 67, 64, 62, 60, 64, 67, 72, 71, 67, 64, 60 }
    for i = 1, 16 do
        M.setPitch(1, i, melody[i])
        M.setVelocity(1, i, 70 + (i % 4) * 15)
        M.setStepLength(1, i, 6)
    end
    M.setType(2, "trig"); M.setDimensions(2, "4x4"); M.setDivision(2, 4)
    for i = 1, 16 do M.setGate(2, i, (i * 7) % 3 ~= 0 and 1 or 0) end
    M.setType(3, "mod"); M.setDimensions(3, "8x2")
    for i = 1, 16 do M.setValue(3, i, (i - 1) * 8) end
    M.setType(4, "gate"); M.setDimensions(4, "4x3"); M.setDivision(4, 2)
    for i = 1, 12 do M.setGate(4, i, (i % 4) < 2 and 1 or 0) end
    return M
end

function M.onStart() M.running = true end
function M.onStop()  M.running = false end
function M.start() return M.onStart() end
function M.stop()  return M.onStop() end
function M.tick()  return M.onPulse() end

local function used(l)
    if l.height == 1 then return l.length end
    return l.width * l.height
end

function M.onPulse()
    if not M.running then return end
    for i = 1, #M.lanes do
        local l = M.lanes[i]
        l.divCount = l.divCount + 1
        if l.divCount >= l.division then
            l.divCount = 0
            local p = l.position + 1
            if p > used(l) then p = 1 end
            l.position = p
        end
    end
end

function M.reset()
    for i = 1, #M.lanes do
        local l = M.lanes[i]
        l.position = 1; l.divCount = 0
    end
end

function M.state(lane) return M.lanes[lane] end

-- lane configuration
function M.setType(lane, kind)
    local l = M.lanes[lane]; if l then l.type = kind end
end
function M.setDimensions(lane, name)
    local l = M.lanes[lane]
    if l and DIMS[name] then
        l.dims = name; l.width = DIMS[name].width; l.height = DIMS[name].height
        l.position = clamp(l.position, 1, used(l))
    end
end
function M.setLength(lane, n)
    local l = M.lanes[lane]
    if l and l.height == 1 then l.length = clamp(n, 1, 16) end
end
function M.setDivision(lane, n)
    local l = M.lanes[lane]; if l then l.division = clamp(n, 1, 16) end
end
function M.setChannel(lane, ch)
    local l = M.lanes[lane]; if l then l.channel = clamp(ch, 1, 16) end
end
-- step edits
function M.setPitch(lane, step, v)
    local l = M.lanes[lane]; if l then l.pitch[step] = clamp(v, 0, 127) end
end
function M.setVelocity(lane, step, v)
    local l = M.lanes[lane]; if l then l.velocity[step] = clamp(v, 1, 127) end
end
function M.setStepLength(lane, step, t)
    local l = M.lanes[lane]; if l then l.stepLength[step] = clamp(t, 1, 96) end
end
function M.setValue(lane, step, v)
    local l = M.lanes[lane]; if l then l.value[step] = clamp(v, 0, 127) end
end
function M.setGate(lane, step, on)
    local l = M.lanes[lane]; if l then l.gate[step] = (on == 1 or on == true) and 1 or 0 end
end
function M.setPosition(lane, step)
    local l = M.lanes[lane]; if l then l.position = clamp(step, 1, used(l)) end
end

-- sequence ops (the ones the control map uses); semantics match
-- src/core/engine.lua shred/zero
function M.shred(lane)
    local l = M.lanes[lane]; if not l then return end
    local pos = l.position
    if l.type == "note" then
        l.pitch[pos] = math.random(0, 127)
        l.velocity[pos] = math.random(1, 127)
    elseif l.type == "mod" then
        l.value[pos] = math.random(0, 127)
    else
        l.gate[pos] = math.random(0, 1)
    end
end
function M.zero(lane)
    local l = M.lanes[lane]; if not l then return end
    local pos = l.position
    if l.type == "note" then l.pitch[pos] = 0
    elseif l.type == "mod" then l.value[pos] = 0
    else l.gate[pos] = 0 end
end

return M