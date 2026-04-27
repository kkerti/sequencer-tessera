# Architecture

Snapshot of the system as of 2026-04-27. This document is the living big-picture reference. `AGENTS.md` remains the agent contract (style, constraints, data model); start there for rules, come here for shape.

---

## One-line shape

A **rich authoring engine** runs on macOS, **compiles songs to flat event arrays**, which a **tiny tape-deck player** walks on the Grid module (ESP32 / Lua 5.4).

```
┌──────────────── macOS (authoring) ────────────────┐    ┌──────── Grid module (playback) ────────┐
│                                                   │    │                                        │
│  songs/<name>.lua          (terse descriptor)     │    │   /player/player.lua                   │
│        │                                          │    │   /<song>/<song>.lua                   │
│        ▼                                          │    │        │                               │
│  sequencer/  (full ER-101 + Metropolis engine)    │    │        ▼                               │
│        │   step / pattern / track / engine        │    │   tape-deck Player                     │
│        │   mathops / scene / probability / swing  │    │   (no engine, no scale, no swing)      │
│        ▼                                          │    │        │                               │
│  tools/song_compile.lua                           │    │        ▼                               │
│        │   walk engine for `bars * beatsPerBar`   │    │   midi_send()  →  MIDI out             │
│        │   → schema v2 event arrays               │    │                                        │
│        ▼                                          │    │   Clock source = either firmware       │
│  compiled/<name>.lua  (single self-contained)     │    │     timer  OR  Ableton MIDI 0xF8       │
│        │                                          │    │                                        │
│        ▼                                          │    │                                        │
│  copy into grid/<song>/<song>.lua                 │────┼──→ upload grid/player/* + grid/<song>/*│
│                                                   │    │                                        │
│  grid/  (final upload bundle, one file per lib)   │    │                                        │
└───────────────────────────────────────────────────┘    └────────────────────────────────────────┘
```

The **boundary** is `tools/song_compile.lua`. Everything left of it is rich and runs only at authoring time. Everything right of it is dumb and small.

---

## Why this split

The Grid module is an ESP32 with tight memory. A full multi-track sequencer engine running per-pulse — with scale quantization, swing, ratchet expansion, direction logic, probability rolls — does not fit comfortably and is not necessary.

**Insight:** for a fixed-length song, every NOTE_ON / NOTE_OFF time can be precomputed once, in order, then replayed. The only per-loop randomness we care about is per-step probability, which is cheap to re-roll in place against a sidecar `srcStepProb[]` array.

Result:
- Authoring: complex but constraint-free (macOS, Lua 5.5, all rocks available).
- Playback: ~180 lines of Lua, walks five parallel arrays, no allocations per pulse.

> **Note on file sizes.** The Grid filesystem used to enforce an 880-char per-file limit, which required a separate splitter tool and per-array sidecar files. That limit no longer applies — files of any size upload and load on device. The compiled song is now a single self-contained file. Memory footprint still matters, so we keep arrays compact (`intList(arr)` produces no whitespace), but file count and per-file size are no longer a concern.

---

## Authoring engine (`sequencer/`)

The full ER-101 + Metropolis-inspired engine. Lives in `sequencer/`; runs only on macOS during authoring/testing. Responsibilities:

| Module | Role |
|---|---|
| `step.lua`        | Step record (pitch, velocity, duration, gate, ratchet, probability, active). `Step.resolvePitch(step, scaleTable, rootNote)` for live quantization. |
| `pattern.lua`     | Named contiguous slice of a track's step list. Pure organisational layer. |
| `track.lua`       | Per-track state: patterns, loop points, clock div/mult, direction mode (forward / reverse / pingpong / random / Brownian). `Track.advance` returns the next step. |
| `engine.lua`      | Top-level: BPM, swing %, scale, root note, multi-track tick. `Engine.tick(eng, emit)` produces NOTE_ON/NOTE_OFF events for one pulse. |
| `performance.lua` | Swing pulse-delay helper (global percentage, Metropolis-style). |
| `mathops.lua`     | Transpose / jitter / random on step parameters (one step, one pattern, or one track). |
| `scene.lua`       | Scene chain — automated loop-point sequencing (per-track scene queue). |
| `probability.lua` | Per-step probability evaluation (non-destructive, Blackbox-style). |
| `snapshot.lua`    | Serialize/deserialize full engine state via `io`. macOS-only path; on-device persistence is out of scope for now. |
| `song_writer.lua` | **Bridges to the tape-deck player.** `SongWriter.rollNextLoop(song, loopIndex)` mutates a compiled song in place at every loop boundary, flipping `kind[]` between active and muted to apply per-step probability. Static songs (no probability) skip this entirely and never ship the writer arrays. |

Tests live in `tests/` and cover behaviour. Module files contain only `assert()` input-validation guards.

---

## Compiled song schema (v2)

Produced by `tools/song_compile.lua` from a song descriptor. The descriptor is a pure-data Lua table (see `songs/dark_groove.lua`); the compiler instantiates the engine, walks it for `bars * beatsPerBar` beats, captures every emitted event, and flattens to:

