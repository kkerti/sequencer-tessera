-- widgets.lua — small consumer widgets for the seq-3 screens: lane label,
-- value readout, and the list menu. All change-detecting set{}, all dumb
-- renderers (strings in, geometry out). Shared methods on one metatable per
-- class: per-instance tables hold data only.
local core = require("layout_core")

local function set(self, kv)
    local dirty = false
    for k, v in pairs(kv) do
        if self[k] ~= v then self[k] = v; dirty = true end
    end
    if dirty then self.change = true end
end

local DIM = { 150, 150, 160 }
local HI  = { 255, 255, 255 }

-- Centred, auto-fit value string for the selected step's focused param.
local function readoutRender(self)
    local x, y, w, h = self.x, self.y, self.w, self.h
    self.lcd:draw_area_filled(x, y, x + w, y + h, { 14, 14, 18 })
    if self.label ~= "" then
        local size = core.fitSize(self.label, w - 8, h - 4, 8)
        self.lcd:draw_text_fast(self.label, core.centerX(self.label, size, x, w),
            y + math.floor((h - size) / 2), size, HI)
    end
end
local READOUT_MT = { __index = { set = set, render = readoutRender } }
local function value_readout()
    return setmetatable({ label = "" }, READOUT_MT)
end

-- List menu: rows of {label, value}, widget-local cursor + edit flag, viewport
-- of rows. Host pushes items via in-place row mutation + set{title=}; cursor
-- and edit are display state (edit = accent value in brackets).
local ACCENT = { 120, 200, 255 }
local function menuRender(self)
    local x, y, w, h = self.x, self.y, self.w, self.h
    self.lcd:draw_area_filled(x, y, x + w, y + h, { 12, 12, 16 })
    local ty = y + 2
    if self.title ~= "" then
        self.lcd:draw_text_fast(self.title, x + 8, ty, 16, ACCENT)
        ty = ty + 22
    end
    local rows = math.floor((y + h - ty) / self.rowH)
    local first = 1
    if self.cursor > rows then first = self.cursor - rows + 1 end
    for i = first, math.min(#self.items, first + rows - 1) do
        local it = self.items[i]
        if it then
            local ry = ty + (i - first) * self.rowH
            local editing = self.edit and i == self.cursor
            if i == self.cursor then
                self.lcd:draw_area_filled(x + 4, ry, x + w - 4, ry + self.rowH - 2, { 40, 60, 90 })
                self.lcd:draw_text_fast(">", x + 6, ry + 8, 8, HI)
            end
            self.lcd:draw_text_fast(it.label, x + 20, ry + 8, 8, DIM)
            if it.value then
                local v = editing and ("[" .. it.value .. "]") or it.value
                local wv = core.textWidth(v, 8)
                self.lcd:draw_text_fast(v, x + w - wv - 8, ry + 8, 8, editing and ACCENT or HI)
            end
        end
    end
end
local MENU_MT = { __index = { set = set, render = menuRender } }
local function menu()
    return setmetatable({ title = "", items = {}, cursor = 1, edit = false, rowH = 24 }, MENU_MT)
end

-- Lane strip: one widget drawing `cols` cells from the values array
-- (playhead + selection included). cols=16 for the Overview's mini cells,
-- cols=4 with big=true for a Focus matrix row. The host writes values/pos/
-- kind directly and sets change (an array diff in set would cost per element).
local function stripRender(self)
    local x, y, w, h = self.x, self.y, self.w, self.h
    if self.labelW > 0 then
        local lw = self.labelW
        self.lcd:draw_area_filled(x, y, x + lw, y + h, { 14, 14, 18 })
        local size = core.fitSize(self.label, lw - 4, 16, 8)
        self.lcd:draw_text_fast(self.label, x + 4,
            y + math.floor((h - size) / 2), size,
            self.selected and HI or DIM)
        x = x + lw
        w = w - lw
    end
    local cw = math.floor(w / self.cols)
    self.lcd:draw_area_filled(x, y, x + w, y + h, { 14, 14, 18 })
    local c = self.color
    for i = 1, self.cols do
        local cx = x + (i - 1) * cw
        local v = self.values[i] or 0
        if self.kind == "note" or self.kind == "mod" then
            local ch = math.floor((h - 2) * v / 127 + 0.5)
            if ch > 0 then
                self.lcd:draw_area_filled(cx + 1, y + h - ch, cx + cw - 1, y + h, c)
            end
        elseif v == 1 then
            self.lcd:draw_area_filled(cx + 1, y + 1, cx + cw - 1, y + h - 1, c)
        end
        if self.big then
            self.lcd:draw_area_filled(cx + cw - 1, y, cx + cw, y + h, { 30, 30, 36 })
        end
    end
    if self.pos >= 1 and self.pos <= self.cols then
        local px = x + (self.pos - 1) * cw
        self.lcd:draw_area_filled(px, y, px + 2, y + h, { 255, 255, 255 })
    end
    if self.selStep >= 1 and self.selStep <= self.cols then
        local px = x + (self.selStep - 1) * cw
        if self.big then
            self.lcd:draw_area_filled(px, y, px + cw, y + 3, HI)
        else
            self.lcd:draw_area_filled(px, y + h - 1, px + cw, y + h, HI)
        end
    end
    if self.selected then
        self.lcd:draw_area_filled(x, y, x + 3, y + h, HI)
    end
end
local STRIP_MT = { __index = { set = set, render = stripRender } }
local function lane_strip(color, cols, big, labelW)
    local values = {}
    for i = 1, (cols or 16) do values[i] = 0 end
    return setmetatable({
        kind = "note", values = values, pos = 0, selStep = 0, selected = false,
        color = color or { 90, 170, 255 }, cols = cols or 16, big = big or false,
        label = "", labelW = labelW or 0,
    }, STRIP_MT)
end

return { value_readout = value_readout, menu = menu, lane_strip = lane_strip }