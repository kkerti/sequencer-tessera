-- tests/run.lua — sequencer-3 spec tests. Run from the sequencer-3 directory:
--   lua tests/run.lua
--
-- The spec is authoritative; seq-2 was only a reference. No third-party deps.

package.path = "src/core/?.lua;src/?.lua;" .. package.path

local Engine    = require("engine")
local Scales    = require("scales")
local Lane      = require("lane")
local Transport = require("transport")
local Sources   = require("sources")
local Persist   = require("persist")

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1
    else fail = fail + 1; print("FAIL: " .. msg) end
end

local function countOn(out)
    local n = 0
    for i = 1, out.n do if out.typ[i] == 1 then n = n + 1 end end
    return n
end
local function hasEvent(out, typ, pitch)
    for i = 1, out.n do
        if out.typ[i] == typ and out.pitch[i] == pitch then return true end
    end
    return false
end

-- ------------------------------------------------------------ scales ---

ok(Scales.quantize(61, Scales.MAJOR) == 60, "C# snaps down to C in C major")
ok(Scales.quantize(62, Scales.MAJOR) == 62, "in-scale note passes through")
ok(Scales.quantize(66, Scales.MAJOR) == 65, "F# snaps down to F in C major")
ok(Scales.rotate(Scales.MAJOR, 2) == 0xAD6, "major rotated up 2 == D major mask")
ok(Scales.step(60, Scales.MAJOR, 2) == 64, "two scale degrees up from C == E")
ok(Scales.step(60, Scales.MAJOR, -1) == 59, "one degree down from C == B")
ok(Scales.quantize(60, 0) == 60, "mask 0 is chromatic")

-- -------------------------------------------------------------- lane ---

