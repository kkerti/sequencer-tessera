# AGENTS.md

## Project

Lua 5.5 step sequencer library targeting the **Grid modular controller platform** (ESP32 + luaVM, which runs Lua 5.4). Development and validation happen on macOS first, then code runs unmodified on device.

Reference designs: `docs/manuals/er-101.md`, `docs/manuals/metropolis.md`. Goal document: `docs/2026-03-09-init-goal.md`. **Big-picture system map: `docs/ARCHITECTURE.md`** — read it before starting non-trivial work; it describes the engine-on-device CV+gate model, the Driver layer, the patch loader, and the build/upload pipeline.

---

## Reference design rationale

Two hardware sequencers inform this project. Their roles are distinct:

### ER-101 — engine architecture (primary)

The ER-101 governs the **data model and playback engine**. Its `Snapshot → Track → Pattern → Step` hierarchy maps well to the multi-track MIDI engine being built on Grid. Key decisions taken from the ER-101:

- Pattern is an **organisational sub-division of a track's step list** — a named, contiguous slice of steps. It is not a complete sequence save slot.
- Loop points are **per-track, independently settable start and end**, expressed as flat absolute step indices. They are a primary performance tool ("play like a sample looper"). RESET always bypasses loop points and rewinds to pattern 1 step 1.
- Clock div/mult is **per-track** (not global), using an accumulator to handle any integer ratio without drift.
- Math operations (jitter, random, transpose) act on individual step parameters, scoped to a step, pattern, or track.
- Snapshots save full engine state (all tracks, all patterns, all steps, loop points, clock settings).
- Ratchet is **per-step boolean** (ER-101 style). When true, the gate cycles inside the step with period = 2 × `gate` pulses (ON for `gate` pulses, OFF for `gate` pulses, repeated until `duration` ends). When false, the step fires once.

### Metropolis — feature design (selective adoption)

The Metropolis's strength is **playability**: its hardware interface (faders, switches, per-stage controls) makes it immediately expressive. Its sequencer architecture (fixed 8 stages, single track, no loop points) is not a good fit for our engine. However, several specific feature designs from the Metropolis are cleaner than the ER-101 equivalents and will be adopted:

| Feature | Metropolis design | Why adopt it over ER-101 |
|---|---|---|
| **Direction modes** | Forward, Reverse, Ping-Pong, Brownian, Random | ER-101 is forward-only; direction modes are valuable for Grid performance |

Features **not** adopted from the Metropolis: its "pattern = complete saved sequence" concept, global-only clock division, fixed 8-stage limit, AUX CV modulation inputs (no equivalent on Grid), hardware-slider pitch editing, the global swing percentage, the live scale quantizer, and the integer ratchet count (1–4) — we use the ER-101's boolean ratchet flag instead. Swing and scale quantization are timing-feel and harmony-shaping concerns; this project intentionally leaves both to downstream MIDI processors. See `docs/2026-04-28-drop-swing-and-scales.md`.

---

## Runtime constraints

- Target device is **Lua 5.4 only** — no standard helper functions exist on-device, plain Lua tables and the standard library only
- No `require` of third-party rocks on device; those are macOS dev tools only
- Single-threaded; **one timer** drives the entire sequencer tick — do not create multiple timers
- `io` is available on device for snapshot file reads/writes
- VSN1 screen is 320×240px LCD; simultaneous high-frequency updates cause buffering lag — batch screen redraws
- The Grid filesystem accepts arbitrarily large Lua files (the old 880-char per-file limit no longer applies). Memory footprint still matters — keep modules small, prefer compact compiled-data layouts.

## Dev environment (macOS)

- System Lua is **5.5** (`lua --version`); keep that in mind when installing rocks
- Package manager: **LuaRocks** (rocks installed under Lua 5.5 path)
- Timer/event loop in dev: `luv` (already installed)
- **`lua-rtmidi` does not build on this machine** (Lua 5.5 ABI mismatch) — use the Python bridge instead
- MIDI bridge: `python3 bridge.py` — reads the line protocol from stdin, opens a virtual port named `"Sequencer"`
- Run on macOS: `lua main.lua [patches/<name>] | python3 bridge.py` (default patch is `patches/dark_groove`)
- Build the Grid upload bundle: `lua tools/build_grid.lua` (produces flat `grid/sequencer.lua` + per-patch `grid/<name>.lua`). See README.md for details.
- Run unit tests: `for t in utils step pattern track engine mathops snapshot scene tui probability midi_translate patch_loader driver grid_bundle_smoke controls; do lua tests/$t.lua || break; done`
- Run feature scenarios: `lua tests/sequence_runner.lua all`
- `python-rtmidi` installed system-wide via `pip3 install python-rtmidi --break-system-packages`

