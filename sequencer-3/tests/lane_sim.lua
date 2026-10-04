-- tests/lane_sim.lua — drive the LANE GUI (src/device/lane_screen.lua) the way
-- the device does: midi_rx loads the chain, the screen draws through the
-- strict LCD mock, and every control goes through S.key/btn/turn/press.
-- Run from the sequencer-3 directory:  lua tests/lane_sim.lua

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1
    else fail = fail + 1; io.write("FAIL: " .. msg .. "\n") end
end

local PATHS = {
    sources = "src/core/sources.lua", scales = "src/core/scales.lua",
    transport = "src/core/transport.lua", lane = "src/core/lane.lua",
    engine = "src/core/engine.lua", ops = "src/core/ops.lua",
    source_names = "src/core/source_names.lua", edit = "src/core/edit.lua",
    preset = "src/core/preset.lua", persist = "src/core/persist.lua",
    device_boot = "src/device/device_boot.lua", midi_rx = "src/device/midi_rx.lua",
    screen = "src/device/lane_screen.lua", lane_focus = "src/device/lane_focus.lua",
}
local loaded = {}
local oldreq = require
require = function(n)
    if loaded[n] ~= nil then return loaded[n] end
    if PATHS[n] then loaded[n] = dofile(PATHS[n]); return loaded[n] end
    return oldreq(n)
end
print = function() end                    -- silence the boot ladder

