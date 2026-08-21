# 2026-04-29 — Remove `sequencer_lite/`, ship device bundle from `sequencer/` directly

## Decision

Drop the lite/full engine carve. Device bundle now sources from `sequencer/` directly. Scope on device: **Engine + Scene** (Step, Pattern, Scene, Track, Engine, MidiTranslate, PatchLoader, Driver). Snapshot, mathops, probability, utils stay host-only.

Rationale: maintaining two parallel engines was a tax on every change to the sample/advance contract. With the 880-char per-file limit gone, the on-device size cost of the full engine is acceptable, and patches gain access to the scene chain on device. The lite-bundle byte savings from earlier today (Lever 1, -829 B) are forfeited; net bundle grows from 9.8 → 15.3 KB raw.

## Changes

### Build pipeline
- `tools/build_grid.lua`: bundles `sequencer/{step,pattern,scene,track,engine,midi_translate,patch_loader}` + `driver/driver.lua`. Dropped `--alias` flags — require keys now match source paths. Exposes Engine / PatchLoader / MidiTranslate / Track / Pattern / Step / Scene.

### Deleted
- `sequencer_lite/` directory (4 files).
- `tests/sequencer_lite.lua`.
- `docs/dropped-features.md`.

### Documentation
- `AGENTS.md`: removed lite/full zones split, updated test list, removed lite-engine bullet from "Multiple agents".
- `README.md`: updated test command, updated `grid/sequencer.lua` description.
- `docs/ARCHITECTURE.md`: replaced "Full engine" + "Lite engine" sections with single "Engine" section; updated file tree; updated deployment block; updated bundle description.
- `tools/bundle.lua`: doc-comment example uses `sequencer/` path.
- `driver/driver.lua`: removed lite-vs-full NOTE.
- `sequencer/controls.lua`: header comment updated.

## Sizes

| Artefact | Before lite-removal | After |
|---|---|---|
| `grid/sequencer.lua` raw | 9 773 B | 15 301 B |
| `grid/controls.lua` raw | 4 957 B | 4 957 B |
| macOS `require('/sequencer')` | 38.75 KB | 56.6 KB |
| macOS playback total (dark_groove) | ~46 KB | 66.8 KB |
| macOS with-UI total (dark_groove) | n/a | 134.7 KB |

Device projection at the measured 1.71× host-to-device ratio:
- Pure playback (dark_groove): 66.8 × 1.71 ≈ **114 KB** (vs 130 KB ceiling → 16 KB headroom).
- With UI: 134.7 × 1.71 ≈ **230 KB** — well over the 130 KB ceiling.

## Status

Pure-playback device mode remains viable with comfortable headroom. **Lever 3 (slim controls)** is still required before the VSN1 UI loads on device. Lever 3 also needs to fix `sequencer/controls.lua:317` `string.format` (unavailable on device).

## Verification

- 15 unit tests green: `for t in utils step pattern track engine mathops snapshot scene tui probability midi_translate patch_loader driver grid_bundle_smoke controls; do lua tests/$t.lua; done`
- 11 scenarios green: `lua tests/sequence_runner.lua all`
- Bundle build green: `lua tools/build_grid.lua`
- `tests/grid_bundle_smoke.lua` exercises the new bundle exactly as the device would.

## Next

1. Re-instrument `controls.lua` BLOCK 1 paste with `print(collectgarbage("count"))` (no `string.format`) and capture fresh on-device baseline against the new 15.3 KB bundle.
2. Lever 3: probe stdlib availability on device, then collapse `sequencer/controls.lua` (14 fns → 6) and replace `string.format` with `..` concatenation.
