-- pattern.lua — a polyphonic, grid-free pattern.
--
-- A pattern owns a note store (event.lua), a loop length in STEPS, and a zoom
-- that maps steps to ticks. Loop length in ticks = steps * ticksPerStep(zoom).
--
--   loopTicks = length * zoom   (zoom stored directly as ticks-per-step)
--
-- Zoom ladder (M1 subset of Hermod's, at 24 PPQN):
--   /2  = 12 ticks/step (1/8),  x1 = 6 (1/16),
--   2/3 = 4  ticks/step (1/16T), x2 = 3 (1/32).
--
-- Per-pattern effect-parameter overrides ("pattern values", Hermod §3.5) are a
-- later milestone (they only matter with >1 pattern per track, i.e. M4). The
-- field is reserved here so the shape is stable.

local Event = require("event")

local M = {}

M.ZOOM = { { name = "/2", tps = 12 }, { name = "x1", tps = 6 },
           { name = "2/3", tps = 4 }, { name = "x2", tps = 3 } }

function M.new(opts)
    opts = opts or {}
    return {
        events   = Event.new(opts.cap or 256),
        length   = opts.length or 16, -- steps
        zoom     = opts.zoom or 6,     -- ticks per step (x1 default)
        fxValues = nil,                -- reserved: per-pattern fx overrides (M4)
    }
end

function M.loopTicks(p)
    return p.length * p.zoom
end

return M
