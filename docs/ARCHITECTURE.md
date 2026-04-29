# Architecture

Snapshot of the system as of 2026-04-28 — after the CV+gate refactor that retired the compile pipeline. This document is the living big-picture reference. `AGENTS.md` remains the agent contract (style, constraints, data model); start there for rules, come here for shape.

---

## One-line shape

A **single ER-101–style CV+gate engine** runs on **both** macOS and the Grid module (ESP32 / Lua 5.4). A thin **Driver** layer samples the engine each pulse and translates rising/falling gates into MIDI NOTE_ON/NOTE_OFF events. There is no compile pipeline and no precomputed event arrays — the engine is the source of truth at all times.

```
┌──────────────── macOS (dev/test) ────────────────┐    ┌──────── Grid module (live) ────────────┐
│                                                  │    │                                        │
│  patches/<name>.lua   (terse pure-data table)    │    │   /sequencer.lua                       │
│        │                                         │    │   /<patch>.lua                         │
│        ▼                                         │    │        │                               │
│  PatchLoader.build(descriptor) → Engine          │    │        ▼                               │
│        │                                         │    │   PatchLoader.build → Engine           │
│        ▼                                         │    │        │                               │
│  Driver.new(engine)                              │    │        ▼                               │
│        │  per pulse, per track:                  │    │   Driver.new(engine)                   │
│        │    cvA,cvB,gate = Engine.sampleTrack    │    │        │  on rtmidi 0xF8:              │
│        │    MidiTranslate.step → emit NOTE_ON/OFF│    │        │    Driver.externalPulse       │
│        │    Engine.advanceTrack                  │    │        │      → midi_send()            │
│        ▼                                         │    │        ▼                               │
│  bridge.py → virtual port "Sequencer"            │    │   MIDI out (DIN / TRS / USB)           │
│        ▼                                         │    │                                        │
│  Ableton                                         │    │   Clock = MIDI 0xF8 (external) by      │
│                                                  │    │   default; Driver.tick available for   │
│                                                  │    │   internal-clock mode                  │
└──────────────────────────────────────────────────┘    └────────────────────────────────────────┘
```

The **boundary** is the engine API itself: `(cursor, pulseCounter) → (cvA, cvB, gate)`. Both halves of the system call the same `Engine.sampleTrack` / `Engine.advanceTrack` and use the same `MidiTranslate` edge detector.

---

## Why this shape

The previous architecture was a rich macOS authoring engine that compiled songs to flat event arrays for a tiny on-device tape-deck player. That worked, but had three costs:

1. **Two truths.** The engine and the compiled song could drift; bug fixes had to be applied to both.
2. **No live editing.** Any change to a step required recompiling the whole song.
3. **Tooling weight.** A compile pipeline (`tools/song_compile.lua`), a writer (`sequencer/song_writer.lua`), an in-place editor (`live/edit.lua`), and a player (`player/player.lua`) all existed to work around the absence of an on-device engine.

Once the Grid filesystem dropped its 880-char per-file limit, the sequencer engine became small enough to ship. The whole compile/player/writer/editor stack collapses into **engine + driver + patch loader**. Bug fixes apply once. Edits are immediate. Future authoring features (knob tweaks, button-driven mathops) just call the existing `Step.set*` setters on the live engine.

---

## Engine (`sequencer/`)

The single ER-101 + Metropolis engine, shared between host (macOS dev harness) and device (bundled to `grid/sequencer.lua`).

| Module | Role | On device? |
|---|---|---|
| `step.lua`           | Step record. `Step.sampleCv(s) → pitch, velocity`. `Step.sampleGate(s, pulseCounter) → bool` (ER-101 boolean ratchet, period = 2 × gate, suppressed once `pulseCounter >= duration`). | yes |
| `pattern.lua`        | Named contiguous slice of a track's step list. Pure organisational layer. | yes |
| `track.lua`          | Per-track state: patterns, loop points, clock div/mult, direction (forward / reverse / pingpong / random / Brownian). `Track.sample → cvA, cvB, gate`; `Track.advance` (no return). Rolls per-step entry probability on `Track.new`/`reset`/cursor advance/zero-dur skip. | yes |
| `engine.lua`         | Top-level: BPM, multi-track sample/advance. `Engine.sampleTrack(eng, i) → cvA, cvB, gate`. `Engine.advanceTrack(eng, i)` (no return). `Engine.onPulse(eng, pulseCount)` runs scene-chain hooks. | yes |
| `scene.lua`          | Scene chain — automated loop-point sequencing. | yes |
| `midi_translate.lua` | **Driver-side** edge detector. Per-track state `{prevGate, lastPitch}`. `step(state, cvA, cvB, gate, channel, emit)` emits NOTE_ON on rising edge, NOTE_OFF on falling, OFF+ON on pitch change mid-gate. `panic(state, channel, emit)` clears all hanging notes. | yes |
| `patch_loader.lua`   | `build(descriptor) → Engine`; `load(modulePath) → Engine`. Walks a pure-data descriptor table and populates a fresh engine. | yes |
| `mathops.lua`        | Transpose / jitter / random on step parameters (one step, one pattern, or one track). | host-only |
| `snapshot.lua`       | Serialize/deserialize full engine state via `io`. | host-only |
| `probability.lua`    | Shared probability helpers. (Per-step entry rolls are inlined in `track.lua`.) | host-only |
| `controls.lua`       | VSN1 control surface UI. Bundled separately to `grid/controls.lua` and lazy-loaded on first BUTTON event. | yes (separate bundle) |

