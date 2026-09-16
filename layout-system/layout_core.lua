-- layout_core.lua
-- Selective-rendering Layout engine for Intech Grid screens.
--
-- This is a FILESYSTEM MODULE: written with the long, human-readable LCD
-- function names (draw_area_filled, draw_swap, ...). The Grid editor minifies
-- it to the short names (ldaf, ldsw, ...) when uploading to the device. Do not
-- minify by hand. Contract: see layout-system/SPEC.md.
--
-- require("layout_core") returns { Layout = <engine>, drawIndicator = <helper> }.

local M = {}

-- ---------------------------------------------------------------------------
-- drawIndicator: OPTIONAL free helper a widget MAY call from its own render()
-- to draw an "active/focused" affordance. Not part of the contract, no base
-- class -- just a convenience so widgets don't re-code the same border/dot/bar.
--   style = { kind = "bar-top"|"bar-left"|"ring"|"dot-tr", color = {r,g,b},
--             thick = <px>, size = <px for dot> }
-- ---------------------------------------------------------------------------
local function drawIndicator(lcd, x, y, w, h, style)
  local c = style.color or { 0, 120, 255 }
  local t = style.thick or 2
  local kind = style.kind or "bar-top"
  if kind == "bar-top" then
    lcd:draw_area_filled(x, y, x + w, y + t, c)
  elseif kind == "bar-left" then
    lcd:draw_area_filled(x, y, x + t, y + h, c)
  elseif kind == "ring" then
    lcd:draw_rectangle(x, y, x + w, y + h, c)          -- outline
  elseif kind == "dot-tr" then
    local r = style.size or 4
    lcd:draw_area_filled(x + w - r, y, x + w, y + r, c) -- top-right dot
  end
end
M.drawIndicator = drawIndicator

-- ---------------------------------------------------------------------------
-- Layout: a cols x rows grid of cells. A cell holds a widget (any table with a
-- render method) or a nested Layout. The engine owns the render lifecycle;
-- widgets only implement render (+ optional data-in callbacks). See SPEC.md.
-- ---------------------------------------------------------------------------
local Layout = {}
Layout.__index = Layout
M.Layout = Layout

function Layout:new()
  local o = setmetatable({}, self)
  o.cells = {}
  -- A nested Layout is visited every frame (a cheap flag-check loop); its inner
  -- loop decides per-cell what actually issues draw calls.
  o.update = { mode = "always" }
  o.change = true
  return o
end

-- initialize(lcd, cols, rows, x, y, w, h): set the draw handle and the grid.
function Layout:initialize(lcd, cols, rows, x, y, w, h)
  self.lcd   = lcd
  self.cols  = cols
  self.rows  = rows
  self.x     = x or 0
  self.y     = y or 0
  self.w     = w or 320
  self.h     = h or 240
  self.cellW = self.w / cols
  self.cellH = self.h / rows
  self.cells = {}
  return self
end

-- addWidget(cx, cy, widget): place widget in cell (cx, cy). Assigns absolute
-- bounds, the lcd handle, and parent once -- no per-frame coordinate recompute.
-- Cell index is row-major: cy * cols + cx.
function Layout:addWidget(cx, cy, widget)
  widget.x      = self.x + math.floor(cx * self.cellW)
  widget.y      = self.y + math.floor(cy * self.cellH)
  widget.w      = math.floor(self.cellW)
  widget.h      = math.floor(self.cellH)
  widget.lcd    = self.lcd
  widget.parent = self
  widget.change = true                       -- draw once on the first frame
  -- A nested Layout gets its cell metrics re-derived for its new bounds, so
  -- children added to it AFTER placement land correctly.
  if widget.cols then
    widget.cellW = widget.w / widget.cols
    widget.cellH = widget.h / widget.rows
  end
  self.cells[cy * self.cols + cx] = widget
  return widget
end

-- decide whether a cell should render this frame
local function should_render(cell, frame)
  local u = cell.update
  if not u or u.mode == "dirty" then
    return cell.change == true
  elseif u.mode == "always" then
    return true
  elseif u.mode == "frames" then
    return cell.change == true or (frame % (u.n or 1)) == 0
  end
  return cell.change == true
end

-- render(frame): the draw pass. Returns true if anything drew. Only the
-- top-level Layout (parent == nil) issues the buffer swap, and only when
-- something actually drew (static frames cost nothing).
function Layout:render(frame)
  frame = frame or 0
  local drew = false
  local n = self.cols * self.rows
  for i = 0, n - 1 do
    local cell = self.cells[i]
    if cell then
      if cell.cells then                       -- nested Layout: recurse
        if cell:render(frame) then drew = true end
      elseif should_render(cell, frame) then
        cell:render()                          -- widget draws content + its own indicator
        cell.change = false                    -- engine clears the dirty flag
        drew = true
      end
    end
  end
  if self.parent == nil and drew then
    self.lcd:draw_swap()
  end
  return drew
end

-- dispatch(cbName, ...): fan an event out to every cell implementing cbName;
-- recurse into sub-Layouts. The open data-in path (midirx_cb, sysexrx_cb, ...).
function Layout:dispatch(cbName, ...)
  local n = self.cols * self.rows
  for i = 0, n - 1 do
    local cell = self.cells[i]
    if cell then
      if cell.cells then
        cell:dispatch(cbName, ...)
      elseif type(cell[cbName]) == "function" then
        cell[cbName](cell, ...)
      end
    end
  end
end

-- hitTest(px, py): OPTIONAL. Return the leaf widget whose bounds contain the
-- point (recurses into sub-Layouts). Mainly for the grid-wasm pointer; device
-- navigation usually addresses widgets by held reference instead.
function Layout:hitTest(px, py)
  local n = self.cols * self.rows
  for i = 0, n - 1 do
    local cell = self.cells[i]
    if cell and px >= cell.x and px < cell.x + cell.w
             and py >= cell.y and py < cell.y + cell.h then
      if cell.cells then
        return cell:hitTest(px, py) or cell
      end
      return cell
    end
  end
  return nil
end

return M
