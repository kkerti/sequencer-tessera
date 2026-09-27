-- screen.lua — direct-draw GUI: Overview / Focus, with Config as a LAZY
-- follow-on (menu.lua compiles on first entry to Config). No layout system,
-- no widget classes. Lazy itself: required on the first control press; until
-- then the adapter's 4-line status shows. Draws only when dirty (playhead
-- move, edit, screen switch). Device module rules: no collectgarbage, no
-- package.loaded, no string.format.
--
-- Control map (same as the grid-wasm harness):
--   key 0 Config (lazy menu.lua) · key 1 View · keys 4/5 Prev/Next ·
--   6/7 Zero/Shred (playhead step) · btns 9-12 lane select · encoder:
--   Focus edit / Config cursor+edit / Overview move; press: cycle param /
--   toggle edit / enter Focus.

local RX     = require("midi_rx")
RX.ensure()                               -- chain + demo if no clock byte yet
local Engine = require("engine")

local S = {}
local lastPos = { 0, 0, 0, 0 }
S.screen = "overview"
S.selLane = 1
S.selStep = 1
S.param = 1
S.cursor = 1
S.editing = false
S.dirtyFlag = true                        -- first draw always paints

local NOTE_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local TYPE_COLORS = { note = { 90, 170, 255 }, mod = { 90, 220, 120 },
    trig = { 255, 180, 90 }, gate = { 255, 110, 110 } }
local BG = { 12, 12, 16 }
local DIM = { 64, 64, 74 }
local WHITE = { 235, 235, 235 }
local BAR = { 255, 255, 255 }
local GREY = { 150, 150, 160 }

local Menu                                -- lazy: menu.lua on first Config

local function used(l)
    if l.height == 1 then return l.length end
    return l.width * l.height
end

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end return v
end

local function stripValue(l, s)
    if l.type == "note" then return l.pitch[s] end
    if l.type == "mod" then return l.value[s] end
    return l.gate[s]
end

function S.touch() S.dirtyFlag = true end

-- ------------------------------------------------------------- drawing ---

-- one step cell: dim base + value fill + playhead/selection bars
local function cell(lcd, x, y, w, h, l, step, selStep)
    local color = TYPE_COLORS[l.type]
    lcd:draw_area_filled(x, y, x + w, y + h, DIM)
    local v = stripValue(l, step)
    if l.type == "note" or l.type == "mod" then
        local fh = math.floor(v / 127 * h)
        if fh > 0 then lcd:draw_area_filled(x, y + h - fh, x + w, y + h, color) end
    elseif v == 1 then
        lcd:draw_area_filled(x, y, x + w, y + h, color)
    end
    if step == l.position then lcd:draw_area_filled(x, y + h - 2, x + w, y + h, BAR) end
    if step == selStep then lcd:draw_area_filled(x, y, x + w, y + 2, BAR) end
end

local function drawOverview(lcd)
    lcd:draw_area_filled(0, 0, 320, 240, BG)
    for lane = 1, #Engine.lanes do
        local l = Engine.state(lane)
        local y = (lane - 1) * 60
        lcd:draw_text_fast(lane .. " " .. string.upper(string.sub(l.type, 1, 3)),
            6, y + 22, 16, (lane == S.selLane) and WHITE or TYPE_COLORS[l.type])
        for s = 1, 16 do
            local sel = (lane == S.selLane) and S.selStep or 0
            cell(lcd, 92 + (s - 1) * 14, y + 8, 12, 44, l, s, sel)
        end
    end
    lcd:draw_swap()
end

local function paramLabel()
    local l = Engine.state(S.selLane)
    if l.type ~= "note" then return "VAL" end
    if S.param == 1 then return "PIT" elseif S.param == 2 then return "VEL" end
    return "LEN"
end

local function readout(l)
    local s = S.selStep
    if l.type == "note" then
        if S.param == 1 then
            local p = l.pitch[s]
            return NOTE_NAMES[(p % 12) + 1] .. (math.floor(p / 12) - 1)
        elseif S.param == 2 then return "V" .. l.velocity[s]
        else return l.stepLength[s] .. "t" end
    elseif l.type == "mod" then return tostring(l.value[s])
    else return (l.gate[s] == 1) and "ON" or "OFF" end
