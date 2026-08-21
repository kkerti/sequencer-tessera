-- tests/run.lua — Core unit tests. Run from repo root:  lua tests/run.lua
package.path = "src/core/?.lua;src/fx/?.lua;src/hal/?.lua;" .. package.path

local Engine  = require("engine")
local Event   = require("event")
local Scales  = require("scales")
local Range   = require("range")
local Random  = require("random")

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1
    else fail = fail + 1; io.write("  FAIL: ", msg, "\n") end
end

-- Drain engine.out into a flat list of {typ,pitch,vel,ch} for assertions.
local function drain(out, acc, atTick)
    for i = 1, out.n do
        acc[#acc + 1] = { typ = out.typ[i], pitch = out.pitch[i],
                          vel = out.vel[i], ch = out.ch[i], t = atTick }
    end
end

-- 1) Scale quantization -------------------------------------------------
do
    local maj = Scales.SCALES[2].mask                 -- C major
    ok(Scales.quantize(61, maj) == 60 or Scales.quantize(61, maj) == 62,
       "C# snaps to a C-major tone")
    ok(Scales.quantize(60, maj) == 60, "C stays C")
    local amin = Scales.rotate(Scales.SCALES[3].mask, 9) -- A minor
    ok((amin >> 9) & 1 == 1, "A minor contains A (pc 9)")
    ok((amin >> 0) & 1 == 1, "A minor contains C (pc 0)")
end

-- 2) RANGE clamp --------------------------------------------------------
do
    local r = Range.new{ pitchMin = 50, pitchMax = 90, velMin = 40, velMax = 110 }
    local buf = { n = 3, pitch = {40, 70, 100}, len = {6,6,6}, vel = {10, 60, 127} }
    r:process(buf)
    ok(buf.pitch[1] == 50 and buf.pitch[3] == 90, "pitch clamps to [50,90]")
    ok(buf.vel[1] == 40 and buf.vel[3] == 110, "vel clamps to [40,110]")
    ok(buf.pitch[2] == 70 and buf.vel[2] == 60, "in-range values untouched")
end

-- 3) RANDOM determinism + chance ---------------------------------------
do
    local a = Random.new{ seed = 123, pitchJit = 5 }
    local b = Random.new{ seed = 123, pitchJit = 5 }
    local ba = { n = 1, pitch = {60}, len = {6}, vel = {100} }
    local bb = { n = 1, pitch = {60}, len = {6}, vel = {100} }
    a:process(ba); b:process(bb)
    ok(ba.pitch[1] == bb.pitch[1], "same seed -> same jitter")

    local skip = Random.new{ seed = 1, chance = 0 }
    local bs = { n = 4, pitch = {60,61,62,63}, len = {6,6,6,6}, vel = {1,1,1,1} }
    skip:process(bs)
    ok(bs.n == 0, "chance=0 drops all notes")
end

-- 4) Playback: notes fire on time, offs after len, chords, 2 tracks ----
do
    Engine.init{ trackCount = 2 }
    -- Default effects are transparent (scale off, chance 100, no jitter).
    Event.add(Engine.tracks[1].pattern.events, 60, 0, 6, 100)   -- step 0, 1/16
    Event.add(Engine.tracks[1].pattern.events, 64, 0, 6, 90)    -- chord w/ above
    Event.add(Engine.tracks[2].pattern.events, 36, 0, 12, 110)  -- ch2, 1/8

    local acc = {}
    Engine.onStart()
    for t = 0, 13 do drain(Engine.onPulse(), acc, t) end

    -- Tick 0: two ONs on ch1 (chord) + one ON on ch2.
    local on0 = 0
    for _, e in ipairs(acc) do
        if e.t == 0 and e.typ == 1 then on0 = on0 + 1 end
    end
    ok(on0 == 3, "tick 0 fires 3 note-ons (chord + bass), got " .. on0)

    -- ch1 notes (len 6) go OFF at tick 6; ch2 (len 12) at tick 12.
    local off_ch1_t, off_ch2_t
    for _, e in ipairs(acc) do
        if e.typ == 0 and e.ch == 1 and not off_ch1_t then off_ch1_t = e.t end
        if e.typ == 0 and e.ch == 2 and not off_ch2_t then off_ch2_t = e.t end
    end
    ok(off_ch1_t == 6, "ch1 note-off at tick 6, got " .. tostring(off_ch1_t))
    ok(off_ch2_t == 12, "ch2 note-off at tick 12, got " .. tostring(off_ch2_t))
