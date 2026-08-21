# 2026-04-29 — On-device heap measurement (Grid VSN1)

## Setup

- Uploaded `grid/sequencer.lua` (10.6 KB), `grid/controls.lua` (4.9 KB),
  `grid/four_on_floor.lua` to device root.
- Pasted instrumented BLOCK 1 (boot block) with
  `collectgarbage("count")` probes after each `require` / build step.
- BLOCKS 2–16 from `controls.lua` pasted unchanged so the UI was wired
  but not yet loaded (lazy `PI()`).
- Triggered module init; read 6 heap values from the Grid Editor log.

## Critical runtime finding

**`string.format` is not available on the Grid Lua build.** The
original probes used `print(string.format("HEAP %.2f KB",
collectgarbage("count")))` and had to be reduced to plain
`print(collectgarbage("count"))` before the module would run.

This is a hard constraint for all future device code: no
`string.format`, plain `tostring()` and `..` concatenation only.
Whether other `string.*` helpers (`gsub`, `match`, `sub`, `find`)
are also stripped is unknown — needs probing before we depend on them
on-device. (The bundle does use `string.format` nowhere in the engine
hot path; controls module needs auditing.)

## Numbers

Probe order matches BLOCK 1 print order:

| # | Probe | Device KB | macOS KB | Δ device-macOS |
|---|---|---:|---:|---:|
| 1 | boot start (before any require) | 91.48 | 23.86 | +67.6 |
| 2 | after `require("/sequencer")` | 138.69 | 65.97 | +72.7 |
| 3 | after `require("/four_on_floor")` | 141.45 | 67.21 | +74.2 |
| 4 | after `PatchLoader.build(desc)` | 142.45 | 68.12 | +74.3 |
| 5 | after `Driver.new(...)` | 142.80 | 68.62 | +74.2 |
| 6 | **after `collectgarbage("collect")`** | **127.19** | **44.83** | **+82.4** |

UI not loaded — `PI()` has not yet been called.

## Interpretation

### Baseline gap

The Grid runtime (Lua 5.4 core + Grid module bindings + screen + rtmidi
+ filesystem) sits at ~91 KB before our code loads. macOS is ~24 KB.
That ~67 KB delta is fixed cost we cannot influence.

### Per-byte ratio

After subtracting baselines:

- Device: 127.2 − 91.5 = **35.7 KB** for full-playback-no-UI.
- macOS:  44.8 − 23.9 = **20.9 KB** for the same code path.
- **Device runs ~1.71× heavier per byte of our code.** Plausible for a
  32-bit ESP32 (vs 64-bit macOS) — pointers, string headers, and Lua
  function prototypes are typically 1.5–2× bigger.

### GC freed real memory

142.80 → 127.19 = **−15.6 KB freed by the post-load GC pass.** On macOS
the same probe shows −23.8 KB freed. Both runtimes accumulate transient
parse + build garbage; the explicit `collectgarbage("collect")` in
BLOCK 1 is doing real work and must stay.

### Headroom

User-stated ceiling is 130 KB. We are at 127.2 KB — **2.8 KB under the
ceiling, with no UI loaded.**

Projection for UI load (using the 1.71× device ratio applied to the
macOS Controls cost of 53.7 KB):

> 53.7 KB × 1.71 ≈ **92 KB** added by UI on device
> 127.2 + 92 ≈ **219 KB total** — well over the 130 KB ceiling.

The lazy load defers the cost but doesn't eliminate it. The first
button press would almost certainly OOM the module.

## Decision

User chose: **skip the UI-load test, go cut more code.**

Pure playback already lives within the ceiling but has no margin for:
- larger patches (e.g. dark_groove was already 6.7 KB heavier than
  four_on_floor on macOS)
- the UI module
- any future feature growth

Next: apply Lever 1 (function collapse, drop utils.lua, inline Step
into Track) and Lever 3 (slim controls from 14 fns to 6) from
`docs/2026-04-29-memory-overflow-plan.md`. Re-measure on device after
each lever to track the real (not projected) saving.

## Confirmed: UI load DOES overflow

User pressed a keyswitch button after boot, triggering `PI()`. Device
log:

```
LUA not OK! MSG: error loading module '/controls' from file '//controls.lua':
    not enough memory
```

Useful properties of the failure:

- **Graceful.** Error raised, event chunk died, but BLOCK 1's globals
  (`D`, `E`, `DR`) survived. Playback should be unaffected.
- **Cliff is above 127 KB.** `require("/controls")` got far enough to
  start parsing before OOMing. The exact ceiling is somewhere between
  the 127.2 KB pre-require heap and the unknown peak that triggered the
  abort. Not 130 KB; probably 150–170 KB based on how far through the
  parse it got.
- **String allocation in error path matters.** The error message itself
  consumes memory; subsequent `PI()` retries may fail differently.

This validates the projection (UI cost ~92 KB device, total would have
hit ~219 KB) and confirms Lever 3 (slim controls) or a bigger refactor
is required before any UI is usable.

Pure-playback patches remain shippable — they never call `PI()`.

## Open questions before re-measuring

- What's the **actual** hard ceiling? The device sat at 142 KB during
  build without crashing. If the real OOM cliff is at, say, 200 KB,
  then we have far more margin than assumed and only the UI is at
  risk. Worth confirming with the user / Grid docs before doing
  destructive refactoring.
- Does the device crash on heap exhaustion or does the GC step in?
  Lua normally raises `not enough memory`; on Grid this may print
  to log or silently halt the module.
- Is `string.format` the only missing standard-library function?
  Probe `string.gsub`, `string.match`, `string.sub`, `table.concat`,
  `math.floor`, `math.random` — all of which the engine uses.

## Next files to touch

When applying levers (after ceiling clarification):

- `sequencer_lite/track.lua` — primary target for Step inlining and
  function collapse.
- `sequencer_lite/engine.lua` — drop scene-chain hooks already gone;
  see if more wrappers can collapse.
- `sequencer/patch_loader.lua` — collapse helper functions inline.
- `sequencer/controls.lua` — Lever 3, slim from 14 fns to 6.
- `utils.lua` — candidate for deletion, inline 2–3 callers.
- `tools/build_grid.lua` — no changes expected.
- `tests/grid_bundle_smoke.lua`, `tests/sequence_runner.lua` — must
  stay green throughout.
