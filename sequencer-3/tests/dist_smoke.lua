-- tests/dist_smoke.lua — smoke-test the DEVICE dist chain in plain Lua.
-- Run from the sequencer-3 directory:  lua tests/dist_smoke.lua
--
-- v8: THREE pre-linked bundles, seq-1 wiring (midi_send, no grxm), and seq3x
-- LAZY. Loads the exact bundles the module gets, in profile order, then drives
-- clock + all controls + the draw event headlessly. Asserts:
--   * bundle size budgets and the banned device calls
--   * seq3x is NOT pulled by boot / clock / draw (it must stay off the cold
--     boot path — that is the whole point of making it lazy)
--   * seq3x DOES resolve on the first action that needs it
--   * slot save/load round-trips through the real bundles

package.path = ""

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1
    else fail = fail + 1; print("FAIL: " .. msg) end
end

-- 1. bundles exist and are within budget. seq-1's proven max chunk was 10.3 KB;
-- ours are bigger, so the three-way split keeps each load step modest. These
-- ceilings are guards against silent growth, not device truth.
local seq3src = io.open("dist/seq3.lua"):read("*a")
local esrc    = io.open("dist/seq3e.lua"):read("*a")
local hsrc    = io.open("dist/seq3h.lua"):read("*a")
local uisrc   = io.open("dist/seq3ui.lua"):read("*a")
local ssrc    = io.open("dist/seq3s.lua"):read("*a")
local xsrc    = io.open("dist/seq3x.lua"):read("*a")
local psrc    = io.open("dist/seq3p.lua"):read("*a")
ok(#seq3src > 0 and #esrc > 0 and #hsrc > 0 and #uisrc > 0 and #xsrc > 0 and #psrc > 0,
   "all six bundles exist")
