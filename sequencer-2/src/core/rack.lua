-- rack.lua — a track's ordered effect chain (<= 8 slots).
--
-- Order is semantically significant (Hermod §3.1). run() folds every effect
-- over the shared scratch buffer in slot order; effects mutate it in place and
-- may shrink it (RANDOM/CHANCE drop notes). No allocation on the hot path.
--
-- Default M1 chain, built by track.lua: RANGE -> RANDOM -> SCALE
-- (limit, vary, then quantize last so output is always in key).

local M = {}

local MAX_SLOTS = 8

function M.new()
    return { n = 0, fx = {} }
end

function M.add(rack, effect)
    if rack.n >= MAX_SLOTS then return false end
    rack.n = rack.n + 1
    rack.fx[rack.n] = effect
    return true
end

function M.run(rack, buf)
    local fx = rack.fx
    for i = 1, rack.n do
        fx[i]:process(buf)
    end
end

return M