end

local function drawFocus(lcd)
    lcd:draw_area_filled(0, 0, 320, 240, BG)
    local l = Engine.state(S.selLane)
    for row = 1, 4 do
        for col = 1, 4 do
            local s = (row - 1) * 4 + col
            cell(lcd, (col - 1) * 70, (row - 1) * 58 + 6, 66, 52, l, s, S.selStep)
        end
    end
    lcd:draw_area_filled(282, 6, 318, 122, DIM)
    lcd:draw_text_fast(paramLabel(), 286, 20, 8, GREY)
    lcd:draw_text_fast(readout(l), 286, 40, 16, WHITE)
    lcd:draw_swap()
end

-- ---------------------------------------------------------------- draw ---

function S.draw(lcd)
    for lane = 1, #Engine.lanes do
        local p = Engine.state(lane).position
        if lastPos[lane] ~= p then lastPos[lane] = p; S.dirtyFlag = true end
    end
    if not S.dirtyFlag then return end
    S.dirtyFlag = false
    if S.screen == "focus" then drawFocus(lcd)
    elseif S.screen == "config" then Menu.draw(lcd)
    else drawOverview(lcd) end
end

-- ------------------------------------------------------------- controls ---

local function move(d)
    S.selStep = ((S.selStep - 1 + d) % used(Engine.state(S.selLane))) + 1
    S.touch()
end

local function editFocused(d)
    local lane, step = S.selLane, S.selStep
    local l = Engine.state(lane)
    if l.type == "note" then
        if S.param == 1 then Engine.setPitch(lane, step, l.pitch[step] + d)
        elseif S.param == 2 then Engine.setVelocity(lane, step, l.velocity[step] + d * 2)
        else Engine.setStepLength(lane, step, l.stepLength[step] + d * 6) end
    elseif l.type == "mod" then
        Engine.setValue(lane, step, l.value[step] + d * 2)
    else
        Engine.setGate(lane, step, (l.gate[step] + 1) % 2)
    end
    S.touch()
end

function S.key(i)
    if S.screen == "config" then
        if i == 0 or i == 1 then
            S.screen = S.cfgReturn or "overview"
            S.touch()
        end
        return
    end
    if i == 0 then
        -- LAZY Config: menu.lua compiles on first entry
        if not Menu then
            Menu = require("menu")
            Menu.init(S, Engine)
            Menu.page = (S.screen == "focus") and "lane" or "globals"
        else
            Menu.page = (S.screen == "focus") and "lane" or "globals"
        end
        S.cfgReturn = S.screen
        S.cursor = 1; S.editing = false
        S.screen = "config"; S.touch()
    elseif i == 1 then
        S.screen = (S.screen == "overview") and "focus" or "overview"; S.touch()
    elseif i == 4 then move(-1)
    elseif i == 5 then move(1)
    elseif i == 6 then Engine.zero(S.selLane); S.touch()
    elseif i == 7 then Engine.shred(S.selLane); S.touch() end
end

function S.btn(i)
    if i >= 9 and i <= 12 then
        local lanes = #Engine.lanes
        if i - 8 <= lanes then
            S.selLane = i - 8
            S.selStep = clamp(S.selStep, 1, used(Engine.state(S.selLane)))
            S.param = 1
            S.touch()
        end
    end
end

function S.turn(d)
    if S.screen == "config" then
        Menu.turn(d)
    elseif S.screen == "focus" then
        editFocused(d)
    else
        move(d)
    end
end

function S.press()
    if S.screen == "config" then
        S.editing = not S.editing; S.touch()
    elseif S.screen == "focus" then
        local n = (Engine.state(S.selLane).type == "note") and 3 or 1
        S.param = (S.param % n) + 1
        S.touch()
    else
        S.screen = "focus"; S.touch()
    end
end

return S
