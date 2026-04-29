# 2026-04-28 — Memory footprint: diet pass + descriptor drop

## Context
Device hit ~140 KB on `dark_groove` patch (over budget); `four_on_floor` fit at ~128 KB. Goal: find ~15-20 KB of headroom.

## Investigation
Wrote `tools/memprofile.lua` to measure Lua-managed allocation per phase via `collectgarbage("count")`. Numbers on macOS Lua 5.5:

| Phase | four_on_floor | dark_groove |
|---|---:|---:|
| `/sequencer` bundle load | 42.28 KB | 41.60 KB |
| Patch descriptor | 1.22 KB | 5.71 KB |
| `PatchLoader.build` engine | 1.47 KB | 7.61 KB |
| Driver.new + start + 100 pulses | 0.46 KB | 0.76 KB |
| **TOTAL** | **45.42 KB** | **55.69 KB** |

Per-step cost was reasonable (~186 B engine, ~137 B descriptor). The 10 KB delta between patches matches the 12 KB device blow-up — patch-side cost is what tips dark_groove over.

## Mitigations applied

### 1. LuaSrcDiet `--maximum --noopt-binequiv` (bundle minifier)
- Installed via `luarocks --lua-version=5.5 install luasrcdiet`.
- `--basic` only collapses whitespace (no VM win). `--maximum` adds `--opt-locals` (renames locals to short names) + `--opt-numbers`.
- Default `--maximum` failed equivalence check on Lua 5.4+ bytecode (LuaSrcDiet was authored for 5.1). Disabling `--opt-binequiv` works; `--opt-srcequiv` (lexer-stream check) still active.
- Wired into `tools/build_grid.lua` after the strip pass; uses tempfile rename because LuaSrcDiet refuses identical in/out paths.
- **On-disk**: 40 KB raw → 21 KB stripped → **10.2 KB diet'd** (51% reduction beyond strip).
- **Lua-managed VM**: 42.28 KB → 40.11 KB (only 2.2 KB; bytecode dominates regardless of identifier length).
- **Device RAM**: expected ~10 KB win because the Grid retains source string for `require()` at runtime.

### 2. Descriptor drop after build (in `grid_module.lua`)
- After `PatchLoader.build(descriptor)`, set `package.loaded["/four_on_floor"] = nil`, `descriptor = nil`, `collectgarbage("collect")`.
- Recovers ~6 KB on dark_groove (no longer pinning nested step tables that PatchLoader already cloned into Step.new tables).

## Combined expected savings on device
~16 KB (10 KB source + 6 KB descriptor). Brings dark_groove from 140 → ~124 KB with comfortable headroom.

## Verification
- `lua tools/build_grid.lua` produces 10.2 KB `grid/sequencer.lua`.
- All 15 unit tests pass (`utils, step, pattern, track, engine, mathops, snapshot, scene, tui, probability, sequencer_lite, midi_translate, patch_loader, driver, grid_bundle_smoke`).
- All 11 sequence scenarios pass.
- `tests/grid_bundle_smoke.lua` confirms diet'd bundle loads + emits 48 events on 96 internal pulses.

## Files changed
- `tools/build_grid.lua` — added LuaSrcDiet step (with PATH detection + WARN fallback).
- `grid_module.lua` — drop descriptor after build.
- `tools/memprofile.lua` — new diagnostic.

## Not yet verified
- Actual on-device RAM measurement. macOS profile is a proxy. Recommend uploading new bundle and reading device-side memory.

## Options held in reserve
- Inline-flatten Step getters/setters (~3-4 KB win, breaks encapsulation).
- Custom local-renamer if luasrcdiet ever proves insufficient.
- Drop trailing default fields from Step tables (~1.7 KB; fragile).
