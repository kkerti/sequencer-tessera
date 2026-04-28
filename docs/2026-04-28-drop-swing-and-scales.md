# 2026-04-28 — drop swing and live scale quantization

## Decision

Both **swing** and the **live scale quantizer** are removed from the project entirely. They are not on-device-only carves; they are gone from the authoring engine, the lite engine, the player, the song descriptor schema, the screens, the songs, the tests, and the docs.

## Why

- The project's identity is "step sequencer engine + MIDI out". Swing is a timing-feel concern; scale quantization is harmony-shaping. Both are **downstream of MIDI** — Ableton, MIDI processors, instrument-side scale modes, etc., all do them well.
- Keeping them inside this codebase added cross-cutting weight (a `Performance` module, ~30 scale tables in `utils.lua`, swing fields on the engine, scale fields on the song descriptor, runtime quantization in the playback path, swing/scale UI rows in `screens/settings.lua`, scenario coverage in `tests/sequences/04` and `05`, and explanatory rows in `AGENTS.md` and `ARCHITECTURE.md`).
- Compiled songs already baked pitches and never carried swing or scale fields. The schema change is removal-only — no `formatVersion` bump.
- The `mathops` jitter operation now produces raw MIDI values (option 1: no quantize-on-jitter safety net). This matches the "engine outputs raw MIDI; harmony is downstream" stance.

## Surface area removed

- Files deleted: `sequencer/performance.lua`, `tests/performance.lua`, `tests/sequences/04_swing_showcase.lua`, `tests/sequences/05_scale_quantizer.lua`.
- APIs removed: `Engine.setScale`, `Engine.clearScale`, `Step.resolvePitch`, `Utils.SCALES`, `Utils.quantizePitch`, `Performance.nextSwingHold`.
- Engine fields removed: `swingPercent`, `scaleName`, `scaleTable`, `rootNote` (on both `sequencer/engine.lua` and `sequencer_lite/engine.lua`).
- Snapshot schema: no longer reads/writes `scaleName` / `rootNote`.
- Song descriptor: `swing`, `scale`, `root` keys removed from all `songs/*.lua` and ignored by `tools/song_compile.lua`.
- Screens: `SWING`, `SCALE`, `ROOT` rows removed from `screens/settings.lua`; `SC` row removed from `screens/trackconfig.lua`.
- Scenarios `09_full_stack_performance`, `10_four_track_polyrhythm_showcase`, `11_four_track_dark_polyrhythm`: swing/scale setup lines stripped, descriptions rewritten.
- `tests/sequence_runner.lua`: no longer requires `Performance`, no longer drives swing hold or scale resolution; calls `Step.getPitch` directly.
- `tests/sequencer_lite.lua`: dropped the scale-quantizer assertion block.
- Docs: `AGENTS.md`, `ARCHITECTURE.md`, `docs/dropped-features.md` updated; `docs/2026-04-11-sequencer-features-and-grid-tutorial.md` and the older 04-10 / 04-14 / 04-24 / 04-27 session notes are left intact as historical record.

## Verification

All test files pass:

```
lua tests/utils.lua && lua tests/step.lua && lua tests/pattern.lua && lua tests/track.lua \
  && lua tests/engine.lua && lua tests/mathops.lua && lua tests/snapshot.lua \
  && lua tests/scene.lua && lua tests/tui.lua && lua tests/probability.lua \
  && lua tests/song_writer.lua && lua tests/player.lua && lua tests/sequencer_lite.lua \
  && lua tests/live_edit.lua
```

All scenarios pass:

```
lua tests/sequence_runner.lua all
```

The grid bundle was regenerated end-to-end; `grid/` contains no references to `swing`, `scale`, `Scale`, `resolvePitch`, or `quantizePitch`.

## Next steps

- If on-device pitch transposition is ever desired, do it as a tiny, dedicated mathop or live-edit primitive — not as a scale subsystem.
- If users ask for "feel", recommend a downstream MIDI groove processor or an Ableton MIDI Effect rack rather than re-introducing a swing field.
