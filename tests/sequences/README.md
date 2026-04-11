# Sequence Scenarios

These scenarios are both:

- **Listenable**: run and route to `bridge.py`/Ableton if you want to hear the behavior.
- **Assertable**: each scenario contains explicit assertions used by `tests/sequence_runner.lua`.

## Run

Single scenario:

```bash
lua tests/sequence_runner.lua 01_basic_patterns
```

All scenarios:

```bash
lua tests/sequence_runner.lua all
```

Optional pulse count override:

```bash
lua tests/sequence_runner.lua 09_full_stack_performance 32
```

Real-time playback to Ableton (via bridge):

```bash
lua tests/sequence_player.lua 09_full_stack_performance gate-ms=40 ch1=1 ch2=10 | python3 bridge.py
```

## Scenario list

- `01_basic_patterns` — patterns + loop points
- `02_direction_modes` — reverse direction behavior
- `03_ratchet_showcase` — ratchet repeat density
- `04_swing_showcase` — odd-pulse swing hold/release behavior
- `05_scale_quantizer` — scale quantization correctness
- `06_clock_div_mult_polyrhythm` — per-track clock division timing
- `07_mathops_mutation` — transpose/randomize preprocessing
- `08_snapshot_roundtrip` — save/load state integrity
- `09_full_stack_performance` — combined feature integration
- `10_four_track_polyrhythm_showcase` — full 4-track performance demonstration
- `11_four_track_dark_polyrhythm` — darker 4-track performance scene
