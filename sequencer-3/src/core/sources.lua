-- sources.lua — source enums and string parsing.
--
-- Sources drive a lane's advance/reset/random/previous/shift. Every source is
-- a transport tap or OFF: lane->lane routing, external MIDI sources and value
-- addressing were cut for device RAM. The public vocabulary is readable
-- strings (see docs/NAMING.md); the engine stores small integers. Parsing
-- happens only at the API boundary, never on the pulse path.

local M = {}

M.OFF                 = 0
M.TRANSPORT_WHOLE     = 1
M.TRANSPORT_HALF      = 2
M.TRANSPORT_QUARTER   = 3
M.TRANSPORT_EIGHTH    = 4
M.TRANSPORT_SIXTEENTH = 5

-- Pulse interval per transport tap at 24 PPQN in 4/4.
M.TRANSPORT_INTERVAL = {
    [M.TRANSPORT_WHOLE]     = 96,
    [M.TRANSPORT_HALF]      = 48,
    [M.TRANSPORT_QUARTER]   = 24,
    [M.TRANSPORT_EIGHTH]    = 12,
    [M.TRANSPORT_SIXTEENTH] = 6,
}

-- Strings live in source_names.lua (lazy, the persist bundle on device):
-- the device passes numeric sources, so the name table is never built there.
function M.parse(value, default)
    if type(value) == "number" then return value end
    local v = require("source_names").names[value]
    if v == nil then return default or M.OFF end
    return v
end

-- Reverse lookup for persist/GUI display: enum -> the public string.
function M.name(src)
    return require("source_names").reverse[src] or "off"
end

return M
