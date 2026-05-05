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
   Polyrhythm comes from per-track `lastStep` + per-step `dur`, not from
   parallel buffers.
6. **Three layers:** HAL → Core → App. Core never knows a screen exists.
   Core never calls a driver — it returns events. App reads Core's public
   tables and calls Core setters.
7. **Greenfield.** Do not port code from `old-impl/`. If you find yourself
   wanting to, stop and re-derive from first principles.
8. **Zero allocations per pulse.** Locked by `tests/test_no_alloc.lua`.
   Any change to the engine hot path that allocates fails CI. No closures,
   no table literals, no string concatenation inside `onPulse` / `advance`.

## Design pillars

1. **Single-track focus, multi-track awareness.** Editing happens on one
   selected track at a time. The screen always tells you what the other
   three are doing where it can (region playhead, lastStep drift, etc.).
2. **Polyrhythm is a feature, not an accident.** Per-track `lastStep`
   and per-step `dur` differences are first-class and visible.
3. **Every parameter the engine supports has a control surface.** If we
   can't edit it, we cut it. (Probability was cut for exactly this reason.)
4. **Color as identity.** Each editable parameter has one RGB color
   defined in `controls.MODES`. That color follows the user across
   modules: VSN1 header word, VSN1 active param row, EN16 turn-layer LED.
5. **EN16 is the keyboard; VSN1 is the monitor.** Fast per-step edits
   on EN16 (encoders 1..16 = current viewport's 16 steps of selected
   track). Deep info on VSN1.

## Grid screen draw model (VSN1)

`scr:draw_swap()` is **smart**: the device only re-blits regions that
were actually touched by `draw_*` calls since the previous swap. A full
clear-then-draw pays for the whole screen; a single `draw_rectangle_filled`
+ `draw_swap` pays only for that rectangle's area.

Implication for future optimisation: the strip-cell repaint can be made
surgical by tracking last-drawn value per cell and only re-issuing the
two `draw_*` calls (well + bar) for cells whose value changed. We
currently full-redraw on any `dirty` flag because input volume is low
and CPU headroom is large; revisit if/when the redraw cost shows up in
profiling.

Do not assume `draw_swap` blits the entire framebuffer.

## Layout

```
src/
  step.lua          packed-int step encode/decode
  track.lua         track state + advance
  engine.lua        4 tracks, onPulse, onStart, onStop
  driver_stdio.lua  macOS event sink (stdout line protocol)
  driver_grid.lua   Grid event sink (midi.send)
  controls.lua      VSN1 UI: 7-mode EDIT screen + LASTSTEP screen
  controls_en16.lua EN16 module UI: 16 push-encoders + RGB LEDs (2 layers)
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
| 29    | mute        | 0/1        |
| 30–36 | (free)      | reserved   |

One Lua integer per step. No per-step tables. 64 steps × 4 tracks = 256 ints.

`Step.noteName(p)` returns the MIDI note name as `"C4"`, `"G#5"` etc.
60 = C4 (Yamaha/Ableton convention). Sharps only. Range C-1..G9.

## Timing model (ER-101 style)

Per-step **duration** and **gate** are independent pulse counts:

- **`dur`** = how many external pulses the step *occupies*. The next step
  fires `dur` pulses after this one started. `dur=1` is the legacy
  every-pulse advance; `dur=4` makes the step a quarter-note when the
  external clock runs at 16 ppqn.
- **`gate`** = how many of those pulses the note is *held*. Capped at
  `dur` at fire time. `gate==dur` is a sustained step (legato candidate);
  `gate < dur` leaves silence at the tail.

There is no per-track clock divider — set `dur` per step instead. The
engine has no BPM concept; pulses arrive externally.

**Legato**: when entering a step whose pitch matches the still-sustaining
prior step (`actPitch == p`) AND `gate >= stepLen`, the engine extends
`actOff` instead of emitting OFF+ON. One MIDI message per legato join.

## Per-track lastStep (polyrhythm)

Each track has its own `lastStep` (default 16, range 1..64). The track
plays steps `1..lastStep` then wraps. Polyrhythm = different `lastStep`
across tracks (e.g. 16/12/14/15) — no parallel buffers, no extra memory.

```lua
engine.setLastStep(t, n)   -- 1..64; clamped
engine.tracks[t].lastStep  -- read-only int
```

## Engine contract

```lua
local engine = require("engine")
engine.init({ trackCount = 4, stepsPerTrack = 64, log = function(s) end })
engine.onStart()
engine.onStop()
local events = engine.onPulse()  -- array of {type, pitch, vel, ch} or nil

engine.setStepParam(t, i, name, val)   -- name ∈ pitch/vel/dur/gate/ratch/mute
engine.setLastStep(t, n)
engine.setTrackChan(t, ch)
```

Events are consumed by a driver. Engine does no IO.

## Glossary (read this before naming anything)

| Term | Meaning |
|------|---------|
| **step** | One packed-int slot in a track buffer (1..64). |
| **track** | A single 64-step buffer + monophonic voice. Fixed length 64. |
| **lastStep** | Per-track loop point. Track plays `1..lastStep` then wraps. Default 16. |
| **viewport** | UI-only concept: which 16-step window of the buffer the screen + EN16 are showing. Indexed 1..4 (steps 1–16, 17–32, 33–48, 49–64). Global, not per track. **Not stored in the engine.** |
| **mode** | The currently-edited focus (NOTE/VEL/GATE/MUTE/STEP/KEY/LASTSTEP). Selected by VSN1 keyswitches 1..7. DUR is reached as SHIFT+endless in GATE focus; RATCH as SHIFT+endless-click in MUTE focus. KEY (slot 6) edits a global, display-only key signature: turn = root pitch (12 chromatic steps), shift+turn or click = toggle major/minor. Engine never reads `Engine.rootPitch` / `Engine.scaleMode` during `onPulse` — they are metadata for the screen only. Each mode has a fixed RGB color defined in `controls.MODES`; the same color appears in the VSN1 header, the active param row, and the EN16 turn-layer LEDs. |
| ~~region~~ | **DEPRECATED.** Used to mean an engine-coordinated 16-step window with global at-end-of-region switching. The engine no longer has regions. The word survives only as a casual synonym for "viewport" in old comments — prefer "viewport". |
| ~~pattern~~ | **FORBIDDEN word.** Reserved. Pattern implies independent step buffers (Model B), which we explicitly do not have. |
| ~~scene~~  | **FORBIDDEN.** |
| ~~snapshot~~ | **FORBIDDEN.** |
| ~~probability~~ | **REMOVED.** Was a per-step field; cut because it had no UI surface and ate a column of step-pack bits + a per-pulse RNG roll. |
| ~~bank~~   | **RESERVED** for the parked Model-B option. Don't use until that returns. |

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
