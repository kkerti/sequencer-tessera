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
6. **Three layers:** HAL → Core → App. Core never knows a screen exists.
   Core never calls a driver — it returns events. App reads Core's public
   tables and calls Core setters.
7. **Greenfield.** Do not port code from `old-impl/`. If you find yourself
   wanting to, stop and re-derive from first principles.

## Layout

```
src/
  step.lua          packed-int step encode/decode
  track.lua         track state + advance + group edit
  engine.lua        4 tracks, onPulse, onStart, onStop
  driver_stdio.lua  macOS event sink (stdout line protocol)
  driver_grid.lua   Grid event sink (midi.send)
  controls.lua      Grid-only UI: 4x2 screen, buttons, endless
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

## Build

```
lua tools/build_dist.lua          # produces dist/sequencer.lua
```

Minifier strips comments, `assert(...)` calls, renames locals, collapses
whitespace. Aggressive but tested on macOS before upload.

## Test

```
lua tests/run.lua
```

Tests run against the pure Core. The `driver_stdio` harness lets you feed
synthetic clock pulses and assert event sequences.

## When in doubt

Ask. Greenfield means we'd rather pause and confirm than make assumptions
that calcify into the architecture.
