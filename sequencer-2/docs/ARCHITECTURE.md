# sequencer-2 — Architecture

Deep design. Assumes you've read `CLAUDE.md` and `AGENTS.md`. Everything here
serves two non-negotiables: **bounded RAM** and **zero-lag playback**.

---

## 0. Locked parameters (M1)

Settled in the requirements interview. Change only by explicit decision.

| Parameter | Value | Notes |
|-----------|-------|-------|
| Tick resolution | **24 PPQN** | `onPulse` fires once per incoming MIDI clock, no interpolation. 1/16 = 6 pulses, 1/16-triplet = 4, 1/8 = 12, 1/4 = 24. |
| Max events / pattern | **256** | Array `cap`; 4 active patterns in RAM at M4 (one per track). |
| Track count | **4** | Up from M1's 2. Re-measure RAM on a real build before going further (see §10). |
| Pattern slots / track | **4**, extensible to **8** | Hermod's P1..P16, scaled down. Only the *active* slot per track is resident; others are filenames until authored (§4). |
| Loop length model | **steps + zoom** | Length in steps; zoom maps steps→ticks. Enables polymetry (per-track lengths drift in sync). |
| Voice cap / track | **4** | Ring of 4 pending note-offs per track; 5th note steals the oldest voice. Keeps OFF scheduling alloc-free. |
| RANGE out-of-bounds | **clamp** | Pin to nearest boundary. Predictable performance sweeps. |
| Default rack order | **RANGE → RANDOM → SCALE** | Limit, vary, then quantize last so output is always in key. Reorderable per track. |
| Record default | **1/16 quantize, overdub** | Snap to nearest 6 pulses, layer non-destructively. |
| Proto clock | **external + optional internal** | Desktop harness can run a `--bpm` test clock; device build is external-only. |
| Zoom ladder (M1) | **/2, ×1, 2/3, ×2** | ticks/step = 12, 6, 4, 3. `loopTicks = length × ticksPerStep`. Per-pattern. |
| Scales (M1) | **8 masks** | off, major, minor, harm-min, dorian, phrygian, mixolydian, min-pent. Per-track root (0–11), snap nearest, tie→down. |
| RANGE params | **min+max per field**, root fixed | pitchMin/Max, velMin/Max, lenMin/Max. Pattern-overridable in principle, but the override plumbing itself is still open — see §9. |
| RANDOM | **free-running**, 4 params | chance / pitchJit / velJit / octJit. Per-instance LCG (seedable). |
| Voice-steal | **oldest-off** | 5th note steals the slot with earliest off-tick, emits its OFF first. |
| Transport | PLAY→reset all to 0 · STOP→OFFs + reset · CONTINUE→resume | Independent per-track wrap (polymetry). |
| Recording | **commit on note-off** | Capture input velocity; same-pitch overlap retriggers (2 notes). |
| Persistence | **file-per-pattern** | `<project>/t<n>/p<n>.lua` + `project.lua` manifest (channels, racks, active). Manifest resident; patterns stream. **Built at M4.** |

**Dev note:** target runtime is Lua 5.4 (Grid); the dev machine here runs Lua
5.5, a compatible superset (integer/bitwise ops unchanged).

---

## 1. The spine

```
external clock pulse
        │
        ▼
  engine.onPulse()  ── for each track ──▶ rack.run(events, scratch)  ──▶ driver.emit
        │                                        │
   (advances playheads,                    (SCALE→RANGE→RANDOM,
    collects due events,                    alloc-free, in place
    zero allocation)                        on the scratch buffer)
```

Everything else — editing, recording, screen redraw, file swap — runs *between*
pulses, off the hot path, and must be interruptible/yielding so a pulse is never
delayed. If an edit can't complete in the inter-pulse gap, it defers, it does not
block `onPulse`.

---

## 2. Event store (structure-of-arrays)  {#event-store}

A pattern's notes are **parallel numeric arrays**, not a list of tables. This is
the single most important RAM decision.

```lua
-- pattern.events
{
  n     = <int>,          -- live event count
  cap   = <int>,          -- allocated capacity (grow in chunks, never per-note)
  pitch = { ... },        -- 0..127
  start = { ... },        -- tick offset from pattern start (off-grid allowed)
  len   = { ... },        -- duration in ticks
  vel   = { ... },        -- 1..127
  -- events kept sorted by `start` so onPulse scans a moving window, not the whole array
}
```

