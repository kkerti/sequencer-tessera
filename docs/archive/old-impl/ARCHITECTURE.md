# Architecture

Snapshot of the system as of 2026-04-29 — after the **single-file collapse** that retired the per-module / bundling layout. This document is the living big-picture reference. `AGENTS.md` is the agent contract (style, constraints, data model); start there for rules, come here for shape.

---

## One-line shape

A **single ER-101–style CV+gate engine** lives in one Lua file, `sequencer.lua`, that runs unchanged on **both** macOS and the Grid module (ESP32 / Lua 5.4). A thin **Driver** layer inside the same file samples the engine each pulse and translates rising/falling gates into MIDI NOTE_ON/NOTE_OFF events. There is no compile pipeline, no precomputed event arrays, and no bundling — the source file is the deployment artifact.

```
┌──────────────── macOS (dev/test) ────────────────┐    ┌──────── Grid module (live) ────────────┐
│                                                  │    │                                        │
│  patches/<name>.lua  (terse pure-data table)     │    │   /sequencer.lua  (= sequencer.lua)    │
│        │                                         │    │   /controls.lua   (lazy-loaded UI)     │
│        ▼                                         │    │   /<patch>.lua                         │
│  Seq = require("sequencer")                      │    │        │                               │
│  engine = Seq.PatchLoader.load(path)             │    │        ▼                               │
│        │                                         │    │   Seq.PatchLoader.build → Engine       │
│        ▼                                         │    │        │                               │
│  Seq.Driver.new(engine)                          │    │        ▼                               │
│        │  per pulse, per track:                  │    │   Seq.Driver.new(engine)               │
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

## sequencer.lua

One file, one require, one returned table:

```lua
local Seq = require("sequencer")
-- Seq.Step, Seq.Pattern, Seq.Track, Seq.Scene, Seq.Engine,
-- Seq.MidiTranslate, Seq.PatchLoader, Seq.Driver, Seq.Utils
```

### Hierarchy (ER-101 model)

`Snapshot → Track → Pattern → Step`

* **Step** — packed Lua integer (37 bits used: pitch 7, velocity 7, duration 7, gate 7, probability 7, ratch 1, active 1). Setters return a new integer; always rebind. See `sequencer.lua` near `local Step = {}` for the bit layout.
* **Pattern** — named contiguous slice of a track's flat step list.
* **Track** — owns Patterns, flat cursor, loop points, direction, clock div/mult state, MIDI channel.
* **Engine** — fixed track count, per-pulse `sampleTrack` / `advanceTrack` API, BPM↔ms conversion, scene hooks.
* **Scene** — automated loop-point sequencing (one tick per beat).
* **MidiTranslate** — per-track edge detector: `(cvA, cvB, gate)` → `NOTE_ON` / `NOTE_OFF` (with retrigger on pitch change, panic).
* **PatchLoader** — turns a pure-data descriptor table into a populated Engine.
* **Driver** — per-pulse loop: sample → translate → advance, per track. Owns the clock-div/mult accumulator. Two entry points: `Driver.tick(d, emit)` (internal clock, host) and `Driver.externalPulse(d, emit)` (external MIDI 0xF8, device).
* **Utils** — table/math helpers.

### Emit signature

```
emit(kind, pitch, velocityOrNil, channel)
```

* `kind` is `"NOTE_ON"` or `"NOTE_OFF"`.
* `velocityOrNil` is the velocity for `NOTE_ON`, `nil` for `NOTE_OFF`.
* `channel` is 1-based MIDI channel.

The Driver invokes `emit` as the only side-effect of a pulse. The host's `main.lua` writes line-protocol text to stdout for `bridge.py`; the device's `grid_module.lua` calls `midi_send()` directly.

### Two clock sources

* **External MIDI 0xF8 (24 ppq) — default on device.** `grid_module.lua`'s rtmidi callback counts MIDI clocks, calls `Driver.externalPulse` once per `(24 / pulsesPerBeat)` clocks. `Driver.tick` is unused.
* **Internal libuv timer — default on host.** `main.lua` schedules a timer at `pulseMs / 2` and calls `Driver.tick(d, emit)`. `tick` reads `clockFn()` (libuv ms) and catches up.

**Never run both clocks at once** — the driver will double-advance.

---

## Host-only modules

Three small files live alongside `sequencer.lua` for authoring work and never ship to the device:

```
mathops.lua       transpose / jitter / random ops on step ranges
snapshot.lua      engine state save/load via io
probability.lua   shared probability helpers
tui.lua           text renderer for engine state (used by sequence_runner)
```

Each does `local Seq = require("sequencer")` and pulls the classes it needs from the returned table.

---

## controls.lua

The VSN1 on-device UI module. Lives at the project root next to `sequencer.lua`. Bundled separately to `grid/controls.lua` because the device **lazy-loads** it on first BUTTON event — pure-playback patches never pay the ~50 KB heap cost. See `grid_module.lua` for the wiring.

---

## Build & deployment

There is no bundler. `tools/build_grid.lua` does five `cp`s:

```sh
lua tools/build_grid.lua
```

```
sequencer.lua          → grid/sequencer.lua
controls.lua           → grid/controls.lua
patches/dark_groove    → grid/dark_groove.lua
patches/four_on_floor  → grid/four_on_floor.lua
patches/empty          → grid/empty.lua
```

Upload the `grid/*.lua` files to the device root.

### Grid require quirk

Grid firmware's `require()` does **not** do `package.path` `?` substitution. The module name is treated as a literal file path, including a leading slash and no `.lua` extension:

```lua
require("/sequencer")    -- works  (loads /sequencer.lua)
require("/dark_groove")  -- works  (loads /dark_groove.lua)
require("sequencer")     -- works on host, fails on device
```

`grid_module.lua` uses the leading-slash form. Host code and tests use the bare name.

### Element wiring

`grid_module.lua` is the canonical source for INIT / TIMER / BUTTON / RTMIDI callback blocks. Copy-paste sections; do not edit them on-device by hand.

---

## macOS harness

```sh
lua main.lua patches/four_on_floor | python3 bridge.py
```

`main.lua` requires an explicit patch path (no default). It builds the engine via `Seq.PatchLoader.load`, constructs a Driver with libuv as clockFn, runs a timer at `pulseMs/2`, and writes `NOTE_ON`/`NOTE_OFF` lines to stdout.

`bridge.py` opens a virtual MIDI port named `"Sequencer"` for Ableton.

SIGINT is trapped to flush all-notes-off via the emit callback before exit.

---

## File layout

```
sequencer.lua                 -- everything: Step, Pattern, Track, Scene, Engine,
                                 MidiTranslate, PatchLoader, Driver, Utils
controls.lua                  -- VSN1 UI (bundled separately to grid/controls.lua)

mathops.lua                   -- host-only authoring ops
snapshot.lua                  -- host-only state save/load
probability.lua               -- host-only probability helpers
tui.lua                       -- host-only text renderer

main.lua                      -- macOS harness (libuv timer → bridge.py)
bridge.py                     -- Python virtual-MIDI bridge
grid_module.lua               -- INIT / TIMER / BUTTON / RTMIDI paste blocks

patches/                      -- terse pure-data descriptors
  dark_groove.lua  four_on_floor.lua  empty.lua

grid/                         -- build output (cp from sources)
  sequencer.lua  controls.lua  dark_groove.lua  four_on_floor.lua  empty.lua

tools/
  build_grid.lua              -- five-cp build script
  memprofile.lua              -- on-device heap estimator

tests/                        -- behavioural tests (each uses require("sequencer"))
  utils.lua  step.lua  pattern.lua  track.lua  engine.lua
  mathops.lua  snapshot.lua  scene.lua  probability.lua  tui.lua
  midi_translate.lua  patch_loader.lua  driver.lua  controls.lua
  grid_bundle_smoke.lua       -- loads grid/sequencer.lua exactly as device would
  sequence_runner.lua         -- runs scenarios under the real Driver
  sequences/                  -- end-to-end feature scenarios

docs/
  ARCHITECTURE.md             -- this file
  2026-03-09-init-goal.md     -- original goal + ER-101/Metropolis decisions
  2026-04-28-cvgate-engine.md -- CV+gate refactor brief
  2026-04-28-drop-swing-and-scales.md
  manuals/                    -- ER-101 & Metropolis reference manuals
  archive/                    -- pre-collapse session notes (kept for history only)
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

## Status (2026-04-29)

* **Single-file collapse complete.** `sequencer/` and `driver/` subdirectories deleted; `utils.lua` folded in. One `sequencer.lua` (~45 KB raw) is the only library file shared between host and device.
* **Build pipeline reduced to file copies.** `tools/bundle.lua`, `strip.lua`, `charcheck.lua` removed. `tools/build_grid.lua` is now 40 lines of `cp`. No LuaSrcDiet, no minification — the Grid filesystem no longer enforces a per-file size limit.
* **All tests pass:** 15 unit-test files + 9 sequence scenarios + 1 grid-bundle smoke test.
* **`main.lua` requires an explicit patch arg** — there is no default.

### Known gaps

* On-device verification of the new single-file bundle still pending (smoke test passes synthetically).
* No on-device authoring UI beyond `controls.lua` — patch authoring is still descriptor-edit + redeploy.
