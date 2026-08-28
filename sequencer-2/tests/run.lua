-- tests/run.lua — Core + App unit tests. Run from repo root:  lua tests/run.lua
package.path = "src/core/?.lua;src/fx/?.lua;src/hal/?.lua;src/app/?.lua;" .. package.path

local Engine  = require("engine")
local Event   = require("event")
local Track   = require("track")
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

-- 9) Loop region: only the sub-range plays ------------------------------
do
    Engine.init{ trackCount = 1 }
    local pat = Engine.tracks[1].pattern
    pat.length = 2
    pat.zoom = 6
    pat.loopStart = 0
    pat.loopEnd = 1                       -- only step 0 (ticks 0..5) loops
    Event.add(pat.events, 60, 0, 3, 100)  -- step 0 (inside region)
    Event.add(pat.events, 72, 6, 3, 100)  -- step 1 (outside region)

    local ons = {}                        -- pitches seen firing
    Engine.onStart()
    for t = 0, 11 do
        local o = Engine.onPulse()
        for i = 1, o.n do if o.typ[i] == 1 then ons[#ons + 1] = o.pitch[i] end end
    end
    ok(#ons == 2, "loop region plays only step 0 (2 ons in 12 ticks), got " .. #ons)
    local all60 = true
    for _, p in ipairs(ons) do if p ~= 60 then all60 = false end end
    ok(all60, "note outside loop region (72) never fires")
end

-- 10) Nap: mute N loops, wake N loops, all on the track's own loops -------
do
    Engine.init{ trackCount = 1 }
    local tr = Engine.tracks[1]
    tr.pattern.length = 1; tr.pattern.zoom = 6
    Event.add(tr.pattern.events, 60, 0, 3, 100)
    Track.armNap(tr, 1, 1)                -- awake 1 loop, napped 1 loop
    local function countOns(t0, t1)
        local c = 0
        for t = t0, t1 do
            local o = Engine.onPulse()
            for i = 1, o.n do if o.typ[i] == 1 then c = c + 1 end end
        end
        return c
    end
    Engine.onStart()
    local a = countOns(0, 5)              -- loop 1: awake
    local b = countOns(6, 11)             -- loop 2: napped
    local c = countOns(12, 17)            -- loop 3: awake again
    ok(a == 1 and b == 0 and c == 1,
       string.format("nap awake/napped/awake = %d/%d/%d", a, b, c))
end

-- 11) Auto-reroll: due flag set on loop wrap (regenerate is deferred) -----
do
    Engine.init{ trackCount = 1 }
    local tr = Engine.tracks[1]
    tr.pattern.length = 1; tr.pattern.zoom = 6
    Event.add(tr.pattern.events, 60, 0, 3, 100)
    Track.armAuto(tr, 1)                  -- reroll every 1 loop
    Engine.onStart()
    local before = tr.auto.due
    for _ = 1, 7 do Engine.onPulse() end  -- gt -1 -> 6, wraps once (at tick 6)
    ok(not before and tr.auto.due, "auto-reroll sets due flag on the track's loop wrap")
end

-- 12) Per-note (STEP) editing -------------------------------------------
do
    local Pattern = require("pattern")
    local p = Pattern.new{ length = 16, zoom = 6 }
    Event.add(p.events, 60, 6, 6, 100)    -- one note at step 1
    local i = Pattern.findEventAtStep(p, 1, 6)
    ok(i ~= nil and p.events.start[i] == 6, "findEventAtStep finds the note at step 1")
    p.events.pitch[i] = 72                -- nudge in place (live, no growth)
    ok(p.events.pitch[i] == 72, "per-note edit mutates pitch in place")
    ok(Pattern.findEventAtStep(p, 0, 6) == nil, "empty step finds no note")
end

-- 13) Sequence switching + sequence-local mute ---------------------------
do
    Engine.init{ trackCount = 4 }
    local tr1 = Engine.tracks[1]
    -- author slot 2 with a distinctive note, then return to slot 1
    Track.setActiveSlot(tr1, 2)
    Event.add(tr1.pattern.events, 64, 0, 6, 100)
    Track.setActiveSlot(tr1, 1)
    Event.add(tr1.pattern.events, 60, 0, 6, 100)

    Engine.setSequence(2)                 -- SEQ2 = slot 2 on every track
    ok(tr1.activeSlot == 2 and tr1.pattern.events.pitch[1] == 64,
       "setSequence(2) swaps track 1 to slot 2")

    Engine.setSequence(1)                 -- back to slot 1 (pitch 60)
    Engine.setTrackMute(1, true)          -- mute track 1 in SEQ1 only
    Engine.onStart()
    local o = Engine.onPulse()            -- tick 0
    local onT1 = 0
    for i = 1, o.n do if o.typ[i] == 1 and o.ch[i] == 1 then onT1 = onT1 + 1 end end
    ok(onT1 == 0, "sequence-local mute suppresses track 1 note-ons")
    Engine.setTrackMute(1, false)
    Engine.onStart()
    local o2 = Engine.onPulse()
    local onT1b = 0
    for i = 1, o2.n do if o2.typ[i] == 1 and o2.ch[i] == 1 then onT1b = onT1b + 1 end end
    ok(onT1b == 1, "unmuting restores track 1 playback")
end