end

-- 5) Loop wrap: a 1-step (6-tick) loop refires every 6 ticks -----------
do
    Engine.init{ trackCount = 1 }
    Engine.tracks[1].pattern.length = 1     -- 1 step * 6 = 6-tick loop
    Event.add(Engine.tracks[1].pattern.events, 60, 0, 3, 100)
    local ons = 0
    Engine.onStart()
    for t = 0, 11 do
        local out = Engine.onPulse()
        for i = 1, out.n do if out.typ[i] == 1 then ons = ons + 1 end end
    end
    ok(ons == 2, "6-tick loop refires twice in 12 ticks, got " .. ons)
end

-- 6) NO ALLOCATION on the pulse hot path -------------------------------
do
    Engine.init{ trackCount = 2 }
    Event.add(Engine.tracks[1].pattern.events, 60, 0, 6, 100)
    Event.add(Engine.tracks[1].pattern.events, 64, 12, 6, 90)
    Event.add(Engine.tracks[2].pattern.events, 36, 6, 12, 110)
    Engine.onStart()
    for _ = 1, 2000 do Engine.onPulse() end        -- warm up
    collectgarbage("collect")
    local before = collectgarbage("count")
    for _ = 1, 20000 do Engine.onPulse() end        -- measured window
    local after = collectgarbage("count")
    local grew = after - before                     -- KB
    ok(grew < 1.0, string.format("onPulse allocates ~0 (grew %.3f KB over 20k pulses)", grew))
end

-- 7) Scale-degree walker -----------------------------------------------
do
    local maj = Scales.SCALES[2].mask                 -- C major
    ok(Scales.step(60, maj, 1) == 62, "C +1 degree = D")
    ok(Scales.step(60, maj, 2) == 64, "C +2 degrees = E")
    ok(Scales.step(60, maj, -1) == 59, "C -1 degree = B")
    ok(Scales.step(60, maj, 7) == 72, "C +7 degrees = C (octave up)")
    ok(Scales.step(60, 0, 3) == 63, "chromatic: +3 degrees = +3 semitones")
end

-- 8) Pattern generator --------------------------------------------------
do
    local Generate = require("generate")
    local Pattern  = require("pattern")
    local p = Pattern.new{ length = 16, zoom = 6 }
    -- Euclid: exactly `hits` onsets; all pitches in key; deterministic.
    local n = Generate.run(p, { scaleIndex = 3, root = 9, hits = 5, seed = 42,
                                pitchRoot = 57, pitchSpread = 5, velRoot = 100, velSpread = 20 })
    ok(n == 5, "5 hits -> 5 notes, got " .. n)
    ok(p.events.n == 5, "event store holds 5 notes")

    local amin = Scales.rotate(Scales.SCALES[3].mask, 9)  -- A minor mask
    local inKey = true
    for i = 1, p.events.n do
        if ((amin >> (p.events.pitch[i] % 12)) & 1) == 0 then inKey = false end
    end
    ok(inKey, "all generated pitches are in A minor")

    -- velocity within root ± spread
    local velOk = true
    for i = 1, p.events.n do
        local v = p.events.vel[i]
        if v < 80 or v > 120 then velOk = false end
    end
    ok(velOk, "velocities within 100 +-20")

    -- starts land on the step grid (multiples of zoom)
    local onGrid = true
    for i = 1, p.events.n do if p.events.start[i] % 6 ~= 0 then onGrid = false end end
    ok(onGrid, "note starts are quantized to the step grid")

    -- determinism: same seed -> identical; overwrite (not append)
    local q = Pattern.new{ length = 16, zoom = 6 }
    Generate.run(q, { scaleIndex = 3, root = 9, hits = 5, seed = 42, pitchRoot = 57, pitchSpread = 5 })
    local same = (q.events.n == p.events.n)
    for i = 1, q.events.n do if q.events.pitch[i] ~= p.events.pitch[i] then same = false end end
    ok(same, "same seed -> identical pattern")
    Generate.run(q, { hits = 3, seed = 7 })
    ok(q.events.n == 3, "regenerate overwrites (3 hits -> 3 notes), got " .. q.events.n)

    -- hits >= length fills every step
    local f = Pattern.new{ length = 8, zoom = 6 }
    Generate.run(f, { hits = 8, seed = 1 })
    ok(f.events.n == 8, "hits==length fills all 8 steps")
end

io.write(string.format("\n%d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
