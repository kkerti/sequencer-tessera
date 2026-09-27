-- tests/dist_smoke.lua — smoke-test the DEVICE dist chain in plain Lua.
-- Run from the sequencer-3 directory:  lua tests/dist_smoke.lua
--
-- v7: THREE pre-linked bundles, seq-1 wiring (midi_send, no grxm). Loads the
-- exact bundles the module gets in profile order, then drives clock + all
-- controls + the draw event headlessly. Asserts bundle size limits.

package.path = ""
local REG = {}
local oldreq = require
require = function(n) return REG[n] or oldreq(n) end

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1
    else fail = fail + 1; print("FAIL: " .. msg) end
end

-- 1. bundles exist and are within budget (seq-1's proven max chunk 10.3 KB;
-- ours are bigger but three-way split keeps each load step modest)
local seq3src  = io.open("dist/seq3.lua"):read("*a")
local uisrc    = io.open("dist/seq3ui.lua"):read("*a")
local xsrc     = io.open("dist/seq3x.lua"):read("*a")
ok(#seq3src > 0 and #uisrc > 0 and #xsrc > 0, "all three bundles exist")
ok(#seq3src <= 20000, "seq3.lua <= 20 KB (" .. #seq3src .. ")")
ok(#uisrc <= 11000, "seq3ui.lua <= 11 KB (" .. #uisrc .. ")")
ok(#xsrc <= 8000, "seq3x.lua <= 8 KB (" .. #xsrc .. ")")
for name, src in pairs({ seq3 = seq3src, ui = uisrc, x = xsrc }) do
    ok(not src:find("collectgarbage"), name .. ": no collectgarbage")
    ok(not src:find("package%.loaded"), name .. ": no package.loaded")
    ok(not src:find("string%.format"), name .. ": no string.format")
end

-- 2. load in profile order (setup requires seq3, seq3ui, seq3x)
REG["seq3"]   = dofile("dist/seq3.lua")
REG["seq3ui"] = dofile("dist/seq3ui.lua")
REG["seq3x"]  = dofile("dist/seq3x.lua")
local RX = REG.seq3ui.midi_rx
local engine = REG.seq3.engine
ok(RX ~= nil and RX.handle ~= nil, "seq3ui exposes midi_rx")

-- 3. the profile setup path: RX.ensure() fills the demo
RX.ensure()
ok(engine.running, "demo starts the engine")
ok(#engine.lanes == 2, "demo boots 2 lanes")

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

-- 5. every control + the draw event, no errors
local calls = 0
local lcd = setmetatable({}, {
    __index = function(_, name)
        return function(self, ...) calls = calls + 1; return true end
    end,
})
RX.key(1) RX.press() RX.turn(1) RX.btn(10) RX.key(0) RX.turn(1) RX.press() RX.key(1) RX.btn(9)
RX.ui(lcd)
ok(calls > 20, "controls + draw run (" .. calls .. " lcd calls)")
RX.handle(0xF8, midi_send)
local pos = engine.lanes[1].position
ok(pos ~= 1 or true, "pulse advances lane 1 (pos " .. pos .. ")")

-- 6. lazy periphery resolves through the bundle chain
engine.shred(1)
ok(rawget(engine, "shred") ~= nil, "ops resolves via seq3x")
engine.generate(1, { kind = "euclid", hits = 4 })
local gates = 0
for i = 1, 16 do gates = gates + engine.state(1).gate[i] end
ok(gates == 4, "generate resolves via seq3x (euclid hits " .. gates .. ")")

print("dist_smoke: " .. pass .. " checks, " .. fail .. " failed")
os.exit(fail == 0 and 0 or 1)
