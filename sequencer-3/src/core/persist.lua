-- persist.lua — save/load engine state as Lua chunks. The only Core module
-- that does IO, and never on the pulse path.
--
-- Format: a Lua chunk returning { version=1, lanes={ ... } }. Slots live under
-- presets/NN.lua. Load applies through Engine.loadPreset, preserving the
-- runtime lane table identities.

local Engine = require("engine")

local M = {}

function M.slotPath(slot)
    if type(slot) == "number" then
        return string.format("presets/%02d.lua", slot)
    end
    return "presets/" .. tostring(slot)
end

function M.save(path)
    local f = io.open(path, "w")
    if not f then return false end
    f:write("return{\n  version=1,\n  lanes={\n")
    for i = 1, #Engine.lanes do
        local l = Engine.lanes[i]
        f:write("    {type=\"", l.type, "\",channel=", l.channel,
                ",dims=\"", l.dims, "\",length=", l.length,
                ",division=", l.division,
                ",scaleMask=", l.rawScaleMask, ",root=", l.root,
                ",pitch={")
        for k = 1, 16 do f:write(l.pitch[k], k < 16 and "," or "") end
        f:write("},velocity={")
        for k = 1, 16 do f:write(l.velocity[k], k < 16 and "," or "") end
        f:write("},stepLength={")
        for k = 1, 16 do f:write(l.stepLength[k], k < 16 and "," or "") end
        f:write("},value={")
        for k = 1, 16 do f:write(l.value[k], k < 16 and "," or "") end
        f:write("},gate={")
        for k = 1, 16 do f:write(l.gate[k], k < 16 and "," or "") end
        f:write("}},\n")
    end
    f:write("  },\n}\n")
    f:close()
    return true
end

function M.load(path)
    local f = io.open(path, "r")
    if not f then return false end
    local src = f:read("*a")
    f:close()
    local chunk = load(src, "preset", "t")
    if not chunk then return false end
    local ok, data = pcall(chunk)
    if not ok then return false end
    return Engine.loadPreset(data)
end

return M
