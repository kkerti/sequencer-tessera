-- generate.lua — one-shot pattern generator (authoring command, not an effect).
--
-- GENERATE overwrites a pattern's event store with a Euclidean rhythm whose
-- notes are drawn root ± spread for pitch (in scale DEGREES, in key), velocity,
-- and gate/length. Deterministic given `seed` so a REROLL (seed++) auditions
-- variants you can recall. Runs at edit time — never on the pulse hot path.
--
--   Generate.run(pattern, opts) -> noteCount
--   opts (all optional; sensible musical defaults):
--     scaleIndex, root   scale + key for in-scale pitch (default off/C)
--     hits, rotate       Euclidean onsets over the pattern's length, rotated
--     pitchRoot, pitchSpread   center MIDI pitch, ± scale degrees
--     velRoot,  velSpread      center velocity 1..127, ± amount
--     gateRoot, gateSpread     center note length in TICKS, ± amount
--     seed               RNG seed (int); same seed => same pattern

local Event  = require("event")
local Scales = require("scales")

local M = {}

-- Euclidean onset test: true if step i (0..M-1) is a hit of E(hits, M).
local function isOnset(i, hits, M_)
    if hits <= 0 then return false end
    if hits >= M_ then return true end
    return (i * hits) // M_ ~= ((i - 1) * hits) // M_
end

function M.run(pattern, opts)
    opts = opts or {}
    local ev  = pattern.events
    local M_  = pattern.length            -- steps (Euclid's M)
    local tps = pattern.zoom              -- ticks per step
    local scaleIndex = opts.scaleIndex or 1
    local root  = (opts.root or 0) % 12
    local mask  = Scales.rotate((Scales.SCALES[scaleIndex] or Scales.SCALES[1]).mask, root)

    local hits   = opts.hits   or math.max(1, M_ // 4)
    local rotate = (opts.rotate or 0) % M_
    local pRoot  = opts.pitchRoot   or (57 + root)   -- ~A3 in the chosen key
    local pSpr   = opts.pitchSpread  or 4            -- scale degrees
    local vRoot  = opts.velRoot     or 100
    local vSpr   = opts.velSpread    or 20
    local gRoot  = opts.gateRoot    or tps           -- one step
    local gSpr   = opts.gateSpread   or (tps // 2)

    -- per-run LCG (alloc-free, deterministic from seed)
    local seed = (opts.seed or 1) & 0xFFFFFFFF
    local function rnd() seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF; return (seed >> 16) & 0x7FFF end
    local function ri(lo, hi) if hi <= lo then return lo end return lo + rnd() % (hi - lo + 1) end

    Event.clear(ev)                       -- overwrite
    local count = 0
    for i = 0, M_ - 1 do
        if isOnset(i, hits, M_) then
            local s = (i + rotate) % M_
            local pitch = Scales.step(pRoot, mask, ri(-pSpr, pSpr))
            local vel = vRoot + ri(-vSpr, vSpr)
            if vel < 1 then vel = 1 elseif vel > 127 then vel = 127 end
            local gate = gRoot + ri(-gSpr, gSpr)
            if gate < 1 then gate = 1 end
            Event.add(ev, pitch, s * tps, gate, vel)
            count = count + 1
        end
    end
    return count
end

return M