-- 14) 4 tracks + 4 sequences by default ----------------------------------
do
    Engine.init{}
    ok(#Engine.tracks == 4, "engine defaults to 4 tracks")
    ok(#Engine.sequences == 4, "engine builds 4 sequences (SEQ1..4)")
    ok(Engine.song.steps[1] == nil and Engine.song.pos == 1, "song starts empty")
    Engine.songAdd(2); Engine.songAdd(1)
    ok(#Engine.song.steps == 2, "songAdd chains sequence ids")
end

-- =========================================================================
-- APP layer: staged commit, 3 modes, draw smoke test
-- =========================================================================
do
    local Engine  = require("engine")
    local Event   = require("event")
    local Control = require("control")
    local Draw    = require("draw_vsn1")

    -- draw mock: records calls, returns nothing
    local calls = 0
    local Mock = {}
    function Mock:draw_rectangle_filled() calls = calls + 1 end
    function Mock:draw_line() calls = calls + 1 end
    function Mock:draw_text_fast() calls = calls + 1 end
    function Mock:draw_swap() calls = calls + 1 end

    Engine.init{ trackCount = 4 }
    Control.bind(Engine, {
        engine = Engine, track = require("track"), pattern = require("pattern"),
        event = require("event"), scales = require("scales"),
        generate = require("generate"), midirx = require("midi_rx"),
    })

    -- A) staged: turn stages, does not regenerate until COMMIT (button 12)
    local tr1 = Engine.tracks[1]
    local n0 = tr1.pattern.events.n
    Control.key(0, true)                         -- KS0 = HITS (quick param)
    local stagedHits = tr1.staged.hits
    for _ = 1, 5 do Control.turn(1) end
    ok(tr1.staged.hits ~= stagedHits and tr1.dirty, "encoder stages HITS and marks dirty")
    ok(tr1.pattern.events.n == n0, "pattern unchanged until commit")
    Control.button(12, true)                     -- COMMIT (dedicated button)
    ok(not tr1.dirty, "commit clears dirty")
    ok(tr1.pattern.events.n == tr1.gen.hits, "commit regenerates with staged hits")

    -- B) reroll is immediate (seed++)
    local seedBefore = tr1.gen.seed
    Control.click(true)
    ok(tr1.gen.seed == seedBefore + 1, "encoder click rerolls immediately (seed++)")

    -- C) mode cycling
    Control.key(7, true)                          -- PLAY -> STEP
    ok(Control.mode == "STEP", "KS7 cycles PLAY -> STEP")
    Control.key(7, true)                          -- STEP -> SEQ
    ok(Control.mode == "SEQ", "KS7 cycles STEP -> SEQ")
    Control.key(7, true)                          -- SEQ -> PLAY
    ok(Control.mode == "PLAY", "KS7 cycles SEQ -> PLAY")

    -- C2) ENTER/BACK hierarchy
    Control.button(10, true)                      -- ENTER -> SETUP
    ok(Control.setup, "ENTER enters SETUP from PLAY")
    Control.button(9, true)                       -- BACK -> compact
    ok(not Control.setup, "BACK returns to compact PLAY")

    -- D) STEP edit: add note at cursor, nudge pitch
    Control.key(7, true)                          -- -> STEP
    Control.key(0, true)                          -- add at step 0
    local pat = Engine.tracks[Control.track].pattern
    local i = require("pattern").findEventAtStep(pat, 0, pat.zoom)
    ok(i ~= nil, "STEP KS0 adds a note at the cursor")
    local p0 = pat.events.pitch[i]
    Control.key(4, true)                          -- field value -
    ok(pat.events.pitch[i] == p0 - 1, "STEP KS4 nudges pitch down")
    Control.click(true)                           -- cycle field -> LEN
    ok(Control.field == 2, "encoder click cycles edit field")

    -- E) SEQ: enter SONG, append, back
    Control.key(7, true)                          -- -> SEQ (SLOT page)
    Control.button(10, true)                      -- ENTER -> SONG
    ok(Control.seqPage == "SONG", "ENTER enters SONG page from SLOT")
    Control.key(0, true)                          -- append current seq
    Control.key(0, true)
    ok(#Engine.song.steps == 2, "SONG KS0 appends sequences")
    Control.button(9, true)                       -- BACK -> SLOT
    ok(Control.seqPage == "SLOT", "BACK returns to SLOT page")

    -- E2) nap is a dedicated button (11), not a chord
    Control.button(11, true)
    ok(Engine.tracks[1].nap.armed, "NAP button arms nap on current track")
    Control.button(11, true)
    ok(not Engine.tracks[1].nap.armed, "NAP button disarms")

    -- F) draw smoke test in every mode/view
    for _, mode in ipairs({ "PLAY", "STEP", "SEQ" }) do
        Control.mode = mode
        if mode == "PLAY" then Control.setup = true end
        if mode == "SEQ" then Control.seqPage = "SLOT" end
        Draw.draw(Mock, Engine, Control)
    end
    Control.mode = "PLAY"; Control.setup = false
    Control.seqPage = "SONG"
    Draw.draw(Mock, Engine, Control)
    ok(calls > 100, "draw runs in all modes/views without error (" .. calls .. " calls)")

    -- G) frame() services auto-reroll due flag
    local tr2 = Engine.tracks[2]
    tr2.pattern.length = 1                       -- 1-step loop -> wraps every 6 ticks
    local sd = tr2.gen.seed
    require("track").armAuto(tr2, 1)
    Engine.onStart()
    for _ = 1, 7 do Engine.onPulse() end        -- wraps once -> due
    ok(tr2.auto.due, "auto-reroll due set")
    Control.frame()
    ok(not tr2.auto.due and tr2.gen.seed == sd + 1, "frame() services auto-reroll off hot path")
end

io.write(string.format("\n%d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)