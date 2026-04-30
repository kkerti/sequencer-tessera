# AGENTS.md

Guidance for AI coding agents (and humans) working on this project.

## Project in one sentence

A 4-track step sequencer library written in Lua 5.4, externally clocked,
emitting MIDI events, designed to run on Intech Studio Grid VSN1 hardware
with an extremely small memory footprint.

## Hard rules

1. **`docs/archive/old-impl/` is OUT OF CONTEXT.** Do not read those files.
   The previous implementation does not inform this one.
2. **Memory is the primary design constraint.** Every feature is evaluated
   for allocation cost and per-pulse runtime cost first, musicality second.
3. **No internal clock.** The engine consumes external pulses. It does not
   know BPM.
4. **One voice per track.** The engine is monophonic per track by design.
5. **No patterns, snapshots, scenes, or song mode.** A track is a sequence.
   See "Glossary" below for the regions feature, which is *not* a pattern.
6. **Three layers:** HAL → Core → App. Core never knows a screen exists.
   Core never calls a driver — it returns events. App reads Core's public
   tables and calls Core setters.
7. **Greenfield.** Do not port code from `old-impl/`. If you find yourself
   wanting to, stop and re-derive from first principles.
8. **Zero allocations per pulse.** Locked by `tests/test_no_alloc.lua`.
   Any change to the engine hot path that allocates fails CI. No closures,
   no table literals, no string concatenation inside `onPulse` / `advance`.

## Layout

```
src/
  step.lua          packed-int step encode/decode
  track.lua         track state + advance + group edit
  engine.lua        4 tracks, onPulse, onStart, onStop
  driver_stdio.lua  macOS event sink (stdout line protocol)
  driver_grid.lua   Grid event sink (midi.send)
  controls.lua      Grid-only UI: 4x2 screen, buttons, endless
  controls_en16.lua Optional EN16 module UI: 16 push-encoders + LEDs
patches/            test patterns (human form, packed on load)
tools/
  build_dist.lua    minify + strip → dist/sequencer.lua
  bridge.py         macOS MIDI <-> stdio bridge (clock in + notes out)
tests/              macOS-only unit & integration tests
main.lua            macOS harness
docs/
  archive/
    GRID_CONTROLS.md           Grid control element model
    GRID_HARDWARE_API.md       Grid screen/button/midi API reference
    LIB-2-HW-MAP.md            VSN1 control mapping spec
    old-impl/                  OUT OF CONTEXT
```

## Step packing (Lua 5.4 native int)

| bits  | field       | range      |
|-------|-------------|------------|
| 0–6   | pitch       | 0–127      |
| 7–13  | velocity    | 0–127      |
| 14–20 | duration    | 0–127 pulses |
| 21–27 | gate        | 0–127 pulses |
| 28    | ratchet     | 0/1        |
| 29    | active      | 0/1        |
| 30–36 | probability | 0–127      |

One Lua integer per step. No per-step tables. 64 steps × 4 tracks = 256 ints.

## Engine contract

```lua
local engine = require("engine")
engine.init({ trackCount = 4, stepsPerTrack = 64, log = function(s) end })
engine.onStart()
engine.onStop()
local events = engine.onPulse()  -- returns array of {type, pitch, vel, ch} or nil
```

Events are consumed by a driver. Engine does no IO.

## Group edit

Public Core API:

```lua
track.setStepParam(t, i, param, val)
track.groupEdit(t, from, to, op, param, val)  -- op = "set" | "add" | "rand"
```

UI calls these. No selection state lives in Core.

## Glossary (read this before naming anything)

