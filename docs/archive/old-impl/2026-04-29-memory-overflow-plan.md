# 2026-04-29 — Memory overflow on boot: investigation + reduction plan

## Problem

Device fails to boot the current bundle. User-stated heap ceiling: **~130 KB**.

## Measurements (macOS Lua 5.5, proxy for device)

| Phase | Cost |
|---|---:|
| `loadfile("grid/sequencer.lua")` (parse → bytecode, no run) | **+72.9 KB** |
| `require("sequencer")` (load + run all module bodies) | **+92.4 KB** |
| `+ require("/dark_groove")` patch descriptor | +5.7 KB |
| `+ PatchLoader.build` (engine populated) | +3.6 KB |
| `+ Driver.new` | +0.4 KB |
| **Total before first pulse (dark_groove)** | **~102 KB** |
| **Total before first pulse (four_on_floor)** | **~89 KB** |

Per-module bytecode load cost (isolated, in-memory `load()`):

| Module | Source | Bytecode load |
|---|---:|---:|
| `step.lua` | 10.4 KB | **19.1 KB** |
| `pattern.lua` | 1.8 KB | 7.0 KB |
| `track.lua` | 13.6 KB | **28.3 KB** |
| `engine.lua` | 3.9 KB | 9.0 KB |
| `driver.lua` | 5.5 KB | 9.3 KB |
| `midi_translate.lua` | 2.5 KB | 3.0 KB |
| `patch_loader.lua` | 5.0 KB | 8.9 KB |
| `controls.lua` | 14.9 KB | **27.4 KB** |
| `utils.lua` | 1.5 KB | 6.5 KB |
| **TOTAL** | 59.1 KB | **118.5 KB** |

## Diagnosis

**Source bytes are not the bottleneck — function/closure count is.** Each
`function ... end` adds ~1–2 KB of bytecode regardless of body size:
prototype header, constant table, upvalue array, line info. The bundle
defines ~85 functions across 9 modules.

LuaSrcDiet renames locals but does not collapse functions. Strip removes
asserts but the surrounding `function ... end` shells stay. We have hit
the ceiling of what minification alone can deliver. The next gains come
from **removing whole functions** — collapsing many one-liners into a
few dispatch functions, deleting modules, dropping the controls layer
out of the always-loaded path.

The earlier session note (2026-04-28-memory-diet) was correct that source
size is roughly halved by diet+strip; it was wrong to expect the device
RAM to track source size. Bytecode dominates, and bytecode is dominated
by function count.

## Strategy

Three orthogonal levers, in priority order:

### Lever 1 — Collapse functions (target: −30 KB)

| Module | Action | Est. saving |
|---|---|---:|
| `step.lua` | **Inline into `track.lua` as locals.** Delete the module. 14 setter/getter/sample functions → 2 dispatch helpers (`stepGet(s, field)`, `stepSet(s, value, field)`) + inline `sampleCv`/`sampleGate`. | **~15 KB** |
| `track.lua` | Collapse 5 direction-mode helpers (`trackNextForward/Reverse/Random/Brownian/PingPong` + `trackResetOutOfRange` + `trackDispatchDirection`) into one table-dispatched function. Replace 3 separate cursor-walk helpers (`trackComputeStepCount`, `trackGetStepAtFlat`, `Track.patternStartIndex/EndIndex`) with one walker that takes a callback or returns multiple values. | **~6 KB** |
| `engine.lua` | Inline `engineInitTracks`. Drop `Engine.bpmToMs` (compute inline at construction; nobody else needs it). Drop `Engine.advanceTrack`/`sampleTrack` wrappers — call `Track.advance/sample` directly from Driver. Engine becomes ~3 functions. | **~5 KB** |
| `patch_loader.lua` | Collapse `patchLoaderApplyPattern` + `patchLoaderApplyTrack` + `patchLoaderBuildStep` into a single `build()` body with locals. | **~4 KB** |
| `utils.lua` | Drop entirely from device bundle. `tableNew` and `pitchToName` are unused on device. `tableCopy` and `clamp` are used in 1–2 places each — inline at callsite. | **~6 KB** |

The Step inlining is the largest single win and the most invasive. See
"Testing the inlined Step" below.

