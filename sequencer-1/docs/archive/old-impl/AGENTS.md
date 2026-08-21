# AGENTS.md

## Project

Lua 5.5 step sequencer library targeting the **Grid modular controller platform** (ESP32 + luaVM, which runs Lua 5.4). Development and validation happen on macOS first, then code runs unmodified on device.

Reference designs: `docs/manuals/er-101.md`, `docs/manuals/metropolis.md`. Goal document: `docs/2026-03-09-init-goal.md`. **Big-picture system map: `docs/ARCHITECTURE.md`** — read it before non-trivial work; it describes the engine-on-device CV+gate model, the Driver layer, the patch loader, and the trivial copy-only build pipeline.

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

The Metropolis's strength is **playability**: its hardware interface (faders, switches, per-stage controls) makes it immediately expressive. Its sequencer architecture (fixed 8 stages, single track, no loop points) is not a good fit for our engine. One specific feature design is cleaner than the ER-101 equivalent and is adopted:

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
- The Grid filesystem accepts arbitrarily large Lua files. There is no per-file size limit and no per-event paste-budget concern. Source code does **not** need to be bundled, stripped, or minified for deployment.

## Dev environment (macOS)

- System Lua is **5.5** (`lua --version`); keep that in mind when installing rocks
- Package manager: **LuaRocks** (rocks installed under Lua 5.5 path)
- Timer/event loop in dev: `luv` (already installed)
- **`lua-rtmidi` does not build on this machine** (Lua 5.5 ABI mismatch) — use the Python bridge instead
- MIDI bridge: `python3 bridge.py` — reads the line protocol from stdin, opens a virtual port named `"Sequencer"`
- Run on macOS: `lua main.lua patches/<name> | python3 bridge.py` (patch arg is required; e.g. `patches/dark_groove`)
- Build the Grid upload bundle: `lua tools/build_grid.lua` (five-cp script). See `docs/ARCHITECTURE.md` for details.
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
- Module tables use **dot-notation**: `Step.new`, `Track.advance`, `Engine.tick`. Within `sequencer.lua` these are local table values returned together as a single `{ Step = ..., Track = ..., ... }` table.
- Prefer expanded readable code over shorthands. There is no per-file size budget and no paste-budget zone any more — write for a future human (or LLM) reading the source. If you find yourself wanting to abbreviate, delete the feature instead.

## Code shape

- One library file: `sequencer.lua`. Host harness, tests, and device all `require("sequencer")` and pull classes off the returned table (`Seq.Step`, `Seq.Driver`, etc.).
- One UI file: `controls.lua` (separate so the device can lazy-load it).
- Host-only authoring: `mathops.lua`, `snapshot.lua`, `probability.lua`, `tui.lua` — each `require("sequencer")` for the classes they need.
- Patches are pure-data Lua tables under `patches/`, copied verbatim to `grid/`.
- Build is `tools/build_grid.lua` — five `cp`s. There is no bundler, stripper, or minifier.

If you grow `sequencer.lua` with a substantial new module that has a well-defined public boundary (think: an effects processor, a MIDI input handler, a quantizer), it can move out into its own file at the project root. Don't pre-emptively split — keep it inline until the boundary justifies a file.

## Testing

- Tests live in `tests/` as separate files: `tests/utils.lua`, `tests/step.lua`, `tests/pattern.lua`, `tests/track.lua`, `tests/engine.lua`, `tests/mathops.lua`, `tests/snapshot.lua`, `tests/scene.lua`, `tests/probability.lua`, `tests/midi_translate.lua`, `tests/patch_loader.lua`, `tests/driver.lua`, `tests/grid_bundle_smoke.lua`, `tests/tui.lua`, `tests/controls.lua`.
- Feature scenario files live in `tests/sequences/` and are executed via `tests/sequence_runner.lua`.
- Run a test file directly: `lua tests/track.lua` — asserts fire and print `OK` on success.
- The library file (`sequencer.lua`) contains **input validation `assert()` guards only** (wrong type, out-of-range) — no behavioural tests in it.
- Behavioural tests (sequencing, event order, boundary conditions) belong in `tests/`.

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

Step is stored as a packed Lua integer (37 bits used). Setters return a new integer; always rebind. The bit layout is documented in the comment block above `local Step = {}` in `sequencer.lua`.

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
| Swing (global percentage, Metropolis-style) | Removed (downstream concern) |
| Math operations (add/jitter/random on params) | Done (host-only, `mathops.lua`) |
| Snapshots (serialize full state via `io`) | Done (host-only, `snapshot.lua`) |
| Scene chain (automated loop-point sequencing) | Done |
| Pattern copy/paste/duplicate/delete/insert/swap | Done |
| Per-step probability (non-destructive, Blackbox-style) | Done |

## Bridge line protocol

```
NOTE_ON  <pitch> <velocity> <channel>   -- channel is 1-based
NOTE_OFF <pitch> <channel>
```

## Session memory

- After each significant session, write a note to `docs/YYYY-MM-DD-<short-topic>.md`
- Keep it minimal and concise — decisions made, current state, next steps.
- `docs/archive/` holds pre-collapse session notes; do not add to it.