do
    local l = Lane.new("note")
    ok(#l.pitch == 16 and #l.velocity == 16 and #l.stepLength == 16, "note lane has 16-slot arrays")
    local g = Lane.new("gate")
    ok(#g.gate == 16, "gate lane has a 16-slot gate array")

    Lane.setDims(l, "4x4")
    ok(Lane.index(l, 0, 0) == 1 and Lane.index(l, 3, 0) == 4, "4x4 row-major index (row 0)")
    ok(Lane.index(l, 0, 1) == 5 and Lane.index(l, 3, 3) == 16, "4x4 row-major index (rows 1,3)")

    Lane.setPosition(l, 4)   -- x=3, y=0
    Lane.advanceX(l)
    ok(l.position == 1, "X advance wraps within the row")
    Lane.setPosition(l, 13)  -- x=0, y=3
    Lane.advanceY(l)
    ok(l.position == 1, "Y advance wraps within the column")

    local n = Lane.new("note")
    Lane.setPosition(n, 16)
    Lane.advanceForward(n)
    ok(n.position == 1, "16x1 advance wraps to 1")
    Lane.advanceBackward(n)
    ok(n.position == 16, "16x1 backward wraps to 16")
end

-- --------------------------------------------------------- transport ---

do
    local t = Transport.new()
    Transport.start(t)
    for _ = 1, 5 do Transport.tick(t) end
    ok(not Transport.fired(t, 6), "no 16th at pulse 5")
    Transport.tick(t)
    ok(Transport.fired(t, 6), "16th fires at pulse 6")
    ok(not Transport.fired(t, 24), "no quarter at pulse 6")
    for _ = 7, 24 do Transport.tick(t) end
    ok(Transport.fired(t, 24), "quarter fires at pulse 24")
end

-- --------------------------------------------------- engine: pulses ---

local function freshLane(kind)
    Engine.init{ lanes = 4 }
    for i = 2, 4 do Engine.setType(i, "trig") end   -- unused lanes stay silent
    Engine.setType(1, kind or "note")
    Engine.setChannel(1, 1)
    Engine.setScale(1, Scales.MAJOR, 0)
    Engine.setDivision(1, 1)
    Engine.setAdvanceSource(1, "external.0")
    Engine.onStart()
    Engine.onPulse()   -- flush the step-1 emit from onStart
end

do
    freshLane("note")
    Engine.setPitch(1, 2, 64)
    Engine.triggerExternal(1)
    Engine.onPulse()
    ok(Engine.state(1).position == 2, "external trigger advances to step 2")
    ok(hasEvent(Engine.out, 1, 64), "step 2 emits its note (64)")
end

do
    freshLane("note")
    Engine.setDivision(1, 2)
    Engine.setPitch(1, 2, 64)
    Engine.triggerExternal(1); Engine.onPulse()
    ok(Engine.state(1).position == 1, "division 2 ignores first advance")
    Engine.triggerExternal(1); Engine.onPulse()
    ok(Engine.state(1).position == 2, "division 2 advances on second trigger")
end

do
    freshLane("note")
    Engine.setResetSource(1, "external.1")
    Engine.triggerExternal(1); Engine.onPulse()   -- step 2
    Engine.triggerExternal(1); Engine.onPulse()   -- step 3
    ok(Engine.state(1).position == 3, "advanced to step 3")
    Engine.triggerExternal(2); Engine.onPulse()   -- reset pending, no advance
    ok(Engine.state(1).position == 3, "reset is deferred until an advance")
    Engine.triggerExternal(1); Engine.onPulse()
    ok(Engine.state(1).position == 1, "next advance honours the reset (step 1)")
end

do
    freshLane("note")
    Engine.setPitch(1, 1, 61)      -- C#, out of scale
    Engine.setPosition(1, 1)
    Engine.onPulse()
    ok(hasEvent(Engine.out, 1, 60), "output is quantized to C")
    ok(not hasEvent(Engine.out, 1, 61), "raw out-of-scale pitch is not emitted")
end

do
    freshLane("note")
    Engine.setPitch(1, 2, 64)
    Engine.triggerExternal(1)
    Engine.onPulse()
    ok(Engine.out.n == 2 and Engine.out.typ[1] == 0 and Engine.out.typ[2] == 1,
       "mono lane retriggers: off then on")
end

do
    freshLane("note")
    Engine.setStepLength(1, 1, 6)
    Engine.setPosition(1, 1)
    Engine.onPulse()               -- (re)emit step 1, noteOffIn = 6
    local offPulse = nil
    for p = 1, 8 do
        Engine.onPulse()
        if hasEvent(Engine.out, 0, 60) then offPulse = p; break end
    end
    ok(offPulse == 6, "note-off lands after 6 pulses (got " .. tostring(offPulse) .. ")")
end

do
    freshLane("trig")
    Engine.setMidiNote(1, 40)
    Engine.setGate(1, 1, 1)
    Engine.setPosition(1, 1)
    Engine.onPulse()
    ok(hasEvent(Engine.out, 1, 40), "trig lane fires on an active step")
    Engine.onPulse()
    ok(hasEvent(Engine.out, 0, 40), "trig pulse releases after one pulse")
end

do
    freshLane("gate")
    Engine.setMidiNote(1, 41)
    Engine.setGate(1, 1, 1); Engine.setGate(1, 2, 1); Engine.setGate(1, 3, 0)
    Engine.setPosition(1, 1); Engine.onPulse()
    Engine.setPosition(1, 2); Engine.onPulse()
    ok(not hasEvent(Engine.out, 0, 41), "gate holds across active steps")
    Engine.setPosition(1, 3); Engine.onPulse()
    ok(hasEvent(Engine.out, 0, 41), "gate releases on the first inactive step")
end

do
    freshLane("mod")
    Engine.setController(1, 74)
    Engine.setValue(1, 1, 99)
    Engine.setPosition(1, 1); Engine.onPulse()
    ok(Engine.out.n == 1 and Engine.out.typ[1] == 2
       and Engine.out.pitch[1] == 74 and Engine.out.velocity[1] == 99,
       "mod lane emits CC 74 = 99")
end

do
    freshLane("note")
    Engine.setAdvanceSource(1, "off")
    Engine.setAddressSource(1, "external.0")
    Engine.setExternalValue(1, 127)
    Engine.onPulse()
    ok(Engine.state(1).position == 16, "address value 127 -> last step")
    Engine.setExternalValue(1, 0)
    Engine.onPulse()
    ok(Engine.state(1).position == 1, "address value 0 -> step 1")
end

-- --------------------------------------------------- engine: API ---

do
    Engine.init{ lanes = 4 }
    Engine.setChannel(1, 99)
    Engine.setDivision(1, 0)
    Engine.setPitch(1, 1, 200)
    ok(Engine.get(1, "channel") == 16, "channel clamps to 16")
    ok(Engine.get(1, "division") == 1, "division clamps to 1")
    ok(Engine.get(1, "pitch")[1] == 127, "pitch clamps to 127")
end

do
    Engine.init{ lanes = 4 }
    for i = 1, 16 do Engine.setPitch(1, i, i) end
    Engine.rotate(1, 1)
    ok(Engine.get(1, "pitch")[1] == 16 and Engine.get(1, "pitch")[2] == 1,
       "rotate(1) moves step 1 value to position 2")
end

do
    Engine.init{ lanes = 4 }
    for i = 1, 16 do Engine.setPitch(1, i, i) end
    Engine.offset(1, 5)
    ok(Engine.get(1, "pitch")[1] == 6, "offset adds a constant to all steps")
end

-- ------------------------------------------------------------- preset ---

do
    Engine.init{ lanes = 4 }
    ok(Persist.load("presets/01.lua"), "preset 01 loads")
    ok(Engine.get(1, "pitch")[1] == 60, "preset 01 sets pitch 1")
    ok(Engine.get(1, "advanceSource") == Sources.TRANSPORT_SIXTEENTH,
       "preset 01 sets the advance source")
end

-- --------------------------------------------------------- no-alloc ---

do
    Engine.init{ lanes = 4 }
    for i = 1, 4 do
        Engine.setScale(i, Scales.MAJOR, 0)
        Engine.setAdvanceSource(i, "transport.sixteenth")
        for k = 1, 16 do Engine.setPitch(i, k, 60 + k) end
    end
    Engine.onStart()
    for _ = 1, 2000 do Engine.onPulse() end
    collectgarbage("collect"); collectgarbage("collect")
    local before = collectgarbage("count")
    for _ = 1, 20000 do Engine.onPulse() end
    local after = collectgarbage("count")
    ok(after - before < 1.0, string.format("pulse path allocates < 1 KB (grew %.2f KB)", after - before))
end

print(string.format("sequencer-3 tests: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
