-- ableton_widgets.lua
-- The four widget types from the "VSN1 Ableton Master Control" screen, rebuilt
-- on the layout system. FILESYSTEM MODULE: long, human-readable LCD names; the
-- Grid editor minifies on upload.
--
-- Widgets (all optional data-in via :set{...}, all self-dirtying):
--   nav_info     -- 3 lines: track (2 lines) + parameter, with a colour accent
--   value_writer -- centred value string (dB / % / Hz / ...), auto-fit
--   arc          -- arc-potmeter, absolute OR centred (pan-style) mode
--   text_button  -- <=4-char label, auto-fit + centred, active/dim colouring
--
-- require("ableton_widgets") returns { nav_info=, value_writer=, arc=, text_button= }.

local core = require("layout_core")
local M = {}

-- generic setter: merge known keys into the widget and mark it dirty.
local function make_set(keys)
  return function(self, t)
    for i = 1, #keys do
      local k = keys[i]
      if t[k] ~= nil then self[k] = t[k] end
    end
    self.change = true
  end
end

-- filled annular sector, a1..a2 radians, inner r / outer R, `segments` steps.
local function draw_arc(lcd, cx, cy, r, R, a1, a2, segments, color)
  if a1 == a2 then return end
  local max_span = math.rad(300)
  local active = math.floor((math.abs(a2 - a1) / max_span) * segments)
  if active < 1 then return end
  local step = max_span / segments
  local dir  = (a2 < a1) and -1 or 1
  local xs, ys = {}, {}
  for i = 0, active do
    local a = a1 + (i * step * dir)
    xs[#xs + 1] = cx + R * math.cos(a); ys[#ys + 1] = cy + R * math.sin(a)
  end
  for i = active, 0, -1 do
    local a = a1 + (i * step * dir)
    xs[#xs + 1] = cx + r * math.cos(a); ys[#ys + 1] = cy + r * math.sin(a)
  end
  lcd:draw_polygon_filled(xs, ys, color)
end

-- ---------------------------------------------------------------------------
-- nav_info: 2 track lines (split on ":") + a parameter line. The two track
-- lines carry a colour swatch, updated by Ableton. set{ track=, param=, color= }.
-- ---------------------------------------------------------------------------
function M.nav_info(opts)
  opts = opts or {}
  return {
    track = opts.track or "", param = opts.param or "",
    color = opts.color or { 200, 200, 200 },
    line  = opts.line or 16,                 -- line height / text size (mult of 8)
    set   = make_set({ "track", "param", "color" }),
    render = function(self)
      local lcd, x, y, lh = self.lcd, self.x, self.y, self.line
      lcd:draw_area_filled(x, y, x + self.w, y + self.h, { 0, 0, 0 })
      local a, b = self.track:match("(.+):(.+)")
      if not a then a, b = self.track, "" end
      local sw = lh - 2                        -- colour swatch size
      -- line 1 + swatch
      lcd:draw_area_filled(x, y, x + sw, y + sw, self.color)
      lcd:draw_text_fast(a, x + lh, y, lh, self.color)
      -- line 2 + swatch
      lcd:draw_area_filled(x, y + lh, x + sw, y + lh + sw, self.color)
      lcd:draw_text_fast(b, x + lh, y + lh, lh, self.color)
      -- line 3: parameter, dim
      lcd:draw_text_fast(self.param, x, y + 2 * lh, lh, { 120, 120, 120 })
    end,
  }
end

-- ---------------------------------------------------------------------------
-- value_writer: a centred value string, auto-fit to the cell width.
-- set{ text= }  (the host formats the number+unit; e.g. "-6.0 dB", "12.5 kHz").
-- ---------------------------------------------------------------------------
function M.value_writer(opts)
  opts = opts or {}
  return {
    text = opts.text or "", color = opts.color or { 220, 220, 220 },
    maxSize = opts.maxSize or 32,
    set   = make_set({ "text", "color" }),
    render = function(self)
      local lcd = self.lcd
      lcd:draw_area_filled(self.x, self.y, self.x + self.w, self.y + self.h, { 0, 0, 0 })
      local s  = core.fitSize(self.text, self.w, self.maxSize, 8)
      local tx = core.centerX(self.text, s, self.x, self.w)
      local ty = self.y + (self.h - s) // 2
      lcd:draw_text_fast(self.text, tx, ty, s, self.color)
    end,
  }
end

-- ---------------------------------------------------------------------------
-- arc: arc-potmeter indicator. Absolute mode fills from the start; centred
-- mode (pan/balance) fills from the middle outward by (value-0.5).
-- set{ value=0..1, color=, centered=true/false }.
-- ---------------------------------------------------------------------------
function M.arc(opts)
  opts = opts or {}
  local span = math.rad(opts.span or 300)
  return {
    value = 0, centered = opts.centered or false,
    color = opts.color or { 0, 200, 220 }, track = opts.track or { 60, 60, 60 },
    set   = make_set({ "value", "color", "centered" }),
    render = function(self)
      local lcd = self.lcd
      local cx, cy = self.x + self.w / 2, self.y + self.h / 2
      local rad = math.min(self.w, self.h) * 0.40
      local rw  = rad * 0.22
      local seg = 96
      local a0  = math.rad(120)
      lcd:draw_area_filled(self.x, self.y, self.x + self.w, self.y + self.h, { 0, 0, 0 })
      draw_arc(lcd, cx, cy, rad - rw, rad + rw, a0, a0 + span, seg, self.track)
      if self.centered then
        local mid = a0 + span / 2
        draw_arc(lcd, cx, cy, rad - rw, rad + rw, mid, mid + span * (self.value - 0.5), seg, self.color)
      else
        draw_arc(lcd, cx, cy, rad - rw, rad + rw, a0, a0 + span * self.value, seg, self.color)
      end
    end,
  }
end

-- ---------------------------------------------------------------------------
-- text_button: <=4-char label, auto-fit to the cell and centred, coloured by
-- active state. set{ label=, active=, color= }.
-- ---------------------------------------------------------------------------
function M.text_button(opts)
  opts = opts or {}
  return {
    label = opts.label or "", active = opts.active or false,
    color = opts.color or { 220, 220, 220 }, dim = opts.dim or { 60, 60, 60 },
    pad   = opts.pad or 4,
    set   = make_set({ "label", "active", "color" }),
    render = function(self)
      local lcd = self.lcd
      lcd:draw_area_filled(self.x, self.y, self.x + self.w, self.y + self.h, { 0, 0, 0 })
      local avail = self.w - 2 * self.pad
      local s  = core.fitSize(self.label, avail, self.h, 8)
      local tx = core.centerX(self.label, s, self.x, self.w)
      local ty = self.y + (self.h - s) // 2
      lcd:draw_text_fast(self.label, tx, ty, s, self.active and self.color or self.dim)
    end,
  }
end

return M