## Ableton setup

In Ableton: Preferences → MIDI → enable **"Sequencer"** as a MIDI input source. The virtual port appears only while `bridge.py` is running.

---

## Naming and style

- **`hungarianNotationForFunctions()`** for all functions and variables — camelCase starting lowercase
  - Correct: `stepGetGate`, `trackClockDiv`, `engineSetBpm`
  - Wrong: `get_gate`, `GetGate`, `step_get_gate`
- Module tables use **dot-notation**: `Step.new`, `Track.advance`, `Engine.tick`
- Prefer expanded readable code over shorthands — but see "Style: zones, abbreviations, and the codebook" below for the zones where short names are required
- Keep functions short and isolated; split into new files when a file grows large
- Utility/helper functions (table ops, math helpers) **must live in `utils.lua`** — not inlined in sequencer modules

## Style: zones, abbreviations, and the codebook

This project is generated and maintained by LLM agents. Code is validated by running it (host harness, unit tests, scenario runner) and by loading the bundle into the Grid Lua VM — not by humans reviewing diffs line-by-line. The style rules below reflect that workflow.

### Optimisation priority (in order)

1. **On-device memory footprint.** Lite engine bundle ceiling ~140 KB; current ~129 KB. Every byte counts.
2. **Clear module boundaries** (lite vs full engine, driver vs engine, controls vs driver).
3. **DRY within a zone.** *Not* across the lite/full boundary — the carve is intentional.
4. **Human readability.** Still valued: future LLMs grep for descriptive names, and humans inspect code when something breaks.

### Zones

| Zone | Audience | Naming style |
|---|---|---|
| `sequencer/`, `tests/`, `tools/`, `main.lua`, `driver/`, `utils.lua`, `tui.lua` | macOS dev + bundled to device | Full readable hungarianNotation. **LuaSrcDiet shortens locals at build for the device bundle.** Source stays clean. |
| `controls.lua` paste blocks | Grid Editor (880-char per-event paste budget) | Short names mandatory. Document every short name in `docs/CODEBOOK.md`. |
| Packed encodings (Step int, future snapshot wire format) | Lua VM | Encoded; bit layouts and constants documented in `docs/CODEBOOK.md`. |

### Rules

- **First resort: delete, don't abbreviate.** If a feature isn't needed, drop it from `sequencer/`. We've already done this for swing and live scale quantization. Bigger byte win than golfing names.
- **Abbreviate only with a measured saving.** Either bytes-on-device after diet, or characters in a paste-budget-constrained block. No vibes-based shortening. If you can't quote a number, leave the name long.
- **Source stays readable; the bundle is what ships short.** Never apply paste-block style (`s`, `EM`, `DR`) to non-paste source code. LuaSrcDiet does that work for you.
- **Every short name or packed encoding gets a `docs/CODEBOOK.md` entry.** Single-letter param codes, packed-int bit layouts, single-char locals in paste blocks, alias short forms in `tools/build_grid.lua` `--as` — all of it. The codebook is the live mapping; date entries when added.

See `docs/CODEBOOK.md` for the live mapping of every short name and packed encoding in the project.

## Testing

- Tests live in `tests/` as separate files: `tests/utils.lua`, `tests/step.lua`, `tests/pattern.lua`, `tests/track.lua`, `tests/engine.lua`, `tests/mathops.lua`, `tests/snapshot.lua`, `tests/scene.lua`, `tests/probability.lua`, `tests/midi_translate.lua`, `tests/patch_loader.lua`, `tests/driver.lua`, `tests/grid_bundle_smoke.lua`, `tests/tui.lua`, `tests/controls.lua`
- Feature scenario files live in `tests/sequences/` and are executed via `tests/sequence_runner.lua`
- Run a test file directly: `lua tests/track.lua` — asserts fire and print `OK` on success
- Module files contain **input validation `assert()` guards only** (wrong type, out-of-range) — no behavioural tests in module files
- Behavioural tests (sequencing, event order, boundary conditions) belong in `tests/`

