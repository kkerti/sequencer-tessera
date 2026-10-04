-- lane_focus.lua — the lane GUI's Focus rows: every lane setting that applies
-- to the selected lane's type and dims (docs/PARAM_DEPENDENCIES.md), plus the
-- selected step's values, ten rows to a page.
--
-- LAZY, its own bundle (seq3f): lane_screen.lua requires it on the first
-- Focus entry, so the first press compiles only the Overview. Splitting keeps
-- each lazy compile small: a compile peaks at ~resident + 3.5x its source.
--
-- Shape: factory(S, tool) -> { build, turn, edit, rows }. S is the screen
-- state; tool carries the screen's lane / used / clamp helpers.
--
-- Device rules: no string.format, no collectgarbage, no package.loaded.

local Lane   = require("lane")
local Scales = require("scales")

local NOTE_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local TYPES = { "note", "trig" }
local DIMS  = { "16x1", "8x2", "5x3", "4x3", "4x4" }
-- Sources in musical order (enums: sources.lua) and their labels.
local SRC_ORD = { 0, 1, 2, 9, 3, 6, 10, 4, 7, 5, 8, 11, 12, 13, 14 }
local SRC_LBL = { [0] = "off", "1", "1/2", "1/4", "1/8", "1/16", "1/4T", "1/8T",
    "1/16T", "1/4.", "1/8.", "L1", "L2", "L3", "L4" }
local SRC_FIELD = { adv = "advanceSource", xadv = "xAdvanceSource",
    yadv = "yAdvanceSource", prev = "previousSource", rst = "resetSource",
    rnd = "randomSource", shft = "shiftSource" }
local SCALES = { 0, 0xAB5, 0x5AD, 0x6AD, 0x5AB, 0xAD5, 0x6B5, 0x9AD, 0x295, 0x4A9 }
-- <= 4 glyphs: "-scale pmaj" is the 11 a right-column row has room for
local SCALE_LBL = { "chr", "maj", "min", "dor", "phr", "lyd", "mix", "hmin", "pmaj", "pmin" }
-- Numeric rows: key -> { lane field, lo, hi, per-step array?, note name? }.
local NUM = { div = { "division", 1, 16 }, ch = { "channel", 1, 16 },
    len = { "length", 1, 16 }, amt = { "shiftAmount", -15, 15 },
    note = { "midiNote", 0, 127, false, 1 }, lo = { "minNote", 0, 127, false, 1 },
    hi = { "maxNote", 0, 127, false, 1 }, pitch = { "pitch", 0, 127, 1, 1 },
    vel = { "velocity", 1, 127, 1 }, dur = { "stepLength", 1, 96, 1 } }
local PAGE = 10                           -- rows on screen: two columns of 5

local function find(list, v)
    for i = 1, #list do if list[i] == v then return i end end
end

local function cycle(list, v, d)
    local idx = find(list, v) or 1
    return list[((idx - 1 + d) % #list) + 1]
end

local function nn(p) return NOTE_NAMES[(p % 12) + 1] .. (p // 12 - 1) end

return function(S, tool)
    local lane, used, clamp = tool.lane, tool.used, tool.clamp
    local F = {}

    -- The selected lane's rows, most-played first; rebuilt when the lane, its
    -- type or its dims change. 16x1 has adv/len, a matrix xadv/yadv up front
    -- and adv later: the engine runs a matrix's linear advance too.
    local ROWS, nrows = {}, 0
    local function add(k) nrows = nrows + 1; ROWS[nrows] = k end
    function F.build()
        local l = lane()
        local note, line = l.type == "note", l.height == 1
        nrows = 0
        add("step"); add(note and "pitch" or "gate"); add("vel"); add("dur"); add("div")
        add(line and "adv" or "xadv"); add(line and "len" or "yadv")
        if note then add("scale"); add("root"); add("lo"); add("hi") else add("note") end
        add("type"); add("dims"); add("ch")
        if not line then add("adv") end
        add("prev")
        add("rst"); add("rnd"); add("shft"); add("amt")
        for i = nrows + 1, #ROWS do ROWS[i] = nil end
        S.cursor = clamp(S.cursor, 1, nrows)
    end

    local function value(k)
        local l, s = lane(), S.selStep
        local f, sp = SRC_FIELD[k], NUM[k]
        if f then return SRC_LBL[l[f]] or "?" end
        if sp then
            local v = l[sp[1]]
            if sp[4] then v = v[s] end
            return sp[5] and nn(v) or v
        end
        if k == "step" then return s .. "/" .. used(l) end
        if k == "root" then return NOTE_NAMES[l.root + 1] end
        if k == "scale" then return SCALE_LBL[find(SCALES, l.rawScaleMask) or 0] or "cust" end
        if k == "gate" then return l.gate[s] == 1 and "on" or "off" end
        return l[k]                       -- type, dims
    end

    -- Lane fields are written DIRECTLY, clamped here: the engine's setters
    -- live in a lazy bundle, and editing must not compile one.
    function F.edit(k, d)
        local l, s = lane(), S.selStep
        local f, sp = SRC_FIELD[k], NUM[k]
        if f then l[f] = cycle(SRC_ORD, l[f], d)
        elseif sp then
            local t, i = l, sp[1]
            if sp[4] then t, i = l[i], s end
            t[i] = clamp(t[i] + d, sp[2], sp[3])
            if l.maxNote < l.minNote then    -- lo pushes hi, hi pushes lo
                if k == "lo" then l.maxNote = l.minNote else l.minNote = l.maxNote end
            end
        elseif k == "type" then l.type = cycle(TYPES, l.type, d)
        elseif k == "dims" then Lane.setDims(l, cycle(DIMS, l.dims, d))
        elseif k == "step" then S.selStep = ((s - 1 + d) % used(l)) + 1
        elseif k == "scale" or k == "root" then
            if k == "scale" then l.rawScaleMask = cycle(SCALES, l.rawScaleMask, d)
            else l.root = (l.root + d) % 12 end
            l.scaleMask = Scales.rotate(l.rawScaleMask, l.root)
        elseif k == "gate" then l.gate[s] = 1 - l.gate[s]
        end
        if l.position > used(l) then l.position = 1 end
        F.build()
        S.selStep = clamp(S.selStep, 1, used(l))
        S.dirtyFlag = true
    end

    -- Encoder turn: edit the cursor's row, or move the cursor.
    function F.turn(d)
        if S.editing then return F.edit(ROWS[S.cursor], d) end
        S.cursor = ((S.cursor - 1 + d) % nrows) + 1
        S.dirtyFlag = true
    end

    -- The cursor's page of rows, two columns of 5 under the grid. One string
    -- per row, <= 11 glyphs: a 160 px column at ~14 px a glyph.
    function F.rows(lcd, white, grey)
        local first = (S.cursor - 1) // PAGE * PAGE
        for i = first + 1, math.min(first + PAGE, nrows) do
            local sel, k, r = i == S.cursor, ROWS[i], i - first - 1
            lcd:draw_text_fast((sel and (S.editing and ">" or "-") or " ") .. k .. " " .. value(k),
                r < 5 and 4 or 164, 122 + (r % 5) * 23, 16, sel and white or grey)
        end
    end

    F.build()
    return F
end
