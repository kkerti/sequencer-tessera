## Session notes

- Implemented Metropolis-style ratchet (`step.ratchet` 1-4) and integrated pulse-level ratchet events via `Step.getPulseEvent`.
- Added direction modes on tracks: `forward`, `reverse`, `pingpong`, `random`, `brownian`.
- Added global swing (50-72) using `sequencer/performance.lua` swing hold helper.
- Added live scale quantizer in engine output path via `Step.resolvePitch` and `Utils.SCALES` (30 scales).
- Added math operations module (`sequencer/mathops.lua`): transpose, jitter, randomize over step ranges.
- Added snapshot module (`sequencer/snapshot.lua`) with save/load full engine state via `io`.
- Extended terminal TUI with per-beat event tracing and per-tick trace lines for log-driven verification.

## Validation

- Full suite passes:
  - `tests/utils.lua`
  - `tests/step.lua`
  - `tests/pattern.lua`
  - `tests/track.lua`
  - `tests/engine.lua`
  - `tests/performance.lua`
  - `tests/mathops.lua`
  - `tests/snapshot.lua`
  - `tests/tui.lua`

## Next

- Add interactive command input (simple REPL) to mutate track/pattern/step parameters while running.
- Add deterministic seed controls for random/brownian/jitter operations in performance mode.
- Add optional compact TUI mode matching VSN1 viewport constraints.
