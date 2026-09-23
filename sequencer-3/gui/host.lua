-- host.lua — the GUI host: owns all widget references, feeds the engine at the
-- two observation points (clock in, action out), pushes state into widgets.
-- Widgets never touch the engine. See docs/SCREENS.md and ADR-0007.
--
-- Heap discipline: the VM is tiny, so methods are shared (metatables), the
-- Overview renders one lane_strip widget per lane (not 16 cells), menu pages
-- are plain data with persistent row tables, and this module avoids closures
-- at module level.
local core = require("layout_core")
local W = require("widgets")

local NOTE_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local TYPES_LIST = { "note", "mod", "trig", "gate" }
local DIMS_LIST = { "16x1", "8x2", "5x3", "4x3", "4x4" }
local TYPE_COLORS = {
    note = { 90, 170, 255 }, mod = { 90, 220, 120 },
    trig = { 255, 180, 90 }, gate = { 255, 110, 110 },
}
local BG = { 14, 14, 18 }

local Host = {}
Host.__index = Host

local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

local function used(l)
    if l.height == 1 then return l.length end
    return l.width * l.height
end

function Host:new(engine, lcd)
    local o = setmetatable({}, self)
    o.engine = engine
    o.lcd = lcd
    o.screen = "overview"
    o.selLane = 1
    o.selStep = 1
    o.param = 1                       -- note: 1 pitch, 2 velocity, 3 length
    o.lastPos = {}
    o.menuRows = {}                   -- persistent menu row tables (no per-push alloc)
    o:_buildOverview(lcd)
    o:_buildFocus(lcd)
    o:_refresh()
    return o
end

-- ------------------------------------------------------------- layouts ---

function Host:_buildOverview(lcd)
    local L = core.Layout:new()
    L:initialize(lcd, nil, nil, 0, 0, 320, 240)
    self.ovStrips = {}
    for lane = 1, 4 do
        self.ovStrips[lane] = L:place(0, (lane - 1) * 60, 320, 58,
            W.lane_strip(nil, 16, false, 42))
    end
    self.ov = L
end

function Host:_buildFocus(lcd)
    local L = core.Layout:new()
    L:initialize(lcd, nil, nil, 0, 0, 320, 240)
    self.fmRows = {}
    for row = 1, 4 do
        self.fmRows[row] = L:place(0, (row - 1) * 60, 280, 58,
            W.lane_strip({ 90, 170, 255 }, 4, true))
    end
    self.fmReadout = L:place(284, 8, 34, 120, W.value_readout())
    self.fm = L
end

function Host:_buildConfig(lcd)
    local L = core.Layout:new()
    L:initialize(lcd, nil, nil, 0, 0, 320, 240)
    self.menu = L:place(0, 0, 320, 240, W.menu())
    self.menu.items = self.menuRows   -- rows are mutated in place by _pushMenu
    self.cfg = L
end

-- ---------------------------------------------------------------- push ---
-- Push functions write a strip's true state; the host renders only the active
-- layout, so no push tests self.screen. _refresh() covers every state change
-- except the per-pulse fast path in onPulse.

function Host:paramCount()
    local l = self.engine.state(self.selLane)
    if l.type == "note" then return 3 end
    return 1
end

-- the per-step value a strip draws (pitch / value / gate)
function Host:_stripValue(l, step)
    if l.type == "note" then return l.pitch[step] end
    if l.type == "mod" then return l.value[step] end
    return l.gate[step]
end

function Host:_pushLane(lane)
    local l = self.engine.state(lane)
    local st = self.ovStrips[lane]
    st.kind = l.type
    st.color = TYPE_COLORS[l.type]
    st.pos = self.lastPos[lane] or l.position
    st.selStep = (lane == self.selLane) and self.selStep or 0
    for i = 1, 16 do st.values[i] = self:_stripValue(l, i) end
    st.label = lane .. " " .. l.type:sub(1, 3):upper()
    st.selected = (lane == self.selLane)
    st.change = true
end

function Host:_pushFmRow(row)
    local l = self.engine.state(self.selLane)
    local st = self.fmRows[row]
    st.kind = l.type
    st.color = TYPE_COLORS[l.type]
    for col = 1, 4 do
        st.values[col] = self:_stripValue(l, (row - 1) * 4 + col)
    end
    local p = self.lastPos[self.selLane]
    if p and math.floor((p - 1) / 4) + 1 == row then
        st.pos = (p - 1) % 4 + 1
    else
        st.pos = 0
    end
    if math.floor((self.selStep - 1) / 4) + 1 == row then
        st.selStep = (self.selStep - 1) % 4 + 1
    else
        st.selStep = 0
    end
    st.selected = false
    st.change = true
