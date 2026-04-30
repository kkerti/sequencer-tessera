-- step.lua
-- Packed-int step encode/decode. Lua 5.4 native 64-bit ints.
--
-- bit layout (LSB = 0):
--   0-6   pitch        7b 0..127
--   7-13  velocity     7b 0..127
--   14-20 duration     7b 0..127 pulses
--   21-27 gate         7b 0..127 pulses
--   28    ratchet      1b
--   29    active       1b
--   30-36 probability  7b 0..127
--
-- One Lua integer per step. No tables.

local M = {}

local band, bor, shl, shr = (bit32 and bit32.band) or function(a,b) return a & b end,
                            (bit32 and bit32.bor)  or function(a,b) return a | b end,
                            (bit32 and bit32.lshift) or function(a,n) return a << n end,
                            (bit32 and bit32.rshift) or function(a,n) return a >> n end

local M7 = 0x7F  -- 7-bit mask

-- shifts
local SH_PITCH = 0
local SH_VEL   = 7
local SH_DUR   = 14
local SH_GATE  = 21
local SH_RAT   = 28
local SH_ACT   = 29
local SH_PROB  = 30

local function clamp7(v) if v < 0 then return 0 elseif v > 127 then return 127 else return v end end
local function clamp1(v) if v and v ~= 0 then return 1 else return 0 end end

-- pack with named fields
function M.pack(t)
    local p = clamp7(t.pitch or 60)
    local v = clamp7(t.vel or 100)
    local d = clamp7(t.dur or 6)
    local g = clamp7(t.gate or 3)
    local r = clamp1(t.ratch)
    local a = clamp1(t.active ~= false and 1 or 0)
    local pr = clamp7(t.prob or 127)
    return shl(p, SH_PITCH) | shl(v, SH_VEL) | shl(d, SH_DUR) | shl(g, SH_GATE)
         | shl(r, SH_RAT)   | shl(a, SH_ACT) | shl(pr, SH_PROB)
end

-- field getters (cheap, inline-friendly)
function M.pitch(s)   return band(shr(s, SH_PITCH), M7) end
function M.vel(s)     return band(shr(s, SH_VEL),   M7) end
function M.dur(s)     return band(shr(s, SH_DUR),   M7) end
function M.gate(s)    return band(shr(s, SH_GATE),  M7) end
function M.ratch(s)   return band(shr(s, SH_RAT),   1) == 1 end
function M.active(s)  return band(shr(s, SH_ACT),   1) == 1 end
function M.prob(s)    return band(shr(s, SH_PROB),  M7) end

-- field setters return a new packed int
local function setField(s, shift, mask, value)
    return (s & ~shl(mask, shift)) | shl(value & mask, shift)
end

local FIELD = {
    pitch  = { SH_PITCH, M7, clamp7 },
    vel    = { SH_VEL,   M7, clamp7 },
    dur    = { SH_DUR,   M7, clamp7 },
    gate   = { SH_GATE,  M7, clamp7 },
    ratch  = { SH_RAT,   1,  clamp1 },
    active = { SH_ACT,   1,  clamp1 },
    prob   = { SH_PROB,  M7, clamp7 },
}

function M.set(s, name, value)
    local f = FIELD[name]; if not f then return s end
    return setField(s, f[1], f[2], f[3](value))
end

function M.get(s, name)
    if name == "pitch"  then return M.pitch(s)
    elseif name == "vel"    then return M.vel(s)
    elseif name == "dur"    then return M.dur(s)
    elseif name == "gate"   then return M.gate(s)
    elseif name == "ratch"  then return M.ratch(s) and 1 or 0
    elseif name == "active" then return M.active(s) and 1 or 0
    elseif name == "prob"   then return M.prob(s)
    end
end

M.FIELDS = { "pitch", "vel", "dur", "gate", "ratch", "active", "prob" }

return M