```
song = {
    bpm,                   -- declared BPM (used by internal-clock player)
    pulsesPerBeat,         -- usually 4; must divide 24 evenly for MIDI clock sync
    durationPulses,        -- total pulses in one loop
    loop,                  -- boolean
    eventCount,            -- N

    -- five parallel arrays of length N, sorted by (atPulse asc, kind asc):
    atPulse[],             -- pulse index (1-based) when this event fires
    kind[],                -- 1=NOTE_ON, 0=NOTE_OFF, 2=muted ON, 3=muted OFF
    pitch[],               -- MIDI note (already scale-quantized at compile time)
    velocity[],            -- 0–127
    channel[],             -- 1-based MIDI channel

    -- writer-only sidecars, present iff hasProbability == true:
    hasProbability,        -- boolean
    pairOff[],             -- index of paired NOTE_OFF for each NOTE_ON (else 0)
    srcStepProb[],         -- 0–100, source step probability for each NOTE_ON
    srcVelocity[],         -- baseline velocity (reserved for future jitter)

    -- optional hook, set by host after compile:
    onLoopBoundary = function(song, loopIndex) end
}
```

Key properties:
- **Interleaved & sorted.** A single cursor walks the arrays linearly per pulse — no separate ON/OFF queues, no priority heap.
- **Scale and swing are baked in.** `pitch[]` is already the post-scale MIDI note; `atPulse[]` already includes swing delay. The player has zero knowledge of either.
- **Static songs cost nothing per loop.** Without `hasProbability`, the writer arrays don't ship and `onLoopBoundary` is `nil`.
- **Single self-contained file.** All five player arrays (and the optional three writer arrays) inline into one Lua module. `dark_groove` compiles to ~2.3 KB.

---

## Tape-deck player (`player/player.lua`)

~180 lines, single file. Public API:

```
Player.new(song, clockFn?, bpm?)   -- clockFn nil → external-clock mode
Player.start(p)                    -- rewinds to pulse 0
Player.stop(p)
Player.setBpm(p, bpm)              -- internal-clock mode only
Player.tick(p, emit)               -- internal clock: pulled by firmware timer
Player.externalPulse(p, emit)      -- external clock: one MIDI 0xF8 (after 24→ppb division)
Player.allNotesOff(p, emit)        -- emergency drain on stop/panic
```

`p.pulseCount` is the source of truth. `Player.tick` is a thin shim that derives a target pulse from `clockFn()` and calls `externalPulse` until caught up. Both modes share the same advance loop.

Loop wrap:
1. `cursor` past `eventCount` AND `pulseCount >= durationPulses`.
2. Subtract `durationPulses` from `pulseCount`, reset `cursor` to 1.
3. Bump `loopIndex`.
4. Call `song.onLoopBoundary(song, loopIndex)` if set.

---

## Two clock sources

### 1. Internal (firmware timer)

Default. The Grid timer fires every `SEQ_INTERVAL` ms (≈ half the pulse interval). Each tick:
- bumps a software ms counter `SEQ_CLOCK_MS`,
- calls `Player.tick(SEQ_PLAYER, SEQ_EMIT)`.

`SEQ_INTERVAL` is set to `floor(pulseMs / 2)` — fine enough to resolve the smallest gate without overspending CPU.

### 2. External MIDI clock (Ableton-driven, working on hardware)

The element's `rtmrx_cb` translates incoming MIDI bytes:

| Byte  | Meaning           | Action |
|-------|-------------------|--------|
| 0xF8  | Timing clock      | count down `24 / ppb` per player pulse, then `externalPulse` |
| 0xFA  | Start             | `Player.start` (rewind to 0) |
| 0xFB  | Continue          | resume from current pulse |
| 0xFC  | Stop              | `Player.stop` + `allNotesOff` |

`song.pulsesPerBeat` must divide 24 evenly (1, 2, 3, 4, 6, 8, 12, 24). All current songs use ppb=4 → 6 MIDI clocks per player pulse.

**Never run both clocks at once** — the player will double-advance. Either start the timer OR enable the rtmidi callback, not both.

---

## Build pipeline & deployment

### Tools

| Tool | Role |
|---|---|
| `tools/song_compile.lua` | Walk engine, flatten to schema v2, emit a single self-contained `compiled/<name>.lua`. |
| `tools/strip.lua`        | Remove comments and statement-form `assert(...)` guards from any Lua module. Preserves value-returning asserts (`local f = assert(io.open(p))`) and overall formatting. Halves the player's footprint. |
| `tools/charcheck.lua`    | Reports raw and minified character counts (no thresholds; used for memory-footprint estimation). |
| `tools/memprofile.lua`   | Quantify on-device memory footprint (run on dev to estimate). |

### Grid require quirk

Grid firmware's `require()` does **not** do `package.path` `?` substitution. The module name is treated as a literal file path. Therefore:

```lua
require("/player/player")            -- works
require("/dark_groove/dark_groove")  -- works
require("player")                    -- fails
```

Hard-code the literal paths in your INIT block (see `grid_module.lua`).

### Folder-per-library on device

Grid uploads/removes whole folders at a time, so each library lives under its own:

