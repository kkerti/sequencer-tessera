-- menu_widgets.lua
-- sequencer-3 menu widgets, built on the layout system (layout-system/SPEC.md).
-- FILESYSTEM MODULE: long LCD names (draw_area_filled, ...); the Grid editor
-- minifies to the short names on upload.
--
-- The menu is ONE widget (SPEC §5: a widget is any table with a render). It
-- owns a stack of menu nodes, so the deeper/upper navigation lives inside the
-- widget as ordinary state — the engine stays out of it (§6 keeps selection
-- and navigation out of the engine by design). The host feeds it through the
-- §4 dispatch fan-out; the widget marks itself dirty in its own callbacks.
--
-- Everything draws within self.x/y/w/h. The LCD has no scissor, so the widget
-- runs its own scroll window and never draws outside its bounds.
--
-- Callbacks the host dispatches (Layout:dispatch fan-out, SPEC §4):
--   nav_cb(self, delta)   -- cursor up/down (-1 / +1)
--   enter_cb(self)        -- deeper: open the selected branch, run an action
--   back_cb(self)         -- upper: pop one level
--   enc_cb(self, delta)   -- edit the selected leaf's value
--
-- Node/item shapes (host data, plain tables — no base class):
--   node   = { title = "LANE 1", items = { item, ... } }
--   leaf   = { label = "TYPE", value = function() return "note" end,
--              edit = function(delta) ... end }      -- encoder edits the value
--   branch = { label = "GEN", sub = <node> or function() return <node> end }
--            (a function re-builds the node on entry — use for menus whose
--            items depend on lane state, e.g. dims/type dependencies)
--   action = { label = "GEN NOW", act = function() ... end }  -- enter runs it
--
-- require("menu_widgets") returns { menu = <factory>, label = <factory> }.

local core = require("layout_core")
local M = {}

-- ---------------------------------------------------------------------------
-- menu: hierarchical text menu of label/value rows, all in one dirty cell.
-- opts: root=<node>, rows=<visible rows>, pad=<px>, optional colors.
-- ---------------------------------------------------------------------------
function M.menu(opts)
  opts = opts or {}
  local rows = opts.rows or 6
  return {
    root = opts.root,
    rows = rows,
    pad  = opts.pad or 8,
    bg      = opts.bg or { 0, 0, 0 },
    rule    = opts.rule or { 46, 46, 54 },
    title_c = opts.title_c or { 249, 150, 0 },
    label_c = opts.label_c or { 130, 130, 130 },
    value_c = opts.value_c or { 235, 235, 235 },
    sel_c   = opts.sel_c or { 249, 150, 0 },
    deep_c  = opts.deep_c or { 100, 100, 110 },
    -- stack frames { node=, cursor=, top= }; top = first visible row
    stack = { { node = opts.root, cursor = 1, top = 1 } },
    change = true,

    sync = function(self) self.change = true end,

    nav_cb = function(self, delta)
      local f = self.stack[#self.stack]
      local c = f.cursor + delta
      if c < 1 then c = 1 end
      local n = #f.node.items
      if c > n then c = n end
      if c ~= f.cursor then f.cursor = c; self:sync() end
    end,

    enter_cb = function(self)
      local f = self.stack[#self.stack]
      local it = f.node.items[f.cursor]
      if not it then return end
      if it.sub then
        local node = (type(it.sub) == "function") and it.sub() or it.sub
        self.stack[#self.stack + 1] = { node = node, cursor = 1, top = 1 }
        self:sync()
      elseif it.act then
        it.act()               -- an action may touch any row; repaint the menu
        self:sync()
      end
    end,

    back_cb = function(self)
      if #self.stack > 1 then
        self.stack[#self.stack] = nil
        self:sync()
      end
    end,

    -- re-resolve each frame's node from the root, re-evaluating function
    -- subs: an edit can change which items exist (DIMS swaps ADV/LEN for
    -- XADV/YADV). Cursors are preserved and clamped.
    resolve = function(self)
      local node = self.root
      for i = 2, #self.stack do
        local pf = self.stack[i - 1]
        local it = pf.node.items[pf.cursor]
        if not it or not it.sub then break end
        node = (type(it.sub) == "function") and it.sub() or it.sub
        self.stack[i].node = node
      end
      for i = 1, #self.stack do
        local f = self.stack[i]
        local n = #f.node.items
        if f.cursor > n then f.cursor = n end
        if f.top > f.cursor then f.top = f.cursor end
      end
    end,

    enc_cb = function(self, delta)
      local f = self.stack[#self.stack]
      local it = f.node.items[f.cursor]
      if it and it.edit then
        it.edit(delta)
        self:resolve()
        self:sync()
      end
    end,

    render = function(self)
      local lcd, x, y = self.lcd, self.x, self.y
      local f = self.stack[#self.stack]
      local node = f.node
      lcd:draw_area_filled(x, y, x + self.w, y + self.h, self.bg)
      -- title bar; "<" marks that a level above exists
      lcd:draw_text_fast(node.title, x + self.pad, y + 8, 16, self.title_c)
      if #self.stack > 1 then
        lcd:draw_text_fast("<", x + self.w - self.pad - 16, y + 8, 16, self.label_c)
      end
      lcd:draw_line(x, y + 32, x + self.w, y + 32, self.rule)
      -- scroll window follows the cursor
      local n = #node.items
      if f.cursor < f.top then f.top = f.cursor end
      if f.cursor > f.top + self.rows - 1 then f.top = f.cursor - self.rows + 1 end
      local ty0 = y + 40
      local rh = (self.h - 44) / self.rows
      for r = 1, self.rows do
        local i = f.top + r - 1
        if i > n then break end
        local it = node.items[i]
        local iy = math.floor(ty0 + (r - 1) * rh)
        local sel = (i == f.cursor)
        if sel then
          core.drawIndicator(lcd, x, iy, self.w, math.floor(rh),
            { kind = "bar-left", color = self.sel_c, thick = 3 })
        end
        local ty = math.floor(iy + (rh - 8) / 2)
        lcd:draw_text_fast(it.label, x + self.pad + 6, ty, 8,
          sel and self.sel_c or self.label_c)
        local v
        if it.sub then v = ">"
        elseif it.value then v = it.value()
        elseif it.act then v = "RUN"
        else v = "" end
        if v ~= "" then
          lcd:draw_text_fast(v, x + self.w - self.pad - #v * 8, ty, 8,
            it.sub and self.deep_c or (sel and self.sel_c or self.value_c))
        end
      end
    end,
  }
end

-- ---------------------------------------------------------------------------
-- label: one line of small text (hint bar), vertically centred. set{ text= }.
-- ---------------------------------------------------------------------------
function M.label(opts)
  opts = opts or {}
  return {
    text  = opts.text or "",
    color = opts.color or { 110, 110, 120 },
    size  = opts.size or 8,
    set   = function(self, text) self.text = text; self.change = true end,
    render = function(self)
      local lcd = self.lcd
      lcd:draw_area_filled(self.x, self.y, self.x + self.w, self.y + self.h, { 0, 0, 0 })
      local tx = self.x + ((self.w - #self.text * self.size) // 2)
      local ty = self.y + (self.h - self.size) // 2
      lcd:draw_text_fast(self.text, tx, ty, self.size, self.color)
    end,
  }
end

return M