## Session notes

- Added `tests/sequences/` scenario suite with one file per feature area.
- Added `tests/sequence_runner.lua` to run single or all scenarios.
- Scenarios are both listenable (event/tick traces) and assertable (embedded `assert` checks).

## Added scenarios

- `01_basic_patterns`
- `02_direction_modes`
- `03_ratchet_showcase`
- `04_swing_showcase`
- `05_scale_quantizer`
- `06_clock_div_mult_polyrhythm`
- `07_mathops_mutation`
- `08_snapshot_roundtrip`
- `09_full_stack_performance`

## Validation

- `lua tests/sequence_runner.lua all` passes all scenario assertions.
- Existing unit/integration tests remain green.
