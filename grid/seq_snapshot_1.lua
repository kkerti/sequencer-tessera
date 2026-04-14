local Snapshot=require("seq_snapshot")
local Engine=require("seq_engine")
local Track=require("seq_track")
local Pattern=require("seq_pattern")
local Step=require("seq_step")
function Snapshot._snapshotSerializeValue(value)
    local valueType = type(value)
    if valueType == "number" then
        return tostring(value)
    end
    if valueType == "boolean" then
        return value and "true" or "false"
    end
    if valueType == "string" then
        return string.format("%q", value)
    end
    if valueType == "table" then
        local parts = { "{" }
        for k, v in pairs(value) do
            local keyPart
            if type(k) == "string" then
                keyPart = "[" .. string.format("%q", k) .. "]"
            else
                keyPart = "[" .. tostring(k) .. "]"
            end
            parts[#parts + 1] = keyPart .. "=" .. snapshotSerializeValue(v) .. ","
        end
        parts[#parts + 1] = "}"
        return table.concat(parts)
    end
    error("snapshotSerializeValue: unsupported type " .. valueType)
end
