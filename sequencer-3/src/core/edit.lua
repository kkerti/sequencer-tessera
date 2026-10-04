-- edit.lua — the engine's setters: lane config, sources, step edits.
--
-- LAZY, in the editing bundle (seq3x on the device): app start never calls a
-- setter (the device demo and the headless sequence write lane fields
-- directly), so the start chain never compiles this. engine.lua resolves any
-- missing `set*` key through its __index on first use and caches it.
--
-- Shape: a factory taking the engine and a small toolbox (the upvalues the
-- setters need from engine.lua), returning the setter table.

local Sources = require("sources")
local Scales  = require("scales")
local Lane    = require("lane")

return function(E, tool)
    local lanep, clamp = tool.lanep, tool.clamp
    local M = {}

    function M.setType(lane, kind)
        local l = lanep(lane); if not l then return false end
        -- old slots may say "mod"/"gate": they load as note/trig
        l.type = (kind == "trig" or kind == "gate") and "trig" or "note"
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

    -- Table-driven setters. Every setter built in a loop shares ONE compiled
    -- function prototype (each name costs only a closure), where a hand-written
    -- `function M.setX` costs a whole prototype apiece (~435 B measured, x28).
    -- Clamped lane fields: name -> { field, lo, hi }.
    for name, f in pairs{ Division = { "division", 1, 16 }, Channel = { "channel", 1, 16 },
        MidiNote = { "midiNote", 0, 127 } } do
        local field, lo, hi = f[1], f[2], f[3]
        M["set" .. name] = function(lane, v)
            local l = lanep(lane); if not l then return false end
            l[field] = clamp(v, lo, hi)
            return true
        end
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
        l.minNote = clamp(min, 0, 127); l.maxNote = clamp(max, 0, 127)
        return true
    end

    -- Source setters: setAdvanceSource -> l.advanceSource, etc.
    for _, name in ipairs{ "Advance", "XAdvance", "YAdvance", "Reset", "Random",
        "Previous", "Shift" } do
        local field = name:sub(1, 1):lower() .. name:sub(2) .. "Source"
        M["set" .. name .. "Source"] = function(lane, src)
            local l = lanep(lane); if not l then return false end
            l[field] = Sources.parse(src)
            return true
        end
    end

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

    -- Clamped step arrays: name -> { array, lo, hi }.
    for name, f in pairs{ Pitch = { "pitch", 0, 127 }, Velocity = { "velocity", 1, 127 } } do
        local field, lo, hi = f[1], f[2], f[3]
        M["set" .. name] = function(lane, step, v)
            local l = lanep(lane); if not l or step < 1 or step > Lane.CAP then return false end
            l[field][step] = clamp(v, lo, hi)
            return true
        end
    end

    function M.setStepLength(lane, step, ticks)
        local l = lanep(lane); if not l or step < 1 or step > Lane.CAP then return false end
        l.stepLength[step] = math.max(1, ticks | 0)
        return true
    end

    function M.setGate(lane, step, on)
        local l = lanep(lane); if not l or step < 1 or step > Lane.CAP then return false end
        l.gate[step] = (on == false or on == 0 or on == nil) and 0 or 1
        return true
    end

    return M
end
