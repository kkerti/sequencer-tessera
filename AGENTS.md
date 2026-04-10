# AGENTS.md

## Project

Lua 5.5 step sequencer library targeting the **Grid modular controller platform** (ESP32 + luaVM, which runs Lua 5.4). Development and validation happen on macOS first, then code runs unmodified on device.

Reference designs for features: `docs/manuals/er-101.md` (primary), `docs/manuals/metropolis.md`. Goal document: `docs/2026-03-09-init-goal.md`.

---

## Runtime constraints

- Target device is **Lua 5.4 only** — no standard helper functions exist on-device, plain Lua tables and the standard library only
- No `require` of third-party rocks on device; those are macOS dev tools only
- Single-threaded; **one timer** drives the entire sequencer tick — do not create multiple timers
- `io` is available on device for snapshot file reads/writes
- VSN1 screen is 320×240px LCD; simultaneous high-frequency updates cause buffering lag — batch screen redraws

## Dev environment (macOS)

- System Lua is **5.5** (`lua --version`); keep that in mind when installing rocks
- Package manager: **LuaRocks** (rocks installed under Lua 5.5 path)
- Timer/event loop in dev: `luv` (already installed)
- **`lua-rtmidi` does not build on this machine** (Lua 5.5 ABI mismatch) — use the Python bridge instead
- MIDI bridge: `python3 bridge.py` — reads the line protocol from stdin, opens a virtual port named `"Sequencer"`
- Run the full stack: `lua main.lua | python3 bridge.py`
- Run engine/module tests only (no MIDI, no timer): `lua sequencer/engine.lua`
- `python-rtmidi` installed system-wide via `pip3 install python-rtmidi --break-system-packages`

## Ableton setup

In Ableton: Preferences → MIDI → enable **"Sequencer"** as a MIDI input source. The virtual port appears only while `bridge.py` is running.

---

## Naming and style

- **`hungarianNotationForFunctions()`** for all functions and variables — camelCase starting lowercase
  - Correct: `stepGetGate`, `trackClockDiv`, `engineSetBpm`
  - Wrong: `get_gate`, `GetGate`, `step_get_gate`
- Prefer expanded readable code over shorthands (author background: JS/TS/NestJS)
- Keep functions short and isolated; split into new files when a file grows large
- Utility/helper functions (table ops, math, scale helpers) **must live in `utils.lua`** — not inlined in sequencer modules

## Testing

- No test framework — use inline `assert()` calls at the bottom of each module
- Tests run automatically when the file is loaded with `lua <file>` directly
- They do not run when the file is `require()`d (returns the module table before reaching the asserts — this is intentional)

---

## Data model (from ER-101 reference design)

The hierarchy is: **Snapshot → Track → Pattern → Step**

Current implementation covers Track and Step only (patterns and snapshots are next).

| Level    | Max count                        | Notes |
|----------|----------------------------------|-------|
| Snapshot | 16                               | Full state save; saving blocks ~0.75s — never save mid-performance |
| Track    | 4 per snapshot                   | Independent clock div/mult and loop points per track |
| Pattern  | 100 per track                    | Logical grouping of steps (like bars); not yet implemented |
| Step     | 2000 total across all tracks     | |

**Step parameters** — pitch/velocity are MIDI (0–127); duration/gate are clock pulses (0–99):
- `pitch`    — MIDI note number; 0 = rest when gate is also 0
- `velocity` — MIDI velocity
- `duration` — step length in clock pulses (0 = skip this step)
- `gate`     — note-on length in clock pulses (0 = rest; `gate >= duration` = legato)
- `active`   — boolean mute without deleting the step

**Pitch is a direct MIDI note number for now.** The voltage-table / scale-index model from the ER-101 is the long-term target; `stepResolvePitch(step, scaleTable)` is the planned hook point — currently it just returns `step.pitch`.

## Key engine behaviours — implementation status

| Feature | Status |
|---|---|
| Single track, flat step list, loop | Done |
| NOTE_ON / NOTE_OFF events from engine tick | Done |
| BPM → pulse interval conversion | Done |
| Per-track clock division / multiplication | Not yet |
| Loop points (loopStart / loopEnd) | Not yet |
| Patterns (sub-grouping of steps) | Not yet |
| Ratcheting (note repeat within step) | Not yet |
| Smoothing (CV glide) | Not yet |
| Swing (boundary-shift between adjacent steps) | Not yet |
| Math operations (add/jitter/random on params) | Not yet |
| Snapshots (serialize full state via `io`) | Not yet |

## File layout

```
main.lua                  -- dev harness: luv timer + line-protocol MIDI emit
bridge.py                 -- Python MIDI bridge: stdin → virtual port "Sequencer"
utils.lua                 -- shared helpers: tableNew, tableCopy, clamp
sequencer/
  step.lua                -- stepNew, getters/setters, stepIsPlayable
  track.lua               -- trackNew, trackAdvance, trackGetCurrentStep, trackReset
  engine.lua              -- engineNew, engineTick, engineSetBpm, engineReset
docs/
  2026-03-09-init-goal.md -- project goal and architecture decisions
  manuals/er-101.md       -- ER-101 feature reference (primary design input)
  manuals/metropolis.md   -- Metropolis reference (empty, PDF not yet converted)
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

Recommended split when parallelising work:

- **Engine agent** — `sequencer/engine.lua`, `sequencer/track.lua` (clock, patterns, loop points)
- **Step agent** — `sequencer/step.lua` (ratchet, smooth, scale table lookup)
- **Utils agent** — `utils.lua` (scale tables, math helpers)
- **Harness agent** — `main.lua`, `bridge.py` (timer tuning, multi-track emit)

Each agent owns its files and only calls the public functions of other modules.
