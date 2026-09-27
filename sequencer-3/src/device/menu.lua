-- menu.lua — the Config screen: menu pages + drawing, split out of
-- screen.lua so the GUI's entry cost stays small (the Config screen is a
-- follow-on; Overview/Focus cover the test map). Loaded lazily by screen.lua
-- on first entry to Config.
--
-- Menu pages are plain data; one applier handles enum / numeric / bool items.

local S -- the screen state table (injected by screen.lua's loader)
local Engine

local M = {}
M.page = "globals"

local NOTE_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local TYPES = { "note", "mod", "trig", "gate" }
local DIMS  = { "16x1", "8x2", "5x3", "4x3", "4x4" }
local WHITE = { 235, 235, 235 }
local GREY  = { 150, 150, 160 }
local BG    = { 12, 12, 16 }

local PAGES = {
    lane = {
        title = "LANE",
        items = {
            { label = "type",     field = "type",     choices = TYPES },
            { label = "dims",     field = "dims",     choices = DIMS },
            { label = "division", field = "division", lo = 1, hi = 16 },
            { label = "channel",  field = "channel",  lo = 1, hi = 16 },
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

function M.init(screenState, engine)
    S = screenState
    Engine = engine
end

local function used(l)
    if l.height == 1 then return l.length end
    return l.width * l.height
end

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end return v
end

function M.itemValue(it)
    if it.field == "_reset" then return "-" end
    if it.bool then return Engine.running and "on" or "off" end
    return tostring(Engine.state(S.selLane)[it.field])
end

function M.applyItem(it, d)
    if it.field == "_reset" then
        Engine.reset()
    elseif it.bool then
        if Engine.running then Engine.onStop() else Engine.onStart() end
    else
        local lane = S.selLane
        local v = Engine.state(lane)[it.field]
        if it.choices then
            local idx = 1
            for i, c in ipairs(it.choices) do if c == v then idx = i end end
            v = it.choices[((idx - 1 + d) % #it.choices) + 1]
            if it.field == "type" then Engine.setType(lane, v)
            else Engine.setDimensions(lane, v) end
        else
            v = clamp(v + d, it.lo, it.hi)
            if it.field == "division" then Engine.setDivision(lane, v)
            else Engine.setChannel(lane, v) end
        end
        S.selStep = clamp(S.selStep, 1, used(Engine.state(lane)))
    end
    S.touch()
end

function M.cursorCount()
    local page = PAGES[M.page]
    return page and #page.items or 1
end

function M.turn(d)
    local page = PAGES[M.page]
    if S.editing then
        M.applyItem(page.items[S.cursor], d)
    else
        S.cursor = ((S.cursor - 1 + d) % #page.items) + 1
        S.touch()
    end
end

function M.draw(lcd)
    lcd:draw_area_filled(0, 0, 320, 240, BG)
    local page = PAGES[M.page]
    lcd:draw_text_fast(page.title .. " " .. S.selLane, 8, 8, 16, WHITE)
    for i, it in ipairs(page.items) do
        local y = 40 + (i - 1) * 28
        local sel = (i == S.cursor)
        local col = sel and WHITE or GREY
        lcd:draw_text_fast((sel and (S.editing and ">" or "-") or " ") .. " " .. it.label,
            8, y, 16, col)
        lcd:draw_text_fast(M.itemValue(it), 170, y, 16, col)
    end
    lcd:draw_swap()
end

return M
