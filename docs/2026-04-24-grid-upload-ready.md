# 2026-04-24 — Grid upload-ready

## Status
The full sequencer + player + song-loader stack now compiles to a clean upload bundle in `grid/` with **zero over-limit warnings**. End-to-end load and tick verified against a flat-namespace simulation (`/tmp/gridsim/`) using only the emitted files — the same pattern the Grid firmware will use.

## What changed today

### `tools/gridsplit.lua`
- **Universal preamble-local promotion**: every `local NAME = ...` in the preamble (constants, tables, multi-line literals — except `require`s) is now promoted to `Module._NAME` and references inside function bodies rewritten. Eliminates per-chunk `localVarsText` duplication and cross-chunk visibility bugs in one pass.
- **Multi-chunk data emission**: `Utils.SCALES` (~900 chars) was a single statement that couldn't fit one data chunk. Splitter now bins multiple data statements across multiple data chunks (`seq_utils_1.lua`, `seq_utils_2.lua`, …) when needed.
- **Slimmed root file**: dropped per-`require` `collectgarbage()` calls (they cost ~38 non-whitespace chars per chunk; 22-chunk Track was overflowing). One trailing GC pass after all requires.
- **`song_loader.lua` added to default sources**, since it's part of the upload bundle.
- **`--include-songs` flag**: when set, copies `songs/*.lua` into outdir as flat names (`songs/dark_groove.lua` → `grid/dark_groove.lua`), since Grid's `require()` uses a flat namespace.
- All `gridCharCount` sizing accounts for the fact that whitespace is free on Grid.

### `utils.lua`
- `Utils.SCALES` literal table converted to per-key assignments (`Utils.SCALES.major = {...}` × 30). Each key is now an independent statement, so the splitter can bin them across data chunks. Tests still pass.

### `sequencer/track.lua`
- `Track.deletePattern` was 886 chars (over 800 limit). Refactored: extracted `trackRemovePatternFromArray` and `trackShiftLoopAfterDelete` helpers. Now under limit.

### `grid_module.lua`
- Updated requires to flat names (`seq_song_loader`, `seq_player`, `seq_engine`).
- Removed obsolete `package.preload` alias comments — splitter now rewrites paths automatically.
- Song reference is now `require("dark_groove")` (flat).
- Documented exact upload list (`grid/*.lua` + `dark_groove.lua`).

## Bundle stats
- **82 files** total in `grid/` (81 split modules + 1 song)
- **40,490 chars** minified across all chunks
- Largest chunks now sit at ~660 chars, all well under the 800 limit

## End-to-end verification
Loading `dark_groove` via `seq_song_loader` and ticking 400 pulses at BPM 118 produces:
- NOTE_ON: 528
- NOTE_OFF: 525
- (3 in flight at end-of-tick — correct)

All desktop tests pass: utils, step, pattern, track, engine, performance, mathops, snapshot, probability, player, tui, sequence_runner.

## Ready to upload
1. `lua tools/gridsplit.lua --include-songs` → produces `grid/`.
2. Upload all `grid/*.lua` to the Grid module's filesystem.
3. Paste the **INIT BLOCK** from `grid_module.lua` into element 0's init event.
4. Paste the **TIMER BLOCK** from `grid_module.lua` into element 0's timer event.
5. Reload config; song should start playing on Ableton MIDI input "Sequencer" (or whatever MIDI sink the firmware exposes).

## Next time
- First device test. Watch for: missing firmware functions (`midi_send`, `element_timer_start`, `self:element_index`), require-name mismatches, or file-size limits stricter than 800 non-whitespace chars.
- If memory pressure shows up, we still have headroom from identifier-shortening in the minifier (~20–40% extra).
- `Engine.reset` and `Player.allNotesOff` button hooks are scaffolded as comments in `grid_module.lua` — wire to actual Grid buttons once the basic loop runs.