Tests live in `tests/`. Module files contain only `assert()` input-validation guards.

---

## Driver (`driver/driver.lua`)

The glue layer that turns engine pulses into MIDI events. Runs on both host and device. Public API:

```
Driver.new(engine, clockFn?, bpm?)    -- clockFn nil → external-clock mode only
Driver.start(d)                        -- panics, rewinds tracks, resets translators
Driver.stop(d)                         -- emits all-notes-off via emit callback
Driver.setBpm(d, bpm)                  -- internal-clock mode
Driver.tick(d, emit)                   -- internal clock: derive target pulse from clockFn() and catch up
Driver.externalPulse(d, emit)          -- one master pulse (e.g. one MIDI 0xF8 after 24→ppb division)
Driver.allNotesOff(d, emit)            -- panic without stopping
```

Per-pulse loop inside `Driver.externalPulse`:

```lua
for each track i:
    track.clockAccum += track.clockMult
    advanceCount = floor(track.clockAccum / track.clockDiv)
    track.clockAccum = track.clockAccum % track.clockDiv
    repeat advanceCount times:
        cvA, cvB, gate = Engine.sampleTrack(engine, i)
        MidiTranslate.step(translators[i], cvA, cvB, gate, channel, emit)
        Engine.advanceTrack(engine, i)
Engine.onPulse(engine, pulseCount)
```

The clock-div/mult **accumulator lives in the driver, not the engine**. The engine's notion of "pulse" is a single sample-then-advance step. The driver is what defines a master clock pulse and decides how many engine pulses each master pulse drives per track.

`Driver.tick` is a thin shim over `externalPulse`: it derives a target pulse count from `clockFn()` and calls `externalPulse` until caught up.

---

## Patch loader (`sequencer/patch_loader.lua`)

`PatchLoader.build(descriptor) → Engine`. The descriptor is a pure-data Lua table (see `patches/dark_groove.lua`); the loader walks it and populates a fresh engine. Loader runs on both host and device — the device just calls `PatchLoader.build(require("/dark_groove"))`.

Descriptor format (all fields with `?` are optional):

```lua
{
    bpm           = 118,
    ppb           = 4,                          -- pulses per beat
    bars?         = 4,                          -- only used by host harness
    beatsPerBar?  = 4,                          -- only used by host harness
    tracks = {
        {
            channel    = 10,                    -- 1-based MIDI channel
            direction  = "forward",             -- forward/reverse/pingpong/random/brownian
            clockDiv   = 1,
            clockMult  = 1,
            loopStart? = 1,
            loopEnd?   = 16,
            patterns = {
                {
                    name  = "kick",
                    steps = {
                        -- {pitch, velocity, duration, gate, ratch?, prob?}
                        { 36, 110, 4, 2 },
                        { 36, 110, 4, 2, false, 100 },
                        ...
                    },
                },
            },
        },
    },
}
```

---

## Two clock sources

### 1. External MIDI clock (default on device)

The `rtmrx_cb` block in `grid_module.lua` translates incoming MIDI bytes:

| Byte  | Meaning           | Action |
|-------|-------------------|--------|
| 0xF8  | Timing clock      | count down `24 / pulsesPerBeat` per master pulse, then `Driver.externalPulse` |
| 0xFA  | Start             | `Driver.start` (rewind, panic) |
| 0xFB  | Continue          | resume from current pulse |
| 0xFC  | Stop              | `Driver.stop` (panic via emit callback) |

`engine.pulsesPerBeat` must divide 24 evenly (1, 2, 3, 4, 6, 8, 12, 24). All current patches use `ppb=4` → 6 MIDI clocks per master pulse.

### 2. Internal timer (default on host)

`main.lua` wires a libuv timer firing every `pulseMs / 2`. The timer body calls `Driver.tick(driver, emit)`; `tick` reads `clockFn()` (an `os.clock`-based ms counter) and catches up. Same pattern works on device by replacing `Driver.externalPulse` in the timer block — `Driver.tick(SEQ_DRIVER, SEQ_EMIT)`.

**Never run both clocks at once** — the driver will double-advance.

---

