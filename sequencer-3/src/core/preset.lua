-- preset.lua — preset loading (Engine.loadPreset) + the copy op. Split from
-- ops.lua: rarely used on the device, so it only compiles when a preset load
-- or lane copy is actually requested (via engine __index).
--
-- Shape: factory(engine, tool) -> table with loadPreset/copy. The generic
-- setters used here live on the engine (E.set*), so no extra upvalues needed.

local Lane = require("lane")

return function(E, tool)
    local lanep, clamp = tool.lanep, tool.clamp
    local M = {}

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

    function M.loadPreset(data)
        if type(data) ~= "table" or type(data.lanes) ~= "table" then return false end
        for i = 1, #E.lanes do
            local p = data.lanes[i]
            if type(p) == "table" then
                local l = E.lanes[i]
                if p.type then E.setType(i, p.type) end
                if p.dims then E.setDimensions(i, p.dims) end
                if p.length then E.setLength(i, p.length) end
                if p.division then E.setDivision(i, p.division) end
                if p.channel then E.setChannel(i, p.channel) end
                if p.controller then E.setController(i, p.controller) end
                if p.midiNote then E.setMidiNote(i, p.midiNote) end
                if p.scaleMask then E.setScale(i, p.scaleMask, p.root or 0) end
                if p.advanceSource then E.setAdvanceSource(i, p.advanceSource) end
                if p.xAdvanceSource then E.setXAdvanceSource(i, p.xAdvanceSource) end
                if p.yAdvanceSource then E.setYAdvanceSource(i, p.yAdvanceSource) end
                if p.resetSource then E.setResetSource(i, p.resetSource) end
                if p.randomSource then E.setRandomSource(i, p.randomSource) end
                if p.previousSource then E.setPreviousSource(i, p.previousSource) end
                if p.shiftSource then E.setShiftSource(i, p.shiftSource) end
                if p.shiftAmount then E.setShiftAmount(i, p.shiftAmount) end
                if p.addressSource then E.setAddressSource(i, p.addressSource) end
                if p.xAddressSource then E.setXAddressSource(i, p.xAddressSource) end
                if p.yAddressSource then E.setYAddressSource(i, p.yAddressSource) end
                -- Ranges are set per type directly (E.setRange routes by lane
                -- type, which would mislabel a Mod lane's pair on reload).
                if p.minNote or p.maxNote then
                    l.minNote = clamp(p.minNote or 0, 0, 127)
                    l.maxNote = clamp(p.maxNote or 127, 0, 127)
                end
                if p.minValue or p.maxValue then
                    l.minValue = clamp(p.minValue or 0, 0, 127)
                    l.maxValue = clamp(p.maxValue or 127, 0, 127)
                end
                if p.pitch then for k = 1, #p.pitch do l.pitch[k] = p.pitch[k] end end
                if p.velocity then for k = 1, #p.velocity do l.velocity[k] = p.velocity[k] end end
                if p.stepLength then for k = 1, #p.stepLength do l.stepLength[k] = p.stepLength[k] end end
                if p.value then for k = 1, #p.value do l.value[k] = p.value[k] end end
                if p.gate then for k = 1, #p.gate do l.gate[k] = p.gate[k] end end
                if p.generate then E.generate(i, p.generate) end
            end
        end
        return true
    end

    return M
end