```
/player/         ← grid/player/player.lua
/dark_groove/    ← grid/dark_groove/dark_groove.lua
```

One file per folder, but the folder boundary makes upload/remove operations atomic per library.

### Build commands

```sh
rm -rf grid
mkdir -p grid/player grid/dark_groove
lua tools/strip.lua player/player.lua --out grid/player/player.lua
lua tools/song_compile.lua songs/dark_groove.lua --outdir grid/dark_groove
```

`tools/strip.lua` removes comments and statement-form `assert(...)` guards. Asserts are an authoring-time test-coverage tool; they are dead weight on device, since every code path that reaches the player has already passed the same checks during macOS dev. Stripping cuts the player from ~6 KB to ~3 KB. Apply it to any sequencer module before upload — the engine itself benefits more (52% reduction across `sequencer/`).

For macOS dev (uses `compiled/<name>.lua` directly, asserts retained):

```sh
lua tools/song_compile.lua songs/dark_groove.lua
lua main_lite.lua | python3 bridge.py
```

### Element wiring

`grid_module.lua` is the canonical source for INIT / TIMER / rtmidi-callback blocks. Copy-paste sections; do not edit them on-device by hand.

---

## Two macOS harnesses

| Harness | Use case |
|---|---|
| `main.lua`      | Live edit. Build a song descriptor inline, compile in memory via `tools/song_compile.lua`, run through luv timer + lite player + bridge. Tweak, save, re-run. |
| `main_lite.lua` | Ship-ready mirror. Loads precompiled `compiled/<name>.lua` exactly as the device would, no compiler dependency at runtime. Use this to validate the upload bundle. |

Both pipe their MIDI line-protocol output to `bridge.py`, which opens a virtual port named `"Sequencer"` for Ableton.

---

## File layout (current)

```
main.lua                       -- live-edit harness: descriptor → compile → lite player + luv
main_lite.lua                  -- ship-mirror harness: precompiled song + lite player + luv
bridge.py                      -- Python MIDI bridge: stdin → virtual port "Sequencer"
grid_module.lua                -- INIT / TIMER / rtmidi-callback copy-paste blocks
utils.lua                      -- shared helpers: tableNew, tableCopy, clamp, scale tables
tui.lua                        -- terminal renderer for engine state snapshots

sequencer/                     -- AUTHORING ENGINE (macOS only)
  step.lua
  pattern.lua
  track.lua
  engine.lua
  performance.lua              -- swing pulse-delay helper
  mathops.lua                  -- transpose/jitter/random ops
  scene.lua                    -- automated loop-point sequencing
  probability.lua              -- per-step probability eval
  snapshot.lua                 -- engine state save/load
  song_writer.lua              -- bridge to player: rollNextLoop on loop boundary

player/                        -- TAPE-DECK PLAYER (runs on Grid)
  player.lua                   -- ~180 lines, walks compiled event arrays

songs/                         -- terse song descriptors (authoring inputs)
  dark_groove.lua

compiled/                      -- output of tools/song_compile.lua (single self-contained file)
  dark_groove.lua

grid/                          -- final upload bundle (one file per library, in its own folder)
  player/player.lua            -- → /player/player.lua  on device
  dark_groove/dark_groove.lua  -- → /dark_groove/dark_groove.lua on device

tools/
  song_compile.lua             -- engine → compiled song + inlined arrays
  strip.lua                    -- comment + statement-assert remover for shipping
  charcheck.lua                -- raw + minified char count reporter
  memprofile.lua               -- memory footprint estimator

tests/                         -- behavioural tests
  utils.lua  step.lua  pattern.lua  track.lua  engine.lua
  performance.lua  mathops.lua  snapshot.lua  scene.lua
  probability.lua  song_writer.lua  player.lua  tui.lua
  sequence_runner.lua          -- runs scenarios in tests/sequences/
  sequences/                   -- 11 end-to-end feature scenarios

docs/
  ARCHITECTURE.md              -- this file
  2026-03-09-init-goal.md      -- original goal + ER-101/Metropolis decisions
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

On device the player calls `midi_send(channel, status, note, velocity)` directly.

---

## Status (2026-04-27)

- **Working on hardware.** Ableton-driven MIDI clock playback verified on the Grid module.
- **All tests pass:** 13 behavioural test files + 11 sequence scenarios.
- **Bundle is two files.** `grid/player/player.lua` (~6 KB raw / ~2 KB minified) plus `grid/dark_groove/dark_groove.lua` (~2.3 KB).
- **Two clock modes shipped:** internal firmware timer and external MIDI 0xF8.

### Known gaps

- `Engine.reset` and a hardware "panic" button are scaffolded in `grid_module.lua` as comments; not yet wired to physical Grid buttons.
- No multi-song selector yet — current setup hard-codes `dark_groove`. Folder-per-library is ready for it.

### Likely next areas

- On-device button controls (start/stop/BPM knob/song select).
- Multi-song workflow + button-bank switching.
- Compile-time scale/transpose baking variants for performance presets.
- Identifier-shortening minifier pass for headroom on large songs.
