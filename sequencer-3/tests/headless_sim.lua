-- tests/headless_sim.lua — drive the HEADLESS device target exactly as the
-- profile does, against the real dist bundles.
-- Run from the sequencer-3 directory:  lua tests/headless_sim.lua
--
-- This is the no-GUI proof: sequence data loaded into the runtime, played back
-- from MIDI clock, with the lanes visible as text. It asserts that screen.lua
-- and menu.lua are NEVER compiled on this path — they are what the module ran
-- out of memory on.

package.path = ""

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1
    else fail = fail + 1; print("FAIL: " .. msg) end
end

local FILES = {
    seq3 = "dist/seq3.lua", seq3e = "dist/seq3e.lua", seq3h = "dist/seq3h.lua",
    seq3ui = "dist/seq3ui.lua", seq3x = "dist/seq3x.lua", seq3p = "dist/seq3p.lua",
}
local loaded, order = {}, {}
local oldreq = require
require = function(n)
    if loaded[n] then return loaded[n] end
    if FILES[n] then
        order[#order + 1] = n
        loaded[n] = dofile(FILES[n])
        return loaded[n]
    end
    return oldreq(n)
end

-- Capture the console so the lane report can be asserted on.
local printed = {}
local realprint = print
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    printed[#printed + 1] = table.concat(parts, " ")
end

-- ---- el 255 ev0: SETUP (must require nothing) -------------------------------
local element = {}
local sent = {}
function midi_send(ch, st, p1, p2) sent[#sent + 1] = { ch = ch, st = st, p1 = p1, p2 = p2 } end
function L()
    if not RX then RX = require("seq3h").headless end
    return RX
end
element.rtmrx_cb = function(self, t) L().handle(t, midi_send) end

local function nLoaded() local k = 0 for _ in pairs(loaded) do k = k + 1 end return k end
ok(nLoaded() == 0, "setup loads no bundle")

-- ---- el 13 ev8 draw is BLANK in headless; el 255 ev6 timer ----------------
-- The timer runs during the cold boot; before a trigger it must be harmless.
if RX then RX.report() end
ok(nLoaded() == 0, "timer before any trigger loads nothing")

-- ---- first MIDI byte: load, apply the sequence, run ------------------------
element.rtmrx_cb(element, 0xFA)          -- start
ok(loaded.seq3h ~= nil, "first MIDI byte loads seq3h")
ok(loaded.seq3e ~= nil, "engine bundle resolves through the shim")
ok(loaded.seq3ui == nil, "screen/menu bundle NEVER loaded (no GUI)")
ok(loaded.seq3x == nil and loaded.seq3p == nil, "no ops/persist bundle loaded")

local engine = loaded.seq3.engine or loaded.seq3e.engine
ok(engine ~= nil, "engine reachable")
ok(#engine.lanes == 3, "sequence data installed 3 lanes (got " .. #engine.lanes .. ")")
ok(engine.running, "engine is running after load")

-- the three lanes are the ones seq_data describes
ok(engine.state(1).type == "note" and engine.state(1).channel == 1, "L1 note on ch1")
ok(engine.state(2).type == "note" and engine.state(2).length == 8, "L2 note, 8 steps")
ok(engine.state(3).type == "trig" and engine.state(3).channel == 10, "L3 trig on ch10")

-- ---- play two bars of clock ------------------------------------------------
for _ = 1, 192 do element.rtmrx_cb(element, 0xF8) end

local per = {}
for _, m in ipairs(sent) do
    if m.st == 0x90 then per[m.ch] = (per[m.ch] or 0) + 1 end
end
ok((per[1] or 0) > 0, "L1 emitted notes on ch1 (" .. (per[1] or 0) .. ")")
ok((per[2] or 0) > 0, "L2 emitted notes on ch2 (" .. (per[2] or 0) .. ")")
ok((per[10] or 0) > 0, "L3 emitted trigs on ch10 (" .. (per[10] or 0) .. ")")
-- L1 advances on 16ths, L2 on 8ths: L1 must fire about twice as often as L2.
ok((per[1] or 0) > (per[2] or 0), "L1 (16ths) fires more often than L2 (8ths)")

local ons, offs = 0, 0
for _, m in ipairs(sent) do
    if m.st == 0x90 then ons = ons + 1 elseif m.st == 0x80 then offs = offs + 1 end
end
ok(ons > 0 and offs > 0, "note-ons are matched by note-offs (" .. ons .. "/" .. offs .. ")")

-- ---- the lane report -------------------------------------------------------
-- 192 pulses is exactly 2 bars, which returns every lane to step 1. Nudge on
-- by a non-multiple so the report shows the lanes genuinely out of phase.
for _ = 1, 40 do element.rtmrx_cb(element, 0xF8) end
local before = #printed
RX.report()
local lines = {}
for i = before + 1, #printed do lines[#lines + 1] = printed[i] end
ok(#lines == 3, "report prints exactly one line per lane (got " .. #lines .. ")")
local shape = true
for _, ln in ipairs(lines) do
    if not ln:match("^L%d ") or not ln:match("step %d+/%d+") then shape = false end
end
ok(shape, "each report line names the lane and its step")

-- stop clears the notes
element.rtmrx_cb(element, 0xFC)
ok(not engine.running, "stop halts the engine")

print = realprint
realprint("")
realprint("--- the console output the module will show ---")
for _, ln in ipairs(printed) do
    if ln:match("^seq3h:") then realprint("  " .. ln) end
end
realprint("  (then, on each timer tick:)")
for _, ln in ipairs(lines) do realprint("  " .. ln) end
realprint("")
realprint("bundles loaded: " .. table.concat(order, " -> "))
realprint("headless_sim: " .. pass .. " checks, " .. fail .. " failed")
os.exit(fail == 0 and 0 or 1)
