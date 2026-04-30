# 2026-04-14 Grid 880-char Deployment Tooling

> **SUPERSEDED (2026-04-27).** The 880-char per-file limit no longer applies — the Grid filesystem now accepts arbitrarily large Lua files. `tools/gridsplit.lua` has been removed; `tools/charcheck.lua` is now a plain raw/minified size reporter (no thresholds). Compiled songs ship as a single self-contained file. See `docs/ARCHITECTURE.md` for the current pipeline.


## What was done

Built tooling to validate and split the sequencer engine files for deployment to Grid controllers, which have an 880-character-per-script-file limit.

### Tools created

1. **`tools/charcheck.lua`** — validates any Lua file(s) against the 880-char limit. Reports raw size, minified size, and pass/fail. Custom `--limit` flag supported.

2. **`tools/gridsplit.lua`** — splits module files into <=880 char chunks for Grid:
   - Strips `assert()` guards (dev-only, not needed on device)
   - Minifies (comments, whitespace, operator spacing)
   - Parses top-level function boundaries
   - Groups functions into chunks that fit the limit
   - Promotes local helper functions to module table when they're too large to inline
   - Emits root + chunk files with correct require chain

3. **`grid_example.lua`** — pseudo-code showing how Grid's internal timer event drives `Engine.tick()`, plus MIDI clock sync alternative.

### Naming scheme

Source file `sequencer/step.lua` becomes:
- `grid/seq_step.lua` — root: creates `Step={}`, requires all chunks, returns it
- `grid/seq_step_1.lua` — chunk: `require("seq_step")` gets the table, attaches functions
- `grid/seq_step_2.lua` — etc.

### Results: 57 files generated, 47 pass, 10 over limit

The 10 failures are individual functions that are inherently complex:

| Function | Over by | Category |
|----------|---------|----------|
| `Engine.tick` | +994 | Core loop — iterates tracks, resolves pitch, builds events |
| `Snapshot.fromTable` | +909 | Deserializer — nested loops over tracks/patterns/steps |
| `Track._trackGetNextCursor` | +716 | Direction mode logic — 5 modes with boundary wrapping |
| `Snapshot.toTable` | +507 | Serializer — mirrors fromTable |
| `Step.getPulseEvent` | +275 | Ratchet pulse logic |
| `Engine.new` | +146 | Constructor — many fields |
| `Track.advance` | +90 | Step advancement with skip logic |
| `Engine.getTrack+setBpm+setSwing+getSwing+setScale` | +26 | Grouping of 5 small funcs |
| `Track.insertPattern` | +24 | Pattern insertion with loop adjustment |
| `Engine.reset` | +15 | Reset with allNotesOff |

## Decision: keep engine source as-is

The 880-char limit is a Grid firmware constraint, not a code quality target. The engine is written with clear function separation and readable code. The tooling handles the mechanical splitting automatically.

For the 10 oversized functions, the options are:
1. **Refactor for Grid** — split complex logic into smaller sub-functions (recommended for `trackGetNextCursor`, `Engine.tick`)
2. **Accept the overage** — Grid firmware may accept slightly larger scripts in practice
3. **Reduce features** — drop snapshot, reduce direction modes (not recommended)

The near-misses (+15, +24, +26) can likely be resolved with more aggressive variable name shortening in the minifier.

## Grid integration pattern

```
-- Element 0 INIT: load engine, build sequence
local Engine = require("seq_engine")
SEQ_ENGINE = Engine.new(120, 4, 1, 0)
...

-- Element 0 TIMER: sequencer clock
local events = Engine.tick(SEQ_ENGINE)
for i = 1, #events do ... midi_send(...) end
element_timer_start(self:element_index(), SEQ_INTERVAL)
```

## Next

- Refactor `Engine.tick` and `Track._trackGetNextCursor` into smaller sub-functions to fit the 880-char limit
- Add variable name shortening to the minifier for tighter output
- Test the split output actually loads on Grid WASM simulator
- Connect the split engine to the screen files from `screens/`