### Lever 2 — Lazy-load controls.lua (target: −20 KB until first UI event)

User insight: bundling vs paste-in-event has the same final heap cost
**once the handler runs**, but bundling forces the cost at boot, while
paste-in-event defers it until the user touches a control.

**Plan:** keep `controls.lua` as a separate file `/controls.lua` on the
device (not bundled into `/sequencer.lua`). The `controls.lua`
paste-glue at the root does:

```lua
-- INIT (or first BUTTON event):
if not P then P = require("/controls") end
```

This means:
- Cold boot loads only engine + driver + patch (~65 KB instead of ~92 KB).
- First UI interaction adds the ~27 KB controls module. Total at that
  point: ~92 KB. Same headroom as today, but **reachable** because boot
  succeeded first.
- If the user never touches the UI (pure-playback patches), controls
  never loads. Free RAM stays at ~65 KB margin.

**Bonus:** allows `collectgarbage("collect")` between phases without
fragmenting the engine's working set.

This requires `tools/build_grid.lua` to output controls as a separate
file `grid/controls.lua` (already happens for patches). The `--as
Controls=...` line moves out of the sequencer bundle command into its
own bundle pass.

### Lever 3 — Slim controls.lua itself (target: −10 KB load cost)

The current `controls.lua` is 14 functions / 14.9 KB / 27.4 KB load. A
realistic minimal version:

- One state table, one `init`, one `onSelect`, one `onRotate`, one
  `onClick`, one `draw`. **6 public functions instead of 14.**
- Replace `LB`/`PO`/`DIR_CYCLE`/`DIR_INDEX` lookup tables with hard-coded
  `if`/`elseif` chains in the dispatch — saves 4 module-level table
  allocs and the closures that reference them.
- Drop the dirty-flag granularity. The screen is small; on rotate, just
  redraw the focused cell + the timeline strip. On select, redraw the
  two affected cells. ~5 dirty-flag-management functions disappear.

Target: ~8 KB source, ~10–12 KB load cost. **Net saving of ~15 KB on top
of Lever 2's deferral.**

## Combined target

| | Before | After Lever 1 | After Lever 1+2 | After Lever 1+2+3 |
|---|---:|---:|---:|---:|
| Cold-boot heap | 92 KB | 62 KB | 62 KB | 62 KB |
| Heap with controls active | 102 KB | 72 KB | 72 KB | 60 KB |
| Heap with controls + dark_groove engine | 110 KB | 80 KB | 80 KB | 68 KB |

Even Lever 1 alone clears the 130 KB ceiling with ~50 KB headroom for
engine data growth (more steps, more patterns).

## Testing strategy for inlined Step

Concern: deleting `step.lua` removes the test seam. Mitigation:

1. The packed-int encoding becomes a **private contract of `track.lua`**.
   All packed-int helpers (`get7`, `pack7`, `getBit`, `packBit`, the
   `P_*` constants) are `local` functions in `track.lua`.

2. **Add a debug inspector**, exposed only for tests:

   ```lua
   -- track.lua
   Track._debug = {
       newStep   = function(p, v, d, g, r, prob) ... end,
       getField  = function(s, field) ... end,
       sampleCv  = function(s) ... end,
       sampleGate = function(s, pc) ... end,
   }
   ```

   The strip pass removes `Track._debug = ...` on the device build (one
   simple regex in `tools/strip.lua`, similar to assert removal).

3. **Move `tests/step.lua` content into `tests/track_step.lua`**, calling
   through `Track._debug`. All existing assertions kept; the test surface
   is identical, just the calling syntax changes.

4. The patch loader, currently `Step.new(p, v, d, g, r, prob)`, becomes
   `Track._debug.newStep(...)` (or, better, the patch loader builds the
   packed int directly with a private helper — one fewer function to
   ship).

**Feasibility for machine testing: high.** The test surface stays
behavioural (give a step these params → expect this gate stream). I can
verify by running the existing `tests/sequence_runner.lua` scenarios
unchanged — they already exercise every Step behaviour through the
Track API end-to-end.

## Results

### Lever 2 — DONE (macOS proxy, dark_groove + four_on_floor)

