-- utils.lua
-- Shared utility functions. No sequencer-specific logic here.
-- Reusable across future Grid projects.

local Utils = {}

-- Creates a table of `n` elements all set to `default`.
function Utils.tableNew(n, default)
    assert(type(n) == "number" and n > 0, "tableNew: n must be a positive number")
    local t = {}
    for i = 1, n do
        t[i] = default
    end
    return t
end

-- Returns a shallow copy of table `t`.
function Utils.tableCopy(t)
    assert(type(t) == "table", "tableCopy: argument must be a table")
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = v
    end
    return copy
end

-- Clamps integer `value` to the range [min, max].
function Utils.clamp(value, min, max)
    assert(type(value) == "number", "clamp: value must be a number")
    assert(type(min) == "number", "clamp: min must be a number")
    assert(type(max) == "number", "clamp: max must be a number")
    if value < min then return min end
    if value > max then return max end
    return value
end

return Utils