---

## Data model (ER-101 architecture)

The hierarchy is: **Snapshot → Track → Pattern → Step**

| Level    | Max count                        | Notes |
|----------|----------------------------------|-------|
| Snapshot | 16                               | Full state save; saving blocks ~0.75s — never save mid-performance |
| Track    | 8 per snapshot                   | Independent clock div/mult and loop points per track |
| Pattern  | 100 per track                    | Contiguous named slice of a track's step list; purely organisational |
| Step     | 2000 total across all tracks     | Shared pool |

**Step parameters** — pitch/velocity are MIDI (0–127); duration/gate are clock pulses (0–99):
- `pitch`    — MIDI note number; 0 = rest when gate is also 0
- `velocity` — MIDI velocity
- `duration` — step length in clock pulses (0 = skip this step)
- `gate`     — note-on length in clock pulses (0 = rest; `gate >= duration` = legato)
- `ratch`    — boolean; when true, gate cycles inside duration (ER-101 style)
- `probability` — chance this step fires (0–100, 100 = always; Blackbox-style, non-destructive)
- `active`   — boolean mute without deleting the step

**Pitch is stored as a raw MIDI note number.** Harmony shaping (scale quantization, transposition) is intentionally out of scope for the engine — apply it downstream of MIDI if you need it.

## Key engine behaviours — implementation status

| Feature | Status |
|---|---|
| Single track, flat step list, loop | Done |
| NOTE_ON / NOTE_OFF events from engine tick | Done |
| BPM → pulse interval conversion | Done |
| Per-track clock division / multiplication | Done |
| Loop points (loopStart / loopEnd) | Done |
| Patterns (sub-grouping of steps into named slices) | Done |
| Ratcheting (boolean per-step, ER-101 style) | Done |
| Direction modes (forward/reverse/ping-pong/random/Brownian) | Done |
| Live scale quantizer (Metropolis-style, 30 scales) | Removed (downstream concern) |
| Swing (global percentage, Metropolis-style) | Done |
| Math operations (add/jitter/random on params) | Done |
| Snapshots (serialize full state via `io`) | Done |
| Scene chain (automated loop-point sequencing) | Done |
| Pattern copy/paste/duplicate/delete/insert/swap | Done |
| Per-step probability (non-destructive, Blackbox-style) | Done |

## File layout

See `docs/ARCHITECTURE.md` for the full system map and rationale. Quick reference:

