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
-- Loop region — a saved sub-range of the pattern's steps that plays in a tight
-- loop when active, instead of the full pattern. Defaults to inactive (the
-- whole pattern). `loopEnd >= length` means inactive at runtime (so editing
-- length later can't leave a stale equality). See docs/ARCHITECTURE.md §11.2.
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
    local length = opts.length or 16
    return {
        events    = Event.new(opts.cap or 256),
        length    = length,             -- steps
        zoom      = opts.zoom or 6,     -- ticks per step (x1 default)
        loopStart = opts.loopStart or 0,   -- steps (0 = first step)
        loopEnd   = opts.loopEnd or length, -- steps; >= length => inactive
        fxValues  = nil,                -- reserved: per-pattern fx overrides (M4)
    }
end

-- Full loop length in ticks (loop region ignored).
function M.loopTicks(p)
    return p.length * p.zoom
end

-- Loop window as (startTick, loopLen): the playhead runs
-- [startTick, startTick + loopLen). Respects the loop region when active.
-- Single source of truth for playback wrap (track.advance).
function M.loopWindow(p)
    local le = p.loopEnd or p.length
    if le < p.length then
        local ls = p.loopStart or 0
        local len = (le - ls) * p.zoom
        if len < 1 then len = 1 end
        return ls * p.zoom, len
    end
    return 0, p.length * p.zoom
end

-- STEP-mode selection: convert a step position to an event index.
-- Off the hot path; events are sorted by start, so a linear scan is fine.
-- Returns the index of the first event whose start == step * zoom, else nil.
function M.findEventAtStep(p, step, zoom)
    local tick = step * zoom
    local ev = p.events
    for i = 1, ev.n do
        if ev.start[i] == tick then return i end
    end
    return nil
end

return M
