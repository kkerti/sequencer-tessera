-- controls.lua
-- Grid VSN1 UI. Reads engine.tracks tables; calls engine setters.
-- Core has zero knowledge of this file.
--
-- Hardware:
--   - 320x240 LCD, 4x2 grid layout (per LIB-2-HW-MAP.md)
--   - 4 small buttons under screen + 8 keyswitches
--   - Endless jog wheel (relative: 65 = up, 63 = down) with click
--
-- 4x2 cells (top row, bottom row):
--   TRACK | STEP  | NOTE  | VEL
--   DUR   | GATE  | RATCH | PROB
--
-- Endless turns the parameter the user last touched.
-- Each cell shows label + value. Active cell drawn red, others grey-white.
-- Surgical redraw: only invalidated cells re-rendered each draw cycle.

local Engine = require("engine")
local Track  = require("track")
local Step   = require("step")

local M = {}

-- ---- selection state (UI only; not in Core) ----
M.selT     = 1   -- selected track 1..4
M.selS     = 1   -- selected step 1..len
M.focus    = 3   -- index into CELLS below; default = NOTE

local CELLS = {
    -- {label, paramName, getter(t,s), setter(t,s,delta), min, max}
    { "TRACK", "track", function(t,s) return t end,
      function(t,s,d) M.selT = ((t - 1 + d) % 4) + 1 end, 1, 4 },
    { "STEP",  "step",  function(t,s) return s end,
      function(t,s,d)
          local tr = Engine.tracks[t]
          local n = (s - 1 + d) % tr.len
          M.selS = n + 1
      end, 1, 64 },
    { "NOTE",  "pitch",
      function(t,s) return Engine.tracks[t].steps[s] and Step.pitch(Engine.tracks[t].steps[s]) or 0 end,
      function(t,s,d)
          local cur = Step.pitch(Engine.tracks[t].steps[s])
          Engine.setStepParam(t, s, "pitch", cur + d)
      end, 0, 127 },
    { "VEL",   "vel",
      function(t,s) return Step.vel(Engine.tracks[t].steps[s]) end,
      function(t,s,d)
          local cur = Step.vel(Engine.tracks[t].steps[s])
          Engine.setStepParam(t, s, "vel", cur + d)
      end, 0, 127 },
    { "DUR",   "dur",
      function(t,s) return Step.dur(Engine.tracks[t].steps[s]) end,
      function(t,s,d)
          local cur = Step.dur(Engine.tracks[t].steps[s])
          Engine.setStepParam(t, s, "dur", cur + d)
      end, 1, 127 },
    { "GATE",  "gate",
      function(t,s) return Step.gate(Engine.tracks[t].steps[s]) end,
      function(t,s,d)
          local cur = Step.gate(Engine.tracks[t].steps[s])
          Engine.setStepParam(t, s, "gate", cur + d)
      end, 0, 127 },
    { "RATCH", "ratch",
      function(t,s) return Step.ratch(Engine.tracks[t].steps[s]) and 1 or 0 end,
      function(t,s,d)
          local cur = Step.ratch(Engine.tracks[t].steps[s]) and 1 or 0
          Engine.setStepParam(t, s, "ratch", (cur + d) % 2)
      end, 0, 1 },
    { "PROB",  "prob",
      function(t,s) return Step.prob(Engine.tracks[t].steps[s]) end,
      function(t,s,d)
          local cur = Step.prob(Engine.tracks[t].steps[s])
          Engine.setStepParam(t, s, "prob", cur + d)
      end, 0, 127 },
}

M.CELLS = CELLS

-- dirty flags: which cells need redraw
local dirty = { true, true, true, true, true, true, true, true }
local function dirtyAll() for i=1,8 do dirty[i] = true end end
M.dirtyAll = dirtyAll

-- ---- input handlers (called from Grid event scripts) ----

-- Endless: dir = +1 or -1
function M.onEndless(dir)
    local cell = CELLS[M.focus]
    cell[4](M.selT, M.selS, dir)
    dirty[M.focus] = true
    if M.focus == 1 or M.focus == 2 then dirtyAll() end
end

-- Keyswitch 1..8 selects which cell the endless controls
function M.onKey(idx)
    if idx < 1 or idx > 8 then return end
    dirty[M.focus] = true
    M.focus = idx
    dirty[idx] = true
end

-- ---- screen drawing ----
-- Caller passes `self` (a Grid screen control element) into M.draw(self).
-- Layout: 4 cols x 2 rows, each cell 80x120 on the 320x240 screen.
local CELL_W, CELL_H = 80, 120

local function cellRect(i)
    local col = (i - 1) % 4
    local row = math.floor((i - 1) / 4)
    return col * CELL_W, row * CELL_H
end

local COL_BG_ACTIVE   = { 200,  30,  30 }
local COL_BG_INACTIVE = {  40,  40,  40 }
local COL_FG          = { 230, 230, 230 }

local function drawCell(scr, i)
    local x, y = cellRect(i)
    local cell = CELLS[i]
    local val  = cell[3](M.selT, M.selS)
    local bg   = (i == M.focus) and COL_BG_ACTIVE or COL_BG_INACTIVE
    -- two-corner rect (x1,y1,x2,y2)
    scr:draw_rectangle_filled(x, y, x + CELL_W - 1, y + CELL_H - 1, bg)
    scr:draw_text_fast(cell[1],       x + 4, y + 6,  8,  COL_FG)
    scr:draw_text_fast(tostring(val), x + 4, y + 24, 16, COL_FG)
end

-- Surgical redraw: only dirty cells. Call from the Screen Draw event
-- (passes `self`); it will batch and call draw_swap() once at the end.
function M.draw(scr)
    local any = false
    for i = 1, 8 do
        if dirty[i] then
            drawCell(scr, i)
            dirty[i] = false
            any = true
        end
    end
    if any then scr:draw_swap() end
end

return M