Why not array-of-tables (the literal Hermod mental model)? Each `{p,start,len,vel}`
is a heap table; a busy pattern is hundreds of them, and editing churns the GC.
Parallel arrays store the same information with N pre-sized array slots and **zero
per-note table allocation**. Chords = multiple events with the same `start`.
Off-grid = arbitrary `start`. Polyphony and freedom are preserved; the cost is
gone.

**Quantization** is a *view/record* operation, not storage: recorded input snaps
`start` to the nearest grid tick at the chosen resolution; stored events remain
free-form so you can later nudge off-grid.

**Playback cursor.** Each track keeps `evCursor` — the index of the next event
whose `start` is due. `onPulse` advances a tick counter and pops events while
`start[evCursor] <= tick`, pushing them into the scratch buffer. No search, no
alloc. On loop wrap, reset cursor to 0.

---

## 3. The effect rack (live, per pulse, alloc-free)  {#rack}

Each track owns an ordered rack of ≤8 effects. Order is meaningful (Hermod §3.1:
Harmonizer-after-Arp ≠ Arp-after-Harmonizer).

**Contract.** Every effect is a table with:

```lua
fx.process(state, buf)   -- mutates buf in place; may drop/add within buf.cap; NO alloc
fx.params                -- numeric params; each has global value + optional per-pattern override
```

**Scratch buffer.** One fixed-capacity event buffer per engine (e.g. 64 slots),
reused every pulse:

```lua
scratch = { n=0, cap=64, pitch={}, len={}, vel={}, ch={} }
```

`onPulse` fills `scratch` from due events, then folds the rack over it:

```lua
buf.n = 0
collectDueEvents(track, tick, buf)      -- from event store, no alloc
for i = 1, track.rack.n do
    track.rack[i].process(state, buf)   -- default order: RANGE, RANDOM, SCALE
end
driver.emit(buf, track.chan)            -- ON now; schedule OFF at tick+len
```

Because `buf` and its sub-arrays are preallocated, an effect that *adds* notes
(future HARMONIZER/RATCHET) writes into spare capacity; one that *drops* notes
(CHANCE, FILTER) compacts `buf.n`. Never allocates.

### Milestone-1 effects

- **SCALE** — snap `pitch` to a pitch-class mask (port seq-1 `scale.lua`),
  octave-aware. `param: scaleIndex` (1 = off).
- **RANGE (performance limiter)** — the "top-level performance effect." Clamps
  each field to `[min,max]` around a `root`:
  `params: pitchRoot, pitchSpan, velMin, velMax, gateMin, gateMax`. These are the
  knobs you sweep live; each supports a per-pattern override (Hermod pattern
  values, §3.5).
- **RANDOM / CHANCE** — `params: chance` (skip probability), `pitchJitter`,
  `velJitter`, `octaveJitter`. Uses a fast integer RNG; one bounded roll per event.

---

## 4. RAM strategy & file swap

Grid modules have very little RAM, and we chose the memory-hungrier polyphonic
model — so swapping is mandatory, not optional.

- **In RAM:** the *active sequence* only — one selected pattern per track, plus
  each track's rack and channel. That's 4 patterns' event arrays at M4 (one
  per track). **Sequences themselves** (which pattern-slot + mute-state per
  track) are cheap metadata — small-int arrays, no note data — and can all
  stay resident regardless of how many exist.
- **On FS:** every other pattern slot, saved as a Lua chunk (`return{n=..,
  pitch={..}, ...}`) like seq-1's `persist.lua`. Loaded with `load()` — zero
  parser code. Unauthored slots simply don't have a file yet.
