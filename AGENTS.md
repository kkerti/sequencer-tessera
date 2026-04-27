# AGENTS.md

## Project

Lua 5.5 step sequencer library targeting the **Grid modular controller platform** (ESP32 + luaVM, which runs Lua 5.4). Development and validation happen on macOS first, then code runs unmodified on device.

Reference designs: `docs/manuals/er-101.md`, `docs/manuals/metropolis.md`. Goal document: `docs/2026-03-09-init-goal.md`. **Big-picture system map: `docs/ARCHITECTURE.md`** — read it before starting non-trivial work; it describes the authoring-engine vs. tape-deck-player split, the compiled song schema, and the build/upload pipeline.

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
- Ratchet in the ER-101 is binary on/off; the repeat count is implied by `gate / duration` ratio — **we will not follow this**; see Metropolis below.

### Metropolis — feature design (selective adoption)

The Metropolis's strength is **playability**: its hardware interface (faders, switches, per-stage controls) makes it immediately expressive. Its sequencer architecture (fixed 8 stages, single track, no loop points) is not a good fit for our engine. However, several specific feature designs from the Metropolis are cleaner than the ER-101 equivalents and will be adopted:

| Feature | Metropolis design | Why adopt it over ER-101 |
|---|---|---|
| **Ratchet count** | Explicit integer 1–4 per step | More musical and directly controllable than ER-101's implied binary count |
| **Direction modes** | Forward, Reverse, Ping-Pong, Brownian, Random | ER-101 is forward-only; direction modes are valuable for Grid performance |
| **Live scale quantizer** | 30 built-in scales, applied in real time | We output MIDI (not CV); a live `pitch → scale degree` mapper is more practical than pre-baked voltage tables |
| **Swing** | Global percentage (50–72%), delays odd-numbered pulses | Cleaner than ER-101's manual boundary-transfer approach |

Features **not** adopted from the Metropolis: its "pattern = complete saved sequence" concept, global-only clock division, fixed 8-stage limit, AUX CV modulation inputs (no equivalent on Grid), and hardware-slider pitch editing.

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
- Run the live-edit stack (descriptor → in-memory compile → lite player): `lua main.lua | python3 bridge.py`
- Run the ship-mirror stack (precompiled song + lite player): `lua main_lite.lua | python3 bridge.py`
- Compile a song to `compiled/`: `lua tools/song_compile.lua songs/<name>.lua`
- Build the Grid upload bundle: see README.md `Build the Grid upload bundle`. Includes `/player/`, `/utils/`, `/sequencer_lite/`, `/live/` and per-song folders.
- Run tests: `lua tests/utils.lua && lua tests/step.lua && lua tests/pattern.lua && lua tests/track.lua && lua tests/engine.lua && lua tests/performance.lua && lua tests/mathops.lua && lua tests/snapshot.lua && lua tests/scene.lua && lua tests/tui.lua && lua tests/probability.lua && lua tests/song_writer.lua && lua tests/player.lua && lua tests/sequencer_lite.lua && lua tests/live_edit.lua`
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
- Prefer expanded readable code over shorthands (author background: JS/TS/NestJS)
- Keep functions short and isolated; split into new files when a file grows large
- Utility/helper functions (table ops, math, scale helpers) **must live in `utils.lua`** — not inlined in sequencer modules

## Testing

- Tests live in `tests/` as separate files: `tests/utils.lua`, `tests/step.lua`, `tests/pattern.lua`, `tests/track.lua`, `tests/engine.lua`, `tests/performance.lua`, `tests/mathops.lua`, `tests/snapshot.lua`, `tests/scene.lua`, `tests/probability.lua`, `tests/song_writer.lua`, `tests/player.lua`, `tests/tui.lua`
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
- `ratchet`  — repeat count per step (1–4, Metropolis-style)
- `probability` — chance this step fires (0–100, 100 = always; Blackbox-style, non-destructive)
- `active`   — boolean mute without deleting the step

**Pitch is stored as direct MIDI note number and can be quantized live at engine output time.** `Step.resolvePitch(step, scaleTable, rootNote)` is the hook used by the engine.

## Key engine behaviours — implementation status

| Feature | Status |
|---|---|
| Single track, flat step list, loop | Done |
| NOTE_ON / NOTE_OFF events from engine tick | Done |
| BPM → pulse interval conversion | Done |
| Per-track clock division / multiplication | Done |
| Loop points (loopStart / loopEnd) | Done |
| Patterns (sub-grouping of steps into named slices) | Done |
| Ratcheting (explicit count 1–4, Metropolis-style) | Done |
| Direction modes (forward/reverse/ping-pong/random/Brownian) | Done |
| Live scale quantizer (Metropolis-style, 30 scales) | Done |
| Swing (global percentage, Metropolis-style) | Done |
| Math operations (add/jitter/random on params) | Done |
| Snapshots (serialize full state via `io`) | Done |
| Scene chain (automated loop-point sequencing) | Done |
| Pattern copy/paste/duplicate/delete/insert/swap | Done |
| Per-step probability (non-destructive, Blackbox-style) | Done |

