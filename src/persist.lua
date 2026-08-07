-- persist.lua
-- Save / load engine state to/from disk. The ONLY Core module that does IO.
--
-- Format: the saved file is a Lua chunk that returns a table:
--   { swing=<int>, tracks={ {chan,lastStep, steps={i1,i2,...,i64}}, ... } }
--
-- Rationale (over binary): zero parser code — `load()` does it. Save state
-- is ~265 ints, so byte-size is irrelevant; what matters is that the
-- code in the Core bundle stays tiny.
--
-- Triggered by user action (SHIFT+key 7 = save) or boot (autoload).
-- Never called per pulse. Pure-playback path never touches this module
-- unless boot autoload runs once.

local Engine = require("engine")

local M = {}

function M.save(path)
    local f = io.open(path, "w")
    if not f then return false end
    f:write("return{swing=", Engine.swing, ",tracks={")
    for ti = 1, #Engine.tracks do
        local tr = Engine.tracks[ti]
        f:write("{chan=", tr.chan, ",lastStep=", tr.lastStep, ",scale=", tr.scale, ",steps={")
        local s = tr.steps
        for i = 1, tr.cap do
            if i > 1 then f:write(",") end
            f:write(s[i])
        end
        f:write("}},")
    end
    f:write("}}")
    f:close()
    return true
end

function M.load(path)
    local f = io.open(path, "r")
    if not f then return false end
    local src = f:read("*a")
    f:close()
    local chunk, _ = load(src, "save", "t")
    if not chunk then return false end
    local ok, data = pcall(chunk)
    if not ok or type(data) ~= "table" or type(data.tracks) ~= "table" then
        return false
    end
    -- Apply in place: preserves runtime fields (pos, stepAcc, etc.) and
    -- the existing track table identities the UI may already hold refs to.
    if type(data.swing) == "number" then Engine.setSwing(data.swing | 0) end
    for ti = 1, #Engine.tracks do
        local td = data.tracks[ti]
        if type(td) == "table" then
            local tr = Engine.tracks[ti]
            if type(td.chan) == "number" then
                Engine.setTrackChan(ti, td.chan | 0)
            end
            if type(td.lastStep) == "number" then
                Engine.setLastStep(ti, td.lastStep | 0)
            end
            if type(td.scale) == "number" then
                Engine.setTrackScale(ti, td.scale | 0)
            end
            if type(td.steps) == "table" then
                local ds = td.steps
                local s = tr.steps
                for i = 1, tr.cap do
                    local v = ds[i]
                    if type(v) == "number" then s[i] = v | 0 end
                end
            end
        end
    end
    return true
end

return M
