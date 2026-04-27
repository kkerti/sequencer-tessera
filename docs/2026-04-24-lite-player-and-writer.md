# 2026-04-24 — lite player + song-writer migration

## What changed

- Deleted the rich `player/player.lua` (≈300 lines of swing/scale/active-notes/probability).
- Renamed `player_lite/` → `player/`. There is now exactly one player.
- Player is a pure tape-deck: walks `atPulse[]/kind[]/pitch[]/velocity[]/channel[]`,
  fires `song.onLoopBoundary(song, loopIndex)` at wrap. BPM is the only runtime knob.
- New `sequencer/song_writer.lua`: in-place `rollNextLoop(song, loopIndex)` that
  flips `kind` between active (1/0) and muted (2/3) for each NOTE_ON+pairOff pair.
  Static songs (no probability) early-out; writer arrays are not even shipped.
- Compiled schema bumped to v2: interleaved NOTE_ON+NOTE_OFF rows, sorted by
  `(atPulse asc, kind asc)`. `gatePulses[]` and runtime `probability[]` removed.
- `tools/song_compile.lua` rewritten to emit v2 + optional writer arrays
  (`pairOff`, `srcStepProb`, `srcVelocity`) only when `hasProbability` is true.
- `song_loader.lua` no longer constructs a `Player`; returns a lightweight stub
  table `{engine, swingPercent, scaleTable, rootNote}` for the compiler walker.
- `tests/sequence_runner.lua` now drives the engine directly (inline pulse loop
  with swing+scale+probability — test-runner concerns, not on-device player).
- `main.lua` rewritten: build inline song descriptor → `SongCompile.compile` →
  wire `SongWriter.rollNextLoop` if `hasProbability` → lite player + luv timer.
- `main_lite.lua` updated for the renamed `player/` path; otherwise unchanged
  (loads precompiled `compiled/dark_groove.lua`).
- `compiled/dark_groove.lua` regenerated for v2 (172 events, 10 sidecars,
  largest piece 708 chars under 800-char gridsplit limit).
- Deleted: `tests/player_live.lua`, `tests/sequence_player.lua`,
  `compiled/dark_groove_probability_1.lua`. Trimmed `tests/probability.lua`
  to `Probability.shouldPlay` + `Step` API only.

## Two harnesses, two workflows

- `main.lua` — live edit: tweak the song descriptor table inline, save,
  re-run. Compiles in memory. Shows `hasProbability` in the boot banner.
- `main_lite.lua` — ship-ready: loads precompiled `compiled/<name>.lua`,
  no compiler dependency at runtime. Mirrors what runs on Grid.

## Test status

All passing:
- `utils`, `step`, `pattern`, `track`, `engine`, `performance`, `mathops`,
  `snapshot`, `tui`, `probability`, `song_writer`, `player`
- `tests/sequence_runner.lua all` — all 11 scenarios
- `tools/song_compile.lua songs/dark_groove.lua` — clean compile

## Next steps

- Update `AGENTS.md` to describe the schema v2 + tape-deck player + writer split,
  and to remove references to the rich player. The current AGENTS.md `File layout`
  and `Bridge line protocol` sections are still accurate but the engine/player
  responsibility split needs a rewrite.
- Run `tools/memprofile.lua` to quantify the ESP32 footprint reduction.
- Consider whether `song_loader.lua` should move into `tools/` since it is now
  a compiler-only adapter.
