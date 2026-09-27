-- ops.lua — the engine's sequence operations, split out of engine.lua.
--
-- LAZY: required by engine.lua on the FIRST call to one of these actions (via
-- its __index), never at setup — the pulse path never calls them, and each
-- resident module costs RAM on the device (measurements in dist/README.md).
-- Slimmed for the device budget: only the ops the control map uses
-- (shred / zero / rotate). Copy/preset moved to preset.lua; the generate/
   -- ramp/hill/boost family lives in git history if needed again.
--
-- Shape: a factory taking the engine and a small toolbox (the upvalues the
-- ops need from engine.lua), returning the ops table. No state of its own.

local Lane = require("lane")

return function(E, tool)
    local lanep = tool.lanep
    local M = {}

    function M.shred(lane)
        local l = lanep(lane); if not l then return false end
        local pos = l.position
        if l.type == "note" then
            l.pitch[pos] = tool.clamp(math.random(l.minNote, l.maxNote), 0, 127)
            l.velocity[pos] = math.random(1, 127)
        elseif l.type == "mod" then
            l.value[pos] = math.random(l.minValue, l.maxValue)
        else
            l.gate[pos] = math.random(0, 1)
        end
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

    function M.rotate(lane, steps)
        local l = lanep(lane); if not l then return false end
        Lane.rotate(l, steps | 0)
        return true
    end

    return M
end
