-- lane_screen.lua — the lane GUI: Overview (all lanes as step strips) and
-- Focus (one lane: its step grid in its own dims + key/value rows).
-- Drop-in for screen.lua / text_screen.lua (same S.key/btn/turn/press/draw/
-- touch surface, bundled as "screen" in seq3s by `build_bundles.py
-- --gui=lanes`). Budgeted against text_screen.lua: the Focus rows ARE the
-- text screen's rows, so no menu module exists.
--
-- Redraw: a full repaint on any edit / selection / screen change. A playhead
-- move only repaints the two cells it moved between (PARTIAL), unless the
-- Overview's "draw" setting is switched to F (full). Partial drawing assumes
-- draw_swap keeps the framebuffer between frames, which is unconfirmed on the
-- device (docs/SCREENS.md): if moving playheads flicker, set draw F.
--
-- Overview = the lanes + the GENERAL settings bar (run, slot, save, load,
-- draw); Focus = one lane + its LANE settings. Controls:
--   key 1 Overview <-> Focus · key 0 run/stop · 3 Random · 6/7 Zero/Shred ·
--   btns 9-12 lane select.
--   Overview: keys 4/5 prev/next general setting; encoder press edits it
--   (run/save/load/draw fire directly); turn changes it while editing,
--   otherwise selects the lane.
--   Focus: keys 4/5 prev/next step; encoder turn moves the row cursor;
--   press toggles edit; turn changes the value while editing.
--
-- Device rules: no string.format, no collectgarbage, no package.loaded.

local RX     = require("midi_rx")
RX.ensure()                               -- chain + demo if no clock byte yet
local Engine = require("engine")
local Lane   = require("lane")

local S = { focus = false, selLane = 1, selStep = 1, cursor = 1, editing = false,
    gcur = 1, gedit = false, slot = 1, status = "-", dirtyFlag = true, partial = true }
local lastPos = { 0, 0, 0, 0 }
local Persist                             -- lazy: persist on first save/load

local NOTE_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local TYPES = { "note", "trig" }
local DIMS  = { "16x1", "8x2", "5x3", "4x3", "4x4" }
local HEAD = 5                            -- lane rows before the step rows
local STEP_ROWS = { note = { "pitch", "vel", "len" }, trig = { "gate", "vel", "len" } }
local FIRST = { "type", "dims", "div", "ch", "step" }
local GEN   = { "run", "slot", "save", "load", "draw" }   -- Overview settings
local BG, WELL = { 0, 0, 0 }, { 40, 40, 48 }
local WHITE, GREY = { 235, 235, 235 }, { 120, 120, 130 }
local COLOR = { note = { 90, 170, 255 }, trig = { 255, 170, 70 } }

local function lane() return Engine.lanes[S.selLane] end

local function used(l)
    if l.height == 1 then return l.length end
    return l.width * l.height
end

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end return v
end

-- ------------------------------------------------------------ rows ---

local function rowKey(i)
    local steps = STEP_ROWS[lane().type]
    if i <= HEAD then return FIRST[i] end
    i = i - HEAD
    return steps[i]
end

local function rowCount() return HEAD + #STEP_ROWS[lane().type] end

