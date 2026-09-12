# AGENTS.md — sequencer-3

Status: **building.** M1–M4 are built and tested. Next is the Grid VSN1 control
interface (out of scope until then). Settled decisions are locked; deferred work
is listed at the end.

## Project in one sentence

A simple, live-performance, 16-step, 4-lane MIDI sequencer inspired by Noise
Engineering's Mimetic Digitwolis, with a **headless Core** and pluggable host
adapters (Mac first, Grid VSN1 later).

## Reference material

- `docs/reference/noise-engineering.md` — distilled Mimetic Digitwolis + Gamut
  Repetitor. **The design reference.**
- `../sequencer-1/`, `../sequencer-2/` — reuse **critical infra only**:
  - `tools/bridge.py` — virtual MIDI ⇄ stdio, spawns the Lua process. Port
    nearly verbatim, rename ports.
  - `src/core/scales.lua` (seq-2) / `src/scale.lua` (seq-1) — 12-bit scale
    masks with `rotate` / `step` / `quantize`.
  - `src/persist.lua` (seq-1) — Lua-chunk `return{...}` save/load, applied in
    place to preserve table identity.
  - `tests/run.lua` no-alloc test pattern.
  - **Do not** port seq-2's tracks / patterns / rack / sequences / control
    modes, or seq-1's mono packed-int engine.

## Hard rules

1. **RAM first.** Every feature is costed for allocation and per-pulse runtime.
2. **Zero allocations on the pulse hot path.** `transport.onPulse()`, advance,
   and note emission allocate nothing: no table literals, closures, or string
   concat. Guarded by a `test_no_alloc`.
3. **No clock is internal-only.** The engine consumes pulses from either
   external MIDI clock (24 PPQN) or an internal timer; both call the same
   `onPulse`. It has no baked-in BPM.
4. **≤16 steps per lane**, fixed storage. No dynamic event store.
5. **Lanes only.** Four lanes, flat. No tracks, patterns, sequences, or racks.
6. **Core is pure and headless.** No drawing, no MIDI, no `ggd*`, no device
   knowledge. Core returns events / state; adapters do IO.
7. **The action API is the boundary.** The Lua shell and the future Grid GUI
   both call the same named actions. No logic lives in a UI.
8. **Reuse only what is proven.** Simpler is the point. When in doubt, leave it
   out.

## Layer model

```
Core   lanes, transport, scales, generators, persist, action API.
       Pure Lua. No IO except explicit persist. Returns events/state.
Adapters
       stdio bridge -> MIDI (Mac) ; Grid VSN1 widget/button map (later).
       Thin: move data, bind inputs, render state. No musical logic.
```

## Settled foundations

### Shape

- **Headless first.** No screen/GUI in seq-3. The Grid VSN1 control interface
  comes later, built against the action API, out of scope for now.
- **Lanes-only**, 4 lanes. Matrix navigation with X/Y advance sources mapped to
  transport taps (e.g. `transport.quarter` on X, `transport.sixteenth` on Y).
- **Action API** for all control; adapters are thin.
- **4 lanes**, implement `Note` first, then Mod/Trig/Gate/Gamut.
- **M1 "Mac loop":** Ableton sends MIDI clock -> engine advances a lane -> Note
  lane emits MIDI notes back to Ableton; the Lua shell changes settings.

### Storage (the contract)

- Each lane is a fixed record built once at init; per-step values live in
  preallocated arrays of exactly 16.
- Note lane: `pitch[16]` 0..127, `velocity[16]` 1..127, `stepLength[16]` in
  24-PPQN ticks. Mod: `value[16]`. Trig/Gate: `gate[16]`.
- Per-lane config is scalars only. Values are stored linearly 0..15;
  `dims` maps (x,y) -> index.

### Timing

- Internal resolution is 24 PPQN; one `onPulse` per pulse. External MIDI clock
  (default when present) and the internal timer share it.
- The transport derives taps from a position counter: `transport.whole` = 96
  pulses, `.half` = 48, `.quarter` = 24, `.eighth` = 12, `.sixteenth` = 6.
- Per-lane `advanceSource` + `division`; multi-dim lanes use separate
  `xAdvanceSource`/`yAdvanceSource`. X and Y wrap independently. Reset is
  deferred to the next advance. Stop freezes position.

### Musical model

- **Scales:** 12-TET only. Per-lane 12-bit mask + root; `Keys` + `Diaton`
  editors. Notes are stored absolute and quantized at output.
- **Output:** a Note lane is monophonic (retrigger) with a fixed preallocated
  note-off scheduler. MPE is an output-layer flag: one member channel per lane.
  Polyphony is deferred; FH-2 plus FHX expanders are the eventual path.