```
main.lua                       -- macOS harness: PatchLoader → Driver → libuv timer → bridge.py
bridge.py                      -- Python MIDI bridge: stdin → virtual port "Sequencer"
grid_module.lua                -- copy-paste INIT / TIMER / BUTTON / rtmidi-callback blocks for the Grid module
utils.lua                      -- shared helpers: tableNew, tableCopy, clamp, pitchToName
tui.lua                        -- terminal renderer for engine state snapshots

sequencer/                     -- FULL AUTHORING ENGINE (macOS only)
  step.lua                     -- Step.new, sampleCv, sampleGate (ER-101 boolean ratchet)
  pattern.lua                  -- Pattern.new, named contiguous slices of a track's step list
  track.lua                    -- Track.new, sample, advance; direction/loop/clock controls; per-step entry-probability roll
  engine.lua                   -- Engine.new, sampleTrack, advanceTrack, onPulse, BPM, reset
  mathops.lua                  -- transpose/jitter/random operations on step params
  snapshot.lua                 -- save/load full engine state via io
  scene.lua                    -- Scene chain: automated loop-point sequencing
  probability.lua              -- shared probability helpers (used by mathops/scene)
  midi_translate.lua           -- per-track edge detector: (cvA,cvB,gate) → NOTE_ON / NOTE_OFF (+ retrigger on pitch change, panic)
  patch_loader.lua             -- patch descriptor (table) → fully populated Engine

driver/                        -- DRIVER LAYER (runs on host AND device)
  driver.lua                   -- per-pulse: sample → translate → advance, per track; clock div/mult accumulator inside externalPulse; tick() for internal clock, externalPulse() for MIDI 0xF8

patches/                       -- terse patch descriptors (pure-data Lua tables)
  dark_groove.lua  four_on_floor.lua  empty.lua

grid/                          -- final upload bundle (FLAT — one file per library at root)
  sequencer.lua                -- → /sequencer.lua  on device  (engine + Scene + MidiTranslate + PatchLoader + Driver, all bundled+stripped+dieted)
  controls.lua                 -- → /controls.lua   on device  (UI module; lazy-loaded on first BUTTON event)
  <patch>.lua                  -- → /<patch>.lua    on device  (pure-data descriptor, e.g. /four_on_floor.lua)

tools/
  build_grid.lua               -- one-shot bundle + strip + patch-copy → grid/
  bundle.lua                   -- splice N modules into one file; rewrites cross-module require(); --alias for cross-path keys
  strip.lua                    -- comment + statement-assert remover
  charcheck.lua                -- raw + minified char count reporter
  memprofile.lua               -- on-device memory footprint estimator

tests/
  utils.lua  step.lua  pattern.lua  track.lua  engine.lua
  mathops.lua  snapshot.lua  scene.lua  probability.lua  tui.lua
  midi_translate.lua           -- edge detection + retrigger + panic
  patch_loader.lua             -- descriptor → engine round-trip (incl. real patches/*)
  driver.lua                   -- driver pulse loop + clock div/mult + start/stop/panic
  grid_bundle_smoke.lua        -- loads grid/sequencer.lua exactly as device would; drives + asserts emit
  controls.lua                 -- UI editing model + screen renderer
  sequence_runner.lua          -- runs scenarios in tests/sequences/ via real Driver
  sequences/                   -- end-to-end feature scenarios

docs/
  ARCHITECTURE.md              -- full system map: engine-on-device, Driver, PatchLoader, deployment, clock modes
  2026-03-09-init-goal.md      -- project goal and architecture decisions
  2026-04-28-cvgate-engine.md  -- CV+gate refactor brief and work plan
  manuals/er-101.md            -- ER-101 feature reference (engine architecture)
  manuals/metropolis.md        -- Metropolis reference (selective feature adoption)
  2026-04-*.md                 -- chronological session notes
```

## Bridge line protocol

```
NOTE_ON  <pitch> <velocity> <channel>   -- channel is 1-based
NOTE_OFF <pitch> <channel>
```

## Session memory

- After each significant session, write a note to `docs/YYYY-MM-DD-<short-topic>.md`
- Keep it minimal and concise — decisions made, current state, next steps

## Multiple agents

Recommended split when parallelising work. A single engine in `sequencer/` is shared between host (macOS dev harness) and device (Grid module via the bundled `grid/sequencer.lua`); the Driver layer runs on both:

- **Engine agent** — `sequencer/engine.lua`, `sequencer/track.lua`, `sequencer/pattern.lua`, `sequencer/step.lua`, `sequencer/scene.lua`. Core playback model. Bundled to device.
- **Authoring agent** — `sequencer/mathops.lua`, `sequencer/snapshot.lua`, `sequencer/probability.lua`. Host-only authoring features; not bundled to device.
- **Driver agent** — `driver/driver.lua`, `sequencer/midi_translate.lua`, `sequencer/patch_loader.lua`. Glue layer that runs on both host and device. Owns the clock-div/mult accumulator and the rising/falling-gate edge detector.
- **Utils agent** — `utils.lua` (table/math helpers; host-only — referenced by `sequencer/track.lua` and `sequencer/mathops.lua`, but those code paths are not exercised on device).
- **UI agent** — `sequencer/controls.lua` (VSN1 control surface; bundled separately to `grid/controls.lua` and lazy-loaded on first BUTTON event).
- **Tooling agent** — `tools/build_grid.lua`, `tools/bundle.lua`, `tools/strip.lua`, `tools/charcheck.lua`, `tools/memprofile.lua`. Owns the upload bundle and on-device size budget.
- **Harness agent** — `main.lua`, `grid_module.lua`, `bridge.py` (libuv timer, MIDI clock sync, INIT/TIMER/BUTTON/RTMIDI blocks).

Each agent owns its files and only calls the public functions of other modules.