end

function Host:_pushFmAll()
    for row = 1, 4 do self:_pushFmRow(row) end
    self:_pushReadout()
end

function Host:_pushReadout()
    local l = self.engine.state(self.selLane)
    local s = self.selStep
    local label
    if l.type == "note" then
        if self.param == 1 then label = NOTE_NAMES[(l.pitch[s] % 12) + 1] .. tostring(math.floor(l.pitch[s] / 12) - 1)
        elseif self.param == 2 then label = "V" .. l.velocity[s]
        else label = l.stepLength[s] .. "t" end
    elseif l.type == "mod" then label = tostring(l.value[s])
    else label = (l.gate[s] == 1) and "ON" or "OFF" end
    self.fmReadout:set({ label = label })
end

function Host:_refresh()
    for lane = 1, 4 do self:_pushLane(lane) end
    if self.screen == "focus" then self:_pushFmAll() end
    if self.screen == "config" then self:_pushMenu() end
end

-- ------------------------------------------------------------ screens ---

function Host:_activeLayout()
    if self.screen == "focus" then return self.fm end
    if self.screen == "config" then return self.cfg end
    return self.ov
end

function Host:switch(name)
    if name == self.screen then return end
    self.screen = name
    if name == "config" then
        if not self.menu then self:_buildConfig(self.lcd) end
        self.cfgPage = self.cfgPage or "globals"
        self.menu.cursor = 1
        self.editing = false
        self.menu.edit = false
        self:_pushMenu()
    elseif name == "focus" then
        self:_pushFmAll()
    end
    local L = self:_activeLayout()
    for i = 1, #L.children do L.children[i].change = true end
    self.clearPending = true          -- next render clears the old screen's pixels
end

-- ------------------------------------------------------------ data in ---

function Host:onPulse()
    self.engine.onPulse()
    for lane = 1, 4 do
        local l = self.engine.state(lane)
        local pos = l.position
        if self.lastPos[lane] ~= pos then
            self.lastPos[lane] = pos
            local st = self.ovStrips[lane]
            st.pos = pos
            st.change = true
            if lane == self.selLane and self.screen == "focus" then
                self:_pushFmAll()
            end
        end
    end
end

-- ------------------------------------------------------------ actions ---

function Host:selectLane(lane)
    if lane == self.selLane then return end
    self.selLane = lane
    self.selStep = clamp(self.selStep, 1, used(self.engine.state(lane)))
    self.param = 1
    self:_refresh()
end

function Host:selectStep(step)
    local l = self.engine.state(self.selLane)
    step = clamp(step, 1, used(l))
    if self.selStep == step then return end
    self.selStep = step
    self:_refresh()
end

function Host:moveStep(d)
    self:selectStep(((self.selStep - 1 + d) % used(self.engine.state(self.selLane))) + 1)
end

function Host:cycleParam(d)
    local n = self:paramCount()
    self.param = ((self.param - 1 + d) % n) + 1
    self:_pushReadout()
end

function Host:editFocused(d)
    local lane, step = self.selLane, self.selStep
    local l = self.engine.state(lane)
    if l.type == "note" then
        if self.param == 1 then self.engine.setPitch(lane, step, l.pitch[step] + d)
        elseif self.param == 2 then self.engine.setVelocity(lane, step, l.velocity[step] + d * 2)
        else self.engine.setStepLength(lane, step, l.stepLength[step] + d * 6) end
    elseif l.type == "mod" then
        self.engine.setValue(lane, step, l.value[step] + d * 2)
    else
        self.engine.setGate(lane, step, (l.gate[step] + 1) % 2)
    end
    self:_refresh()
end

function Host:shred()
    self.engine.shred(self.selLane)   -- acts on the playhead step (engine.lua)
    self:_refresh()
end

function Host:zero()
    self.engine.zero(self.selLane)    -- acts on the playhead step (engine.lua)
    self:_refresh()
end

-- ------------------------------------------------------------- menu ---
-- Pages are plain data; one applier handles enum, numeric and bool items.
-- _pushMenu mutates the persistent row tables in place and dirties only on a
-- real string change, so repeated pushes stay free.

local MENU_PAGES = {
    lane = {
        title = "LANE",
        items = {
            { label = "type",     field = "type",     choices = TYPES_LIST },
            { label = "dims",     field = "dims",     choices = DIMS_LIST },
            { label = "division", field = "division", lo = 1, hi = 16 },
            { label = "channel",  field = "channel",  lo = 1, hi = 16 },
            { label = "length",   field = "length",   lo = 1, hi = 16 },
        },
    },
    globals = {
        title = "GLOBALS",
        items = {
            { label = "run",   field = "running", bool = true },
            { label = "reset", field = "_reset" },
        },
    },
}

