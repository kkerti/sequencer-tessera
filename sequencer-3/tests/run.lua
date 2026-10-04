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
ok(Scales.quantize(60, 0) == 60, "mask 0 is chromatic")

-- -------------------------------------------------------------- lane ---

do
    local l = Lane.new("note")
    ok(#l.pitch == 16 and #l.velocity == 16 and #l.stepLength == 16, "note lane has 16-slot arrays")
    local g = Lane.new("trig")
    ok(#g.gate == 16, "trig lane has a 16-slot gate array")

    Lane.setDims(l, "4x4")

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
    Engine.setAdvanceSource(1, "off")
    Engine.onStart()
    Engine.onPulse()   -- flush the step-1 emit from onStart
end

-- Clocked lane 1: advances on every 16th. step() runs pulses up to and
-- including the next 16th tap (6 pulses), so Engine.out is that pulse's.
local function clocked(kind)
    freshLane(kind)
    Engine.setAdvanceSource(1, "transport.sixteenth")
end
local function step()
    repeat Engine.onPulse() until Transport.fired(Engine.transport, 6)
end

do
    clocked("note")
    Engine.setPitch(1, 2, 64)
    step()
    ok(Engine.state(1).position == 2, "the 16th tap advances to step 2")
    ok(hasEvent(Engine.out, 1, 64), "step 2 emits its note (64)")
end

do
    clocked("note")
    Engine.setDivision(1, 2)
    Engine.setPitch(1, 2, 64)
    step()
    ok(Engine.state(1).position == 1, "division 2 ignores first advance")
    step()
    ok(Engine.state(1).position == 2, "division 2 advances on second tap")
end

do
    clocked("note")
    Engine.setResetSource(1, "transport.quarter")
    step(); step(); step()                        -- pulses 6/12/18: step 4
    ok(Engine.state(1).position == 4, "advanced to step 4")
    step()                                        -- pulse 24: reset + advance
    ok(Engine.state(1).position == 1, "the advance on the reset tap lands on step 1")
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
    clocked("note")
    Engine.setPitch(1, 2, 64)
    Engine.setStepLength(1, 1, 24)                -- still sounding at the advance
    step()
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
    Engine.setGate(1, 1, 1); Engine.setStepLength(1, 1, 1); Engine.setVelocity(1, 1, 77)
    Engine.setPosition(1, 1)
    Engine.onPulse()
    ok(hasEvent(Engine.out, 1, 40), "trig lane fires on an active step")
    ok(Engine.out.velocity[Engine.out.n] == 77, "trig uses the step's velocity")
    Engine.onPulse()
    ok(hasEvent(Engine.out, 0, 40), "a 1-tick trig releases after one pulse")
end

do
    freshLane("trig")
    Engine.setMidiNote(1, 41)
    Engine.setGate(1, 1, 1); Engine.setStepLength(1, 1, 24)
    Engine.setPosition(1, 1); Engine.onPulse()
    local held = true
    for _ = 1, 23 do Engine.onPulse(); if hasEvent(Engine.out, 0, 41) then held = false end end
    ok(held, "a long trig step holds like a gate")
    Engine.onPulse()
    ok(hasEvent(Engine.out, 0, 41), "the long trig releases at its step length")
end

do
    Engine.init{ lanes = 4 }
    Engine.setType(1, "mod"); Engine.setType(2, "gate")
    ok(Engine.get(1, "type") == "note" and Engine.get(2, "type") == "trig",
       "old mod/gate types load as note/trig")
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
    Engine.shred(1)
    ok(Engine.get(1, "pitch")[Engine.state(1).position] ~= nil, "shred writes the playhead step")
end

-- ------------------------------------------------------------- preset ---

do
    Engine.init{ lanes = 4 }
    ok(Persist.load("presets/01.lua"), "preset 01 loads")
    ok(Engine.get(1, "pitch")[1] == 60, "preset 01 sets pitch 1")
    ok(Engine.get(1, "advanceSource") == Sources.TRANSPORT_SIXTEENTH,
       "preset 01 sets the advance source")
end

-- ------------------------------------------------- persist round-trip ---
-- Save must be lossless against load: build a fully-configured four-lane
-- state, write it, reload into a fresh engine, and compare every saved field.
-- Writes to a temp file, never into presets/ (those are hand-authored demos).

do
    local tmp = os.tmpname()

    local function configure()
        Engine.init{ lanes = 4, channel = 1 }
        Engine.setType(1, "note"); Engine.setDimensions(1, "4x4")
        Engine.setScale(1, 0x5AD, 9); Engine.setRange(1, 36, 96)
        Engine.setChannel(1, 5); Engine.setDivision(1, 2)
        Engine.setXAdvanceSource(1, "transport.sixteenth")
        Engine.setYAdvanceSource(1, "transport.quarter")
        Engine.setResetSource(1, "transport.whole")
        Engine.setShiftSource(1, "transport.half"); Engine.setShiftAmount(1, 3)
        for k = 1, 16 do
            Engine.setPitch(1, k, 40 + k * 2)
            Engine.setVelocity(1, k, 30 + k * 3)
            Engine.setStepLength(1, k, 1 + k)
        end
        Engine.setType(2, "note"); Engine.setScale(2, 0, 0)
        Engine.setRange(2, 20, 110)
        Engine.setAdvanceSource(2, "transport.eighth")
        for k = 1, 16 do Engine.setPitch(2, k, k * 7) end
        Engine.setType(3, "trig"); Engine.setDimensions(3, "8x2")
        Engine.setMidiNote(3, 38); Engine.setChannel(3, 10)
        Engine.setAdvanceSource(3, "transport.sixteenth")
        for k = 1, 16 do Engine.setGate(3, k, (k * 5) % 16 < 5 and 1 or 0) end
        Engine.setType(4, "trig"); Engine.setLength(4, 12)
        for k = 1, 12 do Engine.setStepLength(4, k, k * 2) end
        Engine.setMidiNote(4, 45); Engine.setPreviousSource(4, "transport.quarter")
        for k = 1, 12 do Engine.setGate(4, k, k % 3 == 0 and 0 or 1) end
    end

    -- Saved settings only: playback state and derived fields are excluded.
    local SKIP = { position=1, emit=1, pendingReset=1, fired=1, divCount=1,
                   activeNote=1, noteOffIn=1, width=1, height=1,
                   scaleMask=1 }
    local ARRAYS = { pitch=1, velocity=1, stepLength=1, gate=1 }

    local function snapshot()
        local snap = {}
        for i = 1, #Engine.lanes do
            local l, s = Engine.lanes[i], {}
            for k, v in pairs(l) do
                if not SKIP[k] then
                    if ARRAYS[k] then
                        local a = {}
                        for j = 1, Lane.CAP do a[j] = v[j] end
                        s[k] = a
                    else
                        s[k] = v
                    end
                end
            end
            snap[i] = s
        end
        return snap
    end

    configure()
    -- Play for a while: playback state must not leak into the save.
    Engine.onStart()
    for _ = 1, 200 do Engine.onPulse() end
    Engine.onStop()
    local before = snapshot()

    ok(Persist.save(tmp), "save writes a state file")

    Engine.init{ lanes = 4, channel = 1 }
    ok(Persist.load(tmp), "saved state loads back")
    local after = snapshot()

    local diffs, firstDiff = 0, nil
    for i = 1, 4 do
        local b, a = before[i], after[i]
        local keys = {}
        for k in pairs(b) do keys[k] = true end
        for k in pairs(a) do keys[k] = true end
        for k in pairs(keys) do
            if ARRAYS[k] then
                for j = 1, Lane.CAP do
                    if (b[k] and b[k][j]) ~= (a[k] and a[k][j]) then
                        diffs = diffs + 1
                        firstDiff = firstDiff or string.format("lane %d %s[%d]", i, k, j)
                    end
                end
            elseif b[k] ~= a[k] then
                diffs = diffs + 1
                firstDiff = firstDiff or string.format("lane %d %s (%s -> %s)",
                    i, k, tostring(b[k]), tostring(a[k]))
            end
        end
    end
    ok(diffs == 0, "save/load round-trip is lossless (" .. tostring(diffs)
       .. " diffs, first: " .. tostring(firstDiff) .. ")")

    -- Derived fields are rebuilt, not stored.
    ok(Engine.get(1, "width") == 4 and Engine.get(1, "height") == 4,
       "round-trip rebuilds dims-derived width/height")
    ok(Engine.get(1, "scaleMask") == Scales.rotate(0x5AD, 9),
       "round-trip rebuilds the rotated scale mask")
    ok(Engine.get(2, "minNote") == 20 and Engine.get(2, "maxNote") == 110,
       "round-trip keeps a lane's note range")

    -- A saved slot is a valid preset chunk: it reloads over a running engine.
    local reload = Persist.load(tmp)
    ok(reload, "a saved file reloads over an already-configured engine")
    os.remove(tmp)
end

-- ------------------------------------------------------- engine: M2 nav ---

do
    Engine.init{ lanes = 4 }
    for i = 2, 4 do Engine.setType(i, "trig") end
    Engine.setType(1, "note")
    Engine.setDimensions(1, "4x4")
    Engine.setAdvanceSource(1, "off")
    Engine.setXAdvanceSource(1, "transport.sixteenth")
    Engine.setYAdvanceSource(1, "transport.quarter")
    Engine.onStart(); Engine.onPulse()
    Engine.setPosition(1, 1)
    step()                                        -- pulse 6: X only
    ok(Engine.state(1).position == 2, "X advance moves along the row")
    step(); step(); step()                        -- pulse 24: X wraps, then Y
    ok(Engine.state(1).position == 5, "X wraps in the row and Y moves down a row")
end

do
    Engine.init{ lanes = 4 }
    for i = 2, 4 do Engine.setType(i, "trig") end
    Engine.setType(1, "note")
    for i = 1, 16 do Engine.setPitch(1, i, i) end
    Engine.setAdvanceSource(1, "off")
    Engine.setShiftSource(1, "transport.sixteenth")
    Engine.setShiftAmount(1, 1)
    Engine.onStart(); Engine.onPulse()
    step()
    ok(Engine.get(1, "pitch")[1] == 16 and Engine.get(1, "pitch")[2] == 1,
       "shift source rotates the step values")
end

do
    Engine.init{ lanes = 4 }
    Engine.loadPreset{ lanes = { {
        type = "note", dims = "4x4",
        xAdvanceSource = "transport.sixteenth",
        yAdvanceSource = "transport.quarter",
    } } }
    ok(Engine.get(1, "xAdvanceSource") == Sources.TRANSPORT_SIXTEENTH
       and Engine.get(1, "yAdvanceSource") == Sources.TRANSPORT_QUARTER,
       "preset applies X/Y advance sources")
end

-- ------------------------------------------------- engine: lane types ---

do
    Engine.init{ lanes = 4 }
    Engine.setType(1, "note"); Engine.setChannel(1, 1)
    Engine.setType(2, "trig"); Engine.setMidiNote(2, 38); Engine.setChannel(2, 2)
    Engine.setType(3, "note"); Engine.setChannel(3, 3)
    Engine.setType(4, "trig")
    Engine.setGate(2, 1, 1)
    for i = 1, 4 do Engine.setAdvanceSource(i, "off") end
    Engine.onStart(); Engine.onPulse()
    local sawNote, sawTrig, sawCC = false, false, false
    for i = 1, Engine.out.n do
        local t, ch = Engine.out.typ[i], Engine.out.channel[i]
        if t == 1 and ch == 1 then sawNote = true end
        if t == 1 and ch == 2 then sawTrig = true end
        if t == 1 and ch == 3 then sawCC = true end
    end
    ok(sawNote and sawTrig and sawCC, "lanes emit together on their own channels")
end

-- ------------------------------------------------------ random fill ---

do
    Engine.init{ lanes = 4 }
    Engine.setType(1, "note"); Engine.setScale(1, Scales.MAJOR, 0)
    Engine.setRange(1, 48, 72)
    math.randomseed(42)
    ok(Engine.randomize(1), "randomize fills a note lane")
    local inRange, distinct, seen = true, 0, {}
    for i = 1, 16 do
        local p = Engine.get(1, "pitch")[i]
        if p < 48 or p > 72 then inRange = false end
        if not seen[p] then seen[p] = true; distinct = distinct + 1 end
    end
    ok(inRange, "random pitches stay inside the lane's note range")
    ok(distinct > 4, "random fill varies across steps (" .. distinct .. " distinct)")
    Engine.setPosition(1, 1); Engine.onStart(); Engine.onPulse()
    local p = Engine.out.pitch[Engine.out.n]
    ok(((Engine.get(1, "scaleMask") >> (p % 12)) & 1) == 1, "random notes play quantized to the scale")
end

do
    Engine.init{ lanes = 4 }
    Engine.setType(1, "trig"); Engine.setDimensions(1, "4x3")
    math.randomseed(7)
    Engine.randomize(1)
    local hits, outside = 0, 0
    for i = 1, 16 do
        local g = Engine.get(1, "gate")[i]
        if i <= 12 then hits = hits + g elseif g ~= 0 then outside = outside + 1 end
    end
    ok(hits > 0 and hits < 12, "random trig fill sets some gates, not all")
    ok(outside == 0, "random fill touches only the lane's used steps")
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
