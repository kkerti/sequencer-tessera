-- my_own_widgets.lua
-- Consumer widgets built on the layout system. FILESYSTEM MODULE: long,
-- human-readable LCD names; the Grid editor minifies on upload.
--
-- One widget: draw_arc -- an arc potmeter indicator, adapted from the
-- "VSN1 Ableton Master Control" profile's draw_arc.
--
-- require("my_own_widgets") returns { draw_arc = <factory> }.

local core = require("layout_core")

local M = {}

-- draw_arc: a filled annular sector (ring segment) from angle a1..a2 (radians),
-- between inner radius r and outer radius R, tessellated in `segments` steps.
-- Builds the polygon outer-edge forward then inner-edge back, and fills it.
local function draw_arc(lcd, cx, cy, r, R, a1, a2, segments, color)
  if a1 == a2 then return end
  local max_span = math.rad(300)
  local span     = math.abs(a2 - a1)
  local active   = math.floor((span / max_span) * segments)
  if active < 1 then return end
  local step = max_span / segments
  local dir  = (a2 < a1) and -1 or 1
  local xs, ys = {}, {}
  for i = 0, active do
    local a = a1 + (i * step * dir)
    xs[#xs + 1] = cx + R * math.cos(a)
    ys[#ys + 1] = cy + R * math.sin(a)
  end
  for i = active, 0, -1 do
    local a = a1 + (i * step * dir)
    xs[#xs + 1] = cx + r * math.cos(a)
    ys[#ys + 1] = cy + r * math.sin(a)
  end
  lcd:draw_polygon_filled(xs, ys, color)
end

-- draw_arc widget factory.
--   opts.color = value-arc color   (default cyan)
--   opts.track = background color   (default dim grey)
--   opts.cc    = MIDI CC to track   (nil = respond to any CC's value)
--   opts.span  = swept degrees      (default 300, gap at the bottom)
-- Data comes in via midirx_cb (the module's own MIDI, looped back). Value is
-- stored 0..1; the widget marks itself dirty so only its cell redraws.
function M.draw_arc(opts)
  opts = opts or {}
  local span = math.rad(opts.span or 300)
  return {
    value   = 0,                       -- normalized 0..1
    focused = false,
    cc      = opts.cc,                 -- nil => accept any controller
    color   = opts.color or { 0, 200, 220 },
    track   = opts.track or { 60, 60, 60 },

    render = function(self)
      local cx  = self.x + self.w / 2
      local cy  = self.y + self.h / 2
      local rad = math.min(self.w, self.h) * 0.40
      local rw  = rad * 0.22           -- half ring thickness
      local segments = 96
      local a0  = math.rad(120)        -- start; sweeps a0 .. a0+span

      -- clear this cell, then draw the background track and the value arc
      self.lcd:draw_area_filled(self.x, self.y, self.x + self.w, self.y + self.h, { 0, 0, 0 })
      draw_arc(self.lcd, cx, cy, rad - rw, rad + rw, a0, a0 + span, segments, self.track)
      draw_arc(self.lcd, cx, cy, rad - rw, rad + rw, a0, a0 + span * self.value, segments, self.color)

      if self.focused then
        core.drawIndicator(self.lcd, self.x, self.y, self.w, self.h,
                           { kind = "bar-top", color = { 0, 120, 255 }, thick = 2 })
      end
    end,

    -- data-in: incoming MIDI. ev[3] = controller number, ev[4] = value (0..127).
    midirx_cb = function(self, header, ev)
      if self.cc == nil or ev[3] == self.cc then
        self.value  = ev[4] / 127
        self.change = true             -- the one rule: flag dirty in your own callback
      end
    end,
  }
end

return M
