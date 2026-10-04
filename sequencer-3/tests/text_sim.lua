-- tests/text_sim.lua — drive the TEXT-ONLY GUI (src/device/text_screen.lua)
-- the way the device does: midi_rx loads the chain, the screen draws through
-- the strict LCD mock, and every control goes through S.key/btn/turn/press.
-- Run from the sequencer-3 directory:  lua tests/text_sim.lua
--
-- Loads SOURCE modules (the text screen stands in for "screen", exactly as
-- `build_bundles.py --gui=text` bundles it), so it runs whatever the default
-- dist build is.

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
    screen = "src/device/text_screen.lua",
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

-- a control press loads the chain + the text screen
RX.key(1)
ok(loaded.screen ~= nil, "a key press loads the text screen")
ok(loaded.menu == nil, "the text GUI never loads menu.lua")
local S, E = loaded.screen, loaded.engine

local lcd = dofile("tests/lcd_mock.lua").new()
local texts = {}
local draw = lcd.draw_text_fast
lcd.draw_text_fast = function(self, s, ...) texts[#texts + 1] = s; return draw(self, s, ...) end

local function frame()
    texts = {}
    RX.ui(lcd)
    return table.concat(texts, "|")
end

local f = frame()
ok(#lcd.errors == 0, "first draw is within the LCD contract: " .. tostring(lcd.errors[1]))
ok(f:find("type") and f:find("note") and f:find("pitch"), "rows show key/value pairs: " .. f)
ok(f:find("%*1:"), "status line marks the selected lane")
ok(frame() == "", "no redraw when nothing changed")

-- clock moves the playhead -> redraw
RX.handle(0xFA, send)
for _ = 1, 24 do RX.handle(0xF8, send) end
ok(#sent > 0, "clock produces MIDI out")
ok(frame() ~= "", "playhead move triggers a redraw")

-- edit the step pitch: cursor to 'pitch' (row 6), press to edit, turn
local p0 = E.lanes[1].pitch[1]
for _ = 1, 5 do S.turn(1) end
S.press()
S.turn(3)
ok(E.lanes[1].pitch[1] == p0 + 3, "turning in edit mode changes the step pitch")
S.press()

-- change lane type through the 'type' row
S.cursor = 1; S.press(); S.turn(1); S.press()
ok(E.lanes[1].type == "trig", "type row cycles note -> trig")
f = frame()
ok(f:find("gate") and not f:find("pitch"), "trig lane shows a gate row, not pitch")
S.cursor = 1; S.press(); S.turn(1); S.press()
ok(E.lanes[1].type == "note", "type row cycles trig -> note")

-- lane select and trig lane rows
S.btn(10)
ok(S.selLane == 2, "btn 10 selects lane 2")
f = frame()
ok(f:find("gate") and f:find("%*2:"), "trig lane shows the gate row and marks lane 2")

-- run/stop via key 0
local was = E.running
S.key(0)
ok(E.running ~= was, "key 0 toggles run")
S.key(0)

-- shred/zero go through the lazy ops module
S.key(7)
ok(loaded.ops ~= nil, "Shred loads ops lazily")
local before = {}
for i = 1, 16 do before[i] = E.lanes[S.selLane].gate[i] end
local changed = false
for _ = 1, 4 do                           -- 4 rolls: a no-op roll is ~1/65536
    S.key(3)
    for i = 1, 16 do if E.lanes[S.selLane].gate[i] ~= before[i] then changed = true end end
end
ok(changed, "key 3 (Random) rerolls the selected lane")

-- save/load rows are listed, and persist stays unloaded until one is pressed
f = frame()
ok(f:find("save") and f:find("load") and f:find("slot"), "slot rows are listed")
ok(loaded.persist == nil, "persist is not compiled until save/load is pressed")

-- every drawn frame stayed inside the LCD contract
ok(#lcd.errors == 0, "all draws within the LCD contract: " .. tostring(lcd.errors[1]))

-- the text GUI stays off the pulse path: no allocation in a clock tick
local sink = function() end
for _ = 1, 200 do RX.handle(0xF8, sink) end   -- warm up: first-use lazy loads
collectgarbage(); collectgarbage()
local before = collectgarbage("count")
for _ = 1, 200 do RX.handle(0xF8, sink) end
local grew = collectgarbage("count") - before
ok(grew < 1, "200 pulses allocate < 1 KB with the text GUI loaded (" .. grew .. ")")

io.write("text_sim: " .. (pass + fail) .. " checks, " .. fail .. " failed\n")
os.exit(fail == 0 and 0 or 1)
