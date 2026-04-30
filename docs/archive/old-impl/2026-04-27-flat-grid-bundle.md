# 2026-04-27 — Single-file lite engine + flat grid bundle

## What changed

- New `tools/bundle.lua`: splices N Lua source modules into one self-contained file. Each module becomes a `do ... end` block; cross-module `require()` calls are rewritten to local upvalues; secondary modules are exposed as fields on the main returned table.
- `sequencer_lite/{utils,step,pattern,track,engine}` are now bundled into a single `grid/sequencer_lite.lua` (17 998 B stripped — same total as the four separate stripped files; no overhead). Bundle returns `Engine`; `Engine.Step`, `Engine.Pattern`, `Engine.Track`, `Engine.Utils` are accessible as fields.
- `grid/` is now **fully flat**:
  ```
  grid/player.lua  grid/utils.lua  grid/sequencer_lite.lua  grid/edit.lua
  grid/empty.lua   grid/four_on_floor.lua  grid/dark_groove.lua
  ```
  No subfolders. Device paths become `/player.lua`, `/sequencer_lite.lua`, `/<song>.lua`, etc. — easier to reason about under Grid's literal-path `require()`.
- `grid_module.lua`, `grid_module_test.lua`, `README.md`, `AGENTS.md`, `docs/ARCHITECTURE.md` updated to flat layout.

## Source-of-truth decision

`sequencer_lite/{step,pattern,track,engine}.lua` + `utils.lua` remain the edit target. `grid/sequencer_lite.lua` is a generated build artifact only (never edit by hand). Tests still target the source modules so per-file ownership / bisection still works.

## How the bundle resolves cross-module requires

Original: `local Step = require("sequencer_lite/step")`.

Bundler maps the require key `sequencer_lite/step` to the local name `Step` (declared via `--as Step=sequencer_lite/step.lua`). Each `require("sequencer_lite/step")` in any module body gets rewritten to `(Step)`. All module locals are forward-declared at the top of the bundle so order doesn't matter:

```lua
local Utils, Step, Pattern, Track, Engine
Utils = (function() ... return Utils end)()
Step  = (function() ... return Step end)()
... etc.
return Engine
```

Unknown require keys are left untouched (e.g. firmware modules on Grid).

## Verification

- 15/15 unit suites pass (including `tests/sequencer_lite.lua` ran against the bundle by overriding `package.loaded`).
- 11/11 sequence scenarios pass.
- `Player.new(song)` + `Edit.setPitch(song, ...)` round-trips under the flat path.
- Bundle byte-equivalent to four separate stripped files (no padding, no extra wrappers cost beyond the forward-decl line).

## Build commands

```sh
rm -rf grid && mkdir -p grid
lua tools/strip.lua player/player.lua --out grid/player.lua
lua tools/strip.lua utils.lua          --out grid/utils.lua
lua tools/strip.lua live/edit.lua      --out grid/edit.lua
lua tools/bundle.lua --out /tmp/sequencer_lite.lua \
    --as Utils=utils.lua \
    --as Step=sequencer_lite/step.lua \
    --as Pattern=sequencer_lite/pattern.lua \
    --as Track=sequencer_lite/track.lua \
    --as Engine=sequencer_lite/engine.lua \
    --expose Utils --expose Step --expose Pattern --expose Track \
    --main Engine
lua tools/strip.lua /tmp/sequencer_lite.lua --out grid/sequencer_lite.lua
lua tools/song_compile.lua songs/empty.lua          --outdir grid
lua tools/song_compile.lua songs/four_on_floor.lua  --outdir grid
lua tools/song_compile.lua songs/dark_groove.lua    --outdir grid
```

## Next

- Upload flat `grid/` and re-run the tiered RAM measurement protocol from `docs/2026-04-27-live-edit-and-measurement-bundle.md` (just substitute `/sequencer_lite/engine` → `/sequencer_lite` etc. — the tier hooks in `grid_module.lua` are already updated).
- Folding `tools/bundle.lua` into a single `make grid` target if a Makefile is added later.
