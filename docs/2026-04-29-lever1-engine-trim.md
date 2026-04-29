# 2026-04-29 — Lever 1: Engine bundle trim

## What shipped

Three sub-cuts inside the lite-engine bundle, no API change, all tests green:

1. **Drop Utils from lite bundle.** `utils.lua` was bundled+exposed but no
   on-device code path referenced it. Removed `--as Utils=utils.lua` and
   `--expose Utils` from `tools/build_grid.lua`.
2. **Collapse direction-mode dispatch.** `sequencer_lite/track.lua` had 5
   private next-cursor helpers + `trackIsDirectionValid` + `trackDispatchDirection`
   (~95 lines of if/elseif). Replaced with a single `DIRECTION_NEXT` table keyed
   by direction string. `setDirection` validation now checks the same table.
3. **Strip dead range constants from Step.** `sequencer_lite/step.lua` declared
   `local PITCH_MIN=0`, `PITCH_MAX=127`, ... 10 such constants used only inside
   asserts. Stripping removes the asserts on device but LuaSrcDiet leaves the
   unreferenced locals in place. Inlined the constants as numeric literals in
   the assert messages so deletion is safe; on host the asserts still validate,
   on device the asserts vanish along with the literals.

Sub-cut C (inline Step into Track) was **cancelled**: Step is consumed by
`sequencer/patch_loader.lua` (engine bundle) and `sequencer/controls.lua`
(UI bundle, reads `Driver.Step`). Inlining would require duplicating ~20
public functions across both modules — net loss, not gain.

## Numbers

### macOS proxy heap (memprofile.lua)

| Step                  | Before | After   | Delta    |
|-----------------------|--------|---------|----------|
| `require('/sequencer')` | 42.1 KB | 38.75 KB | **-3.35 KB** |
| dark_groove playback total | 51.5 KB | 48.90 KB | -2.60 KB |
| four_on_floor playback | 44.8 KB | 42.13 KB | -2.67 KB |
| empty playback        | ~43 KB  | 41.00 KB | -2.0 KB |

### Source bundle size

| File                  | Before | After  | Delta |
|-----------------------|--------|--------|-------|
| `grid/sequencer.lua`  | 10602 B | 9773 B | **-829 B (-7.8%)** |
| `grid/controls.lua`   | 4957 B | 4957 B | 0 |

### Projected device savings

Applying the measured device/macOS heap ratio of 1.71× from
`docs/2026-04-29-on-device-heap.md`:

| Metric                        | Device before | Device projected | Headroom under 130 KB |
|-------------------------------|---------------|------------------|------------------------|
| Boot + bundle require         | 138.69 KB     | ~133.0 KB        | -3 KB (still over) |
| After patch + Driver.new      | 142.80 KB     | ~137.4 KB        | -7 KB (still over) |
| **Steady playback (post-gc)** | **127.19 KB** | **~122.6 KB**    | **+7.4 KB headroom** |

GC behaviour means the boot peak goes up and then down. Steady-state is what
actually matters for survival; we have ~7 KB of fresh slack. **Pure-playback
patches still survive comfortably.**

UI is still out of reach: `require('/controls')` costs +51.6 KB on host →
~88 KB on device, way over what 7 KB of headroom can absorb. Lever 3
(controls slim) is the next required move.

## Tests

All green:

- 16 unit tests (utils, step, pattern, track, engine, mathops, snapshot,
  scene, tui, probability, sequencer_lite, midi_translate, patch_loader,
  driver, grid_bundle_smoke, controls)
- 11 sequence scenarios via `tests/sequence_runner.lua all`
- `tests/grid_bundle_smoke.lua` (loads built bundle exactly as device does)

## Files touched

- `tools/build_grid.lua` — remove Utils from bundle
- `sequencer_lite/track.lua` — direction-mode dispatch table
- `sequencer_lite/step.lua` — drop range constants, inline as literals

No public API change. No test edits required. `docs/CODEBOOK.md`,
`docs/ARCHITECTURE.md`, `docs/dropped-features.md` need only the Utils-not-
bundled-in-lite note added.

## Next

1. **Re-measure on device.** Reflash `grid/sequencer.lua`, run the same
   instrumented BLOCK 1 from `docs/2026-04-29-on-device-heap.md`, confirm
   steady-state ≈ 122 KB.
2. **Lever 3: slim controls.** The 14 functions in `sequencer/controls.lua`
   need to compact to ~6, and the broken `string.format` call at line 317
   needs rewriting (Grid Lua build does not ship `string.format`).
3. **Probe stdlib availability on device** — `string.gsub/match/sub/find/rep`,
   `math.floor/random`, `table.concat/insert/remove`. Needed before Lever 3.
