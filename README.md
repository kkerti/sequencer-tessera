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

```sh
rm -rf grid
mkdir -p grid/player grid/empty grid/four_on_floor grid/dark_groove
lua tools/strip.lua player/player.lua --out grid/player/player.lua
lua tools/song_compile.lua songs/empty.lua          --outdir grid/empty
lua tools/song_compile.lua songs/four_on_floor.lua  --outdir grid/four_on_floor
lua tools/song_compile.lua songs/dark_groove.lua    --outdir grid/dark_groove
```

`tools/strip.lua` removes comments and statement-form `assert(...)` guards (cuts the player roughly in half). Value-returning asserts like `local f = assert(io.open(p))` are preserved. Feed it any authoring module before upload.

Three songs ship as memory-footprint datapoints:
- `empty` — 0 events, `loop=false`, ~150 bytes. Player loads and idles silently. Baseline.
- `four_on_floor` — 32 events (16 kicks), 4 bars looping, ~600 bytes. Mid-size.
- `dark_groove` — 232 events across 4 channels (bass / keys / kick / hat), ~3.1 KB. Full song.

Swap which song the Grid module's INIT block requires (see `grid_module.lua`) to compare on-device memory.

Then upload each folder to `/<name>/` on the device and paste the INIT / TIMER / rtmidi-callback blocks from `grid_module.lua` into element 0.

## Inspect file sizes

```sh
lua tools/charcheck.lua grid/player/player.lua grid/dark_groove/dark_groove.lua
```

Reports raw and minified character counts. No thresholds — files of any size load on the Grid filesystem; smaller is just better for memory.

## Optional: serve docs locally

```sh
python3 -m http.server 8080
```