Build pipeline split: `tools/build_grid.lua` now produces two stripped+
diet'd files: `grid/sequencer.lua` (engine + driver + patch_loader +
midi_translate, 10.6 KB raw) and `grid/controls.lua` (Controls module
with shim `local _D = require("/sequencer"); local Step=_D.Step;
local Track=_D.Track`, 4.9 KB raw). Root `controls.lua` paste glue
defines `PI()` in BLOCK 1; every BUTTON/ENDLESS/SCREEN handler calls
`PI()` (or guards on `if P then`) so the Controls module loads only on
first user interaction.

| Phase | four_on_floor | dark_groove |
|---|---:|---:|
| baseline (Lua VM) | 28.9 KB | 30.8 KB |
| `require('/sequencer')` | +42.1 KB | +41.4 KB |
| `+ require('/<patch>')` | +1.2 KB | +5.7 KB |
| `+ PatchLoader.build` | +1.0 KB | +3.6 KB |
| `+ Driver.new + start + 100 pulses` | +0.5 KB | +0.8 KB |
| **PLAYBACK TOTAL (no UI)** | **44.8 KB** | **51.5 KB** |
| `+ require('/controls') + init` | +53.7 KB | +53.7 KB |
| **TOTAL (with UI)** | **98.5 KB** | **105.2 KB** |

Cold-boot (no UI) is **51.5 KB** worst case — well under the 130 KB
ceiling. After UI loads, **105.2 KB** worst case — still under ceiling
with ~25 KB margin.

All 16 unit-test files pass. All 11 sequence-runner scenarios pass.
`tests/grid_bundle_smoke.lua` and `tests/controls.lua` pass against the
new bundle layout.

**Decision: ship Lever 2 alone.** No need to invade Step inlining,
direction-helper collapse, or controls slimming yet. Levers 1 and 3
remain documented above for future application if the heap pressure
returns (e.g. larger patches, additional features).

## Order of operations (original plan)

1. **Lever 2 first** — it's the cheapest, most reversible change.
   Rebuild, measure heap deltas with `tools/memprofile.lua`. If 2-alone
   gets us under the ceiling, ship and stop.
2. **Lever 1 (Step inline)** — the highest single saving. Mirror to
   `sequencer/` only if needed (tests run against full engine; we can
   keep `sequencer/step.lua` intact for host-side tests and only inline
   in `sequencer_lite/`).
3. **Lever 1 (others)** — track direction collapse, engine wrapper drop,
   patch_loader collapse, utils removal. Each one independently.
4. **Lever 3 (slim controls)** — only if heap is still tight after 1+2.
5. **Update CODEBOOK.md** for any new abbreviations or short field codes
   introduced.
6. **Update ARCHITECTURE.md** and `dropped-features.md` to reflect the
   new module layout.

## Reversibility

All changes touch `sequencer_lite/` and `driver/`/`patch_loader.lua`
build-rewrites. The full `sequencer/` engine stays intact as the
authoring reference and the test bedrock. If a Lever-1 change misbehaves,
revert that one lite file.

## What we are explicitly not doing

- **Not** abandoning the packed-int Step. The data win (8 B/step inline
  in array part vs. 80 B table) is independent of the function-count
  problem and remains the right call for >100-step patches.
- **Not** writing a custom local-renamer. LuaSrcDiet already does this.
- **Not** dropping direction modes / probability / ratchet / clock div
  yet (the tier-3 candidates from `dropped-features.md`). Those are
  feature losses; we attack code organisation first.
- **Not** rewriting in C / using ESP32 native bindings. Out of scope and
  not needed at this saving level.

## Open questions for next session

- Real on-device RAM after Lever 1+2. The macOS proxy is reliable
  directionally but Lua 5.4 on ESP32 may have different per-function
  overhead. Add a `print(collectgarbage("count"))` after each `require`
  in the device's INIT block and read the device log.
- Whether the patch descriptor itself (`/dark_groove.lua` ≈ 5.7 KB heap
  for a 36-step patch) is a worthwhile target. It is consumed-once at
  boot then dropped (`grid_module.lua` already does this), so unlikely.
- Whether `collectgarbage("collect")` between Lever-2 phases buys
  measurable headroom or just CPU.
