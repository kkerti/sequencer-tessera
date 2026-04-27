# Sequencer

Lua step sequencer for the Grid modular controller. Authoring engine runs on macOS, compiles songs to a flat event-array schema that a tiny tape-deck player walks on the device.

See `docs/ARCHITECTURE.md` for the full system map.

## Run on macOS

```sh
# Live edit: compile the inline song descriptor in memory and play through the bridge
lua main.lua | python3 bridge.py

# Ship-mirror: load a precompiled song exactly as the device would
lua main_lite.lua | python3 bridge.py
```

In Ableton: Preferences → MIDI → enable **Sequencer** as a MIDI input.

## Run feature scenarios

```sh
lua tests/sequence_runner.lua all
```

## Build the Grid upload bundle

The bundle is **flat** — every file ends up directly under `grid/` with no
subfolders, so paths on the Grid filesystem are just `/player.lua`,
`/sequencer_lite.lua`, `/<song>.lua`, etc.

```sh
rm -rf grid && mkdir -p grid

# Single-file libraries (already one source file each)
lua tools/strip.lua player/player.lua --out grid/player.lua
lua tools/strip.lua utils.lua          --out grid/utils.lua
lua tools/strip.lua live/edit.lua      --out grid/edit.lua

# Lite authoring engine — bundle 5 source modules into one file, then strip
lua tools/bundle.lua --out /tmp/sequencer_lite.lua \
    --as Utils=utils.lua \
    --as Step=sequencer_lite/step.lua \
    --as Pattern=sequencer_lite/pattern.lua \
    --as Track=sequencer_lite/track.lua \
    --as Engine=sequencer_lite/engine.lua \
    --expose Utils --expose Step --expose Pattern --expose Track \
    --main Engine
lua tools/strip.lua /tmp/sequencer_lite.lua --out grid/sequencer_lite.lua

# Compiled songs (one file each)
lua tools/song_compile.lua songs/empty.lua          --outdir grid
lua tools/song_compile.lua songs/four_on_floor.lua  --outdir grid
lua tools/song_compile.lua songs/dark_groove.lua    --outdir grid
```

`tools/strip.lua` removes comments and statement-form `assert(...)` guards (cuts the player roughly in half). Value-returning asserts like `local f = assert(io.open(p))` are preserved.

`tools/bundle.lua` splices N source modules into one self-contained file: each module becomes a `do ... end` block, cross-module `require()` calls are rewritten to local upvalues, and secondary modules are exposed as fields on the main export (so `Engine.Step`, `Engine.Pattern`, etc. are accessible from the bundle).

Three songs ship as memory-footprint datapoints:
- `empty` — 0 events, `loop=false`, ~150 bytes. Player loads and idles silently. Baseline.
- `four_on_floor` — 32 events (16 kicks), 4 bars looping, ~600 bytes. Mid-size.
- `dark_groove` — 232 events across 4 channels (bass / keys / kick / hat), ~3.1 KB. Full song.

Three editing-engine candidates are bundled for on-device RAM measurement:
- `live/edit.lua` — ~6.6 KB stripped. In-place editor on compiled-song arrays. O(1) pitch/velocity/mute; ratchet via queued splice at loop boundary.
- `sequencer_lite.lua` — ~17.8 KB stripped (5 source modules bundled into one). Carved authoring engine: Step/Pattern/Track/Engine, no scene chain, no pattern manipulation, no snapshot. The bundle returns the Engine table; Step/Pattern/Track/Utils are accessible as `Engine.Step` etc.
- Load both for combined cost.

See `grid_module.lua` for the INIT block, the rtmidi callback, and the (commented-out) measurement hooks for `sequencer_lite.lua` and `edit.lua`.

## Inspect file sizes

```sh
lua tools/charcheck.lua grid/player.lua grid/dark_groove.lua
```

Reports raw and minified character counts. No thresholds — files of any size load on the Grid filesystem; smaller is just better for memory.

## Optional: serve docs locally

```sh
python3 -m http.server 8080
```