- **Swap trigger:** selecting a different **Sequence** (which changes 0 or more
  tracks' active pattern-slot). Per changed track: save-current then
  load-next, both **off the hot path**, ideally during a bar boundary so audio is
  seamless (Hermod's synchronized swap). Playback of the *currently sounding*
  pattern continues from its in-RAM copy until the swap point. Tracks whose
  slot didn't change in the new Sequence don't swap.
- **Never** touch the FS inside `onPulse`. Persist is an explicit App action.
- **Re-measure at 4 tracks.** §10's numbers (9.6 KB engine RAM) were measured
  at 2 tracks. Bumping to 4 tracks, plus Sequence/Song metadata, loop-region
  ints, nap/auto-reroll counters, and the new STEP/SEQ control code, needs a
  fresh measurement on a real build before assuming headroom — don't assume
  linear scaling holds.

Budget check to keep honest: pick a target max events/pattern (e.g. 256), size
`cap` accordingly, and add a `test_persist` round-trip + a `test_no_alloc`
covering the pulse path.

---

## 5. Screen — 320×240, split 120/120

VSN1: buffered draw, one `draw_swap()` per frame, ≤20 fps. Never redraw per
pulse — redraw on a UI timer, clear only dirty regions (`GRID_HARDWARE_API.md`).

```
┌────────────────────────────── 320 ──────────────────────────────┐
│ TOP  (y 0..119)   PIANO ROLL + PLAYHEAD                           │
│  - horizontal = time (current page), vertical = pitch            │
│  - events = filled rects; playhead = 1px vertical line, moving    │
│  - shows the selected track; ghost the other track dimmed         │
├──────────────────────────────────────────────────────────────────┤
│ BOTTOM (y 120..239)   MENU / PARAMETER CONTEXT                    │
│  - "where am I": TRACK n · PATTERN p · MODE · selected FX/param   │
│  - the active parameter's value, big, via draw_text_fast          │
│  - breadcrumb of the menu path                                    │
└──────────────────────────────────────────────────────────────────┘
```

Rendering is a pure function of state → `ggd*` draw calls, ending in `ggdsw()`
(one swap/frame). The M2 proto (`screens/seq2_screen.lua`) implements this layout
on the real Grid renderer via grid-wasm. See §8 for the screen dialect + render.

---

## 6. Menu system & control surface

**Superseded.** The original plan below assumed 4 function buttons + 8 small
buttons (B1..B8) as a working context row. On real hardware the small buttons
turned out to be dead; only **8 keyswitches + 1 push encoder** are usable.
Everything now goes through those. Design the menu as a small explicit state
machine (not nested closures — cheap to reason about, cheap in RAM). GUI/exact
screen layout is a separate pass — this section is data-model/control-flow
only.

**Modes.** Three, cycled by tapping a dedicated keyswitch (today KS7):
- **PLAY** — generator params (staged; see below). Compact bottom-bar view and
  the full-screen SETUP grid are two zoom levels of this *same* mode, not
  separate top-level modes.
- **STEP** — per-note editing, live (not staged). Select the note under the
  cursor/playhead; encoder click cycles which field is being edited (pitch →
  length → velocity); turn adjusts it directly — same flow as Hermod's STEP
  mode.
- **SEQ** — pattern-slot picking, Sequence building (pattern-slot + mute per
  track), Song chaining (ordered list of sequence-ids), launch/jump.

**Staging rule.** Only generator-param edits (PLAY mode: root, scale, spread,
hits, ...) stage — each would otherwise *regenerate the whole pattern*, a
destructive action worth protecting behind an explicit commit. A dedicated
keyswitch commits (applies staged values, calls the generator once). Every
other action — per-note edits (STEP), reroll, auto-reroll, mute, nap — applies
**immediately**, never staged.

**Fitting more onto 8 keys.** Secondary actions (commit, mute-toggle,
nap-arm, auto-reroll-arm) use **hold-vs-tap** on existing keys rather than
consuming new ones — the same "chord" idea the original F-button plan used,
adapted to keyswitches since that's all that survived the hardware. Exact
key-by-key bindings are an implementation detail decided while building, not
a design fork — see `src/app/control.lua` for the current map.

**Original plan (kept for history, not current):**

| Control | Role |
|---------|------|
| **Encoder turn** | Adjust the focused parameter / scroll the menu list. |
| **Encoder press** | Enter / confirm / toggle global-vs-pattern value (hold). |
| **F1..F4** | Top-level modes: `STEP` (edit), `FX` (rack), `TRACK`, `SEQ`. Mirrors Hermod's 4 modes. |
| **B1..B8** | Context row: in STEP = the 8 params / grid actions; in FX = the 8 rack slots; in TRACK = track/mute selects. |
| **Function chord** | Hold F + button for secondary actions (record arm, save, panic). |

**Control handoff.** Another Grid controller (e.g. a 16-button module) can be
bound as a *step keyboard* for quantized recording, or as a performance surface
that writes RANGE params. Handoff = the second module's input decoder posts into
the same App input queue over the Grid module link; Core doesn't care which
surface an edit came from. Keep input decoding in `hal/input.lua` per surface.

---

## 7. Recording quantized MIDI

From a connected 16-button Grid module (or bridge MIDI-in):

1. **Arm** (F-chord). While playing, incoming note-on/off are timestamped
   against the engine tick.
2. **Quantize on write:** `start` snaps to nearest grid tick at the current
   resolution; `len` from the note-off (or a default gate). Chords = same-tick
   events. Overdub by default; hard-record (overwrite) as a chord option
   (Hermod §1.7–1.8).
3. **Edit:** add/delete by grid cell, nudge `start`, stretch `len`, scale `vel`.
   Edits mutate the event store between pulses.

Recording writes to the *pattern's* event store directly; the live rack still
transforms playback, so you hear the recorded notes through SCALE/RANGE/RANDOM.

---

## 8. Prototyping & run loops

**Terminal → Ableton** (M1, headless):
```
lua proto/term/main.lua | python3 tools/bridge.py
```
`proto/term/main.lua` reads the seq-1 stdin protocol (`START`/`STOP`/`CLK`/
`QUIT`), drives `engine.onPulse`, writes `ON pitch vel ch` / `OFF pitch ch` to
stdout. `bridge.py` relays real MIDI clock in and notes out over virtual ports.
Set each track's channel via a patch or the App.

**grid-wasm screen proto** (M2, the on-device screen path — no game engine).

The grid-wasm page resolves screens at `<server-root>/screens/` (a sibling of
`grid-wasm/`) and lists them from `screens/manifest.json`. Our canonical screens
live in `sequencer-2/screens/`; a repo-root symlink `sequencer/screens ->
sequencer-2/screens` exposes them there. **Serve from the `sequencer` dir** (the
one holding both `grid-wasm/` and the `screens` symlink):
```
cd ..                       # the `sequencer` dir
python3 -m http.server 8080
```
Interactive (see it live): open `http://localhost:8080/grid-wasm/index.html`,
pick `seq2_screen` from the **Screen file** dropdown (auto-loads in a normal
browser), and turn the **Endless encoder [8]** field to sweep the playhead.

Headless (PNG, for CI / quick checks):
```
cd grid-wasm
node screenshot.mjs ../sequencer-2/screens/seq2_screen.lua 128 shot.png   # slider 0..255
```
`screens/seq2_screen.lua` is a FLAT Grid VM script (the real renderer):
no `require`, global state, `ggd*` draw primitives (`ggdrf`=rect_filled,
`ggdft`=text_fast, `ggdl`=line, `ggdr`=rect, `ggdpx`=pixel, `ggdsw`=swap),
inputs via injected globals (`sliderValue` 0..255 = encoder, `uiControlDown[0..12]`
= keyswitches/buttons), ~2 KB init-size budget. `screenshot.mjs` extracts the
`-- INIT START/END` and `-- LOOP START/END` blocks, loads them into the WASM
Grid VM via Playwright/chromium, and screenshots the canvas.

Because the harness previews ONE screen script in isolation, it draws a static
data snapshot (embedded demo notes) and sweeps the playhead from `sliderValue`.
Live engine↔screen wiring is a hardware concern (engine runs in the module's
other event scripts on-device; the screen reads shared globals). The screen
dialect (flat, `ggd*`, size-limited) is deliberately separate from the OO
`src/` engine — don't try to `require` engine modules from a screen script.

---

## 9. Open questions

**Resolved (see §0):** PPQN = 24 · event cap = 256 · loop length = steps+zoom ·
voice cap = 4 · RANGE = clamp · rack order = RANGE→RANDOM→SCALE · record =
1/16 overdub · proto clock = external+optional internal.

**Note-off scheduling** — RESOLVED in shape: a fixed 4-slot ring of pending offs
per track (voice cap = 4), each slot holding `{pitch, offTick, ch}`. `onPulse`
emits OFFs whose `offTick <= tick`; a new note in a full ring steals the slot
with the earliest `offTick`. Preallocated, alloc-free. Detail to nail at M1: the
exact tick-wrap comparison across loop boundaries.

**Resolved at M1 build:** zoom ladder = /2·×1·2/3·×2 · RANGE root fixed ·
voice-steal = oldest-off · transport reset semantics (see §0).

**Resolved at M4 grill (2026-08-26), see §11:** Sequence/Song data shape and
chaining · loop region · nap/wake · commit staging scope · per-note (STEP
mode) editing · auto-reroll · track count (2→4) · pattern slots/track (4,
extensible to 8) · mode structure (PLAY/STEP/SEQ).

**Still open:**
- Whether RANGE should also re-clamp *velocity/length* after RANDOM (currently
  only pitch is guaranteed in-key, via SCALE running last). **Revisit when
  performing.**
- Pattern-value override plumbing (per-pattern fx-param overrides — e.g. can
  P2's RANGE differ from P1's). Its precondition (>1 pattern/track) is now
  true, but the feature itself wasn't part of this grill — genuinely still
  open, not just gated on a precondition anymore.

---

## 10. Bundle, deployment & memory findings

**Build.** `lua tools/build.lua` minifies + concatenates the Core (`src/core`,
`src/fx`) into a single loadable **`dist/seq2.lua`** (require-shim + wrapped
modules + namespace table). Load with `local SEQ = (loadfile"dist/seq2.lua")()`
and use `SEQ.engine`, `SEQ.event`, `SEQ.pattern`, … The build also emits
`screens/seq2_live.lua` (the bundle embedded in a Grid screen that runs the real
engine, encoder-scrubbed — see below).

**Measured on desktop Lua 5.5 (proxy for the MCU's 5.4):**

| Metric | Value |
|--------|-------|
| Bundle size | 9.2 KB (from 17 KB source) |
| Engine RAM, realistic pattern (11 notes/track, 2 tracks) | ~9.6 KB |
| Per-pulse cost | ~1.3 µs, **zero-alloc** (0 KB / 200k pulses) |

**Findings from running the bundle inside the real Grid VM (grid-wasm):**

1. **Pre-sizing patterns to `cap` (256) OOM'd the Grid VM.** `event.new` used to
   fill all 4 arrays to 256 slots per pattern (2048 idle slots for 2 tracks).
   The Grid VM's Lua heap is small; this exhausted it. **Fix:** arrays now start
   empty and grow as notes are *added* (edit-time, off the hot path); `onPulse`
   only reads `1..n`, so playback stays zero-alloc. Engine footprint 27 KB → 9.6 KB.

2. **Embedding the WHOLE engine inside one screen chunk is memory-marginal.**
   The live screen (`seq2_live.lua`) builds the engine and replays it per frame.
   With **2 tracks + effects**, replaying a full 96-tick loop in one frame
   OOM'd; with **1 track** it renders across the whole encoder-scrub range. The
   Grid VM leaves little heap headroom once a big code chunk + engine tables are
   resident. **Implication for hardware:** the engine must live in the module's
   own event scripts (loaded once), and the **screen script must be thin** —
   reading published state, not embedding the engine. One giant chunk is the
   worst case. **Resolved:** `seq2_live.lua` is now a *thin data-only* screen —
   the generator runs at BUILD time and its notes are baked in as arrays; the
   screen only draws (~1.7 KB total, init 484 B). It survives unlimited input
   presses with no OOM. This is the correct hardware shape: **generation/engine
   happen elsewhere; the screen reads baked/published state and draws.**

**Net:** the sequencer runs in the real Grid VM. Compute and per-pulse cost are
non-issues; **RAM is the whole game**, exactly as the architecture assumed. Keep
patterns sparse, keep the screen script thin, load the engine once.

---

## 11. M4 — Composition, Sequence/Song, per-note editing

Output of the 2026-08-26 grill (`docs/research/composition-and-song-mode.md`
has the cross-device research this is grounded in). Data model and behavior
only — screen/GUI layout is a deliberately separate pass.

### 11.1 Sequence & Song {#seq-song}

A **Sequence** is cheap metadata, not note data — safe to keep all of them
resident:

```lua
sequence = {
  slot = { 1, 1, 1, 1 },        -- pattern-slot index per track (1..8)
  mute = { false, false, false, false },  -- per-track mute, local to this sequence
}
```

A **Song** is the Hermod-simple shape: a chain step is just a sequence-id, not
a row of fields. The gap between steps is one global setting, not per-step
state:

```lua
song = {
  steps   = { 1, 2, 1, 3 },     -- ordered sequence-ids, may repeat
  syncBars = 1,                 -- bars between step advances (applies to all)
  pos      = 1,                 -- index into steps currently playing
}
```

**Switching a Sequence** = for each track whose `slot[track]` differs from the
current one: swap that track's active pattern (§4's file-swap, off the hot
path, ideally at a bar boundary). Tracks whose slot didn't change don't
touch the FS. This is the concrete trigger for the swap mechanism §4 already
specified.

### 11.2 Pattern additions

**Loop region** — a saved sub-range, defaults to the whole pattern:

```lua
pattern.loopStart = 0             -- steps
pattern.loopEnd   = pattern.length -- steps; loopEnd == length ⇒ inactive (full pattern)
```

`track.advance` wraps against `[loopStart*zoom, loopEnd*zoom)` instead of
`[0, loopTicks)` when `loopEnd < length`. Small, local change — no new event
storage.

**Pattern slots** — a track has up to 8 addressable slots (Hermod's P1..P16,
scaled down; 4 active for the first build). Only the *currently selected*
slot's `Pattern` object is resident per track (§4); the rest are filenames
(`p<n>.lua`) that may not exist yet if never authored.

### 11.3 Nap & auto-reroll — transient per-track performance state

Neither persists to FS; both reset on track/pattern change. Both are driven
by the track's **own** loop count (its own pattern's wraps), not a shared
clock.

```lua
-- per track, engine-resident, not saved:
tr.nap = { armed=false, napLoops=4, wakeLoops=4, counter=0, muted=false }
-- PPW's 3rd param, Loop Shift (phase-offset nap/wake start), deliberately
-- deferred — v1 is Nap+Wake only; add a `shift` field later if it earns it.
tr.auto = { armed=false, everyLoops=4, counter=0, due=false }
```

**Hot-path split (important):** `track.advance` detects loop-wrap already
(§2's cursor reset). On wrap:
- **Nap's mute flip** is alloc-free (just a boolean) — safe to do directly in
  `onPulse`/`track.advance`: decrement `counter`; at 0, flip `muted` and reset
  `counter` to the other phase's length (`napLoops`/`wakeLoops`).
- **Auto-reroll's regenerate is NOT alloc-free** — `generate.run` clears and
  re-adds events, which can grow arrays. It must **not** run inside `onPulse`.
  On wrap, `track.advance` only sets `tr.auto.due = true` (alloc-free). A
  per-frame App-level check (already exists for screen redraw) reads
  `due` flags across tracks and calls the generator **off the hot path**,
  then clears the flag. Same rule as persistence: never touch the expensive
  path from inside a pulse.

**Napped-but-still-generating:** a napped track's rack/generator keep
running; only the *emitted* note-on is suppressed (checked at the same point
`emit()` is called in `track.advance`). This is what lets a track wake into
an evolved state rather than silence.

**Reroll and auto-reroll both apply immediately** (never staged) — see
§6's staging rule.

### 11.4 Per-note (STEP mode) editing

No new storage — `pitch[]/len[]/vel[]` already exist per-event (§2). What's
missing is *selection*: converting a UI step-position to an event index.

```lua
-- off the hot path; pattern.events kept sorted by start (§2), so linear scan is fine
local function findEventAtStep(pattern, step, zoom)
    local tick = step * zoom
    local ev = pattern.events
    for i = 1, ev.n do
        if ev.start[i] == tick then return i end
    end
    return nil
end
```

Editing found event `i`: mutate `ev.pitch[i]`/`ev.len[i]`/`ev.vel[i]` directly
in place — no array growth, applies live (no staging, per §6).

### 11.5 Track count

2 → 4 (locked param, §0). Sequence/Song structures scale with track count as
plain small-int arrays, so this doesn't complicate §11.1–11.4 — but see §4's
"re-measure at 4 tracks" note before assuming it fits.