| Term | Meaning |
|------|---------|
| **step** | One packed-int slot in a track buffer (1..64). |
| **track** | A single 64-step buffer + monophonic voice. Fixed length 64. |
| **region** | A fixed 16-step window of a track. **Exactly 4 per track**, indexed 1..4 (steps 1–16, 17–32, 33–48, 49–64). |
| **active region** | The region all 4 tracks are currently playing. **Global**, single int on the engine. |
| **queued region** | Region selected to switch to at next region boundary. 0 = none queued. |
| ~~pattern~~ | **FORBIDDEN word.** Reserved. Use "region". Pattern implies independent step buffers (Model B), which we explicitly do not have. |
| ~~scene~~  | **FORBIDDEN.** |
| ~~snapshot~~ | **FORBIDDEN.** |
| ~~bank~~   | **RESERVED** for the parked Model-B option. Don't use until that returns. |

## Regions

Regions subdivide a track's existing 64-step buffer into 4 fixed windows of
16 steps. They are **not patterns**: there is no extra step memory. A region
switch just changes which 16-step window the engine plays.

Switching is **global** (all 4 tracks share `activeRegion`) and **at-end-of-region**
(each track finishes its current region, then jumps to the queued region's
first step on its next own-clock advance).

Edge cases:
- Per-track flip is independent — a track on `div=4` finishes its region
  several pulses after a `div=1` track. `activeRegion` only updates after
  *all four* tracks have flipped.
- `DIR_REV` / `DIR_PP`: boundary detection uses region bounds, not just
  `pos == regionEnd`. See `track.lua` for specifics.
- `DIR_RND`: random tracks have no natural boundary. They piggyback —
  flip when `activeRegion` is updated by the last non-random track.

Public API:

```lua
engine.setQueuedRegion(r)  -- 1..4, schedules a global switch
engine.activeRegion        -- read-only int 1..4
engine.queuedRegion        -- read-only int 0..4 (0 = none)
```

## Build

```
lua tools/build_dist.lua          # produces dist/sequencer.lua + dist/sequencer_ui.lua
```

Two bundles for memory-conscious lazy loading on Grid:

- **`dist/sequencer.lua`** (~10 KB) — Core only (`step`, `track`, `engine`).
  Required at module init. Pure-playback paths run with this alone.
- **`dist/sequencer_ui.lua`** (~8 KB) — Controls layer (`controls`,
  `controls_en16`). Lazy-loaded by `VSN1.lua` on first input event or
  first screen draw via `loadUI()`. Boot-failure / pure-playback paths
  never pay this cost.

The UI bundle's internal require-shim falls back to the host `require`
for missing modules, so its `require("engine")` resolves through the
already-loaded Core bundle's flat aliases.

Minifier strips comments, `assert(...)` calls, renames locals, collapses
whitespace. Aggressive but tested on macOS before upload.

### Bundle namespace (IoT-style separation of concerns)

Both bundles return tables that mirror the HAL → Core → App architecture.
Consumers (`VSN1.lua`, `EN16.lua`, tests) should use the namespaced form;
flat aliases exist only for the UI shim's fallback path.

```lua
-- Core bundle (always loaded):
local SEQ = require("sequencer")
SEQ.Core.engine     -- pure engine, no IO
SEQ.Core.track      -- pure track logic
SEQ.Core.step       -- packed-int step codec
SEQ.Controls        -- nil; promoted by VSN1's loadUI()
SEQ.HAL             -- reserved; populated on-device by per-module wiring

-- UI bundle (lazy-loaded):
local UI = require("sequencer_ui")
UI.screen           -- VSN1 screen UI (no hardware calls; takes scr arg)
UI.en16             -- EN16 logic surface (no hardware calls; takes emit fn)
```

Locked by `tests/test_dist_smoke` (3 tests). If you add a new bundled
module, decide which layer AND which bundle it belongs to. Keep the Core
bundle pure — anything that touches a screen, button, or LED goes in UI.

## Test

```
lua tests/run.lua
```

Tests run against the pure Core. The `driver_stdio` harness lets you feed
synthetic clock pulses and assert event sequences.

## When in doubt

Ask. Greenfield means we'd rather pause and confirm than make assumptions
that calcify into the architecture.