## File layout

See `docs/ARCHITECTURE.md` for the full system map and rationale. Quick reference:

```
main.lua                       -- live-edit harness: descriptor → in-memory compile → lite player + luv
main_lite.lua                  -- ship-mirror harness: precompiled song + lite player + luv
bridge.py                      -- Python MIDI bridge: stdin → virtual port "Sequencer"
grid_module.lua                -- copy-paste INIT / TIMER / rtmidi-callback blocks for the Grid module
utils.lua                      -- shared helpers: tableNew, tableCopy, clamp, scale tables
tui.lua                        -- terminal renderer for engine state snapshots

sequencer/                     -- AUTHORING ENGINE (macOS only)
  step.lua                     -- Step.new, getters/setters, Step.isPlayable, Step.resolvePitch
  pattern.lua                  -- Pattern.new, named contiguous slices of a track's step list
  track.lua                    -- Track.new, Track.advance, direction/loop/clock controls
  engine.lua                   -- Engine.new, Engine.tick, BPM/swing/scale, Engine.reset
  performance.lua              -- swing pulse-delay helper for playback timing
  mathops.lua                  -- transpose/jitter/random operations on step params
  snapshot.lua                 -- save/load full engine state via io
  scene.lua                    -- Scene chain: automated loop-point sequencing
  probability.lua              -- non-destructive per-step probability evaluation
  song_writer.lua              -- bridge to player: rollNextLoop on loop boundary

sequencer_lite/                -- ON-DEVICE AUTHORING ENGINE (carve of sequencer/)
  step.lua / pattern.lua       -- byte-equivalent to sequencer/
  track.lua                    -- pattern-manipulation ops removed
  engine.lua                   -- scene-chain hooks removed
  -- See docs/dropped-features.md.

live/                          -- ON-DEVICE LIVE EDITOR (operates on compiled songs)
  edit.lua                     -- O(1) pitch/velocity/mute; queued ratchet splice on loop boundary

player/                        -- TAPE-DECK PLAYER (runs on Grid; ~180 lines)
  player.lua                   -- walks compiled event arrays; internal + external (MIDI 0xF8) clock modes

songs/                         -- terse song descriptors (authoring inputs, pure-data tables)
  dark_groove.lua

compiled/                      -- output of tools/song_compile.lua (single self-contained file)
  <name>.lua

grid/                          -- final upload bundle (FLAT — one file per library at root)
  player.lua                   -- → /player.lua            on device
  utils.lua                    -- → /utils.lua             on device
  sequencer_lite.lua           -- → /sequencer_lite.lua    on device (optional; bundled by tools/bundle.lua)
  edit.lua                     -- → /edit.lua              on device (optional)
  <song>.lua                   -- → /<song>.lua            on device

tools/
  song_compile.lua             -- engine → compiled song (schema v2), single inlined file
  bundle.lua                   -- splice N modules into one file; rewrites cross-module require()
  strip.lua                    -- comment + statement-assert remover
  charcheck.lua                -- raw + minified char count reporter
  memprofile.lua               -- on-device memory footprint estimator

tests/
  utils.lua  step.lua  pattern.lua  track.lua  engine.lua
  performance.lua  mathops.lua  snapshot.lua  scene.lua
  probability.lua  song_writer.lua  player.lua  tui.lua
  sequencer_lite.lua           -- smoke test for the lite engine carve
  live_edit.lua                -- behavioural tests for live/edit.lua
  sequence_runner.lua          -- runs scenarios in tests/sequences/
  sequences/                   -- end-to-end feature scenarios

docs/
  ARCHITECTURE.md              -- full system map: pipeline, schema v2, deployment, clock modes
  dropped-features.md          -- what sequencer_lite/ leaves out and how to revive it
  2026-03-09-init-goal.md      -- project goal and architecture decisions
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

Recommended split when parallelising work. Note the authoring-engine vs. tape-deck-player boundary (see `docs/ARCHITECTURE.md`):

- **Engine agent** — `sequencer/engine.lua`, `sequencer/track.lua` (clock, patterns, loop points). Authoring side.
- **Step agent** — `sequencer/step.lua`, `sequencer/pattern.lua` (ratchet, scale quantizer, pattern ops). Authoring side.
- **Utils agent** — `utils.lua` (scale tables, math helpers).
- **Player/writer agent** — `player/player.lua`, `sequencer/song_writer.lua` (tape-deck playback + per-loop probability re-roll). Strict size budget; the player runs on device.
- **Tooling agent** — `tools/song_compile.lua` (compile pipeline; schema v2 owner).
- **Harness agent** — `main.lua`, `main_lite.lua`, `grid_module.lua`, `bridge.py` (timer tuning, MIDI clock sync, INIT/TIMER blocks).

Each agent owns its files and only calls the public functions of other modules.
