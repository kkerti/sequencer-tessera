-- sources.lua — source enums and string parsing.
--
-- Sources drive a lane's advance/reset/random/previous/shift (trigger sources)
-- or address its playhead (value sources). The public vocabulary is readable
-- strings (see docs/NAMING.md); the engine stores small integers. Parsing
-- happens only at the API boundary, never on the pulse path.

local M = {}

M.OFF                 = 0
M.TRANSPORT_WHOLE     = 1
M.TRANSPORT_HALF      = 2
M.TRANSPORT_QUARTER   = 3
M.TRANSPORT_EIGHTH    = 4
M.TRANSPORT_SIXTEENTH = 5
M.EXTERNAL_FIRST      = 6          -- +0 .. +7
M.EXTERNAL_LAST       = 13
M.EXTERNAL_COUNT      = 8
M.LANE_FIRST          = 14         -- +0 .. +3
M.LANE_LAST           = 17
M.LANE_COUNT          = 4

-- Pulse interval per transport tap at 24 PPQN in 4/4.
M.TRANSPORT_INTERVAL = {
    [M.TRANSPORT_WHOLE]     = 96,
    [M.TRANSPORT_HALF]      = 48,
    [M.TRANSPORT_QUARTER]   = 24,
    [M.TRANSPORT_EIGHTH]    = 12,
    [M.TRANSPORT_SIXTEENTH] = 6,
}

local NAMES = {
    ["off"]                 = M.OFF,
    ["transport.whole"]     = M.TRANSPORT_WHOLE,
    ["transport.half"]      = M.TRANSPORT_HALF,
    ["transport.quarter"]   = M.TRANSPORT_QUARTER,
    ["transport.eighth"]    = M.TRANSPORT_EIGHTH,
    ["transport.sixteenth"] = M.TRANSPORT_SIXTEENTH,
}
for i = 0, M.EXTERNAL_COUNT - 1 do
    NAMES["external." .. i] = M.EXTERNAL_FIRST + i
end
for i = 0, M.LANE_COUNT - 1 do
    NAMES["lane." .. (i + 1)] = M.LANE_FIRST + i
end

function M.parse(value, default)
    if type(value) == "number" then return value end
    local v = NAMES[value]
    if v == nil then return default or M.OFF end
    return v
end

function M.isTransport(src)
    return src >= M.TRANSPORT_WHOLE and src <= M.TRANSPORT_SIXTEENTH
end

function M.isExternal(src)
    return src >= M.EXTERNAL_FIRST and src <= M.EXTERNAL_LAST
end

function M.isLane(src)
    return src >= M.LANE_FIRST and src <= M.LANE_LAST
end

return M
