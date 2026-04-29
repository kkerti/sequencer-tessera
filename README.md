# Sequencer

Lua step sequencer for the Grid modular controller. ER-101–style CV+gate engine that runs **on the device** — no compile pipeline, no precomputed event arrays. The host (macOS) and the Grid module run the same engine; a Driver module samples the engine each pulse and translates rising/falling gates into MIDI NOTE_ON/NOTE_OFF events.

See `docs/ARCHITECTURE.md` for the full system map.

## Run on macOS

```sh
# Default patch (patches/dark_groove.lua)
lua main.lua | python3 bridge.py

# Pick another patch
lua main.lua patches/four_on_floor | python3 bridge.py
```

In Ableton: Preferences → MIDI → enable **Sequencer** as a MIDI input.

## Run feature scenarios

```sh
lua tests/sequence_runner.lua all
```

## Run unit tests

```sh
for t in utils step pattern track engine mathops snapshot scene tui \
         probability midi_translate patch_loader driver \
         grid_bundle_smoke controls; do
  lua tests/$t.lua || break
done
```

## Build the Grid upload bundle

```sh
lua tools/build_grid.lua
```

Produces a flat `grid/` directory:

| File | Purpose |
|---|---|
| `grid/sequencer.lua` | Single bundled file: engine (Step/Pattern/Scene/Track/Engine) + MidiTranslate + PatchLoader + Driver. Goes to `/sequencer.lua` on device. |
| `grid/<patch>.lua` | Pure-data patch descriptor (e.g. `dark_groove.lua`, `four_on_floor.lua`, `empty.lua`). Goes to `/<patch>.lua` on device. |

`tools/build_grid.lua` calls `tools/bundle.lua` to splice the modules and `tools/strip.lua` to remove comments and statement-form `assert(...)` guards. Value-returning asserts like `local f = assert(io.open(p))` are preserved.

`tools/bundle.lua` features:
- `--as NAME=PATH` declares a module to inline.
- `--alias KEY=NAME` adds extra require-key → local-name mappings, used so PatchLoader's `require("sequencer/engine")` resolves to the inlined lite Engine local.
- `--expose NAME` attaches secondary modules as fields on the main export (so `Driver.Engine`, `Driver.PatchLoader`, etc. are reachable from the bundle).

The three shipped patches:
- `empty` — no tracks, no steps. Driver idles silently. Baseline.
- `four_on_floor` — single channel, kick on every beat. Smallest non-trivial patch.
- `dark_groove` — four tracks (bass / keys / kick / hat) with patterns, loops, ratchets, probability. Full song.

See `grid_module.lua` for the INIT / TIMER / BUTTON / RTMIDI callback blocks.

## Inspect file sizes

```sh
lua tools/charcheck.lua grid/sequencer.lua grid/dark_groove.lua
```

Reports raw and minified character counts. No thresholds — files of any size load on the Grid filesystem; smaller is just better for memory.

## Optional: serve docs locally

```sh
python3 -m http.server 8080
```