- **Lane semantics:** Mod emits CC on advance; Trig emits a short note pulse on
  active steps; Gate holds a note across active runs.
- **MIDI in:** exposed only as routable sources — trigger sources
  (advance/reset/random/previous/shift) and value sources (addressing). No
  MD2-style editor mappings and no Program Change preset loading. Parameter
  modulation by a value source is a separate, deferred decision.
- **Gamut** is a generator over Note/Trig lanes, not a new lane type. Parameters
  and UI still to be mapped.
- **Presets:** 24 Lua-chunk files under `presets/`, loaded on demand.

## Device-code reality (revised from seq-1/2)

The Grid has **filesystem access**. The ~10 KB text-chunk watchdog limit applies
to **element event scripts** (the inline scripts in a profile), **not** to Lua
modules loaded from the filesystem. So seq-3 can be organised into real modules
on the Grid FS instead of size-tuned bundles. Keep hot-path allocation
discipline regardless.

## Proposed layout (to be built)

```
sequencer-3/
  AGENTS.md  CONTEXT.md
  docs/reference/noise-engineering.md
  docs/adr/                 -- created as decisions warrant
  src/
    core/   lane.lua transport.lua engine.lua scales.lua persist.lua
    midi/   out.lua in.lua
    io/     stdio.lua
  proto/term/main.lua       -- headless harness / stdin command protocol
  presets/                  -- Lua-chunk slots
  tools/bridge.py
  tests/run.lua
```

## Milestones

- **M1 — Mac loop. ✅ BUILT.** 1 Note lane, external MIDI clock from Ableton,
  notes out, action API, no-alloc test. `presets/01.lua`.
- **M2 — Four lanes + matrix nav. ✅ BUILT.** `dims` layouts, X/Y advance,
  X/Y address value sources, shift/rotate, per-step velocity/length,
  same-pulse lane→lane, external MIDI mapping. `presets/02.lua` (matrix),
  `presets/03.lua` (MIDI-reactive). Tests: 57 checks, no-alloc green.
- **M3 — Lane types + four-lane performance. ✅ BUILT.** Lane `fire` now reflects
  output (Trig = active step, Gate = rising edge, Mod = at/above threshold);
  start no longer cascades. `presets/04.lua` (Voice: trig drives note + 2×mod)
  and `presets/05.lua` (4-lane polyrhythm) exercise all types. Tests: 65 checks.
- **M4 — Gamut generator. ✅ BUILT.** `src/core/generate.lua`: seeded, alloc-free
  Gamut (root/base, spread, downUp, velocity/gate spread) with one-shot fill and
  `live` playhead regeneration, plus a Euclidean rhythm fill for Trig/Gate
  lanes. `presets/06.lua` (live gamut + euclid). Tests: 73 checks, no-alloc
  green with a live generator on the pulse path.
- **Later — Grid VSN1 control interface** (widget system, buttons, minimal
  screen) against the action API.

## Deferred / future

- **Parameter modulation** — a value source driving division/length/scale/root/
  range. Deliberately deferred; not in the v1 API.
- **Gamut UI mapping** — parameters exist in the Core; the control surface is
  part of the later Grid work.
- **Polyphony via MPE** — FH-2 + FHX expanders; member-channel path only.
- **14-bit CC** — Mod lane stays 7-bit for now.
- **Grid VSN1 control interface** — buttons + minimal screen, built against the
  action API.

## Build log (M1–M4 done)

M1: full Core (`scales` -> `lane` -> `transport` -> `engine` -> `midi/out`),
no-alloc test, `bridge.py`, preset. M2: X/Y advance and address, shift/rotate,
same-pulse lane→lane, `io/midi_in` external mapping, presets 02/03. M3: lane
fire semantics per type, four-lane presets 04/05. M4: `generate.lua` Gamut +
Euclid, live generation, preset 06. Tests: 73 checks.

## Cross-cutting references

- `docs/ACTION_API.md` — the full named control surface.
- `docs/NAMING.md` — naming policy + source vocabulary + abbreviation lookup.
- `docs/PARAM_DEPENDENCIES.md` — which settings apply under which `dims` or
  lane type. The GUI will hide inapplicable controls from this.
- `docs/adr/` — the hard-to-reverse decisions and their rationale.
- `tools/bridge.py` — MIDI ⇄ stdio; `tools/send.py` — send notes/CC/clock to the
  bridge's virtual input from a second terminal (no DAW needed).

## When in doubt

Ask. Names and formats are cheap to change now and expensive later. Settle the
glossary before coding.
