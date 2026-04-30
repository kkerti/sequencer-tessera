# 2026-04-27 — Drop char-limit tooling, single-file compiled songs

## What changed

The Grid filesystem now accepts arbitrarily large Lua files; the old 880/800-char per-file limit no longer applies. Removed all the chunking infrastructure built around it.

### Deleted
- `tools/gridsplit.lua` — module → ≤800-char chunks splitter.
- `tools/gridsplit.lua --require-prefix` workflow.
- `compiled/dark_groove_*.lua` sidecar files (atpulse / kind / pitch / velocity / channel × 2 each).
- `package.path = "compiled/?.lua;..."` from `main_lite.lua`.

### Rewritten
- `tools/song_compile.lua` — single self-contained file output. CLI is now `lua tools/song_compile.lua <song.lua> [--outdir DIR]`. No `--require-prefix`, no `--no-split`, no chunking. Reports event count, duration, file size.
- `tools/charcheck.lua` — plain raw + minified char-count reporter. No thresholds, no PASS/FAIL, no chunk math. Minifier kept; useful for memory-footprint estimation.

### Unchanged but verified
- `player/player.lua` — tape-deck player, ~180 lines, single file.
- `sequencer/song_writer.lua` — per-loop probability re-roll.
- Schema v2 — interleaved NOTE_ON/NOTE_OFF rows sorted by `(atPulse asc, kind asc)`.
- Two clock modes (internal firmware timer / external MIDI 0xF8).

### Other fixes
- `Player.allNotesOff` API mismatch fixed in comment scaffolds: `grid_module.lua` (2 sites) and `main_lite.lua flushAllNotes` now use the callback form.

## Bundle size after cleanup

```
FILE                                                      RAW   MINIFIED
grid/player/player.lua                                   6255       2069
grid/dark_groove/dark_groove.lua                         2308       2302
TOTAL                                                    8563       4371
```

Two files total. ~4.4 KB minified across the entire upload.

## Build commands now

```sh
rm -rf grid
mkdir -p grid/player grid/dark_groove
cp player/player.lua grid/player/player.lua
lua tools/song_compile.lua songs/dark_groove.lua --outdir grid/dark_groove
```

Upload:
- `grid/player/player.lua`           → `/player/player.lua`
- `grid/dark_groove/dark_groove.lua` → `/dark_groove/dark_groove.lua`

## Folder-per-library kept

Even though each library is now one file, we keep the folder layout so the Grid module's per-folder upload/remove semantics still work cleanly.

## Grid require quirk still applies

Grid's `require()` does not do `package.path` `?` substitution — module names are treated as literal file paths. INIT block continues to use:

```lua
local Player = require("/player/player")
local song   = require("/dark_groove/dark_groove")
```

## Docs scrubbed

- `README.md` — rewritten.
- `AGENTS.md` — file layout, build commands, runtime constraints updated; `gridsplit` references removed.
- `docs/ARCHITECTURE.md` — diagram, pipeline narrative, tools table, build commands, file-layout section, "Why this split" sidebar, "Known gaps" updated.
- `grid_module.lua` — upload section + INIT-block require paths updated.
- Obsolete session notes annotated with SUPERSEDED headers:
  - `docs/2026-04-14-grid-880-deployment-tooling.md`
  - `docs/2026-04-24-grid-upload-ready.md`
  - `docs/2026-04-24-prefixed-require-working.md`
  - `docs/2026-04-24-lite-player-and-writer.md` (partial)
  - `docs/2026-04-14-memory-profiling-and-grid-constraints.md` (partial)

## Verified

- 13 behavioural test files pass.
- 11 sequence scenarios pass.
- `lua main_lite.lua` plays the single-file compiled song correctly.
- Bundle rebuilds clean with the new commands.

## Next steps

- Smoke-test the rebuilt single-file bundle on actual hardware.
- Multi-song selector (folder layout already supports it).