local RX = require("midi_rx")
local sent = {}
local function send(ch, st, p1, p2) sent[#sent + 1] = st end

RX.key(1)                                 -- loads chain + screen, and only that
local S, E = loaded.screen, loaded.engine
ok(S ~= nil, "a key press loads the lane screen")
ok(loaded.menu == nil, "the lane GUI never loads menu.lua")
ok(not S.focus, "the loading press does not act: the GUI opens on the Overview")

local lcd = dofile("tests/lcd_mock.lua").new()
local texts, rects, swaps = {}, 0, 0
local dt, dr, ds = lcd.draw_text_fast, lcd.draw_rectangle_filled, lcd.draw_swap
lcd.draw_text_fast = function(self, s, ...) texts[#texts + 1] = s; return dt(self, s, ...) end
lcd.draw_rectangle_filled = function(self, ...) rects = rects + 1; return dr(self, ...) end
lcd.draw_swap = function(self, ...) swaps = swaps + 1; return ds(self, ...) end

local function frame()
    texts, rects, swaps = {}, 0, 0
    RX.ui(lcd)
    return table.concat(texts, "|")
end

-- ---- Overview ---------------------------------------------------------------
local f = frame()
ok(#lcd.errors == 0, "Overview draws within the LCD contract: " .. tostring(lcd.errors[1]))
ok(f:find("1 N") and f:find("2 T") and f:find("3 N") and f:find("4 T"),
   "Overview labels all four lanes with their type: " .. f)
-- draw-call budget: the harness drops a frame's tail past ~110 calls, and the
-- device may queue draws the same way
ok(rects >= 4 and rects + #texts + swaps <= 90,
   "Overview frame stays within the draw-call budget (" .. (rects + #texts + swaps) .. " calls)")
ok(swaps == 1, "one swap per frame")
ok(f:find("run on") and f:find("slot 1") and f:find("save") and f:find("load") and f:find("draw P"),
   "Overview shows the general settings bar: " .. f)
frame()
ok(swaps == 0 and rects == 0, "no redraw when nothing changed")

-- partial playhead redraw: a moved playhead repaints only its cells, no text
RX.handle(0xFA, send)
for _ = 1, 24 do RX.handle(0xF8, send) end
ok(#sent > 0, "clock produces MIDI out")
f = frame()
ok(f == "" and rects > 0 and rects < 32 and swaps == 1,
   "partial redraw: a playhead move repaints a few cells only (" .. rects .. " rects)")

-- general settings: key 5 x4 -> "draw", press flips it to F (full repaints)
for _ = 1, 4 do S.key(5) end
ok(S.gcur == 5, "Overview: key 5 steps through the general settings")
S.press()
ok(not S.partial and frame():find("draw F"), "pressing 'draw' switches to full repaints")
for _ = 1, 24 do RX.handle(0xF8, send) end
f = frame()
ok(f:find("1 N") and rects > 2 * 16, "draw F: a playhead move repaints the whole frame")
S.press()
ok(S.partial, "pressing 'draw' again restores partial repaints")
S.key(4)
ok(S.gcur == 4, "Overview: key 4 steps back through the general settings")
-- slot is edited, not fired: press, turn, press
S.key(4); S.key(4)
ok(S.gcur == 2, "cursor on 'slot'")
S.press(); S.turn(2); S.press()
ok(S.slot == 3 and not S.gedit, "slot: press to edit, turn to 3, press to leave")
S.key(4)
frame()

-- encoder in Overview selects the lane; press opens Focus
S.turn(1)
ok(S.selLane == 2, "Overview: turning selects the next lane")
S.turn(-1)
S.key(1)
ok(S.focus, "key 1 opens Focus")

-- ---- Focus ------------------------------------------------------------------
f = frame()
ok(#lcd.errors == 0, "Focus draws within the LCD contract: " .. tostring(lcd.errors[1]))
ok(rects + #texts + swaps <= 90, "Focus frame stays within the draw-call budget ("
   .. (rects + #texts + swaps) .. " calls)")
ok(f:find("pitch") and f:find("adv") and not f:find("save"),
   "Focus shows the lane rows (no general settings): " .. f)
ok(not f:find("2 T"), "Focus shows only the selected lane")

-- the demo's lane 1 is a 4x4 matrix: make it a line for the row tests
require("lane").setDims(E.lanes[1], "16x1"); E.lanes[1].advanceSource = 3; S.btn(9)

-- edit the step pitch: cursor to 'pitch' (row 2), press to edit, turn
local p0 = E.lanes[1].pitch[1]
S.turn(1)
S.press(); S.turn(3); S.press()
ok(E.lanes[1].pitch[1] == p0 + 3, "Focus: editing the pitch row changes the step")

-- dims: a 4x4 lane draws as a grid, every cell in bounds
-- the row index of setting k (the cursor's row draws as "-k value")
local function row(k)
    for i = 1, 30 do
        S.cursor = i; S.touch()
        if frame():find("-" .. k .. " ", 1, true) then return i end
    end
end
local DIMSROW = row("dims")
S.cursor = DIMSROW; S.press(); S.turn(4); S.press()
ok(E.lanes[1].dims == "4x4", "dims row cycles to 4x4")
frame()
ok(#lcd.errors == 0, "4x4 Focus grid stays in bounds: " .. tostring(lcd.errors[1]))
f = frame()
ok(row("xadv") and row("yadv") and not row("adv") and not row("len") and not row("prev"),
   "a matrix lane shows X/Y advance, not adv/len/prev")
S.cursor = row("dims"); S.press(); S.turn(1); S.press()
ok(E.lanes[1].dims == "16x1", "dims row cycles back to 16x1")

-- every lane setting is reachable: sources, scale, root, range, length
S.cursor = row("adv"); S.press(); S.turn(-1); S.press()
ok(frame():find("adv 1/4%."), "adv cycles in musical order (1/4 -> 1/4.)")
S.cursor = row("adv"); S.press(); S.turn(-4); S.press()
ok(E.lanes[1].advanceSource == 14 and frame():find("adv L4"), "adv wraps to lane 4 (L4)")
S.press(); S.turn(5); S.press()
ok(E.lanes[1].advanceSource == 3, "adv back to 1/4")
S.cursor = row("scale"); S.press(); S.turn(1); S.press()
ok(E.lanes[1].rawScaleMask == 0x5AD and frame():find("scale min"), "scale row: major -> minor")
S.cursor = row("root"); S.press(); S.turn(2); S.press()
ok(E.lanes[1].root == 2 and E.lanes[1].scaleMask == 0x5AD << 2 & 0xFFF | 0x5AD >> 10,
   "root row: D minor, mask rotated")
S.cursor = row("lo"); S.press(); S.turn(200); S.press()
ok(E.lanes[1].minNote == 127 and E.lanes[1].maxNote == 127, "lo pushes hi up")
S.press(); S.turn(-200); S.press()
S.cursor = row("len"); S.press(); S.turn(-8); S.press()
ok(E.lanes[1].length == 8 and frame():find("step %d+/8"), "len row shortens the lane to 8")
S.press(); S.turn(8); S.press()
for _, k in ipairs{ "rst", "rnd", "shft", "amt", "ch", "type", "prev", "hi" } do
    ok(row(k), "row '" .. k .. "' is on a Focus page")
end
ok(#lcd.errors == 0, "paged rows stay in bounds: " .. tostring(lcd.errors[1]))
S.cursor = 1

-- keys 4/5 in Focus move the step, not a setting
local st = S.selStep
S.key(5)
ok(S.selStep == st + 1, "Focus: key 5 is next step")
S.key(4)
ok(S.selStep == st, "Focus: key 4 is previous step")

-- lane select with the small buttons, trig lane rows
S.btn(10)
f = frame()
ok(S.selLane == 2 and f:find("gate"), "btn 10 selects lane 2 and its gate row shows")
ok(row("note") and not row("scale"), "a trig lane has a note row, no scale row")

-- key 1 back to the Overview
S.key(1)
f = frame()
ok(not S.focus and f:find("1 N"), "key 1 returns to the Overview")

-- performance keys
local was = E.running
S.key(0)
ok(E.running ~= was, "key 0 toggles run")
S.key(0)
S.key(7)
ok(loaded.ops ~= nil, "Shred loads ops lazily")
local before, changed = {}, false
for i = 1, 16 do before[i] = E.lanes[2].gate[i] end
for _ = 1, 4 do
    S.key(3)
    for i = 1, 16 do if E.lanes[2].gate[i] ~= before[i] then changed = true end end
end
ok(changed, "key 3 (Random) rerolls the selected lane")
ok(loaded.persist == nil, "persist is not compiled until save/load is pressed")

frame()
ok(#lcd.errors == 0, "all draws within the LCD contract: " .. tostring(lcd.errors[1]))

-- the GUI stays off the pulse path: no allocation in a clock tick
local sink = function() end
for _ = 1, 200 do RX.handle(0xF8, sink) end
collectgarbage(); collectgarbage()
local b = collectgarbage("count")
for _ = 1, 200 do RX.handle(0xF8, sink) end
local grew = collectgarbage("count") - b
ok(grew < 1, "200 pulses allocate < 1 KB with the lane GUI loaded (" .. grew .. ")")

io.write("lane_sim: " .. (pass + fail) .. " checks, " .. fail .. " failed\n")
os.exit(fail == 0 and 0 or 1)