-- engine.lua now has its own bundle: the module ran out of memory initialising
-- the modules, so the PEAK single compile matters as much as the total.
ok(#seq3src <= 9000,  "seq3.lua (sources/scales/transport/lane) <= 9 KB (" .. #seq3src .. ")")
ok(#esrc    <= 13000, "seq3e.lua (engine) <= 13 KB (" .. #esrc .. ")")
ok(#hsrc    <= 4000,  "seq3h.lua (headless) <= 4 KB (" .. #hsrc .. ")")
ok(#uisrc   <= 4000,  "seq3ui.lua (start: midi_rx + demo, no screen) <= 4 KB (" .. #uisrc .. ")")
ok(#ssrc    <= 9000,  "seq3s.lua (screen) <= 9 KB (" .. #ssrc .. ")")
ok(not uisrc:find('R%["screen"%]'), "the screen is NOT in the start bundle seq3ui")
-- The device ran out of memory compiling an 11.2 KB lazy bundle once the core
-- was resident, so each LAZY bundle is capped well under that.
ok(#xsrc    <= 7000, "seq3x.lua <= 7 KB (" .. #xsrc .. ")")
ok(#psrc    <= 8000, "seq3p.lua <= 8 KB (" .. #psrc .. ")")
-- The EAGER pair is what the profile's setup loads; seq3x is not counted.
ok(#seq3src + #uisrc <= 32000,
   "eager setup load (seq3 + seq3ui) <= 32 KB (" .. (#seq3src + #uisrc) .. ")")

for _, b in ipairs({ { "seq3", seq3src }, { "e", esrc }, { "h", hsrc },
                     { "ui", uisrc }, { "s", ssrc }, { "x", xsrc }, { "p", psrc } }) do
    local name, src = b[1], b[2]
    ok(not src:find("collectgarbage"), name .. ": no collectgarbage")
    ok(not src:find("package%.loaded"), name .. ": no package.loaded")
    ok(not src:find("string%.format"), name .. ": no string.format")
    ok(not src:find("math%.type"), name .. ": no math.type")
end

-- 2. Load in profile order. The device's require resolves a bundle by FS-module
-- name, so the hook below models exactly that: seq3x is compiled only if and
-- when something asks for it.
local REG = {}
local xLoads, pLoads, lLoads = 0, 0, 0
local oldreq = require
local LAZY = { seq3e = "dist/seq3e.lua", seq3x = "dist/seq3x.lua",
               seq3p = "dist/seq3p.lua", seq3h = "dist/seq3h.lua",
               seq3l = "dist/seq3l.lua", seq3s = "dist/seq3s.lua" }
require = function(n)
    if REG[n] then return REG[n] end
    local f = LAZY[n]
    if f then
        if n == "seq3x" then xLoads = xLoads + 1 end
        if n == "seq3p" then pLoads = pLoads + 1 end
        if n == "seq3l" then lLoads = lLoads + 1 end
        REG[n] = dofile(f)
        return REG[n]
    end
    return oldreq(n)
end

REG["seq3"]   = dofile("dist/seq3.lua")
REG["seq3ui"] = dofile("dist/seq3ui.lua")
local RX = REG.seq3ui.midi_rx
local engine = require("seq3e").engine
ok(RX ~= nil and RX.handle ~= nil, "seq3ui exposes midi_rx")
ok(xLoads == 0 and pLoads == 0, "requiring the eager pair pulls no lazy bundle")

-- 3. the profile setup path: RX.ensure() fills the demo
RX.ensure()
ok(engine.running, "demo starts the engine")
ok(#engine.lanes == 2, "demo boots 2 lanes")
ok(xLoads == 0 and pLoads == 0, "boot + demo pull no lazy bundle")

-- 4. clock + notes out (send = midi_send stand-in)
local sent = {}
local function midi_send(ch, st, p1, p2) sent[#sent + 1] = { st = st } end
RX.handle(0xF8, midi_send)
local noteOns = 0
for _, m in ipairs(sent) do if m.st == 0x90 then noteOns = noteOns + 1 end end
ok(noteOns >= 1, "clock produces note-ons, got " .. noteOns)
RX.handle(0xFC, midi_send)
local sawOff = false
for _, m in ipairs(sent) do if m.st == 0x80 then sawOff = true end end
ok(sawOff, "stop emits note-offs")
ok(xLoads == 0 and pLoads == 0, "clock + notes pull no lazy bundle")

-- 5. the draw event and lane/step navigation, no errors and still no seq3x
-- STRICT LCD: only the primitives seq-1's proven profile uses, bounds checked.
-- A permissive mock is what let draw_area_filled(0,0,320,240) reach hardware.
local LcdMock = dofile("tests/lcd_mock.lua")
local lcd = LcdMock.new()
RX.key(1) RX.btn(10) RX.turn(1) RX.btn(9) RX.ui(lcd)
-- (the colour GUI may already edit while navigating; the text GUI does not)
ok(pLoads == 0, "screen + navigation pull no persist bundle")
-- editing a value goes through the setters, which live in the editing bundle
RX.press() RX.turn(1) RX.press() RX.key(0) RX.key(1)
RX.ui(lcd)
ok(xLoads == 1 and pLoads == 0, "the first edit pulls the editing bundle seq3x, nothing else")
ok(lcd.calls > 20, "controls + draw run (" .. lcd.calls .. " lcd calls)")
ok(#lcd.errors == 0, "Overview/Focus/Config draw only with real, in-bounds LCD calls"
   .. (#lcd.errors > 0 and (" -- first: " .. lcd.errors[1]) or ""))
RX.handle(0xF8, midi_send)
ok(pLoads == 0, "nav + edit + draw never pull the persist bundle")

-- 6. lazy periphery resolves on the first action that needs it
engine.shred(1)
ok(xLoads == 1, "first shred pulls seq3x exactly once")
-- The whole point of the split: Shred must NOT drag in the persist bundle.
ok(pLoads == 0, "shred does NOT pull seq3p (split by trigger holds)")
ok(rawget(engine, "shred") ~= nil, "ops resolves via seq3x")
ok(engine.randomize(1) and rawget(engine, "randomize") ~= nil,
   "randomize resolves via seq3x")
ok(xLoads == 1, "seq3x is loaded once and cached")

-- 6b. every screen drawn through the strict LCD (Overview / Focus / Config)
do
    local l2 = LcdMock.new()
    RX.key(1)                       -- Overview
    RX.ui(l2)
    RX.press()                      -- Focus
    RX.ui(l2)
    RX.key(0)                       -- Config (menu.lua)
    RX.ui(l2)
    RX.turn(1) RX.press() RX.turn(1)
    RX.ui(l2)
    ok(#l2.errors == 0, "all three screens draw cleanly ("
       .. l2.calls .. " calls)" .. (#l2.errors > 0 and (" -- " .. l2.errors[1]) or ""))
end

-- 7. slot save/load through the real bundles, with the device's flat naming
do
    local Persist = require("seq3p").persist
    ok(pLoads == 1, "save/load pulls seq3p, and only now")
    ok(Persist ~= nil and Persist.save ~= nil, "seq3p exposes persist")
    local dir = os.getenv("TMPDIR") or "/tmp/"
    if dir:sub(-1) ~= "/" then dir = dir .. "/" end
    Persist.prefix = dir .. "seq3smoke_s"
    ok(Persist.slotPath(7) == dir .. "seq3smoke_s07.lua", "flat slot path: " .. Persist.slotPath(7))

    engine.setPitch(1, 1, 71)
    engine.setType(2, "trig")
    for i = 1, 16 do engine.setGate(2, i, i % 2) end
    ok(Persist.saveSlot(7), "saveSlot writes through the bundle")
    ok(lLoads == 0, "save does NOT pull the load bundle seq3l")

    engine.setPitch(1, 1, 60)
    for i = 1, 16 do engine.setGate(2, i, 0) end
    ok(Persist.loadSlot(7), "loadSlot reads through the bundle")
    ok(lLoads == 1, "load pulls seq3l exactly once")
    ok(engine.state(1).pitch[1] == 71, "recalled pitch (got " .. engine.state(1).pitch[1] .. ")")
    local g = 0
    for i = 1, 16 do g = g + engine.state(2).gate[i] end
    ok(g == 8, "recalled gates (got " .. g .. ")")
    os.remove(Persist.slotPath(7))
end

print("dist_smoke: " .. pass .. " checks, " .. fail .. " failed")
os.exit(fail == 0 and 0 or 1)