## Build pipeline & deployment

### Tools

| Tool | Role |
|---|---|
| `tools/build_grid.lua` | One-shot: bundle + strip + patch-copy → `grid/`. |
| `tools/bundle.lua`     | Splice N source modules into one self-contained Lua file. `--as NAME=PATH` declares an inlined module; `--alias KEY=NAME` adds extra require-key → local mappings (used so PatchLoader's `require("sequencer/engine")` resolves to the inlined lite Engine local). |
| `tools/strip.lua`      | Remove comments and statement-form `assert(...)` guards. Preserves value-returning asserts (`local f = assert(io.open(p))`). Halves the bundle's footprint. |
| `tools/charcheck.lua`  | Reports raw and minified character counts (no thresholds; used for memory-footprint estimation). |
| `tools/memprofile.lua` | On-device memory footprint estimator. |

### Grid require quirk

Grid firmware's `require()` does **not** do `package.path` `?` substitution. The module name is treated as a literal file path, including a leading slash and no `.lua` extension:

```lua
require("/sequencer")    -- works  (loads /sequencer.lua)
require("/dark_groove")  -- works  (loads /dark_groove.lua)
require("sequencer")     -- fails
```

### Flat layout on device

Every module bundles into a single file at the filesystem root:

```
/sequencer.lua       ← grid/sequencer.lua    (engine + Scene + MidiTranslate + PatchLoader + Driver, bundled+stripped+dieted)
/controls.lua        ← grid/controls.lua     (~5 KB stripped+diet: UI module; LAZY-LOADED on first button event)
/dark_groove.lua     ← grid/dark_groove.lua  (pure-data patch descriptor)
/four_on_floor.lua   ← grid/four_on_floor.lua
/empty.lua           ← grid/empty.lua
```

`require("/sequencer")` returns the Driver module table; `Driver.PatchLoader`, `Driver.Engine`, `Driver.MidiTranslate`, `Driver.Track`, `Driver.Pattern`, `Driver.Step`, `Driver.Utils` are all reachable as fields (via `--expose`).

`require("/controls")` returns the Controls module. It is **not** loaded
at boot — root `controls.lua` paste glue defines `PI()` which
`require()`s the module on first BUTTON / SCREEN INIT event. This keeps
cold-boot heap to ~50 KB (worst case dark_groove); UI loads on-demand
adding ~54 KB. See `docs/2026-04-29-memory-overflow-plan.md`.

The Controls bundle is built with `--alias sequencer/step=Step
--alias sequencer/track=Track` and prepends a one-line shim
`local _D = require("/sequencer"); local Step=_D.Step; local Track=_D.Track`
so it shares the engine's already-loaded Step/Track classes rather than
duplicating them.

### Build commands

```sh
lua tools/build_grid.lua
```

That's it. The script wipes stale grid contents, runs the bundle + strip, and copies patch descriptors. Output:

```
grid/sequencer.lua       20.9 KB stripped (40.4 KB raw)
grid/dark_groove.lua     880 B
grid/four_on_floor.lua   482 B
grid/empty.lua           420 B
```

For ad-hoc bundling (e.g. with the full engine for testing):

```sh
lua tools/bundle.lua --out /tmp/bundle.lua \
    --as Utils=utils.lua \
    --as Step=sequencer/step.lua \
    --as Pattern=sequencer/pattern.lua \
    --as Track=sequencer/track.lua \
    --as Engine=sequencer/engine.lua \
    --as MidiTranslate=sequencer/midi_translate.lua \
    --as PatchLoader=sequencer/patch_loader.lua \
    --as Driver=driver/driver.lua \
    --main Driver \
    --expose Engine --expose PatchLoader
```

### Element wiring

`grid_module.lua` is the canonical source for INIT / TIMER / BUTTON / RTMIDI callback blocks. Copy-paste sections; do not edit them on-device by hand.

---

## macOS harness

`main.lua [patch_path]` — defaults to `patches/dark_groove`. Loads the descriptor, builds the engine via `PatchLoader`, constructs a `Driver` with an `os.clock`-based clockFn, runs a libuv timer at `pulseMs/2`, and pipes `NOTE_ON`/`NOTE_OFF` line-protocol events to stdout. Pipe to `bridge.py`:

```sh
lua main.lua patches/four_on_floor | python3 bridge.py
```

`bridge.py` opens a virtual MIDI port named `"Sequencer"` for Ableton.

SIGINT is trapped to flush all-notes-off via the emit callback before exit.

---

## File layout (current)

```
main.lua                       -- macOS harness: PatchLoader → Driver → libuv timer → bridge.py
bridge.py                      -- Python MIDI bridge: stdin → virtual port "Sequencer"
grid_module.lua                -- INIT / TIMER / BUTTON / RTMIDI callback copy-paste blocks
utils.lua                      -- shared helpers: tableNew, tableCopy, clamp, pitchToName
tui.lua                        -- terminal renderer for engine state snapshots

sequencer/                     -- ENGINE (host + device)
  step.lua                     -- sampleCv, sampleGate (boolean ratchet)
  pattern.lua                  -- named slice of a track's step list
  track.lua                    -- sample/advance + entry-probability roll
  engine.lua                   -- sampleTrack/advanceTrack/onPulse + scene hooks
  scene.lua                    -- automated loop-point sequencing
  midi_translate.lua           -- per-track edge detector + retrigger + panic
  patch_loader.lua             -- descriptor table → Engine
  controls.lua                 -- VSN1 UI (bundled separately to grid/controls.lua)
  mathops.lua                  -- transpose/jitter/random ops (host-only)
  snapshot.lua                 -- engine state save/load (host-only)
  probability.lua              -- shared probability helpers (host-only)

driver/                        -- DRIVER LAYER (host + device)
  driver.lua                   -- per-pulse sample → translate → advance loop;
                               -- clock div/mult accumulator inside externalPulse;
                               -- tick() (internal) and externalPulse() (MIDI 0xF8) entry points

patches/                       -- terse pure-data descriptors
  dark_groove.lua  four_on_floor.lua  empty.lua

grid/                          -- final upload bundle (FLAT, root files)
  sequencer.lua                -- → /sequencer.lua  on device  (engine + driver + patch loader)
  controls.lua                 -- → /controls.lua   on device  (UI; lazy-loaded)
  dark_groove.lua              -- → /dark_groove.lua  on device
  four_on_floor.lua            -- → /four_on_floor.lua  on device
  empty.lua                    -- → /empty.lua  on device

tools/
  build_grid.lua               -- one-shot bundle + strip + patch-copy
  bundle.lua                   -- splice N modules; rewrites cross-module require(); --alias for cross-path keys
  strip.lua                    -- comment + statement-assert remover
  charcheck.lua                -- raw + minified char count reporter
  memprofile.lua               -- memory footprint estimator

tests/                         -- behavioural tests
  utils.lua  step.lua  pattern.lua  track.lua  engine.lua
  mathops.lua  snapshot.lua  scene.lua  probability.lua  tui.lua
  midi_translate.lua           -- edge detection + retrigger + panic
  patch_loader.lua             -- descriptor → engine round-trip (incl. real patches/*)
  driver.lua                   -- driver pulse loop + clock div/mult + start/stop/panic
  controls.lua                 -- UI editing model + screen renderer
  grid_bundle_smoke.lua        -- loads grid/sequencer.lua exactly as device would
  sequence_runner.lua          -- runs scenarios in tests/sequences/ via real Driver
  sequences/                   -- end-to-end feature scenarios

docs/
  ARCHITECTURE.md              -- this file
  2026-03-09-init-goal.md      -- original goal + ER-101/Metropolis decisions
  2026-04-28-cvgate-engine.md  -- CV+gate refactor brief and work plan
  manuals/                     -- ER-101 & Metropolis reference manuals
  2026-04-*.md                 -- session notes (chronological)
```

---

## Bridge line protocol

Used between any macOS Lua harness and `bridge.py`:

```
NOTE_ON  <pitch> <velocity> <channel>   -- channel is 1-based
NOTE_OFF <pitch> <channel>
```

On device the Driver's `emit` callback calls `midi_send(channel, status, note, velocity)` directly.

---

## Status (2026-04-28)

- **CV+gate refactor complete.** Engine, Driver, PatchLoader, MidiTranslate all in place; compile pipeline + tape-deck player + in-place editor all deleted.
- **All tests pass:** 15 unit-test files + 9 sequence scenarios + 1 grid-bundle smoke test.
- **Bundle is 5 files.** `grid/sequencer.lua` (~10 KB stripped+diet) + `grid/controls.lua` (~5 KB stripped+diet, lazy-loaded) + 3 patch descriptors (~0.4–0.9 KB each).
- **Two clock modes shipped:** internal libuv timer (host) and external MIDI 0xF8 (device). Internal-timer mode is also available on device by swapping the rtmidi callback for a `Driver.tick` call in the timer block.

### Known gaps

- Hardware on-device verification of the new bundle pending (smoke test passes synthetically; real-device run is the next step).
- No on-device authoring UI yet — edits are made by editing patch descriptors and rebuilding the bundle. The architecture supports live edits via direct `Step.set*` / `Track.set*` calls; just no UI to drive them.

### Likely next areas

- Wire physical Grid buttons to `Driver.start` / `Driver.stop` / `Driver.allNotesOff`.
- On-device patch selector (multiple `/<patch>.lua` files; reload-on-button).
- Knob-driven mathops on the live engine (transpose / jitter / random).
- Identifier-shortening minifier pass for headroom.
