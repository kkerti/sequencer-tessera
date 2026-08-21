# 2026-04-28 — CV+gate refactor complete

The compile pipeline is gone. Engine runs on device. Driver layer translates per-pulse `(cvA, cvB, gate)` samples into MIDI NOTE_ON/NOTE_OFF via a small edge detector.

## What changed

- `Step.sampleCv` / `Step.sampleGate` (boolean ER-101 ratchet, period 2×gate, suppressed once `pulseCounter >= duration`).
- `Track.sample → cvA, cvB, gate` and `Track.advance` (no return). Per-step entry probability rolled on `Track.new` / `Track.reset` / cursor advance / zero-dur skip; AND'd with `Step.sampleGate` via `currentStepGateEnabled`.
- `Engine.sampleTrack(eng, i) → cvA, cvB, gate` and `Engine.advanceTrack(eng, i)` (no return).
- New `sequencer/midi_translate.lua` — per-track edge detector. Rising gate → NOTE_ON; falling → NOTE_OFF; pitch change mid-gate → OFF+ON retrigger. `panic(state, channel, emit)` clears all hanging notes.
- New `sequencer/patch_loader.lua` — `build(descriptor) → Engine`, `load(modulePath) → Engine`. Walks pure-data Lua tables.
- New `driver/driver.lua` (renamed from `player/`) — `new`, `start`, `stop`, `setBpm`, `tick`, `externalPulse`, `allNotesOff`. Per-pulse loop: sample → translate → advance, per track, with per-track clockDiv/clockMult accumulator inside `externalPulse`. Calls `Engine.onPulse(engine, pulseCount)` at the end.
- `sequencer_lite/*` carved in parallel: byte-equivalent step/pattern; track without pattern manipulation; engine without scene hooks.
- `main.lua` rewritten as `lua main.lua [patch_path] | python3 bridge.py`; default patch `patches/dark_groove`.
- `tools/build_grid.lua` — one-shot bundle + strip + patch-copy. Output: 4 files (`grid/sequencer.lua` 20.9 KB stripped + 3 patch descriptors).
- `tools/bundle.lua` extended with `--alias KEY=NAME` so PatchLoader's `require("sequencer/engine")` resolves to the inlined lite Engine local.
- `grid_module.lua` rewritten: INIT loads `/sequencer` + `/four_on_floor`, builds engine via `PatchLoader`, constructs `Driver`. RTMIDI callback divides 24 ppq → engine pulses (= 24/`pulsesPerBeat`) and calls `Driver.externalPulse`. 0xFA/0xFB/0xFC handle start/continue/stop with auto all-notes-off.

## Deleted

`tools/song_compile.lua`, `sequencer/song_writer.lua`, `live/`, `player/`, `compiled/`, `song_loader.lua`, `main_lite.lua`, `tests/song_writer.lua`, `tests/live_edit.lua`, `tests/player.lua`.

## Tests

15 unit-test files + 9 sequence scenarios + 1 grid-bundle smoke test. All green. Scenarios passed unchanged via the new `Driver` path — the (sample, translate, advance) abstraction held cleanly against the existing scenario definitions.

## Smoke verification

- `timeout 1 lua main.lua patches/four_on_floor` emits expected NOTE_ON/NOTE_OFF stream on stdout.
- `lua main.lua patches/four_on_floor | python3 bridge.py` produces audible kick on every beat in Ableton.
- `tests/grid_bundle_smoke.lua` loads `grid/sequencer.lua` exactly as the device would (`require("/sequencer")` style on a `package.path` containing only `grid/`); drives 96 internal pulses; asserts ≥4 emit calls.

## Next

Hardware verification on a real Grid module. After that, on-device authoring UI: button-driven start/stop, knob-driven mathops, patch selector.

## Refactor brief

Full work plan, ratchet semantics, API tables, and post-refactor outcome appendix: `docs/2026-04-28-cvgate-engine.md`.
