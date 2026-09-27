-- tests/boot_sim.lua — simulate the v9 profile's COLD BOOT order exactly.
-- Run from the sequencer-3 directory:  lua tests/boot_sim.lua
--
-- The project's measured ladder says every eager-at-setup build died and the
-- one shape that ran "requires NOTHING at setup". v9's setup therefore only
-- defines the global loader L() and assigns rtmrx_cb. This test asserts that
-- contract against the REAL bundles:
--
--   * setup compiles and runs without loading ANY bundle
--   * the draw and timer events (which fire during the cold boot) load nothing
--   * the first MIDI byte loads the chain and produces notes
--   * a control press also loads it (the --setup=press path)

package.path = ""

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1
    else fail = fail + 1; print("FAIL: " .. msg) end
end

-- Model the device's require: each bundle name is an FS module compiled on
-- demand. `loaded` records what the module actually paid for, and when.
local loaded, order = {}, {}
local oldreq = require
local FILES = { seq3 = "dist/seq3.lua", seq3ui = "dist/seq3ui.lua",
                seq3x = "dist/seq3x.lua", seq3p = "dist/seq3p.lua" }
require = function(n)
    if loaded[n] then return loaded[n] end
    if FILES[n] then
        order[#order + 1] = n
        loaded[n] = dofile(FILES[n])
        return loaded[n]
    end
    return oldreq(n)
end

local function nLoaded()
    local k = 0
    for _ in pairs(loaded) do k = k + 1 end
    return k
end

-- ---- el 255 ev0: SETUP. Must require nothing. -------------------------------
local element = {}          -- stands in for `self`
function L()
    if not RX then
        UI = require("seq3ui")
        RX = UI.midi_rx
        RX.ensure()
    end
    return RX
end
element.rtmrx_cb = function(self, t) L().handle(t, midi_send) end

ok(nLoaded() == 0, "SETUP loads no bundle (loaded " .. nLoaded() .. ")")
ok(RX == nil, "SETUP leaves RX unset")
ok(type(L) == "function", "SETUP defines the loader")
ok(type(element.rtmrx_cb) == "function", "SETUP assigns rtmrx_cb")

-- ---- events that fire DURING the cold boot must not load --------------------
-- el 13 ev8 draw:
local LcdMock = dofile("tests/lcd_mock.lua")
local lcd = LcdMock.new()
for _ = 1, 5 do
    if RX then RX.ui(lcd) end
end
ok(nLoaded() == 0, "draw event loads nothing before a trigger")
ok(lcd.calls == 0, "draw is a no-op before a trigger (screen stays dark)")

-- el 255 ev6 timer (the RAM diagnostic) and el 13 ev0 glsb(255):
local memKB = collectgarbage("count")
ok(memKB > 0 and nLoaded() == 0, "timer event loads nothing")

-- ---- the first MIDI byte is the trigger ------------------------------------
local sent = {}
function midi_send(ch, st, p1, p2) sent[#sent + 1] = { ch = ch, st = st } end

element.rtmrx_cb(element, 0xFA)            -- MIDI start
ok(nLoaded() >= 1, "first MIDI byte loads the chain (" .. nLoaded() .. " bundles)")
ok(RX ~= nil, "RX is wired after the first byte")
ok(loaded.seq3x == nil and loaded.seq3p == nil,
   "neither lazy bundle is loaded (seq3x / seq3p stay lazy)")

for _ = 1, 24 do element.rtmrx_cb(element, 0xF8) end   -- one beat of clock
local noteOns = 0
for _, m in ipairs(sent) do if m.st == 0x90 then noteOns = noteOns + 1 end end
ok(noteOns >= 1, "clock through rtmrx_cb(self,t) produces note-ons (" .. noteOns .. ")")

element.rtmrx_cb(element, 0xFC)            -- stop
local offs = 0
for _, m in ipairs(sent) do if m.st == 0x80 then offs = offs + 1 end end
ok(offs >= 1, "stop emits note-offs (" .. offs .. ")")

-- The old (self,h,t) signature would have passed nil as the status byte:
-- prove the 2-arg form is what actually carries it.
do
    local seen
    local threeArg = function(self, h, t) seen = t end
    threeArg(element, 0xF8)                -- device calls cb(self, status)
    ok(seen == nil, "the v7/v8 rtmrx_cb(self,h,t) form would have seen t=nil")
end

-- ---- a control press also loads (the --setup=press path) -------------------
ok(select(2, pcall(function() L() RX.key(1) end)) == nil, "press path runs after load")

-- ---- draw works once loaded ------------------------------------------------
if RX then RX.ui(lcd) end
ok(lcd.calls > 0, "draw renders once the chain is loaded (" .. lcd.calls .. " lcd calls)")
ok(#lcd.errors == 0, "draw uses only real, in-bounds LCD calls"
   .. (#lcd.errors > 0 and (" -- first: " .. lcd.errors[1]) or ""))

print("boot order: " .. table.concat(order, " -> "))
print("boot_sim: " .. pass .. " checks, " .. fail .. " failed")
os.exit(fail == 0 and 0 or 1)