local function cycle(list, v, d)
    local idx = 1
    for i = 1, #list do if list[i] == v then idx = i end end
    return list[((idx - 1 + d) % #list) + 1]
end

local function value(k)
    local l, s = lane(), S.selStep
    if k == "type" or k == "dims" then return l[k] end
    if k == "div" then return l.division end
    if k == "ch" then return l.channel end
    if k == "step" then return s .. "/" .. used(l) end
    if k == "pitch" then
        local p = l.pitch[s]
        return NOTE_NAMES[(p % 12) + 1] .. (p // 12 - 1)
    end
    if k == "vel" then return l.velocity[s] end
    if k == "len" then return l.stepLength[s] .. "t" end
    return l.gate[s] == 1 and "on" or "off"   -- gate
end

-- General (Overview) settings.
local function gvalue(k)
    if k == "run" then return Engine.running and "on" or "off" end
    if k == "slot" then return S.slot end
    if k == "draw" then return S.partial and "P" or "F" end
    return S.status                       -- save / load: "-", "ok", "er"
end

local function persist()
    if not Persist then
        Persist = require("persist")
        Persist.prefix = "s"              -- module file storage is flat: s01.lua
    end
    return Persist
end

local function apply(k, d)
    local n, l, s = S.selLane, lane(), S.selStep
    -- Lane fields are written DIRECTLY, clamped here: the engine's setters
    -- live in a lazy bundle, and editing must not compile one.
    if k == "type" then l.type = cycle(TYPES, l.type, d)
    elseif k == "dims" then Lane.setDims(l, cycle(DIMS, l.dims, d))
    elseif k == "div" then l.division = clamp(l.division + d, 1, 16)
    elseif k == "ch" then l.channel = clamp(l.channel + d, 1, 16)
    elseif k == "step" then S.selStep = ((s - 1 + d) % used(l)) + 1
    elseif k == "pitch" then l.pitch[s] = clamp(l.pitch[s] + d, 0, 127)
    elseif k == "vel" then l.velocity[s] = clamp(l.velocity[s] + d * 2, 1, 127)
    elseif k == "len" then l.stepLength[s] = clamp(l.stepLength[s] + d, 1, 96)
    elseif k == "gate" then l.gate[s] = 1 - l.gate[s]
    end
    S.selStep = clamp(S.selStep, 1, used(lane()))
    S.cursor = clamp(S.cursor, 1, rowCount())
    S.dirtyFlag = true
end

local function gapply(k, d)
    if k == "run" then
        if Engine.running then Engine.onStop() else Engine.onStart() end
    elseif k == "slot" then S.slot = clamp(S.slot + d, 1, 24)
    elseif k == "save" then S.status = persist().saveSlot(S.slot) and "ok" or "er"
    elseif k == "load" then S.status = persist().loadSlot(S.slot) and "ok" or "er"
    elseif k == "draw" then S.partial = not S.partial
    end
    S.selStep = clamp(S.selStep, 1, used(lane()))   -- a load may shrink a lane
    S.dirtyFlag = true
end

function S.touch() S.dirtyFlag = true end

-- ------------------------------------------------------------ cells ---

-- Cell rectangle of step s of lane i: Overview = one 16-cell strip per lane;
-- Focus = the selected lane's grid in its own dims (16x1 .. 4x4).
local function cellRect(i, l, s)
    if not S.focus then                   -- 48 px a lane, bar below at 196
        local x0, y0 = 64 + (s - 1) * 16, (i - 1) * 48 + 3
        return x0, y0, x0 + 13, y0 + 40
    end
    local w, h = l.width, l.height
    local cw, ch = 320 // w, 114 // h
    local x0 = ((s - 1) % w) * cw + 1
    local y0 = 2 + ((s - 1) // w) * ch
    return x0, y0, x0 + cw - 3, y0 + ch - 3
end

-- A note lane's pitch span over its used steps: bars are scaled to it so
-- the melody's contour shows (a fixed 0..127 scale flattens an octave).
local function span(l)
    local lo, hi = 127, 0
    for s = 1, used(l) do
        local p = l.pitch[s]
        if p < lo then lo = p end
        if p > hi then hi = p end
    end
    return lo, (hi > lo) and (hi - lo) or 1
end

-- One step cell: value (pitch bar / gate block), playhead bar, selection
-- outline. Draw calls are budgeted (the harness — and maybe the device —
-- drops a frame's tail past ~110 calls): a full Overview frame paints one
-- background strip per lane and then only what is ON, so an empty trig step
-- costs nothing. `clear` repaints the cell's own background first (partial
-- redraws and Focus). Steps past the used length are left as background.
local function cell(lcd, i, l, s, clear)
    if s > used(l) then return end
    local x0, y0, x1, y1 = cellRect(i, l, s)
    if clear then lcd:draw_rectangle_filled(x0, y0, x1, y1, WELL) end
    if l.type == "note" then
        local lo, range = span(l)
        local fh = 2 + (y1 - y0 - 2) * (l.pitch[s] - lo) // range
        lcd:draw_rectangle_filled(x0, y1 - fh, x1, y1, COLOR.note)
    elseif l.gate[s] == 1 then
        lcd:draw_rectangle_filled(x0, y0, x1, y1, COLOR.trig)
    end
    if s == l.position then lcd:draw_rectangle_filled(x0, y1 - 3, x1, y1, WHITE) end
    if i == S.selLane and s == S.selStep then lcd:draw_rectangle(x0, y0, x1, y1, WHITE) end
end

-- ------------------------------------------------------------- draw ---

local function drawOverview(lcd)
    for i = 1, #Engine.lanes do
        local l = Engine.lanes[i]
        local y = (i - 1) * 48 + 3
        local c = (i == S.selLane) and WHITE or GREY
        -- size-16 text is ~14 px a glyph: the 60 px label column fits 3-4
        lcd:draw_text_fast(i .. (l.type == "note" and " N" or " T"), 4, y, 16, c)
        lcd:draw_text_fast("/" .. l.division, 4, y + 20, 16, c)
        -- one strip behind the lane's used steps; cells paint only what is on
        local u = used(l)
        if u > 16 then u = 16 end
        lcd:draw_rectangle_filled(63, y - 1, 64 + (u - 1) * 16 + 14, y + 41, WELL)
        for s = 1, u do cell(lcd, i, l, s) end
    end
    -- general settings bar: 3 + 2 items, selected white, editing orange
    for g = 1, #GEN do
        local c = (g ~= S.gcur) and GREY or (S.gedit and COLOR.trig or WHITE)
        lcd:draw_text_fast(GEN[g] .. " " .. gvalue(GEN[g]),
            4 + ((g - 1) % 3) * 106, 198 + ((g - 1) // 3) * 21, 16, c)
    end
end

local function drawFocus(lcd)
    local l = lane()
    for s = 1, l.width * l.height do cell(lcd, S.selLane, l, s, true) end
    for i = 1, rowCount() do
        local sel = i == S.cursor
        local k = rowKey(i)
        local x, y = (i <= 4) and 4 or 164, 122 + ((i - 1) % 4) * 19
        -- one string per row, <= 11 glyphs: a 160 px column at ~14 px a glyph
        lcd:draw_text_fast((sel and (S.editing and ">" or "-") or " ") .. k .. " " .. value(k),
            x, y, 16, sel and WHITE or GREY)
    end
end

function S.draw(lcd)
    local lanes = Engine.lanes
    local moved = false
    for i = 1, #lanes do
        local p = lanes[i].position
        if lastPos[i] ~= p then
            -- Partial: repaint only the cells this lane's playhead left and
            -- reached (Focus shows only the selected lane).
            if S.partial and not S.dirtyFlag and (not S.focus or i == S.selLane) then
                local l, old = lanes[i], lastPos[i]
                if old >= 1 and old <= 16 then cell(lcd, i, l, old, true) end
                cell(lcd, i, l, p, true)
                moved = true
            elseif not S.partial then
                S.dirtyFlag = true
            end
            lastPos[i] = p
        end
    end
    if S.dirtyFlag then
        S.dirtyFlag = false
        lcd:draw_rectangle_filled(0, 0, 319, 239, BG)
        if S.focus then drawFocus(lcd) else drawOverview(lcd) end
        moved = true
    end
    if moved then lcd:draw_swap() end
end

-- --------------------------------------------------------- controls ---

function S.turn(d)
    if not S.focus then
        if S.gedit then gapply(GEN[S.gcur], d); return end
        S.selLane = ((S.selLane - 1 + d) % #Engine.lanes) + 1
        apply("", 0)
    elseif S.editing then
        apply(rowKey(S.cursor), d)
    else
        S.cursor = ((S.cursor - 1 + d) % rowCount()) + 1
        S.dirtyFlag = true
    end
end

function S.press()
    if S.focus then S.editing = not S.editing; S.dirtyFlag = true; return end
    local k = GEN[S.gcur]
    if k == "slot" then S.gedit = not S.gedit; S.dirtyFlag = true
    else gapply(k, 1) end                 -- run / save / load / draw fire
end

-- Keys 4/5: prev/next STEP in Focus, prev/next general SETTING in Overview.
local function prevNext(d)
    if S.focus then apply("step", d); return end
    S.gcur = ((S.gcur - 1 + d) % #GEN) + 1
    S.gedit = false
    S.dirtyFlag = true
end

function S.key(i)
    if i == 0 then gapply("run", 1)
    elseif i == 1 then
        S.focus = not S.focus; S.editing = false; S.gedit = false; S.dirtyFlag = true
    elseif i == 4 then prevNext(-1)
    elseif i == 5 then prevNext(1)
    elseif i == 3 then Engine.randomize(S.selLane); S.dirtyFlag = true
    elseif i == 6 then Engine.zero(S.selLane); S.dirtyFlag = true
    elseif i == 7 then Engine.shred(S.selLane); S.dirtyFlag = true end
end

function S.btn(i)
    if i >= 9 and i - 8 <= #Engine.lanes then
        S.selLane = i - 8
        apply("", 0)                      -- re-clamp step + cursor, redraw
    end
end

return S
