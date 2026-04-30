# 2026-04-29 — Lazy-loading controls fixes the boot overflow

## Problem

Device boot failed: `/sequencer.lua` bundle (with Controls inlined) loaded
~92 KB at `require`, climbing to ~110 KB after engine build for
dark_groove. User-stated heap ceiling is ~130 KB; we were too close to
the edge for a stable boot.

## What we did (Lever 2 from `2026-04-29-memory-overflow-plan.md`)

Split the device upload into two files. Defer the UI cost until the user
touches a control.

### Build pipeline (`tools/build_grid.lua`)

- Removed `--as Controls=...` and `--expose Controls` from the main
  bundle command.
- Added a second `tools/bundle.lua` invocation:

  ```sh
  lua tools/bundle.lua --out grid/controls.lua \
      --as Controls=sequencer/controls.lua \
      --alias sequencer/step=Step --alias sequencer/track=Track \
      --main Controls
  ```

  The two `--alias` flags rewrite `require("sequencer/step")` →
  `Step` (a local var) inside the bundled controls source. A four-line
  shim is prepended:

  ```lua
  local _D = require("/sequencer")
  local Step  = _D.Step
  local Track = _D.Track
  ```

  After LuaSrcDiet renames locals, this becomes
  `local e=require("/sequencer")local t=e.Step` etc. — Step/Track are
  captured as upvalues of the Controls closure, sharing the engine's
  already-loaded classes.

- Both `grid/sequencer.lua` and `grid/controls.lua` go through
  `tools/strip.lua` then LuaSrcDiet (`--maximum --noopt-binequiv`).
- Added `grid/controls.lua` to the stale-cleanup list.

Output sizes: `grid/sequencer.lua` 10.6 KB, `grid/controls.lua` 4.9 KB.

### Root paste glue (`controls.lua`)

- BLOCK 1 (UTILITY) no longer assigns `P`. Instead it defines a global
  helper:

  ```lua
  function PI()
      if P then return end
      P = require("/controls")
      P.init(E)
      collectgarbage("collect")
  end
  ```

- Every BUTTON / SCREEN INIT event prefixes its body with `PI()` so the
  module loads on first use (and never if the user only plays back).
- ENDLESS rotation and SCREEN DRAW guard with `if P then` — these don't
  trigger a load on their own; they only do work when controls is
  already alive.

### memprofile

`tools/memprofile.lua` extended with a final phase: `require('/controls')
+ Controls.init(engine)`, GC pass, then a "TOTAL (with UI)" line.

## Results (macOS Lua 5.5 proxy, `tools/memprofile.lua`)

| Phase | four_on_floor | dark_groove |
|---|---:|---:|
| `require('/sequencer')` | +42.1 KB | +41.4 KB |
| + patch descriptor | +1.2 KB | +5.7 KB |
| + PatchLoader.build | +1.0 KB | +3.6 KB |
| + Driver setup + 100 pulses | +0.5 KB | +0.8 KB |
| **PLAYBACK TOTAL (no UI)** | **44.8 KB** | **51.5 KB** |
| + `require('/controls') + init` | +53.7 KB | +53.7 KB |
| **TOTAL (with UI)** | **98.5 KB** | **105.2 KB** |

Both phases comfortably under the 130 KB ceiling.

## Tests

All green:

- 16 unit-test files (utils, step, pattern, track, engine, mathops,
  snapshot, scene, tui, probability, sequencer_lite, midi_translate,
  patch_loader, driver, grid_bundle_smoke, controls).
- 11 sequence-runner scenarios.

`tests/grid_bundle_smoke.lua` loads `grid/sequencer.lua` exactly as the
device does and drives 100 pulses end-to-end — passes.
`tests/controls.lua` exercises the Controls module against the live
engine — passes.

## What we did NOT do

Lever 1 (function collapse: inline Step into Track, drop engine
wrappers, collapse patch_loader, drop utils.lua) and Lever 3 (slim the
controls module from 14 fns to 6) are documented in
`docs/2026-04-29-memory-overflow-plan.md` but **not applied** — Lever 2
alone got us under the ceiling with ~25 KB margin. Both levers remain
on the shelf for the next time heap pressure returns (larger patches,
more features, etc.).

## Files touched

- `tools/build_grid.lua` — split bundle pass; added controls build +
  strip + diet steps; cleanup list updated.
- `tools/memprofile.lua` — added deferred-controls measurement phase.
- `controls.lua` (root paste glue) — `PI()` lazy loader; every button
  block calls it; rotation/draw guard with `if P then`.
- `docs/ARCHITECTURE.md` — flat layout description updated for the new
  two-file device bundle.
- `docs/2026-04-29-memory-overflow-plan.md` — added "Results" section
  recording Lever 2 outcome; original plan kept as-is below it.

## Follow-up: do we need the bundler at all?

User raised: now that the device can hold 5 small files instead of one
big bundled file, is `tools/bundle.lua` still earning its keep? Could
we just upload `step.lua`, `pattern.lua`, `track.lua`, `engine.lua`,
`driver.lua` (etc.) as separate files and have INIT do five `require()`
calls?

Measured on the macOS Lua 5.5 proxy with each module
**stripped + LuaSrcDiet'd individually** and uploaded to flat paths
(no `sequencer/` or `sequencer_lite/` prefix, mirroring how the device
filesystem would resolve them):

| Path | Heap after all requires |
|---|---:|
| Bundled (`require('/sequencer')`, current) | **42.1 KB** |
| Split, 8 flat files (utils, step, pattern, track, engine, midi_translate, patch_loader, driver) | **44.8 KB** |
| **Delta** | **+2.7 KB** (~340 B per `require`) |

Per-file source sizes after diet: utils 413 B, step 1707 B, pattern
391 B, track 4432 B, engine 637 B, midi_translate 484 B, patch_loader
978 B, driver 1355 B — total ~10.4 KB, on par with the 10.6 KB bundle.
Source bytes are essentially the same; the heap delta is pure
per-`require` bookkeeping (string keys in `package.loaded`, separate
function prototypes for each chunk's main body, separate upvalue
arrays).

Decision: **keep the bundle.** User's stated rule was "more files only
acceptable if footprint is meaningfully better." Split costs us
2.7 KB and buys nothing measurable; one file is also easier to
re-upload after a crash. Bundler stays.

The measurement scripts (`tools/memprofile_split.lua`,
`tools/memprofile_split2.lua`) were one-shot and have been deleted.

## Open questions

- Lua 5.4 on ESP32 may have different per-function bytecode overhead
  than macOS Lua 5.5. Add `print(collectgarbage("count"))` after each
  `require` in the device's INIT block and read the device log to
  confirm the macOS proxy ratio.
- Does the lazy-load actually defer the cost on-device, or does the
  Grid Lua VM eagerly parse `/controls.lua` at filesystem mount? If the
  latter, the saving is purely organisational and we'd need to also
  delete the file from the device when not in use.
