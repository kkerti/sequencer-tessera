-- layout_core.lua
-- Selective-rendering Layout engine for Intech Grid screens.
--
-- FILESYSTEM MODULE: long, human-readable LCD names (draw_area_filled, ...).
-- The Grid editor minifies to the short names (ldaf, ...) on upload. Contract:
-- see layout-system/SPEC.md.
--
-- require("layout_core") returns:
--   { Layout=<engine>, drawIndicator=<helper>,
--     textWidth=, fitSize=, centerX= }   -- text helpers (§ text)

local M = {}

-- ===========================================================================
-- Text helpers (for draw_text_fast, whose glyph advance is ~= size px/char).
-- Widgets use these to fit/centre text within their bounds instead of each
-- re-deriving the maths. textWidth is an upper bound (real font may be
-- narrower), so fitSize never overflows.
-- ===========================================================================
local function textWidth(text, size) return #text * size end
M.textWidth = textWidth

-- largest size that is a multiple of 8 in [minSize,maxSize] whose text fits maxW
local function fitSize(text, maxW, maxSize, minSize)
  maxSize = maxSize or 32
  minSize = minSize or 8
  local n = #text
  if n == 0 then return minSize end
  local s = (maxW // n) // 8 * 8            -- round down to a multiple of 8
  if s > maxSize then s = maxSize end
  if s < minSize then s = minSize end
  return s
end
M.fitSize = fitSize

-- left x that centres text of the given size within [x, x+w]
local function centerX(text, size, x, w)
  return x + ((w - #text * size) // 2)
end
M.centerX = centerX

-- ===========================================================================
-- drawIndicator: OPTIONAL free helper a widget MAY call from its render() to
-- draw an "active/focused" affordance. No base class -- just a convenience.
--   style = { kind="bar-top"|"bar-left"|"ring"|"dot-tr", color=, thick=, size= }
-- ===========================================================================
local function drawIndicator(lcd, x, y, w, h, style)
  local c = style.color or { 0, 120, 255 }
  local t = style.thick or 2
  local kind = style.kind or "bar-top"
  if kind == "bar-top" then
    lcd:draw_area_filled(x, y, x + w, y + t, c)
  elseif kind == "bar-left" then
    lcd:draw_area_filled(x, y, x + t, y + h, c)
  elseif kind == "ring" then
    lcd:draw_rectangle(x, y, x + w, y + h, c)
  elseif kind == "dot-tr" then
    local r = style.size or 4
    lcd:draw_area_filled(x + w - r, y, x + w, y + r, c)
  end
end
M.drawIndicator = drawIndicator

-- ===========================================================================
-- Layout: holds child widgets (any table with a render method) or nested
-- Layouts. Children are placed either on a uniform grid (addWidget) or at an
-- explicit rect (place). The engine owns the render lifecycle. See SPEC.md.
-- ===========================================================================
local Layout = {}
Layout.__index = Layout
M.Layout = Layout

function Layout:new()
  local o = setmetatable({}, self)
  o.children = {}                 -- flat list; both addWidget and place append here
  o.update = { mode = "always" }  -- a nested Layout is visited every frame; its
                                  -- inner loop decides what actually draws.
  o.change = true
  return o
end

-- initialize(lcd, cols, rows, x, y, w, h). cols/rows may be nil for a
-- placement-only (explicit-rect) Layout.
function Layout:initialize(lcd, cols, rows, x, y, w, h)
  self.lcd      = lcd
  self.cols     = cols
  self.rows     = rows
  self.x        = x or 0
  self.y        = y or 0
  self.w        = w or 320
  self.h        = h or 240
  self.cellW    = cols and (self.w / cols) or self.w
  self.cellH    = rows and (self.h / rows) or self.h
  self.children = {}
  return self
end

-- give a child its bounds + engine fields, and re-grid it if it is a Layout.
local function attach(self, widget, x, y, w, h)
  widget.x, widget.y, widget.w, widget.h = x, y, w, h
  widget.lcd    = self.lcd
  widget.parent = self
  widget.change = true
  if widget.cols and widget.initialize == Layout.initialize then
    widget.cellW, widget.cellH = w / widget.cols, h / widget.rows
  end
  self.children[#self.children + 1] = widget
  return widget
end

-- grid placement: cell (cx, cy) of the cols x rows grid (row-major).
function Layout:addWidget(cx, cy, widget)
  return attach(self, widget,
    self.x + math.floor(cx * self.cellW),
    self.y + math.floor(cy * self.cellH),
    math.floor(self.cellW), math.floor(self.cellH))
end

-- explicit placement: an arbitrary rect within this Layout. Coordinates are
-- relative to the Layout's origin. Use for variable-size screen regions.
function Layout:place(x, y, w, h, widget)
  return attach(self, widget, self.x + x, self.y + y, w, h)
end

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

-- render(frame): draw pass. Returns true if anything drew. Only the top-level
-- Layout (parent == nil) swaps, and only when something drew.
function Layout:render(frame)
  frame = frame or 0
  local drew = false
  for i = 1, #self.children do
    local cell = self.children[i]
    if cell.children then                      -- nested Layout: recurse
      if cell:render(frame) then drew = true end
    elseif should_render(cell, frame) then
      cell:render()                            -- widget draws content + own indicator
      cell.change = false                      -- engine clears the dirty flag
      drew = true
    end
  end
  if self.parent == nil and drew then
    self.lcd:draw_swap()
  end
  return drew
end

-- dispatch(cbName, ...): fan an event out to every child implementing cbName;
-- recurse into sub-Layouts. The open data-in path (midirx_cb, sysexrx_cb, ...).
function Layout:dispatch(cbName, ...)
  for i = 1, #self.children do
    local cell = self.children[i]
    if cell.children then
      cell:dispatch(cbName, ...)
    elseif type(cell[cbName]) == "function" then
      cell[cbName](cell, ...)
    end
  end
end

-- hitTest(px, py): OPTIONAL. Leaf widget whose bounds contain the point.
function Layout:hitTest(px, py)
  for i = 1, #self.children do
    local cell = self.children[i]
    if px >= cell.x and px < cell.x + cell.w
       and py >= cell.y and py < cell.y + cell.h then
      if cell.children then return cell:hitTest(px, py) or cell end
      return cell
    end
  end
  return nil
end

return M
