-- ext.lua — playhead addressing by value source (X/Y address). Split out of
-- engine.lua: the demo and step-edit paths never address, so this compiles
-- only when an address source is first SET (the address setters load it) and
-- the pulse path pays one cached-field check per lane.
--
-- Shape: factory(engine, tool) -> applyAll(lane). tool.srcVal resolves a
-- value source (the engine's sourceValue). Sources.OFF is 0.

-- (Sources is required only for documentation parity; OFF is inlined as 0 in
-- the returned closure so this module needs no runtime dependency.)


return function(E, tool)
    local srcVal = tool.srcVal

    local function applyAddress(lane, src)
        local v = srcVal(src)
        if not v then return end
        local used = lane.width * lane.height
        local pos = (v * used) // 127 + 1
        if pos > used then pos = used end
        if pos < 1 then pos = 1 end
        if pos ~= lane.position then
            lane.position = pos
            lane.emit = true
        end
    end

    local function applyXAddress(lane, src)
        local v = srcVal(src)
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
        local v = srcVal(src)
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

    -- one entry point for the pulse hook; Sources.OFF == 0
    return function(l)
        if l.addressSource ~= 0 then applyAddress(l, l.addressSource) end
        if l.xAddressSource ~= 0 then applyXAddress(l, l.xAddressSource) end
        if l.yAddressSource ~= 0 then applyYAddress(l, l.yAddressSource) end
    end
end