function Host:_itemValue(it)
    if it.field == "_reset" then return "-" end
    if it.bool then return self.engine.running and "on" or "off" end
    local l = self.engine.state(self.selLane)
    return tostring(l[it.field])
end

function Host:_applyItem(it, d)
    if it.field == "_reset" then
        self.engine.reset()
    elseif it.bool then
        if self.engine.running then self.engine.onStop() else self.engine.onStart() end
    else
        local lane = self.selLane
        local v = self.engine.state(lane)[it.field]
        if it.choices then
            local idx = 1
            for i, c in ipairs(it.choices) do if c == v then idx = i end end
            v = it.choices[((idx - 1 + d) % #it.choices) + 1]
            if it.field == "type" then self.engine.setType(lane, v)
            elseif it.field == "dims" then self.engine.setDimensions(lane, v) end
        else
            v = clamp(v + d, it.lo, it.hi)
            if it.field == "division" then self.engine.setDivision(lane, v)
            elseif it.field == "channel" then self.engine.setChannel(lane, v)
            elseif it.field == "length" then self.engine.setLength(lane, v) end
        end
        self:_pushLane(lane)
        self.selStep = clamp(self.selStep, 1, used(self.engine.state(lane)))
    end
    self:_refresh()
end

function Host:_pushMenu()
    local page = MENU_PAGES[self.cfgPage or "globals"]
    local menu = self.menu
    local changed = false
    local title = page.title .. " " .. self.selLane
    if menu.title ~= title then menu.title = title; changed = true end
    for i, it in ipairs(page.items) do
        local r = self.menuRows[i]
        if not r then r = {}; self.menuRows[i] = r end
        local label, value = it.label, self:_itemValue(it)
        if r.label ~= label then r.label = label; changed = true end
        if r.value ~= value then r.value = value; changed = true end
    end
    if changed then menu.change = true end
end

function Host:menuCursor(d)
    local page = MENU_PAGES[self.cfgPage]
    self.menu.cursor = ((self.menu.cursor - 1 + d) % #page.items) + 1
    self.menu.change = true
end

function Host:toggleEdit()
    self.editing = not self.editing
    self.menu.edit = self.editing
    self.menu.change = true
end

function Host:menuEditValue(d)
    local page = MENU_PAGES[self.cfgPage]
    local it = page.items[self.menu.cursor]
    if it then self:_applyItem(it, d) end
end

-- ------------------------------------------------------------ render ---

function Host:render(frame)
    if self.clearPending then
        self.lcd:draw_area_filled(0, 0, 320, 240, BG)
        self.clearPending = false
    end
    self:_activeLayout():render(frame)
end

-- ------------------------------------------------------------ controls ---
-- Control map (docs/SCREENS.md): keys 0-7 = Config, View, Save, Load,
-- Prev, Next, Zero, Shred; screen btns 9-12 = lane select; encoder press/turn.

function Host:keyDown(i)
    if self.screen == "config" then
        if i == 0 or i == 1 then            -- Config/View also back out
            self:switch(self.cfgReturn or "overview")
        end
        return
    end
    if i == 0 then                          -- Config: lane menu from Focus, globals from Overview
        self.cfgReturn = self.screen
        self.cfgPage = (self.screen == "focus") and "lane" or "globals"
        self:switch("config")
    elseif i == 1 then                      -- View: Overview <=> Focus
        self:switch(self.screen == "overview" and "focus" or "overview")
    elseif i == 4 then self:moveStep(-1)
    elseif i == 5 then self:moveStep(1)
    elseif i == 6 then self:zero()
    elseif i == 7 then self:shred()
    end
end

function Host:btnDown(i)                    -- 9..12 -> lane 1..4
    if i >= 9 and i <= 12 then self:selectLane(i - 8) end
end

function Host:encTurn(d)
    if self.screen == "config" then
        if self.editing then self:menuEditValue(d) else self:menuCursor(d) end
    elseif self.screen == "focus" then
        self:editFocused(d)
    else
        self:moveStep(d)                    -- Overview: turn walks the selected step
    end
end

function Host:encPress()
    if self.screen == "config" then
        self:toggleEdit()
    elseif self.screen == "focus" then
        self:cycleParam(1)
    else
        self:switch("focus")                -- Overview: press enters the lane
    end
end

return Host
