# 2026-04-29 — single-file collapse

## What changed

Collapsed the per-module split into one library file. Killed the bundler.

- `sequencer/` and `driver/` subdirs deleted; root `utils.lua` folded in.
- `sequencer.lua` (~45 KB) now contains: `Utils`, `Step`, `Pattern`, `Track`, `Scene`, `Engine`, `MidiTranslate`, `PatchLoader`, `Driver`. `require("sequencer")` returns a flat table.
- `controls.lua` stays at the project root as a separate file (lazy-loaded on device for cold-boot heap savings).
- Host-only modules (`mathops.lua`, `snapshot.lua`, `probability.lua`, `tui.lua`) hoisted to the project root; each does `local Seq = require("sequencer")`.
- 26 test files rewritten from `require("sequencer.X")` to `Seq.X` off the flat table. `tests/grid_bundle_smoke.lua` updated for the 4-arg `emit(kind, pitch, velocity, channel)` signature.
- `main.lua` now requires an explicit patch arg (no default) and prints usage if missing.
- `grid_module.lua` updated to `require("/sequencer")` and pull `Driver` / `PatchLoader` off the returned table.
- `tools/build_grid.lua` reduced to five `cp`s. Deleted `tools/bundle.lua`, `tools/strip.lua`, `tools/charcheck.lua`.
- All 16 unit tests + 11 sequence scenarios pass under the new layout.

## Docs

- Rewrote `docs/ARCHITECTURE.md` to match single-file shape.
- Trimmed `AGENTS.md` (dropped zones / codebook / multi-agent territory sections).
- Archived `docs/CODEBOOK.md` and 30 obsolete session notes to `docs/archive/`.
- Kept active: `2026-03-09-init-goal.md`, `2026-04-28-cvgate-engine.md`, `2026-04-28-drop-swing-and-scales.md`, `manuals/`.

## Decisions

- **Flat namespace** over Driver-as-root: cleanest call sites in the harness and on device. Required ~3-line touchups in `grid_module.lua` and `tests/grid_bundle_smoke.lua`.
- **Full collapse** over incremental split: bundler/strip/alias machinery only existed to splice files back together. Grid filesystem has no per-file size limit, so there's no upside to keeping it.
- **Rewrite tests, no shims**: lower long-term maintenance.
- **Drop default patch in `main.lua`**: harness shouldn't own policy that doesn't exist on device.
- **Out of scope this pass**: `grid-wasm/`, `screens/` — left alone.

## Next

- On-device verification of the new bundle (only `tests/grid_bundle_smoke.lua` covers loading so far).
- Consider whether `controls.lua` actually needs to stay separate now that there's no size pressure — only the lazy-load heap argument remains.
